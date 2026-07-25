import 'dart:ui';

import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as local_notif;

import '../models/payment.dart';
import '../overlay/payment_overlay.dart';

/// Controls the floating "chat head" bubble from the main app: permission
/// handling, showing/hiding the overlay window, and pushing live payment
/// updates into it whenever a new Telebirr SMS is parsed.
///
/// Android only — the underlying SYSTEM_ALERT_WINDOW overlay API has no
/// iOS equivalent (see main app README for the reasoning).
class OverlayService {
  /// Cap on how many recent payments are shared into the overlay's list
  /// view. The overlay only needs "recent enough to be useful", not the
  /// full history (that's what Payment History screen is for), and keeping
  /// this small keeps the shareData JSON payload cheap.
  static const int maxSharedPayments = 30;

  Future<bool> isPermissionGranted() => FlutterOverlayWindow.isPermissionGranted();

  /// Opens Android's "Display over other apps" settings screen for this app.
  /// Returns true once the driver grants it (they have to do this manually
  /// in system settings — Android does not allow a simple in-app prompt).
  Future<bool> requestPermission() async {
    final granted = await FlutterOverlayWindow.requestPermission();
    return granted ?? false;
  }

  Future<bool> isActive() => FlutterOverlayWindow.isActive();

  /// Android 13+ (API 33+) requires the POST_NOTIFICATIONS runtime
  /// permission before any notification -- including the one backing the
  /// overlay's foreground service, and the payment-received alert shown by
  /// NotificationService -- can be shown. Without this, showOverlay can
  /// fail to actually display anything on affected devices, with no visible
  /// error. On < API 33 this resolves to true immediately.
  ///
  /// Wrapped in a timeout + try/catch: this plugin call has been observed to
  /// hang indefinitely on some devices instead of failing fast, which would
  /// otherwise leave the calling UI stuck in a "loading" state forever.
  Future<bool> requestNotificationPermission() async {
    try {
      final plugin = local_notif.FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<local_notif.AndroidFlutterLocalNotificationsPlugin>();
      final granted = await plugin
          ?.requestNotificationsPermission()
          .timeout(const Duration(seconds: 5));
      return granted ?? true;
    } catch (_) {
      // Don't let a notification-permission hiccup block the overlay from
      // starting -- worst case, the foreground-service notification just
      // won't show, which isn't fatal.
      return true;
    }
  }

  /// Starts the floating bubble, collapsed, anchored bottom-right. It's
  /// draggable anywhere on screen after that (implemented ourselves in
  /// Dart via moveOverlay -- see payment_overlay.dart -- since the
  /// plugin's own native `enableDrag` has the buffer-compounding bug
  /// documented below).
  ///
  /// The window is sized from the device's real pixel ratio (see
  /// [overlayPhysicalPx]) rather than a fixed guess -- a fixed size that's
  /// too small for a given device's density leaves part of the bubble
  /// (the counter badge, the dismiss button, the ping ring) drawn outside
  /// the native window's touchable bounds, which is what made the overlay
  /// look "off-screen" and unresponsive on some phones.
  Future<void> start() async {
    if (await isActive()) return;
    await requestNotificationPermission();
    final view = PlatformDispatcher.instance.views.first;
    final dpr = view.devicePixelRatio;
    final screenPx = view.physicalSize;
    final cap = (screenPx.shortestSide).round();
    final size = overlayPhysicalPx(kOverlayCollapsedContentSize, dpr,
        logicalOvershoot: kOverlayCollapsedRingOvershoot, maxPx: cap);
    await FlutterOverlayWindow.showOverlay(
      height: size,
      width: size,
      alignment: OverlayAlignment.bottomRight,
      visibility: NotificationVisibility.visibilityPublic,
      overlayTitle: 'Telebirr Driver Assistant',
      overlayContent: 'Watching for payments',
      // enableDrag is deliberately OFF. Its native drag-handling path
      // re-applies a logical-to-physical pixel conversion to the window's
      // OWN already-physical size on every relayout frame while dragging,
      // compounding it each frame (270px -> 759px -> 2134px -- each step
      // is roughly x2.81, this device's exact pixel ratio, applied again
      // and again). That runaway buffer size is what crashes the native
      // compositor. This is inside the plugin's own drag code, not
      // anything in this Dart layer. Dragging is instead implemented in
      // payment_overlay.dart using moveOverlay() directly, which only
      // changes position, never size, so it can't trigger this bug.
      enableDrag: false,
      positionGravity: PositionGravity.none,
      flag: OverlayFlag.defaultFlag,
    ).timeout(const Duration(seconds: 8));
  }

  Future<void> stop() => FlutterOverlayWindow.closeOverlay();

  /// Call this every time a new payment is parsed from SMS. [recentPayments]
  /// should be the day's payments, most-recent-first -- this method takes
  /// care of trimming it down to [maxSharedPayments] before sending. Safe to
  /// call even if the overlay isn't currently active (callers should still
  /// guard with `isActive()` first to avoid the wasted work, but nothing
  /// breaks if they don't).
  Future<void> pushPaymentUpdate({
    required int todayCount,
    required double todayTotal,
    required List<Payment> recentPayments,
  }) async {
    if (!await isActive()) return;
    final update = OverlayPaymentUpdate(
      todayCount: todayCount,
      todayTotal: todayTotal,
      payments: recentPayments
          .take(maxSharedPayments)
          .map((p) => OverlayPaymentEntry(
                amount: p.amount,
                payerPhone: p.payerPhone,
                payerName: p.payerName,
                receivedAt: p.receivedAt,
              ))
          .toList(),
    );
    await FlutterOverlayWindow.shareData(update.toJson());
  }
}
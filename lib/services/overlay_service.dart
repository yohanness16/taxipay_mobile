import 'dart:convert';
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

  /// Starts the floating bubble, collapsed, near the bottom-right corner.
  /// It's draggable anywhere on screen after that (implemented ourselves
  /// in Dart via moveOverlay -- see payment_overlay.dart -- since the
  /// plugin's own native `enableDrag` has the buffer-compounding bug
  /// documented below).
  ///
  /// Note the unit split, which the plugin does not make obvious: this
  /// call's width/height are **physical pixels** (the native side hands
  /// them straight to WindowManager.LayoutParams), whereas `startPosition`
  /// and the resize/move calls the overlay makes later are in **dp**. See
  /// the UNITS block at the top of payment_overlay.dart.
  Future<void> start() async {
    if (await isActive()) return;
    await requestNotificationPermission();
    final view = PlatformDispatcher.instance.views.first;
    final dpr = view.devicePixelRatio;
    final screenPx = view.physicalSize;
    final screenDp = screenPx / dpr;
    final cap = screenPx.shortestSide.round();
    final sizePx = overlayPhysicalPx(kOverlayCollapsedWindowDp, dpr, maxPx: cap);
    final startDp = defaultBubbleAnchorDp(screenDp, kOverlayCollapsedWindowDp);
    await FlutterOverlayWindow.showOverlay(
      height: sizePx,
      width: sizePx,
      alignment: OverlayAlignment.topLeft,
      startPosition: OverlayPosition(startDp.dx, startDp.dy),
      visibility: NotificationVisibility.visibilityPublic,
      overlayTitle: 'Telebirr Driver Assistant',
      overlayContent: 'Watching for payments',
      enableDrag: false,
      positionGravity: PositionGravity.none,
      flag: OverlayFlag.defaultFlag,
    ).timeout(const Duration(seconds: 8));

    // Signal the overlay engine (which is cached and may retain state across
    // show/hide cycles) that the window is freshly shown, so it can reset
    // any expanded state back to collapsed and re-apply current geometry.
    try {
      await FlutterOverlayWindow.shareData(jsonEncode({'type': 'overlay_shown'}));
    } catch (_) {
      // Best-effort signal
    }
  }

  Future<void> stop() => FlutterOverlayWindow.closeOverlay();

  /// Call this every time a new payment is parsed from SMS. [recentPayments]
  /// should be the day's payments, most-recently-*arrived* first (i.e. from
  /// `getAllPayments(byArrival: true)`) -- this method takes care of trimming
  /// it down to [maxSharedPayments] before sending. Safe to call even if the
  /// overlay isn't currently active (callers should still guard with
  /// `isActive()` first to avoid the wasted work, but nothing breaks if they
  /// don't).
  ///
  /// Each entry carries its `payments` row id, which is what the overlay's
  /// unread badge counts with. Passing payments that have not been inserted
  /// yet (id == null) means they cannot be counted as arrivals, so always
  /// push rows read back from the database, not freshly-constructed models.
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
                id: p.id ?? 0,
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
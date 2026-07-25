import 'dart:convert';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../db/database_helper.dart';
import '../models/ride.dart';
import '../services/ride_manager.dart';
import '../widgets/app_logo.dart';

/// A single payment, as sent from the main app -> overlay. Deliberately
/// tiny/serializable -- this travels over `FlutterOverlayWindow.shareData`
/// as JSON.
class OverlayPaymentEntry {
  OverlayPaymentEntry({
    required this.amount,
    required this.payerPhone,
    this.payerName,
    required this.receivedAt,
  });

  final double amount;
  final String payerPhone;
  final String? payerName;
  final DateTime receivedAt;

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'payerPhone': payerPhone,
        'payerName': payerName,
        'receivedAt': receivedAt.toIso8601String(),
      };

  static OverlayPaymentEntry? tryParse(dynamic raw) {
    try {
      final map = raw as Map<String, dynamic>;
      return OverlayPaymentEntry(
        amount: (map['amount'] as num).toDouble(),
        payerPhone: map['payerPhone'] as String,
        payerName: map['payerName'] as String?,
        receivedAt: DateTime.parse(map['receivedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Shape of the data pushed from the main app -> overlay every time a new
/// Telebirr payment is parsed. [payments] is most-recent-first and capped
/// by the sender (see OverlayService.pushPaymentUpdate) so the shareData
/// payload stays small.
class OverlayPaymentUpdate {
  OverlayPaymentUpdate({
    required this.todayCount,
    required this.todayTotal,
    required this.payments,
  });

  final int todayCount;
  final double todayTotal;
  final List<OverlayPaymentEntry> payments;

  Map<String, dynamic> toJson() => {
        'type': 'payment_update',
        'todayCount': todayCount,
        'todayTotal': todayTotal,
        'payments': payments.map((p) => p.toJson()).toList(),
      };

  static OverlayPaymentUpdate? tryParse(dynamic raw) {
    try {
      final map = raw is String
          ? jsonDecode(raw) as Map<String, dynamic>
          : raw as Map<String, dynamic>;
      if (map['type'] != 'payment_update') return null;
      final rawPayments = (map['payments'] as List?) ?? const [];
      final payments = rawPayments
          .map(OverlayPaymentEntry.tryParse)
          .whereType<OverlayPaymentEntry>()
          .toList();
      return OverlayPaymentUpdate(
        todayCount: map['todayCount'] as int,
        todayTotal: (map['todayTotal'] as num).toDouble(),
        payments: payments,
      );
    } catch (_) {
      return null;
    }
  }
}

// Collapsed bubble is sized like a normal home-screen app icon.
const double _bubbleSize = 60;

// The actual on-screen footprint of the collapsed bubble, including the
// badge/ping-ring/dismiss-affordance that render outside the core circle
// (see _Bubble's SizedBox below) -- this, not _bubbleSize, is what the
// native window needs to fit.
const double kOverlayCollapsedContentSize = _bubbleSize + 26; // 86

// Peak scale the one-shot "ping" ring animation transform-scales up to
// (see _ringScale in _PaymentOverlayAppState). Shared here so the window
// sizing math (kOverlayCollapsedRingOvershoot below) can never silently
// drift out of sync with the animation that actually needs the room.
const double _ringMaxScale = 2.4;

// How far (in logical px, per side) the ping ring paints beyond
// kOverlayCollapsedContentSize at its peak scale. The ring itself is
// _bubbleSize wide, so at _ringMaxScale it's `_bubbleSize * _ringMaxScale`
// wide -- centered, so it overshoots the content box by half the
// difference on each side.
const double kOverlayCollapsedRingOvershoot =
    (_bubbleSize * _ringMaxScale - kOverlayCollapsedContentSize) / 2; // ~35

/// The default "home" position for the collapsed bubble: bottom-right
/// corner with a margin, in physical pixels (clear of the nav bar). Both
/// the main-app side (sets this as the overlay's initial `startPosition`)
/// and the overlay isolate itself (which owns dragging from here on, and
/// deliberately never reads position back from the plugin -- see the
/// dragging note in _PaymentOverlayAppState) compute this the same way
/// from the same screen size, so they always agree without needing to
/// pass the value between isolates.
Offset defaultBubbleAnchorPx(
    Size screenPhysicalPx, int collapsedSizePx, double devicePixelRatio,
    {double marginDp = 20}) {
  final marginPx = marginDp * devicePixelRatio;
  final x = screenPhysicalPx.width - collapsedSizePx - marginPx;
  final y = screenPhysicalPx.height -
      collapsedSizePx -
      marginPx * 4; // clear of the nav bar
  return Offset(x < 0 ? 0 : x, y < 0 ? 0 : y);
}

/// Where the expanded detail panel always opens, regardless of wherever
/// the collapsed bubble was last dragged to -- bottom-right with a margin,
/// same idea as the bubble's anchor but sized for the panel. Requested
/// explicitly: the panel should be easy to find and read every time, not
/// pop up wherever a tiny dragged bubble happens to be (which could be
/// anywhere, including hard-to-reach corners).
Offset panelAnchorPx(Size screenPhysicalPx, int panelWidthPx, int panelHeightPx,
    double devicePixelRatio,
    {double marginDp = 12}) {
  final marginPx = marginDp * devicePixelRatio;
  final x = screenPhysicalPx.width - panelWidthPx - marginPx;
  final y = screenPhysicalPx.height - panelHeightPx - marginPx * 4;
  return Offset(x < 0 ? 0 : x, y < 0 ? 0 : y);
}

Size centeredPanelSizePx(Size screenPhysicalPx) {
  final widthPx = (screenPhysicalPx.width * 0.9).round();
  final heightPx = (screenPhysicalPx.height / 3).round();
  return Size(widthPx.toDouble(), heightPx.toDouble());
}

Offset centeredPanelAnchorPx(
    Size screenPhysicalPx, int panelWidthPx, int panelHeightPx) {
  final x = (screenPhysicalPx.width - panelWidthPx) / 2;
  final y = (screenPhysicalPx.height - panelHeightPx) / 2;
  return Offset(x < 0 ? 0 : x, y < 0 ? 0 : y);
}

// `flutter_overlay_window` sizes its native Android window in raw physical
// pixels, while every widget above is laid out in logical pixels. Using a
// fixed pixel guess (the old code used 160-170px collapsed / 320x460px
// expanded) works only on the one density it was eyeballed on -- on higher
// density phones the real content is bigger than the window, so parts of
// it (the counter badge, the dismiss "x", the ping ring) get drawn *outside*
// the window's actual bounds. Android never delivers touches outside a
// window's bounds to that window, so those parts silently stop being
// tappable and can look like they're "off-screen" even though they're
// visually still there. Converting through the device's own pixel ratio
// (plus a safety margin) keeps the native window exactly as big as what's
// actually drawn into it, on any device.
//
// The safety margin has two parts:
//  - [marginPx]: a small flat allowance for shadow bleed (blur/spread on
//    the bubble's boxShadow), which doesn't scale with anything -- it's
//    just soft pixels around the edge.
//  - [logicalOvershoot]: extra *logical* content that paints outside the
//    nominal `logicalSize` box, e.g. the ping-ring animation, which
//    transform-scales up to `_ringMaxScale` (2.4x) of `_bubbleSize` --
//    nearly 60% wider than the 86dp content box it lives in. This has to
//    be converted through devicePixelRatio just like the base size,
//    otherwise it under-shoots on exactly the high-density devices where
//    it matters most. Omitting this term is what let the ring (and, once
//    dragged near an edge, the touch target itself) get silently clipped
//    by the native window -- looking like a visual "overflow" glitch and,
//    separately, like the bubble going unresponsive/disappearing mid-drag.
//
// [maxPx], when provided, hard-clamps the result. This overlay never has
// a legitimate reason to be bigger than the screen it floats on --
// clamping is a safety net so a bad computation can never ask
// WindowManager to allocate a buffer larger than the display (which is a
// way to crash the compositor outright instead of failing gracefully).
int overlayPhysicalPx(double logicalSize, double devicePixelRatio,
    {double marginPx = 28, double logicalOvershoot = 0, int? maxPx}) {
  final safeMargin = marginPx + logicalOvershoot * devicePixelRatio;
  final raw = (logicalSize * devicePixelRatio + safeMargin).round();
  if (maxPx == null) return raw;
  return raw > maxPx ? maxPx : raw;
}

const _brandGreen = Color(0xFF00C766);
const _brandGreenDark = Color(0xFF00A651);

class PaymentOverlayApp extends StatefulWidget {
  const PaymentOverlayApp({super.key});

  @override
  State<PaymentOverlayApp> createState() => _PaymentOverlayAppState();
}

class _PaymentOverlayAppState extends State<PaymentOverlayApp>
    with TickerProviderStateMixin {
  bool _expanded = false;
  OverlayPaymentUpdate? _latest;
  DateTime? _lastSeenPaymentAt;

  // Badge shows payments received *since the panel was last opened*, not
  // the running total-for-today -- that's what makes it read as a real
  // "you have unread stuff" counter instead of a static daily count.
  int _unseenCount = 0;

  Ride? _activeRide;
  int _rideRidePaymentCount = 0;
  double _rideRideTotal = 0;

  final AudioPlayer _popPlayer = AudioPlayer();

  // Current collapsed-bubble "home" position, in physical pixels. Seeded
  // to the exact same bottom-right anchor the launcher (overlay_service.
  // dart) used as the window's startPosition -- both sides compute it
  // from the same formula/screen size, so they agree without either one
  // needing to ask the plugin what the current position actually is.
  //
  // Deliberately never calling FlutterOverlayWindow.getOverlayPosition()
  // anywhere in this file: dragging is entirely tracked here in Dart by
  // accumulating pan deltas, which is both simpler and sidesteps ever
  // needing to trust a read-back position from the plugin.
  late Offset _bubblePos;
  late Size _screenPx;
  late double _dpr;
  late int _collapsedSizePx;
  late int _expandedWidthPx;
  late int _expandedHeightPx;
  late double _expandedWidthLogical;
  late double _expandedHeightLogical;

  late final AnimationController
      _glowController; // continuous slow "alive" blink
  late final AnimationController
      _popController; // one-shot burst on new payment
  late final Animation<double> _popScale;
  late final Animation<double> _ringOpacity;
  late final Animation<double> _ringScale;

  final _rideManager = RideManager();
  final _dbHelper = DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();

    final view = PlatformDispatcher.instance.views.first;
    _screenPx = view.physicalSize;
    _dpr = view.devicePixelRatio;
    _collapsedSizePx = overlayPhysicalPx(kOverlayCollapsedContentSize, _dpr,
        logicalOvershoot: kOverlayCollapsedRingOvershoot,
        maxPx: _screenPx.shortestSide.round());
    _bubblePos = defaultBubbleAnchorPx(_screenPx, _collapsedSizePx, _dpr);
    final expandedSize = centeredPanelSizePx(_screenPx);
    _expandedWidthPx = expandedSize.width.round();
    _expandedHeightPx = expandedSize.height.round();
    _expandedWidthLogical = _expandedWidthPx / _dpr;
    _expandedHeightLogical = _expandedHeightPx / _dpr;

    _glowController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);

    _popController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 750));
    _popScale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.4)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 35),
      TweenSequenceItem(
          tween: Tween(begin: 1.4, end: 1.0)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 65),
    ]).animate(_popController);
    _ringOpacity = Tween<double>(begin: 0.6, end: 0.0).animate(
        CurvedAnimation(parent: _popController, curve: Curves.easeOut));
    _ringScale = Tween<double>(begin: 0.55, end: _ringMaxScale).animate(
        CurvedAnimation(parent: _popController, curve: Curves.easeOut));

    _loadActiveRide();

    FlutterOverlayWindow.overlayListener.listen((event) {
      final update = OverlayPaymentUpdate.tryParse(event);
      if (update == null || !mounted) return;

      final newest =
          update.payments.isEmpty ? null : update.payments.first.receivedAt;
      final isGenuinelyNew = newest != null &&
          (_lastSeenPaymentAt == null || newest.isAfter(_lastSeenPaymentAt!));

      setState(() => _latest = update);

      if (isGenuinelyNew) {
        _lastSeenPaymentAt = newest;
        HapticFeedback.mediumImpact();
        _popController.forward(from: 0);
        setState(() => _unseenCount++);
        _playPopSound();
        _refreshRideTotals();
      }
    });
  }

  /// Short "pop" played from inside the overlay itself the instant a new
  /// payment arrives -- distinct from (and in addition to) the system
  /// notification sound, since the overlay can be on-screen with the phone
  /// muted-for-notifications but the driver still glancing at it directly.
  Future<void> _playPopSound() async {
    try {
      await _popPlayer.stop();
      await _popPlayer.play(AssetSource('sounds/pop.wav'), volume: 0.9);
    } catch (_) {
      // Non-fatal -- the haptic buzz and visual burst already fired.
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    _popController.dispose();
    _popPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadActiveRide() async {
    final id = await _dbHelper.getActiveRideId();
    if (id == null) {
      if (mounted) setState(() => _activeRide = null);
      return;
    }
    final ride = await _rideManager.getRide(id);
    if (!mounted) return;
    setState(() => _activeRide = ride);
    await _refreshRideTotals();
  }

  Future<void> _refreshRideTotals() async {
    final ride = _activeRide;
    if (ride?.id == null) {
      if (mounted) {
        setState(() {
          _rideRidePaymentCount = 0;
          _rideRideTotal = 0;
        });
      }
      return;
    }
    final payments = await _rideManager.getPaymentsForRide(ride!.id!);
    if (!mounted) return;
    setState(() {
      _rideRidePaymentCount = payments.length;
      _rideRideTotal = payments.fold<double>(0, (sum, p) => sum + p.amount);
    });
  }

  Future<void> _toggleRide() async {
    HapticFeedback.selectionClick();
    if (_activeRide == null) {
      final phone = await _dbHelper.getSetting('driver_phone') ?? '';
      final id = await _rideManager
          .createRide(Ride(driverPhone: phone, startTime: DateTime.now()));
      await _dbHelper.setActiveRideId(id);
      await _loadActiveRide();
    } else {
      await _rideManager.endRide(_activeRide!.id!);
      await _dbHelper.setActiveRideId(null);
      setState(() => _activeRide = null);
    }
  }

  Future<void> _toggle() async {
    final next = !_expanded;
    setState(() => _expanded = next);
    if (next) {
      setState(() =>
          _unseenCount = 0); // panel opened -> those payments are now "seen"
    }

    if (next) {
      // Expanding: always resize and move to the centered panel slot,
      // regardless of where the collapsed bubble was dragged.
      final anchor =
          centeredPanelAnchorPx(_screenPx, _expandedWidthPx, _expandedHeightPx);
      await FlutterOverlayWindow.moveOverlay(
          OverlayPosition(anchor.dx, anchor.dy));
      await FlutterOverlayWindow.resizeOverlay(
          _expandedWidthPx, _expandedHeightPx, false);
    } else {
      // Collapsing: shrink back down and return to wherever the driver
      // last dragged the bubble to (its "home"), not back to the default
      // corner -- the point of letting it be draggable is that it stays
      // put where they left it.
      await FlutterOverlayWindow.resizeOverlay(
          _collapsedSizePx, _collapsedSizePx, true);
      await FlutterOverlayWindow.moveOverlay(
          OverlayPosition(_bubblePos.dx, _bubblePos.dy));
    }
  }

  /// Drags the collapsed bubble anywhere on screen. Position is tracked
  /// entirely here by accumulating pan deltas (converted to physical
  /// pixels) rather than ever reading the window's position back from the
  /// plugin -- see the field doc on [_bubblePos] for why. Clamped to stay
  /// fully on-screen so it can never be dragged out of reach.
  void _onBubblePanUpdate(DragUpdateDetails details) {
    final dx = details.delta.dx * _dpr;
    final dy = details.delta.dy * _dpr;
    final maxX = _screenPx.width - _collapsedSizePx;
    final maxY = _screenPx.height - _collapsedSizePx;

    double nextX = _bubblePos.dx + dx;
    double nextY = _bubblePos.dy + dy;
    if (nextX < 0) nextX = 0;
    if (maxX > 0 && nextX > maxX) nextX = maxX;
    if (nextY < 0) nextY = 0;
    if (maxY > 0 && nextY > maxY) nextY = maxY;

    _bubblePos = Offset(nextX, nextY);
    FlutterOverlayWindow.moveOverlay(OverlayPosition(nextX, nextY));
  }

  Future<void> _closeCompletely() => FlutterOverlayWindow.closeOverlay();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        color: Colors.transparent,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child)),
          child: _expanded
              ? _GlassCard(
                  key: const ValueKey('expanded'),
                  width: _expandedWidthLogical,
                  height: _expandedHeightLogical,
                  update: _latest,
                  activeRide: _activeRide,
                  ridePaymentCount: _rideRidePaymentCount,
                  rideTotal: _rideRideTotal,
                  onCollapse: _toggle,
                  onClose: _closeCompletely,
                  onToggleRide: _toggleRide,
                )
              : GestureDetector(
                  key: const ValueKey('collapsed'),
                  onTap: _toggle,
                  onPanUpdate: _onBubblePanUpdate,
                  child: _Bubble(
                    unseenCount: _unseenCount,
                    rideActive: _activeRide != null,
                    glow: _glowController,
                    popScale: _popScale,
                    ringOpacity: _ringOpacity,
                    ringScale: _ringScale,
                    onClose: _closeCompletely,
                  ),
                ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.unseenCount,
    required this.rideActive,
    required this.glow,
    required this.popScale,
    required this.ringOpacity,
    required this.ringScale,
    required this.onClose,
  });

  final int unseenCount;
  final bool rideActive;
  final Animation<double> glow;
  final Animation<double> popScale;
  final Animation<double> ringOpacity;
  final Animation<double> ringScale;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final count = unseenCount;
    return SizedBox(
      width: _bubbleSize + 26,
      height: _bubbleSize + 26,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // One-shot expanding "ping" ring on a fresh payment.
          AnimatedBuilder(
            animation: Listenable.merge([ringOpacity, ringScale]),
            builder: (context, _) => Opacity(
              opacity: ringOpacity.value,
              child: Transform.scale(
                scale: ringScale.value,
                child: Container(
                  width: _bubbleSize,
                  height: _bubbleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _brandGreen, width: 3),
                  ),
                ),
              ),
            ),
          ),
          // Continuous, clearly-visible "alive" blink -- a fast breathing
          // glow ring plus a pulsing halo, so the bubble reads as active
          // even with zero new payments (not just a flat circle).
          AnimatedBuilder(
            animation: Listenable.merge([glow, popScale]),
            builder: (context, child) {
              final glowValue = glow.value;
              return Transform.scale(
                scale: popScale.value,
                child: Container(
                  width: _bubbleSize,
                  height: _bubbleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                        color: Colors.white.withOpacity(0.5), width: 2),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4)),
                      BoxShadow(
                        color: _brandGreen.withOpacity(0.35 + glowValue * 0.5),
                        blurRadius: 14 + glowValue * 16,
                        spreadRadius: 1 + glowValue * 4,
                      ),
                    ],
                  ),
                  child: child,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: rideActive
                  ? const Icon(Icons.local_taxi_rounded,
                      color: _brandGreenDark, size: 30)
                  : const AppLogo(size: 44),
            ),
          ),
          if (count > 0)
            Positioned(
              right: 4,
              top: 4,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1.0),
                duration: const Duration(milliseconds: 260),
                curve: Curves.elasticOut,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30),
                    shape: count > 9 ? BoxShape.rectangle : BoxShape.circle,
                    borderRadius: count > 9 ? BorderRadius.circular(12) : null,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black38,
                          blurRadius: 5,
                          offset: Offset(0, 1))
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1),
                  ),
                ),
              ),
            ),
          // Always-visible dismiss affordance -- tapping removes the bubble
          // entirely, no need to expand first.
          Positioned(
            left: 2,
            bottom: 2,
            child: GestureDetector(
              onTap: onClose,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withOpacity(0.7), width: 1),
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The expanded panel: frosted "glass" look (translucent + blurred
/// background) so it stays visually light and stays legible over whatever
/// app is underneath, rather than a big opaque card.
class _GlassCard extends StatelessWidget {
  const _GlassCard({
    super.key,
    required this.width,
    required this.height,
    required this.update,
    required this.activeRide,
    required this.ridePaymentCount,
    required this.rideTotal,
    required this.onCollapse,
    required this.onClose,
    required this.onToggleRide,
  });

  final double width;
  final double height;
  final OverlayPaymentUpdate? update;
  final Ride? activeRide;
  final int ridePaymentCount;
  final double rideTotal;
  final VoidCallback onCollapse;
  final VoidCallback onClose;
  final VoidCallback onToggleRide;

  @override
  Widget build(BuildContext context) {
    final payments = update?.payments ?? const <OverlayPaymentEntry>[];

    // Deliberately NOT using BackdropFilter/ImageFilter.blur here. A real
    // backdrop blur needs to sample and blur the framebuffer behind this
    // widget every frame (a saveLayer + blur pass), which is expensive even
    // in a normal app screen -- and this panel doesn't render in a normal
    // app screen. `flutter_overlay_window` runs it in a second, minimal
    // Flutter engine composited directly into a small system
    // TYPE_APPLICATION_OVERLAY surface, which is a much more constrained
    // GPU/buffer environment than the main Activity's window. That's
    // exactly what the repeated native "gralloc4: Format allocation info
    // not found" buffer failures right before the crash point to, followed
    // by the window suddenly demanding a buffer far bigger than the entire
    // screen. A layered semi-transparent gradient gives essentially the
    // same "frosted glass" look at a fraction of the cost, with no
    // framebuffer sampling at all, and can't trigger this failure mode.
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF163324).withOpacity(0.94),
              const Color(0xFF0B1810).withOpacity(0.97),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.14)),
          boxShadow: const [
            BoxShadow(
                color: Colors.black45, blurRadius: 24, offset: Offset(0, 8))
          ],
        ),
        // This card is a fixed-size native overlay window, not a normal
        // scrollable screen -- there's no room to grow. The header and
        // ride-control row above the (Expanded) payment list are sized
        // for one line of text each; if the device's system font-size /
        // accessibility text scale is turned up, or a translated string
        // runs long, those two rows silently grow taller than the space
        // this fixed 440px card budgeted for them, leaving the Expanded
        // list with negative height -- which is exactly what threw the
        // "RenderFlex overflowed" banner the instant the panel opened.
        // Clamping the scale here (and capping every label to one line
        // below) keeps this specific compact widget's layout predictable
        // regardless of the user's OS text-size setting -- it doesn't
        // affect text size anywhere else in the app.
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.0)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(update: update, onCollapse: onCollapse, onClose: onClose),
              _RideControl(
                activeRide: activeRide,
                paymentCount: ridePaymentCount,
                total: rideTotal,
                onToggleRide: onToggleRide,
              ),
              const Divider(
                  height: 1, color: Colors.white24, indent: 16, endIndent: 16),
              Expanded(
                child: payments.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No payments yet.\nThey\'ll show up here the moment they arrive.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: payments.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1, color: Colors.white12, indent: 56),
                        itemBuilder: (context, index) => _StaggeredListItem(
                            index: index,
                            child: _PaymentRow(entry: payments[index])),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.update, required this.onCollapse, required this.onClose});
  final OverlayPaymentUpdate? update;
  final VoidCallback onCollapse;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final u = update;
    return GestureDetector(
      onTap: onCollapse,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _brandGreen.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.payments_rounded,
                  color: _brandGreen, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    u == null
                        ? 'Telebirr payments'
                        : '${u.todayTotal.toStringAsFixed(0)} ETB today',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                  Text(
                    u == null
                        ? 'Waiting for payments…'
                        : '${u.todayCount} payment${u.todayCount == 1 ? '' : 's'} received',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onClose,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RideControl extends StatefulWidget {
  const _RideControl({
    required this.activeRide,
    required this.paymentCount,
    required this.total,
    required this.onToggleRide,
  });

  final Ride? activeRide;
  final int paymentCount;
  final double total;
  final VoidCallback onToggleRide;

  @override
  State<_RideControl> createState() => _RideControlState();
}

class _RideControlState extends State<_RideControl> {
  @override
  Widget build(BuildContext context) {
    final active = widget.activeRide != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: widget.onToggleRide,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: active
                        ? [Colors.redAccent.shade200, Colors.redAccent.shade400]
                        : [_brandGreen, _brandGreenDark],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: (active ? Colors.red : _brandGreen)
                            .withOpacity(0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(active ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      active ? 'End ride' : 'Start ride',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (active) ...[
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${widget.paymentCount} this ride',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                Text(
                  '${widget.total.toStringAsFixed(0)} ETB',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _brandGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StaggeredListItem extends StatefulWidget {
  const _StaggeredListItem({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_StaggeredListItem> createState() => _StaggeredListItemState();
}

class _StaggeredListItemState extends State<_StaggeredListItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    final delay = Duration(milliseconds: 30 * widget.index.clamp(0, 10));
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child));
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.entry});
  final OverlayPaymentEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: _brandGreen.withOpacity(0.18), shape: BoxShape.circle),
            child: const Icon(Icons.arrow_downward_rounded,
                color: _brandGreen, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '+${entry.amount.toStringAsFixed(0)} ETB',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _brandGreen),
                ),
                Text(
                  entry.payerName != null
                      ? '${entry.payerName} · ${entry.payerPhone}'
                      : entry.payerPhone,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(_timeAgo(entry.receivedAt),
              style: const TextStyle(fontSize: 11, color: Colors.white38)),
        ],
      ),
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
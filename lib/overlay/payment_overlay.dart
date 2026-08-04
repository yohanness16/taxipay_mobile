import 'dart:async';
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

// ---------------------------------------------------------------------------
// UNITS -- read this before touching any geometry below.
//
// `flutter_overlay_window` is NOT self-consistent about the units its
// three sizing/positioning APIs take, and getting this wrong is what broke
// the overlay:
//
//   * showOverlay(width:, height:)  -> RAW PHYSICAL PIXELS. The native side
//     assigns them straight into WindowManager.LayoutParams, which is a
//     pixel API. No conversion happens.
//   * resizeOverlay(width, height)  -> LOGICAL DP. The native side runs
//     dpToPx() on both values before storing them.
//   * moveOverlay(OverlayPosition) -> LOGICAL DP. Same -- native runs
//     dpToPx() on x and y.
//
// (See OverlayService.java: `params.width = dpToPx(width)` in
// resizeOverlay/moveOverlay, versus `new WindowManager.LayoutParams(
// WindowSetup.width, ...)` used verbatim for showOverlay.)
//
// This file used to pass physical pixels to all three. For resize/move
// that means the value gets multiplied by the display density a *second*
// time: on a 2.8x-density phone a 240px window asks to become 672px, and
// the expanded panel asks WindowManager for a buffer several times larger
// than the whole display -- which is what crashed the native compositor,
// and what flung the bubble off-screen on the first drag.
//
// Rule from here on: every geometry value in this file is in **dp**, and
// the only place physical pixels appear is [overlayPhysicalPx], used
// solely to feed showOverlay.
// ---------------------------------------------------------------------------

// Collapsed bubble is sized like a normal home-screen app icon.
const double _bubbleSize = 60;

// The on-screen footprint of the collapsed bubble's core content, including
// the badge and dismiss affordance that render outside the circle itself
// (see _Bubble's SizedBox below).
const double kOverlayCollapsedContentSize = _bubbleSize + 26; // 86 dp

// Peak scale the one-shot "ping" ring animation transform-scales up to
// (see _ringScale in _PaymentOverlayAppState). Shared here so the window
// sizing math can never silently drift out of sync with the animation that
// actually needs the room.
const double _ringMaxScale = 2.4;

// How far (dp, per side) the ping ring paints beyond the content box at its
// peak scale. The ring is _bubbleSize wide, so at _ringMaxScale it is
// `_bubbleSize * _ringMaxScale` wide -- centered, so it overshoots the
// content box by half the difference on each side.
const double kOverlayCollapsedRingOvershoot =
    (_bubbleSize * _ringMaxScale - kOverlayCollapsedContentSize) / 2; // ~35 dp

/// Total size (dp) the collapsed overlay window needs so the bubble, its
/// unread badge, the dismiss affordance and the ping ring at peak scale all
/// fit inside the window's real bounds. Anything drawn outside those bounds
/// is not just clipped -- Android never delivers touches there either, which
/// is what made parts of the bubble silently stop responding.
const double kOverlayCollapsedWindowDp =
    kOverlayCollapsedContentSize + kOverlayCollapsedRingOvershoot * 2; // ~156

/// The default "home" position (dp, from the top-left of the screen) for the
/// collapsed bubble: bottom-right corner, held clear of the nav bar. The
/// launcher (overlay_service.dart) passes this as the window's
/// `startPosition` and the overlay isolate seeds its own drag tracking from
/// the same function, so the two always agree without passing anything
/// between isolates.
Offset defaultBubbleAnchorDp(Size screenDp, double windowDp,
    {double marginDp = 12}) {
  final x = screenDp.width - windowDp - marginDp;
  final y = screenDp.height - windowDp - marginDp * 6; // clear of the nav bar
  return Offset(x < 0 ? 0 : x, y < 0 ? 0 : y);
}

/// Size (dp) of the expanded detail panel. Height is clamped so the panel
/// stays readable on short screens without ever growing taller than the
/// display it floats on.
Size centeredPanelSizeDp(Size screenDp) {
  final width = screenDp.width * 0.92;
  var height = screenDp.height / 2.6;
  if (height < 260) height = 260;
  if (height > 420) height = 420;
  final maxHeight = screenDp.height - 80;
  if (maxHeight > 0 && height > maxHeight) height = maxHeight;
  return Size(width, height);
}

/// Where the expanded panel opens (dp, from the top-left of the screen):
/// dead centre, regardless of wherever the collapsed bubble was dragged to.
/// The panel should be easy to find and read every time, not pop up in
/// whatever hard-to-reach corner a tiny dragged bubble happened to land in.
Offset centeredPanelAnchorDp(Size screenDp, Size panelDp) {
  final x = (screenDp.width - panelDp.width) / 2;
  final y = (screenDp.height - panelDp.height) / 2;
  return Offset(x < 0 ? 0 : x, y < 0 ? 0 : y);
}

/// Converts a dp measurement to the physical pixels `showOverlay` expects.
///
/// [maxPx], when provided, hard-clamps the result. This overlay never has a
/// legitimate reason to be bigger than the screen it floats on -- clamping
/// is a safety net so a bad computation can never ask WindowManager to
/// allocate a buffer larger than the display (a way to crash the compositor
/// outright rather than fail gracefully).
int overlayPhysicalPx(double dp, double devicePixelRatio, {int? maxPx}) {
  final raw = (dp * devicePixelRatio).round();
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
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

  // Current collapsed-bubble "home" position, in **dp** from the top-left
  // of the screen. Seeded from the same [defaultBubbleAnchorDp] the
  // launcher (overlay_service.dart) passes as the window's startPosition,
  // so both sides agree without either needing to ask the plugin where the
  // window actually is.
  //
  // Deliberately never calling FlutterOverlayWindow.getOverlayPosition()
  // anywhere in this file: dragging is tracked here in Dart by
  // accumulating pan deltas, which is simpler and sidesteps ever needing
  // to trust a read-back position from the plugin.
  late Offset _bubblePosDp;
  late Size _screenDp;
  late double _dpr;
  late Size _panelDp;

  late final AnimationController
      _glowController; // continuous slow "alive" blink
  late final AnimationController
      _popController; // one-shot burst on new payment
  late final Animation<double> _popScale;
  late final Animation<double> _ringOpacity;
  late final Animation<double> _ringScale;

  final _rideManager = RideManager();
  final _dbHelper = DatabaseHelper.instance;

  // Held so it can be cancelled in dispose(). Without this the handler
  // outlives the State it closes over: a payment arriving after teardown
  // calls setState on a disposed State and throws.
  StreamSubscription<dynamic>? _overlaySub;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();

    final view = PlatformDispatcher.instance.views.first;
    _dpr = view.devicePixelRatio;
    _screenDp = view.physicalSize / _dpr;
    _bubblePosDp = defaultBubbleAnchorDp(_screenDp, kOverlayCollapsedWindowDp);
    _panelDp = centeredPanelSizeDp(_screenDp);
    WidgetsBinding.instance.addObserver(this);

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
    _loadTodaySoFar();

    // The overlay's contents are refreshed by pushes from the main app,
    // but two things go stale on their own with no push to trigger them:
    // the relative "2m ago" stamps, and the active-ride state (which the
    // driver can change from the main app's UI while the bubble is up).
    // A slow tick covers both without meaningfully costing anything.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {}); // re-render the relative timestamps
      _loadActiveRide();
    });

    _overlaySub = FlutterOverlayWindow.overlayListener.listen((event) {
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

  /// Seeds the panel with the day's payments already on record.
  ///
  /// The overlay is otherwise fed exclusively by pushes from the main app,
  /// which only happen when a *new* payment SMS arrives. Starting the
  /// bubble halfway through a shift therefore showed "Waiting for
  /// payments…" and an empty list on top of a day that already had plenty
  /// of them, until the next one happened to land. The overlay isolate has
  /// its own DB access, so it can just read the current state itself.
  ///
  /// Deliberately does not touch [_unseenCount] or fire the pop/haptic:
  /// these payments are pre-existing, not new arrivals. [_lastSeenPaymentAt]
  /// is primed from the newest one so the first real push afterwards is
  /// correctly recognised as new.
  Future<void> _loadTodaySoFar() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final payments = await _rideManager.getAllPayments(from: startOfDay);
      if (!mounted || payments.isEmpty) return;

      // Already newest-first (getAllPayments orders by received_at DESC).
      final entries = payments
          .take(30)
          .map((p) => OverlayPaymentEntry(
                amount: p.amount,
                payerPhone: p.payerPhone,
                payerName: p.payerName,
                receivedAt: p.receivedAt,
              ))
          .toList();

      setState(() {
        _latest = OverlayPaymentUpdate(
          todayCount: payments.length,
          todayTotal: payments.fold<double>(0, (sum, p) => sum + p.amount),
          payments: entries,
        );
        _lastSeenPaymentAt = entries.first.receivedAt;
      });
    } catch (_) {
      // Non-fatal: the overlay still works, it just starts empty and
      // fills in from the next push.
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _overlaySub?.cancel();
    _refreshTimer?.cancel();
    _glowController.dispose();
    _popController.dispose();
    _popPlayer.dispose();
    super.dispose();
  }

  /// Screen metrics were captured once in initState, which is wrong the
  /// moment the device rotates or enters split-screen: the drag clamp
  /// would keep the bubble inside the *old* bounds (stranding it
  /// off-screen, or refusing to let it reach part of the new screen), and
  /// the expanded panel would be sized and centred for the old geometry.
  ///
  /// Re-derive everything from the new metrics, re-clamp the bubble into
  /// the new bounds, and re-apply whichever layout is currently showing.
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;

    final view = PlatformDispatcher.instance.views.first;
    final dpr = view.devicePixelRatio;
    final screenDp = view.physicalSize / dpr;
    if (screenDp.width <= 0 || screenDp.height <= 0) return;
    if (screenDp == _screenDp && dpr == _dpr) return;

    _dpr = dpr;
    _screenDp = screenDp;

    final maxX = screenDp.width - kOverlayCollapsedWindowDp;
    final maxY = screenDp.height - kOverlayCollapsedWindowDp;
    _bubblePosDp = Offset(
      _bubblePosDp.dx.clamp(0.0, maxX > 0 ? maxX : 0.0),
      _bubblePosDp.dy.clamp(0.0, maxY > 0 ? maxY : 0.0),
    );

    setState(() => _panelDp = centeredPanelSizeDp(screenDp));
    _applyCurrentWindowGeometry();
  }

  /// Pushes the window size/position that matches the current expanded or
  /// collapsed state. Shared by [_toggle] and [didChangeMetrics] so the two
  /// can never drift apart.
  Future<void> _applyCurrentWindowGeometry() async {
    if (_expanded) {
      // Resize first, then move -- moving a window that is about to change
      // size just gets re-anchored by the resize, so the order matters.
      //
      // The trailing `false` is resizeOverlay's `enableDrag` flag, and it
      // must stay false: natively it assigns straight into
      // WindowSetup.enableDrag, re-arming the plugin's own drag handler
      // that overlay_service.dart deliberately disabled at showOverlay time.
      await FlutterOverlayWindow.resizeOverlay(
          _panelDp.width.round(), _panelDp.height.round(), false);
      final anchor = centeredPanelAnchorDp(_screenDp, _panelDp);
      await FlutterOverlayWindow.moveOverlay(
          OverlayPosition(anchor.dx, anchor.dy));
    } else {
      await FlutterOverlayWindow.resizeOverlay(
          kOverlayCollapsedWindowDp.round(),
          kOverlayCollapsedWindowDp.round(),
          false);
      await FlutterOverlayWindow.moveOverlay(
          OverlayPosition(_bubblePosDp.dx, _bubblePosDp.dy));
    }
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
    setState(() {
      _expanded = next;
      // Panel opened -> those payments are now "seen".
      if (next) _unseenCount = 0;
    });
    // Expanding always resizes and moves to the centred panel slot,
    // regardless of where the collapsed bubble was dragged. Collapsing
    // returns to wherever the driver last dragged the bubble to (its
    // "home"), not the default corner -- the point of letting it be
    // draggable is that it stays put where they left it.
    await _applyCurrentWindowGeometry();
  }

  /// Drags the collapsed bubble anywhere on screen. Position is tracked
  /// entirely here by accumulating pan deltas rather than ever reading the
  /// window's position back from the plugin -- see the field doc on
  /// [_bubblePosDp] for why. Pan deltas are already in dp, which is exactly
  /// what moveOverlay wants, so no conversion is applied. Clamped to stay
  /// fully on-screen so it can never be dragged out of reach.
  void _onBubblePanUpdate(DragUpdateDetails details) {
    final maxX = _screenDp.width - kOverlayCollapsedWindowDp;
    final maxY = _screenDp.height - kOverlayCollapsedWindowDp;

    double nextX = _bubblePosDp.dx + details.delta.dx;
    double nextY = _bubblePosDp.dy + details.delta.dy;
    if (nextX < 0) nextX = 0;
    if (maxX > 0 && nextX > maxX) nextX = maxX;
    if (nextY < 0) nextY = 0;
    if (maxY > 0 && nextY > maxY) nextY = maxY;

    _bubblePosDp = Offset(nextX, nextY);
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
                  width: _panelDp.width,
                  height: _panelDp.height,
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
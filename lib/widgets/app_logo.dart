import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Custom-drawn app mark, entirely vector (no bundled image asset).
///
/// Concept: this app does exactly two things -- tracks where/when a ride
/// happens, and confirms a payment landed for it. Instead of a generic
/// rounded badge with an icon inside (what most fintech-utility apps use),
/// the mark's own silhouette IS a map pin -- the ride half of the story --
/// with a bright, pulsing "confirmed payment" core where the pin's head
/// would normally just be empty -- the money half. The two ideas share one
/// shape instead of being an icon-on-a-badge.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 88, this.animate = false});

  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter()),
    );
    if (!animate) return mark;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.elasticOut,
      builder: (context, t, child) => Transform.scale(scale: t, child: Opacity(opacity: t.clamp(0, 1), child: child)),
      child: mark,
    );
  }
}

class _LogoPainter extends CustomPainter {
  /// The mark's own accent. Deliberately the brand green rather than a raw
  /// Material swatch, so the logo's ping rings and rim light match the
  /// primary used everywhere else on screen.
  static const _accent = AppTheme.primary;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final headCenter = Offset(w * 0.5, h * 0.42);
    final headRadius = w * 0.30;

    // --- Pin silhouette: a rounded head fused with a tapered point ---
    final headPath = Path()..addOval(Rect.fromCircle(center: headCenter, radius: headRadius));
    final tipPath = Path()
      ..moveTo(headCenter.dx - headRadius * 0.82, headCenter.dy + headRadius * 0.48)
      ..quadraticBezierTo(headCenter.dx - headRadius * 0.18, h * 0.92, headCenter.dx, h * 0.94)
      ..quadraticBezierTo(headCenter.dx + headRadius * 0.18, h * 0.92, headCenter.dx + headRadius * 0.82, headCenter.dy + headRadius * 0.48)
      ..close();
    final pinPath = Path.combine(PathOperation.union, headPath, tipPath);

    // Outward GPS-style ping rings, faint, centered on the pin head --
    // reads as "live"/"tracking" without needing a separate status dot.
    for (final f in [1.55, 1.3]) {
      canvas.drawCircle(
        headCenter,
        headRadius * f,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.014
          ..color = _accent.withValues(alpha: f == 1.3 ? 0.28 : 0.14),
      );
    }

    // Soft ground shadow beneath the pin's point for a touch of depth.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.945), width: w * 0.30, height: h * 0.035),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.02),
    );

    // Pin body: deep charcoal-to-black, matching the app's black/green
    // brand rather than a literal red map-pin color.
    canvas.drawPath(
      pinPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF17241D), Color(0xFF050907)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawPath(
      pinPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.022
        ..color = _accent.withValues(alpha: 0.5),
    );

    // Glass highlight across the pin's upper-left, purely additive.
    canvas.save();
    canvas.clipPath(pinPath);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h * 0.5),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, w, h * 0.5)),
    );
    canvas.restore();

    // --- Payment-pulse core, inside the pin's head ---
    final coreRadius = headRadius * 0.62;
    canvas.drawCircle(
      headCenter,
      coreRadius * 1.35,
      Paint()
        ..color = _accent.withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.045),
    );
    canvas.drawCircle(
      headCenter,
      coreRadius,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7CFFB2), AppTheme.primary],
        ).createShader(Rect.fromCircle(center: headCenter, radius: coreRadius)),
    );

    // A confirmed-payment check, not a generic bolt/chevron -- reinforces
    // "payment verified" rather than just "money" or "speed".
    final checkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF06130D);
    final checkPath = Path()
      ..moveTo(headCenter.dx - coreRadius * 0.46, headCenter.dy + coreRadius * 0.02)
      ..lineTo(headCenter.dx - coreRadius * 0.10, headCenter.dy + coreRadius * 0.40)
      ..lineTo(headCenter.dx + coreRadius * 0.52, headCenter.dy - coreRadius * 0.38);
    canvas.drawPath(checkPath, checkPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

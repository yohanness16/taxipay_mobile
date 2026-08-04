import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared building blocks so Dashboard/Rides/Expenses/Reports/History all
/// feel like one designed app instead of five screens built at different
/// times -- consistent entrance animation, icon-badge style, and empty
/// states, reused everywhere instead of re-implemented per screen.

/// Simple fade + slide-up entrance, staggered by [index] when used in a
/// list. Cheap enough to wrap around anything without measurable cost.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.delayStepMs = 45});
  final Widget child;
  final int index;
  final int delayStepMs;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppTheme.dSlow);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: AppTheme.ease));
    final delay = Duration(milliseconds: widget.delayStepMs * widget.index.clamp(0, 12));
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
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _fade, child: SlideTransition(position: _slide, child: widget.child));
}

/// Icon-in-a-tinted-circle badge, used as the leading element on nearly
/// every list row across the app so payments/rides/expenses all read the
/// same visual language.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, this.size = 40});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: context.tintedSurface(color), shape: BoxShape.circle),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Centered icon + title + subtitle for empty lists -- replaces plain
/// "No X yet" text with something that actually looks designed.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(color: context.faintFill, shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: context.faintText),
            ),
            const SizedBox(height: AppTheme.s4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppTheme.s2),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.subtleText, fontSize: 13, height: 1.45),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppTheme.s5),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Section title row with an optional trailing action -- the "Recent
/// payments · View all" pattern, generalized for reuse.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action!),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, size: 16),
              ],
            ),
          ),
      ],
    );
  }
}

/// Animated counting number -- used for the big hero earnings figure so it
/// visibly ticks up on refresh instead of just flashing to a new value.
class CountUpText extends StatelessWidget {
  const CountUpText({super.key, required this.value, required this.style, this.suffix = ''});
  final double value;
  final TextStyle style;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(value),
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 700),
      curve: AppTheme.ease,
      builder: (context, v, child) => Text('${v.toStringAsFixed(0)}$suffix', style: style),
    );
  }
}

/// A tinted "soft" card for stats and callouts -- the tinted-surface +
/// hairline-border treatment used all over the app, in one place so the
/// alpha values stay consistent (and stay legible in dark mode, where a
/// light-mode tint over black is nearly invisible).
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(AppTheme.s4),
    this.onTap,
    this.radius = AppTheme.rLg,
  });

  final Widget child;
  final Color? accent;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final a = accent;
    final bg = a == null ? (context.isDark ? AppTheme.surfaceCard : Colors.white) : context.tintedSurface(a);
    final border = a == null ? context.hairline : a.withValues(alpha: context.isDark ? 0.26 : 0.18);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Pressable wrapper that dips slightly on touch. Applied to the primary
/// tappable cards so taps feel physically acknowledged rather than only
/// producing a ripple.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.onTap, this.scale = 0.97});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: AppTheme.dFast,
        curve: AppTheme.ease,
        child: widget.child,
      ),
    );
  }
}

/// Full-width banner for a semantic message (service due, offline, pending
/// verification). Replaces the hand-rolled amber/red containers that each
/// screen used to build, which all picked slightly different alphas and
/// none of which were readable in dark mode.
class CalloutBanner extends StatelessWidget {
  const CalloutBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.accent,
    this.onTap,
  });

  final IconData icon;
  final String message;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      accent: accent,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
      radius: AppTheme.rMd,
      child: Row(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: context.isDark ? Colors.white : Colors.black87,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: accent, size: 20),
        ],
      ),
    );
  }
}

/// Shimmering placeholder block, shown while a screen's data loads instead
/// of a bare centred spinner -- keeps the layout stable so content does not
/// jump into place once it arrives.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.height = 16, this.width, this.radius = AppTheme.rSm});
  final double height;
  final double? width;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: context.faintFill.withValues(alpha: 0.4 + _controller.value * 0.5),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

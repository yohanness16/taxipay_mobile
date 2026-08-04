import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../localization/app_strings.dart';
import '../services/overlay_service.dart';
import '../services/sms_reader.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/modern_widgets.dart';
import 'main_shell.dart';

/// Shown exactly once, right after registration/first login: walks the
/// driver through every permission the app actually needs (SMS,
/// notifications, the floating overlay) up front, with a plain-language
/// reason for each -- instead of scattering permission prompts across
/// random screens later and hoping the driver says yes when surprised.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const _doneKey = 'onboarding_done';

  static Future<bool> isDone() async {
    final v = await DatabaseHelper.instance.getSetting(_doneKey);
    return v == 'true';
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with WidgetsBindingObserver {
  final _pageController = PageController();
  int _page = 0;

  bool _smsGranted = false;
  bool _notifGranted = false;
  bool _overlayGranted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  /// Granting the overlay permission sends the driver away to Android's
  /// system settings -- a separate screen this app doesn't control -- and
  /// they manually flip a toggle there before coming back. That return
  /// trip is the reliable moment to re-check, rather than depending on
  /// requestPermission()'s own future (which has been observed to just
  /// hang on some devices/OS versions, leaving the button stuck spinning
  /// forever with no way to tell it actually worked).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_overlayGranted && _steps[_page].titleKey == 'onboarding_overlay_title') {
      _refreshOverlayPermission();
    }
  }

  Future<void> _refreshOverlayPermission() async {
    final granted = await context.read<OverlayService>().isPermissionGranted();
    if (mounted && granted != _overlayGranted) {
      setState(() {
        _overlayGranted = granted;
        _busy = false; // clear a stuck spinner if requestPermission() itself never resolved
      });
    }
  }

  late final List<_Step> _steps = [
    _Step(
      icon: Icons.sms_rounded,
      titleKey: 'onboarding_sms_title',
      bodyKey: 'onboarding_sms_body',
      granted: () => _smsGranted,
      action: _requestSms,
    ),
    _Step(
      icon: Icons.notifications_active_rounded,
      titleKey: 'onboarding_notif_title',
      bodyKey: 'onboarding_notif_body',
      granted: () => _notifGranted,
      action: _requestNotifications,
    ),
    _Step(
      icon: Icons.blur_circular_rounded,
      titleKey: 'onboarding_overlay_title',
      bodyKey: 'onboarding_overlay_body',
      granted: () => _overlayGranted,
      action: _requestOverlay,
    ),
  ];

  Future<void> _requestSms() async {
    final granted = await context.read<SmsReader>().requestPermissions();
    if (!mounted) return;
    setState(() => _smsGranted = granted);
  }

  Future<void> _requestNotifications() async {
    final granted = await context.read<OverlayService>().requestNotificationPermission();
    if (!mounted) return;
    setState(() => _notifGranted = granted);
  }

  Future<void> _requestOverlay() async {
    final overlay = context.read<OverlayService>();
    try {
      // Best-effort: on devices where this resolves normally, great, we
      // catch the grant immediately. On devices where it hangs, the
      // timeout below and the app-resume check above both still catch it.
      await overlay.requestPermission().timeout(const Duration(seconds: 45));
    } catch (_) {
      // Fall through -- didChangeAppLifecycleState will pick this up the
      // moment the driver returns from the settings screen regardless.
    }
    if (!mounted) return;
    final granted = await overlay.isPermissionGranted();
    if (!mounted) return;
    setState(() => _overlayGranted = granted);
  }

  Future<void> _next() async {
    if (_page < _steps.length - 1) {
      setState(() => _page++);
      _pageController.nextPage(duration: AppTheme.dBase, curve: AppTheme.ease);
    } else {
      await _finish();
    }
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    await DatabaseHelper.instance.setSetting(OnboardingScreen._doneKey, 'true');
    if (!mounted) return;
    final overlay = context.read<OverlayService>();
    if (await overlay.isPermissionGranted()) {
      await overlay.start();
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<AppStrings>();
    final step = _steps[_page];

    // This flow is intentionally always dark — it renders before the driver
    // reaches the themed shell — so the neutrals here are pinned to the
    // dark-surface palette rather than read off the ambient brightness.
    return Scaffold(
      backgroundColor: AppTheme.surfaceDark,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF15211C), AppTheme.surfaceDark],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: AppTheme.s5),
              const FadeSlideIn(index: 0, child: AppLogo(size: 60)),
              const SizedBox(height: AppTheme.s3),
              FadeSlideIn(
                index: 1,
                child: Text(
                  'Telebirr Driver Assistant',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                ),
              ),
              const SizedBox(height: AppTheme.s5),
              FadeSlideIn(
                index: 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _steps.length,
                    (i) => AnimatedContainer(
                      duration: AppTheme.dBase,
                      curve: AppTheme.ease,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 26 : AppTheme.s2,
                      height: AppTheme.s2,
                      decoration: BoxDecoration(
                        color: i <= _page ? AppTheme.primary : Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AppTheme.s1),
                        boxShadow: i == _page
                            ? AppTheme.shadow(tint: AppTheme.primary, opacity: 0.5, blur: 8, y: 0)
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _steps.length,
                  itemBuilder: (context, i) => _StepView(step: _steps[i]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppTheme.s6, 0, AppTheme.s6, AppTheme.s8),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                if (step.granted()) {
                                  await _next();
                                  return;
                                }
                                setState(() => _busy = true);
                                await step.action();
                                if (mounted) setState(() => _busy = false);
                              },
                        child: _busy
                            ? const SizedBox(
                                height: AppTheme.s5,
                                width: AppTheme.s5,
                                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black),
                              )
                            : Text(
                                step.granted() ? strings.t('continue_label') : strings.t('allow_and_continue'),
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                    if (step.granted())
                      TextButton(
                        onPressed: _busy ? null : _next,
                        child: Text(strings.t('next'), style: const TextStyle(color: Colors.white60)),
                      )
                    else
                      TextButton(
                        onPressed: _busy ? null : _next,
                        child: Text(strings.t('skip_for_now'), style: const TextStyle(color: Colors.white38)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step {
  _Step({required this.icon, required this.titleKey, required this.bodyKey, required this.granted, required this.action});
  final IconData icon;
  final String titleKey;
  final String bodyKey;
  final bool Function() granted;
  final Future<void> Function() action;
}

class _StepView extends StatelessWidget {
  const _StepView({required this.step});
  final _Step step;

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<AppStrings>();
    return TweenAnimationBuilder<double>(
      key: ValueKey(step.titleKey),
      tween: Tween(begin: 0, end: 1),
      duration: AppTheme.dSlow,
      curve: AppTheme.ease,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * AppTheme.s4), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.s8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.22),
                    AppTheme.primaryDark.withValues(alpha: 0.06),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.18),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(step.icon, size: 44, color: AppTheme.primary),
            ),
            const SizedBox(height: AppTheme.s8),
            Text(
              strings.t(step.titleKey),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.25),
            ),
            const SizedBox(height: AppTheme.s3),
            Text(
              strings.t(step.bodyKey),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 14.5, height: 1.55),
            ),
            AnimatedSwitcher(
              duration: AppTheme.dBase,
              child: step.granted()
                  ? Padding(
                      key: const ValueKey('granted'),
                      padding: const EdgeInsets.only(top: AppTheme.s6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(AppTheme.rLg),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 18),
                            SizedBox(width: AppTheme.s2),
                            Text(
                              'Granted',
                              style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox(key: ValueKey('ungranted'), height: 0),
            ),
          ],
        ),
      ),
    );
  }
}

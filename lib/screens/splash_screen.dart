import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/subscription_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/modern_widgets.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';
import 'registration_screen.dart';
import 'subscription_payment_screen.dart';

/// Checks login + onboarding + subscription status on launch, then routes
/// to the dashboard, the onboarding permission flow, the payment lockout
/// screen, or registration -- behind a short branded intro animation.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // Let the intro animation actually play instead of instantly navigating
    // away underneath it.
    final minSplash = Future.delayed(const Duration(milliseconds: 1100));

    final auth = context.read<AuthService>();
    final loggedIn = await auth.isLoggedIn;

    await minSplash;
    if (!mounted) return;

    if (!loggedIn) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RegistrationScreen()));
      return;
    }

    final onboardingDone = await OnboardingScreen.isDone();
    if (!mounted) return;
    if (!onboardingDone) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const OnboardingScreen()));
      return;
    }

    final phone = await auth.phone;
    if (!mounted) return;
    final subscriptionManager = context.read<SubscriptionManager>();
    final snapshot = await subscriptionManager.checkSubscriptionStatus(phone!);

    if (!mounted) return;

    if (subscriptionManager.shouldLock(snapshot)) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SubscriptionPaymentScreen(snapshot: snapshot)),
      );
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
    }
  }

  @override
  Widget build(BuildContext context) {
    // The splash is a deliberate brand moment, so it stays on the dark
    // canvas in both themes (it also matches the native launch screen, so
    // there is no white flash on the way in). Everything else on it is
    // driven by the design tokens.
    return Scaffold(
      backgroundColor: AppTheme.surfaceDark,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.35),
            radius: 1.1,
            colors: [Color(0xFF17241D), AppTheme.surfaceDark, Colors.black],
            stops: [0, 0.55, 1],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 96, animate: true),
              const SizedBox(height: AppTheme.s5),
              const FadeSlideIn(
                index: 2,
                delayStepMs: 130,
                child: Text(
                  'Telebirr Driver Assistant',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.s2),
              FadeSlideIn(
                index: 3,
                delayStepMs: 130,
                child: Text(
                  'Payments. Rides. Effortless.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    letterSpacing: 0.2,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.s8),
              // A slim determinate-looking bar reads calmer than a spinner
              // for a fixed ~1s wait, and echoes the brand green.
              FadeSlideIn(
                index: 4,
                delayStepMs: 130,
                child: SizedBox(
                  width: 96,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.s1),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

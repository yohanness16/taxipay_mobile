import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/subscription_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
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
    return Scaffold(
      backgroundColor: AppTheme.surfaceDark,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 96, animate: true),
            const SizedBox(height: 20),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              builder: (context, t, child) => Opacity(opacity: t, child: child),
              child: const Text(
                'Telebirr Driver Assistant',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Payments. Rides. Effortless.',
              style: TextStyle(fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: AppTheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

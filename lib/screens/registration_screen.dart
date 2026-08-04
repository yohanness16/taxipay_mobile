import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/modern_widgets.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController(text: '+251');
  final _nameCtrl = TextEditingController();
  final _vehicleCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isLogin = false;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = context.read<AuthService>();
    try {
      if (_isLogin) {
        await auth.login(phone: _phoneCtrl.text.trim(), password: _passwordCtrl.text);
      } else {
        await auth.register(
          phone: _phoneCtrl.text.trim(),
          name: _nameCtrl.text.trim(),
          vehicleNumber: _vehicleCtrl.text.trim().isEmpty ? null : _vehicleCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      }
      if (!mounted) return;
      final onboardingDone = await OnboardingScreen.isDone();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => onboardingDone ? const MainShell() : const OnboardingScreen()),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.s6, vertical: AppTheme.s8),
            child: ConstrainedBox(
              // Keeps the form a comfortable reading width on tablets and
              // large phones instead of stretching edge to edge.
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Same mark the splash just showed, so the hand-off from
                    // launch into sign-up feels continuous.
                    const FadeSlideIn(child: Center(child: AppLogo(size: 76))),
                    const SizedBox(height: AppTheme.s5),
                    FadeSlideIn(
                      index: 1,
                      child: Text(
                        _isLogin ? 'Welcome back' : 'Create your driver account',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: AppTheme.s6),
                    FadeSlideIn(
                      index: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Phone number',
                              hintText: '+251911234567',
                              prefixIcon: Icon(Icons.phone_iphone_rounded),
                            ),
                            validator: (v) => (v == null || !RegExp(r'^\+251[97]\d{8}$').hasMatch(v))
                                ? 'Enter a valid Ethiopian number, e.g. +251911234567'
                                : null,
                          ),
                          if (!_isLogin) ...[
                            const SizedBox(height: AppTheme.s3),
                            TextFormField(
                              controller: _nameCtrl,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Full name',
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                              validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null,
                            ),
                            const SizedBox(height: AppTheme.s3),
                            TextFormField(
                              controller: _vehicleCtrl,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Vehicle number (optional)',
                                prefixIcon: Icon(Icons.directions_car_outlined),
                              ),
                            ),
                          ],
                          const SizedBox(height: AppTheme.s3),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                            ),
                            validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppTheme.s4),
                      CalloutBanner(
                        icon: Icons.error_outline_rounded,
                        message: _error!,
                        accent: AppTheme.danger,
                      ),
                    ],
                    const SizedBox(height: AppTheme.s5),
                    FadeSlideIn(
                      index: 3,
                      child: FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  // Match the filled button's own foreground so the
                                  // spinner does not vanish into the green fill.
                                  color: context.isDark ? Colors.black : Colors.white,
                                ),
                              )
                            : Text(_isLogin ? 'Log in' : 'Register (7-day free trial)'),
                      ),
                    ),
                    const SizedBox(height: AppTheme.s1),
                    FadeSlideIn(
                      index: 4,
                      child: TextButton(
                        onPressed: _loading ? null : () => setState(() => _isLogin = !_isLogin),
                        child: Text(_isLogin ? "Don't have an account? Register" : 'Already registered? Log in'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

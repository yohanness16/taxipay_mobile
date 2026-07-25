import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
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
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.local_taxi, size: 56, color: Color(0xFF00A651)),
                  const SizedBox(height: 12),
                  Text(
                    _isLogin ? 'Welcome back' : 'Create your driver account',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone number', hintText: '+251911234567'),
                    validator: (v) => (v == null || !RegExp(r'^\+251[97]\d{8}$').hasMatch(v))
                        ? 'Enter a valid Ethiopian number, e.g. +251911234567'
                        : null,
                  ),
                  if (!_isLogin) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Full name'),
                      validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _vehicleCtrl,
                      decoration: const InputDecoration(labelText: 'Vehicle number (optional)'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isLogin ? 'Log in' : 'Register (7-day free trial)'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading ? null : () => setState(() => _isLogin = !_isLogin),
                    child: Text(_isLogin ? "Don't have an account? Register" : 'Already registered? Log in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

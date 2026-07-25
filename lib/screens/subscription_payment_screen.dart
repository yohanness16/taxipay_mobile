import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../localization/app_strings.dart';
import '../services/auth_service.dart';
import '../services/subscription_manager.dart';
import '../services/subscription_payment_queue.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import 'main_shell.dart';

/// Shown whenever the subscription has lapsed (past the grace period) --
/// hard-locks the rest of the app until payment is confirmed.
///
/// Flow: the driver sends [AppConfig.monthlySubscriptionFeeEtb] to
/// [AppConfig.businessTelebirrPhone] via Telebirr, taps "I've sent it",
/// and then just waits -- the SMS confirmation Telebirr sends back is
/// picked up automatically by the same always-on listener that captures
/// ride payments, and submitted to the backend with zero further taps. A
/// manual paste box is also offered as a fallback in case auto-capture
/// isn't available (permission not granted, message arrived before the
/// app was reachable, etc).
class SubscriptionPaymentScreen extends StatefulWidget {
  const SubscriptionPaymentScreen({super.key, required this.snapshot});
  final SubscriptionSnapshot snapshot;

  @override
  State<SubscriptionPaymentScreen> createState() => _SubscriptionPaymentScreenState();
}

class _SubscriptionPaymentScreenState extends State<SubscriptionPaymentScreen> {
  final _smsController = TextEditingController();
  bool _awaiting = false;
  bool _submitting = false;
  String? _error;
  int _pendingCount = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refreshQueueState();
    // Polls locally (no extra server load beyond the flush's own network
    // calls) so the screen unlocks itself the instant the backend confirms
    // the payment, without the driver needing to tap anything again.
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) => _pollForConfirmation());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _smsController.dispose();
    super.dispose();
  }

  Future<void> _refreshQueueState() async {
    final awaiting = await SubscriptionPaymentQueue.instance.isAwaitingPayment();
    final count = await SubscriptionPaymentQueue.instance.pendingCount();
    if (!mounted) return;
    setState(() {
      _awaiting = awaiting;
      _pendingCount = count;
    });
  }

  Future<void> _pollForConfirmation() async {
    final snapshot = await SubscriptionPaymentQueue.instance.flush();
    await _refreshQueueState();
    if (snapshot != null && snapshot.paid && mounted) {
      _goToApp();
    }
  }

  void _goToApp() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
  }

  Future<void> _markSent() async {
    HapticFeedback.mediumImpact();
    await SubscriptionPaymentQueue.instance.markAwaitingPayment(AppConfig.monthlySubscriptionFeeEtb);
    await _refreshQueueState();
  }

  Future<void> _submitManualText() async {
    final text = _smsController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      final driverId = await auth.driverId;
      if (driverId == null) {
        setState(() => _error = 'Could not identify your account. Please log in again.');
        return;
      }
      await SubscriptionPaymentQueue.instance.enqueue(
        amount: AppConfig.monthlySubscriptionFeeEtb,
        smsText: text,
      );
      _smsController.clear();
      await _refreshQueueState();
      await _pollForConfirmation();
      if (mounted && !_awaiting) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Submitted -- verifying now (or as soon as you\'re back online).')),
        );
      }
    } catch (e) {
      setState(() => _error = 'Could not submit right now. It has been saved and will retry automatically.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _copyPhone() {
    Clipboard.setData(const ClipboardData(text: AppConfig.businessTelebirrPhone));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone number copied')));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<AppStrings>();
    final expires = widget.snapshot.expires;
    final expiredText = expires != null
        ? '${strings.t('subscription_expired_with_date')} ${DateFormat.yMMMd().format(expires)}.'
        : strings.t('trial_ended');

    return Scaffold(
      backgroundColor: AppTheme.surfaceDark,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
          children: [
            Center(child: const AppLogo(size: 64)),
            const SizedBox(height: 18),
            Text(
              expiredText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${strings.t('pay_to_unlock')} (${AppConfig.monthlySubscriptionFeeEtb.toStringAsFixed(0)} ETB, ${AppConfig.subscriptionDurationDays} days)',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 26),

            // Step 1: send the money.
            _GlassSection(
              step: '1',
              title: strings.t('send_payment_telebirr'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(strings.t('send_to'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            Text(
                              AppConfig.businessTelebirrPhone,
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                            ),
                            Text(AppConfig.businessTelebirrName, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _copyPhone,
                        icon: const Icon(Icons.copy_rounded, color: AppTheme.primary),
                        tooltip: 'Copy number',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Amount: ${AppConfig.monthlySubscriptionFeeEtb.toStringAsFixed(0)} ETB',
                    style: const TextStyle(color: AppTheme.primary, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Step 2: confirm, then let auto-capture do the rest.
            _GlassSection(
              step: '2',
              title: strings.t('confirm_sent'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _awaiting
                        ? 'Waiting for the Telebirr confirmation SMS -- it\'ll be verified automatically the moment it arrives, no need to do anything else.'
                        : 'Once you\'ve sent the payment, tap below. We\'ll watch for the confirmation SMS and verify it automatically.',
                    style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  if (_awaiting)
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                        ),
                        const SizedBox(width: 10),
                        Text(strings.t('watching_for_sms'), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _markSent,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(strings.t('ive_sent_payment')),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Fallback: manual paste.
            _GlassSection(
              step: '3',
              title: strings.t('paste_sms_manually'),
              subtitleColor: Colors.white38,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'If auto-detection doesn\'t work (e.g. SMS permission not granted), paste the confirmation message here.',
                    style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _smsController,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Dear ... Your transaction number is ...',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _submitting ? null : _submitManualText,
                      child: _submitting
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(strings.t('submit_for_verification')),
                    ),
                  ),
                ],
              ),
            ),

            if (_pendingCount > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.accentAmber.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accentAmber.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top_rounded, color: AppTheme.accentAmber, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_pendingCount ${strings.t('payments_pending')} -- will retry automatically when online.',
                        style: const TextStyle(color: AppTheme.accentAmber, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
            ],
          ],
        ),
      ),
    );
  }
}

class _GlassSection extends StatelessWidget {
  const _GlassSection({required this.step, required this.title, required this.child, this.subtitleColor});
  final String step;
  final String title;
  final Widget child;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                child: Text(step, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

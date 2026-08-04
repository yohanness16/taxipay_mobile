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
import '../widgets/modern_widgets.dart';
import 'main_shell.dart';

/// Shown whenever the subscription has lapsed (past the grace period) --
/// hard-locks the rest of the app until payment is confirmed.
///
/// Flow: the driver sends [AppConfig.monthlySubscriptionFeeEtb] to
/// [AppConfig.businessTelebirrPhone] via Telebirr, taps "I've sent it",
/// and then just waits -- the SMS confirmation Telebirr sends back is
/// picked up automatically by the always-on listener that captures
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

    // This screen is a deliberate dark "brand lockout" surface in both
    // themes (it follows the splash, and the amount is the only thing that
    // should draw the eye). Because the canvas is dark regardless of the
    // app's brightness, the role-based neutrals have to be resolved against
    // a dark theme -- otherwise light mode would paint near-black caption
    // text onto a near-black card. The Builder is what puts `context` below
    // this Theme so `context.subtleText` and friends see Brightness.dark.
    return Theme(
      data: AppTheme.dark(),
      child: Builder(
        builder: (context) => _buildBody(context, strings),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppStrings strings) {
    final expires = widget.snapshot.expires;
    final expiredText = expires != null
        ? '${strings.t('subscription_expired_with_date')} ${DateFormat.yMMMd().format(expires)}.'
        : strings.t('trial_ended');
    // Always read the price from config -- never hardcode the figure.
    final fee = AppConfig.monthlySubscriptionFeeEtb.toStringAsFixed(0);
    final days = AppConfig.subscriptionDurationDays;

    return Scaffold(
      backgroundColor: AppTheme.surfaceDark,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppTheme.s5, AppTheme.s8, AppTheme.s5, AppTheme.s8),
          children: [
            const FadeSlideIn(child: Center(child: AppLogo(size: 64))),
            const SizedBox(height: AppTheme.s5),
            FadeSlideIn(
              index: 1,
              child: Text(
                expiredText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(height: AppTheme.s2),
            FadeSlideIn(
              index: 2,
              child: Text(
                '${strings.t('pay_to_unlock')} ($fee ETB, $days days)',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.subtleText, fontSize: 13.5, height: 1.4),
              ),
            ),
            const SizedBox(height: AppTheme.s6),

            // Step 1: send the money.
            FadeSlideIn(
              index: 3,
              child: _StepSection(
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
                              Text(
                                strings.t('send_to'),
                                style: TextStyle(color: context.faintText, fontSize: 12),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                AppConfig.businessTelebirrPhone,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                AppConfig.businessTelebirrName,
                                style: TextStyle(color: context.faintText, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _copyPhone,
                          icon: const Icon(Icons.copy_rounded, color: AppTheme.primary),
                          tooltip: 'Copy number',
                          style: IconButton.styleFrom(
                            backgroundColor: context.tintedSurface(AppTheme.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.rSm),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.s3),
                    // The amount, given its own tinted plate so it reads as
                    // the one number that matters on the screen.
                    SoftCard(
                      accent: AppTheme.primary,
                      radius: AppTheme.rMd,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.s3,
                        vertical: AppTheme.s2,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.payments_rounded, color: AppTheme.primary, size: 18),
                          const SizedBox(width: AppTheme.s2),
                          Text(
                            'Amount: $fee ETB',
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.s4),

            // Step 2: confirm, then let auto-capture do the rest.
            FadeSlideIn(
              index: 4,
              child: _StepSection(
                step: '2',
                title: strings.t('confirm_sent'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _awaiting
                          ? 'Waiting for the Telebirr confirmation SMS -- it\'ll be verified automatically the moment it arrives, no need to do anything else.'
                          : 'Once you\'ve sent the payment, tap below. We\'ll watch for the confirmation SMS and verify it automatically.',
                      style: TextStyle(color: context.subtleText, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: AppTheme.s3),
                    if (_awaiting)
                      Row(
                        children: [
                          const SizedBox(
                            width: AppTheme.s4,
                            height: AppTheme.s4,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                          ),
                          const SizedBox(width: AppTheme.s3),
                          Expanded(
                            child: Text(
                              strings.t('watching_for_sms'),
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
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
            ),
            const SizedBox(height: AppTheme.s4),

            // Fallback: manual paste.
            FadeSlideIn(
              index: 5,
              child: _StepSection(
                step: '3',
                title: strings.t('paste_sms_manually'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'If auto-detection doesn\'t work (e.g. SMS permission not granted), paste the confirmation message here.',
                      style: TextStyle(color: context.faintText, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: AppTheme.s3),
                    TextField(
                      controller: _smsController,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                      decoration: InputDecoration(
                        hintText: 'Dear ... Your transaction number is ...',
                        hintStyle: TextStyle(color: context.faintText, fontSize: 13),
                        filled: true,
                        fillColor: context.faintFill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.rSm),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.rSm),
                          borderSide: BorderSide(color: context.hairline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.rSm),
                          borderSide: const BorderSide(color: AppTheme.primary, width: 1.6),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.s3),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _submitting ? null : _submitManualText,
                        child: _submitting
                            ? const SizedBox(
                                height: AppTheme.s4,
                                width: AppTheme.s4,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(strings.t('submit_for_verification')),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Was a hand-rolled amber container; CalloutBanner is the same
            // treatment with the design system's alphas.
            if (_pendingCount > 0) ...[
              const SizedBox(height: AppTheme.s4),
              CalloutBanner(
                icon: Icons.hourglass_top_rounded,
                message: '$_pendingCount ${strings.t('payments_pending')} -- will retry automatically when online.',
                accent: AppTheme.accentAmber,
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: AppTheme.s4),
              CalloutBanner(
                icon: Icons.error_outline_rounded,
                message: _error!,
                accent: AppTheme.danger,
              ),
            ],

            const SizedBox(height: AppTheme.s5),
          ],
        ),
      ),
    );
  }
}

/// A dark card with a numbered step medallion in its header. Same visual
/// role as before, now built on [SoftCard] so the surface/border treatment
/// matches every other card in the app.
class _StepSection extends StatelessWidget {
  const _StepSection({required this.step, required this.title, required this.child});
  final String step;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                child: Text(
                  step,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.s3),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.s3),
          child,
        ],
      ),
    );
  }
}

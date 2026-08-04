import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/payment.dart';
import '../services/ride_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_widgets.dart';

enum _Filter { all, week, month }

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  List<Payment> _payments = [];
  bool _loading = true;
  _Filter _filter = _Filter.all;

  Future<void> _callPayer(String phone) async {
    if (phone == 'Unknown') return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    DateTime? from;
    final now = DateTime.now();
    if (_filter == _Filter.week) {
      from = now.subtract(const Duration(days: 7));
    } else if (_filter == _Filter.month) {
      from = DateTime(now.year, now.month, 1);
    }
    final payments = await context.read<RideManager>().getAllPayments(from: from);
    if (!mounted) return;
    setState(() {
      _payments = payments;
      _loading = false;
    });
  }

  /// Flattens the payments into a render list where a day header is emitted
  /// whenever the calendar day changes. Purely presentational -- the order
  /// the manager returned is preserved exactly.
  List<Object> _sectioned() {
    final items = <Object>[];
    DateTime? currentDay;
    for (final p in _payments) {
      final day = DateTime(p.receivedAt.year, p.receivedAt.month, p.receivedAt.day);
      if (currentDay == null || day != currentDay) {
        currentDay = day;
        items.add(day);
      }
      items.add(p);
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final total = _payments.fold<double>(0.0, (sum, p) => sum + p.amount);
    final telebirrTotal =
        _payments.where((p) => p.method == PaymentMethod.telebirr).fold<double>(0, (s, p) => s + p.amount);
    final cashTotal = _payments.where((p) => p.method == PaymentMethod.cash).fold<double>(0, (s, p) => s + p.amount);

    return Scaffold(
      appBar: AppBar(title: const Text('Payment history')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.s4, AppTheme.s3, AppTheme.s4, 0),
            child: SegmentedButton<_Filter>(
              style: SegmentedButton.styleFrom(
                backgroundColor: context.isDark ? AppTheme.surfaceCard : Colors.white,
                selectedBackgroundColor: context.tintedSurface(AppTheme.primaryDark),
                selectedForegroundColor: context.isDark ? AppTheme.primary : AppTheme.primaryDark,
                foregroundColor: context.subtleText,
                side: BorderSide(color: context.hairline),
                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.rSm)),
              ),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _Filter.all, label: Text('All')),
                ButtonSegment(value: _Filter.week, label: Text('This week')),
                ButtonSegment(value: _Filter.month, label: Text('This month')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) {
                setState(() => _filter = s.first);
                _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppTheme.s4),
            child: FadeSlideIn(
              child: _TotalsHeader(
                total: total,
                telebirrTotal: telebirrTotal,
                cashTotal: cashTotal,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const _PaymentListSkeleton()
                : _payments.isEmpty
                    ? const EmptyState(
                        icon: Icons.payments_outlined,
                        title: 'No payments recorded yet',
                        subtitle: 'Telebirr and cash payments will show up here as they come in.',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: Builder(
                          builder: (context) {
                            final items = _sectioned();
                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(AppTheme.s4, 0, AppTheme.s4, AppTheme.s6),
                              itemCount: items.length,
                              itemBuilder: (context, i) {
                                final item = items[i];
                                if (item is DateTime) {
                                  return FadeSlideIn(
                                    index: i,
                                    delayStepMs: 20,
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        top: i == 0 ? 0 : AppTheme.s4,
                                        bottom: AppTheme.s1,
                                      ),
                                      child: SectionHeader(title: DateFormat.yMMMEd().format(item)),
                                    ),
                                  );
                                }
                                final p = item as Payment;
                                return FadeSlideIn(
                                  index: i,
                                  delayStepMs: 20,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: AppTheme.s2),
                                    child: _PaymentRow(
                                      payment: p,
                                      onCall: () => _callPayer(p.payerPhone),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// Hero earnings card. Keeps the brand gradient but pulls its radius,
/// spacing and glow from the design tokens so it sits in the same family as
/// the cards below it.
class _TotalsHeader extends StatelessWidget {
  const _TotalsHeader({required this.total, required this.telebirrTotal, required this.cashTotal});

  final double total;
  final double telebirrTotal;
  final double cashTotal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.s5, vertical: AppTheme.s4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        boxShadow: AppTheme.shadow(
          tint: AppTheme.primaryDark,
          opacity: context.isDark ? 0.22 : 0.28,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: AppTheme.s1),
                CountUpText(
                  value: total,
                  suffix: ' ETB',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.s3),
          _MiniTotal(icon: Icons.phone_android, label: 'Telebirr', value: telebirrTotal),
          Container(
            width: 1,
            height: 30,
            margin: const EdgeInsets.symmetric(horizontal: AppTheme.s3),
            color: Colors.white.withValues(alpha: 0.22),
          ),
          _MiniTotal(icon: Icons.payments_rounded, label: 'Cash', value: cashTotal),
        ],
      ),
    );
  }
}

/// One payment in the history list.
class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment, required this.onCall});

  final Payment payment;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final isCash = p.method == PaymentMethod.cash;
    final brand = context.isDark ? AppTheme.primary : AppTheme.primaryDark;
    final accent = isCash ? AppTheme.teal : brand;
    final canCall = !isCash && p.payerPhone != 'Unknown';

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(AppTheme.s3, AppTheme.s3, AppTheme.s2, AppTheme.s3),
      child: Row(
        children: [
          IconBadge(
            icon: isCash ? Icons.payments_rounded : Icons.arrow_downward,
            color: accent,
            size: 42,
          ),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCash
                      ? '${p.amount.toStringAsFixed(0)} ETB — cash${p.payerName != null ? ' (${p.payerName})' : ''}'
                      : '${p.amount.toStringAsFixed(0)} ETB from ${p.payerPhone}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, letterSpacing: -0.2),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      DateFormat.jm().format(p.receivedAt),
                      style: TextStyle(color: context.subtleText, fontSize: 12.5),
                    ),
                    if (p.synced) ...[
                      const SizedBox(width: AppTheme.s2),
                      Icon(Icons.cloud_done_rounded, size: 13, color: context.faintText),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (canCall)
            IconButton(
              icon: Icon(Icons.call_rounded, size: 19, color: brand),
              style: IconButton.styleFrom(
                backgroundColor: context.tintedSurface(brand),
                minimumSize: const Size(36, 36),
                padding: EdgeInsets.zero,
              ),
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              onPressed: onCall,
            )
          else
            const SizedBox(width: AppTheme.s2),
        ],
      ),
    );
  }
}

class _MiniTotal extends StatelessWidget {
  const _MiniTotal({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 13),
            const SizedBox(width: AppTheme.s1),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value.toStringAsFixed(0),
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

/// Placeholder rows while payments load, so the list keeps its shape rather
/// than collapsing to a lone centred spinner.
class _PaymentListSkeleton extends StatelessWidget {
  const _PaymentListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppTheme.s4, 0, AppTheme.s4, AppTheme.s6),
      itemCount: 6,
      physics: const NeverScrollableScrollPhysics(),
      separatorBuilder: (_, __) => const SizedBox(height: AppTheme.s2),
      itemBuilder: (context, i) => FadeSlideIn(
        index: i,
        delayStepMs: 20,
        child: SoftCard(
          padding: const EdgeInsets.all(AppTheme.s3),
          child: Row(
            children: const [
              SkeletonBox(height: 42, width: 42, radius: 21),
              SizedBox(width: AppTheme.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 12, width: 170, radius: AppTheme.s1),
                    SizedBox(height: AppTheme.s2),
                    SkeletonBox(height: 10, width: 80, radius: AppTheme.s1),
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

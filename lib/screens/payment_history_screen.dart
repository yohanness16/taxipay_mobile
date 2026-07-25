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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<_Filter>(
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
            padding: const EdgeInsets.all(16),
            child: FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppTheme.primaryDark, AppTheme.primary]),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text('${total.toStringAsFixed(0)} ETB',
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    _MiniTotal(icon: Icons.phone_android, label: 'Telebirr', value: telebirrTotal),
                    const SizedBox(width: 16),
                    _MiniTotal(icon: Icons.payments_rounded, label: 'Cash', value: cashTotal),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _payments.isEmpty
                    ? const EmptyState(
                        icon: Icons.payments_outlined,
                        title: 'No payments recorded yet',
                        subtitle: 'Telebirr and cash payments will show up here as they come in.',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _payments.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final p = _payments[i];
                            final isCash = p.method == PaymentMethod.cash;
                            return FadeSlideIn(
                              index: i,
                              delayStepMs: 20,
                              child: Card(
                                child: ListTile(
                                  leading: IconBadge(
                                    icon: isCash ? Icons.payments_rounded : Icons.arrow_downward,
                                    color: isCash ? Colors.teal : AppTheme.primaryDark,
                                  ),
                                  title: Text(
                                    isCash
                                        ? '${p.amount.toStringAsFixed(0)} ETB — cash${p.payerName != null ? ' (${p.payerName})' : ''}'
                                        : '${p.amount.toStringAsFixed(0)} ETB from ${p.payerPhone}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(DateFormat.yMMMd().add_jm().format(p.receivedAt)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!isCash && p.payerPhone != 'Unknown')
                                        IconButton(
                                          icon: const Icon(Icons.call, size: 20, color: AppTheme.primaryDark),
                                          onPressed: () => _callPayer(p.payerPhone),
                                        ),
                                      if (p.synced) const Icon(Icons.cloud_done, size: 18, color: Colors.grey),
                                    ],
                                  ),
                                ),
                              ),
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
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
        Text('${value.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

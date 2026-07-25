import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../services/auth_service.dart';
import '../services/expense_tracker.dart';
import '../services/report_service.dart';
import '../services/ride_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_widgets.dart';

IconData _categoryIcon(ExpenseCategory c) {
  switch (c) {
    case ExpenseCategory.fuel:
      return Icons.local_gas_station_rounded;
    case ExpenseCategory.maintenance:
      return Icons.build_rounded;
    case ExpenseCategory.insurance:
      return Icons.shield_rounded;
    case ExpenseCategory.other:
      return Icons.receipt_long_rounded;
  }
}

Color _categoryColor(ExpenseCategory c) {
  switch (c) {
    case ExpenseCategory.fuel:
      return Colors.deepOrange;
    case ExpenseCategory.maintenance:
      return Colors.blueGrey;
    case ExpenseCategory.insurance:
      return Colors.indigo;
    case ExpenseCategory.other:
      return Colors.grey;
  }
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _loading = true;
  bool _sharing = false;
  List<double> _dailyEarnings = List.filled(7, 0);
  double _totalEarnings = 0;
  double _totalExpenses = 0;
  Map<ExpenseCategory, double> _expenseByCategory = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rideManager = context.read<RideManager>();
    final expenseTracker = context.read<ExpenseTracker>();

    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));

    final dailyEarnings = List<double>.filled(7, 0);
    for (int i = 0; i < 7; i++) {
      final day = weekStart.add(Duration(days: i));
      final nextDay = day.add(const Duration(days: 1));
      dailyEarnings[i] = await rideManager.getTotalEarnings(from: day, to: nextDay);
    }

    final totalEarnings = await rideManager.getTotalEarnings(from: weekStart);
    final totalExpenses = await expenseTracker.getTotalExpenses(weekStart, now);
    final byCategory = await expenseTracker.getTotalsByCategory(weekStart, now);

    if (!mounted) return;
    setState(() {
      _dailyEarnings = dailyEarnings;
      _totalEarnings = totalEarnings;
      _totalExpenses = totalExpenses;
      _expenseByCategory = byCategory;
      _loading = false;
    });
  }

  Future<void> _shareReport() async {
    setState(() => _sharing = true);
    try {
      final auth = context.read<AuthService>();
      final name = await auth.name ?? 'Driver';
      final phone = await auth.phone ?? '';
      final now = DateTime.now();
      final weekStart = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));

      await context.read<ReportService>().shareEarningsReport(
            driverName: name,
            driverPhone: phone,
            from: weekStart,
            to: now,
          );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not generate the report. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final netProfit = _totalEarnings - _totalExpenses;
    final maxCategory = _expenseByCategory.values.isEmpty
        ? 0.0
        : _expenseByCategory.values.reduce((a, b) => a > b ? a : b);

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Reports'),
              actions: [
                IconButton(
                  icon: _sharing
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.ios_share_rounded),
                  tooltip: 'Share earnings report (last 7 days)',
                  onPressed: _sharing ? null : _shareReport,
                ),
              ],
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FadeSlideIn(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Earnings — last 7 days', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 160,
                          child: BarChart(
                            BarChartData(
                              barGroups: [
                                for (int i = 0; i < _dailyEarnings.length; i++)
                                  BarChartGroupData(x: i, barRods: [
                                    BarChartRodData(
                                      toY: _dailyEarnings[i],
                                      gradient: const LinearGradient(
                                        colors: [AppTheme.primary, AppTheme.primaryDark],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                      width: 18,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ]),
                              ],
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                                      final i = value.toInt();
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(i >= 0 && i < labels.length ? labels[i] : '',
                                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                      );
                                    },
                                  ),
                                ),
                                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              borderData: FlBorderData(show: false),
                              gridData: const FlGridData(show: false),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  index: 1,
                  child: Row(
                    children: [
                      Expanded(child: _SummaryTile(label: 'Earnings (7d)', value: _totalEarnings, icon: Icons.trending_up, color: AppTheme.primaryDark)),
                      const SizedBox(width: 12),
                      Expanded(child: _SummaryTile(label: 'Expenses (7d)', value: _totalExpenses, icon: Icons.receipt_long, color: Colors.deepOrange)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FadeSlideIn(
                  index: 2,
                  child: _SummaryTile(
                    label: 'Net profit (7d)',
                    value: netProfit,
                    icon: Icons.account_balance_wallet_rounded,
                    color: netProfit >= 0 ? AppTheme.primaryDark : Colors.red,
                    fullWidth: true,
                  ),
                ),
                if (_expenseByCategory.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Expenses by category', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  ..._expenseByCategory.entries.toList().asMap().entries.map((entry) {
                    final e = entry.value;
                    final color = _categoryColor(e.key);
                    final fraction = maxCategory > 0 ? (e.value / maxCategory).clamp(0.0, 1.0) : 0.0;
                    return FadeSlideIn(
                      index: entry.key,
                      delayStepMs: 30,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            IconBadge(icon: _categoryIcon(e.key), color: color, size: 34),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(e.key.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      Text('${e.value.toStringAsFixed(0)} ETB', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0, end: fraction),
                                      duration: const Duration(milliseconds: 600),
                                      curve: Curves.easeOutCubic,
                                      builder: (context, v, _) => LinearProgressIndicator(
                                        value: v,
                                        minHeight: 6,
                                        backgroundColor: color.withOpacity(0.12),
                                        valueColor: AlwaysStoppedAnimation(color),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value, required this.icon, required this.color, this.fullWidth = false});
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconBadge(icon: icon, color: color, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: color, fontSize: 12)),
                  Text('${value.toStringAsFixed(0)} ETB', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

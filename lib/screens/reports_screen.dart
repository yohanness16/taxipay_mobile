import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

/// Category accents come from the design system rather than raw Material
/// swatches, so the four categories stay distinguishable from each other
/// *and* from the brand green in both themes. (deepOrange/blueGrey/indigo/
/// grey all muddied into the background on black.)
Color _categoryColor(ExpenseCategory c) {
  switch (c) {
    case ExpenseCategory.fuel:
      return AppTheme.accentAmber;
    case ExpenseCategory.maintenance:
      return AppTheme.info;
    case ExpenseCategory.insurance:
      return AppTheme.violet;
    case ExpenseCategory.other:
      return AppTheme.teal;
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
      // Resolved before the awaits below so the provider lookup never
      // crosses an async gap (use_build_context_synchronously).
      final reportService = context.read<ReportService>();
      final name = await auth.name ?? 'Driver';
      final phone = await auth.phone ?? '';
      final now = DateTime.now();
      final weekStart = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));

      await reportService.shareEarningsReport(
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
    final positive = netProfit >= 0;
    final brand = context.isDark ? AppTheme.primary : AppTheme.primaryDark;

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
          ? const _ReportsSkeleton()
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppTheme.s4, AppTheme.s2, AppTheme.s4, AppTheme.s8),
              children: [
                FadeSlideIn(
                  child: SoftCard(
                    padding: const EdgeInsets.fromLTRB(AppTheme.s4, AppTheme.s4, AppTheme.s4, AppTheme.s2),
                    radius: AppTheme.rXl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconBadge(icon: Icons.bar_chart_rounded, color: brand, size: 34),
                            const SizedBox(width: AppTheme.s3),
                            Expanded(
                              child: Text(
                                'Earnings — last 7 days',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.s4),
                        SizedBox(
                          height: 168,
                          child: _EarningsBarChart(dailyEarnings: _dailyEarnings),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.s3),
                FadeSlideIn(
                  index: 1,
                  child: Row(
                    children: [
                      Expanded(
                        child: _SummaryTile(
                          label: 'Earnings (7d)',
                          value: _totalEarnings,
                          icon: Icons.trending_up,
                          color: brand,
                        ),
                      ),
                      const SizedBox(width: AppTheme.s3),
                      Expanded(
                        child: _SummaryTile(
                          label: 'Expenses (7d)',
                          value: _totalExpenses,
                          icon: Icons.receipt_long,
                          color: AppTheme.danger,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.s3),
                FadeSlideIn(
                  index: 2,
                  child: _SummaryTile(
                    label: 'Net profit (7d)',
                    value: netProfit,
                    icon: positive
                        ? Icons.account_balance_wallet_rounded
                        : Icons.trending_down_rounded,
                    color: positive ? brand : AppTheme.danger,
                  ),
                ),
                if (_expenseByCategory.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.s6),
                  FadeSlideIn(
                    index: 3,
                    child: const SectionHeader(title: 'Expenses by category'),
                  ),
                  const SizedBox(height: AppTheme.s2),
                  ..._expenseByCategory.entries.toList().asMap().entries.map((entry) {
                    final e = entry.value;
                    final color = _categoryColor(e.key);
                    final fraction = maxCategory > 0 ? (e.value / maxCategory).clamp(0.0, 1.0) : 0.0;
                    return FadeSlideIn(
                      index: 4 + entry.key,
                      delayStepMs: 30,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.s2),
                        child: SoftCard(
                          padding: const EdgeInsets.all(AppTheme.s3),
                          child: Row(
                            children: [
                              IconBadge(icon: _categoryIcon(e.key), color: color, size: 38),
                              const SizedBox(width: AppTheme.s3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          e.key.label,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                        ),
                                        Text(
                                          '${e.value.toStringAsFixed(0)} ETB',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13.5,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppTheme.s2),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(AppTheme.s1),
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween(begin: 0, end: fraction),
                                        duration: AppTheme.dSlow,
                                        curve: AppTheme.ease,
                                        builder: (context, v, _) => LinearProgressIndicator(
                                          value: v,
                                          minHeight: 6,
                                          backgroundColor: context.faintFill,
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
                      ),
                    );
                  }),
                ],
              ],
            ),
    );
  }
}

/// The weekly earnings bars.
///
/// Everything the chart draws is pulled from the theme rather than baked in:
/// the previous version used `Colors.grey.shade600` day labels and no grid,
/// which vanished against the near-black dark surface. Each bar also sits on
/// a faint track so days with no earnings still read as a slot rather than
/// as empty space.
class _EarningsBarChart extends StatelessWidget {
  const _EarningsBarChart({required this.dailyEarnings});

  final List<double> dailyEarnings;

  /// Labels are derived from the dates the data was actually built from,
  /// not a fixed Mon-Sun list.
  ///
  /// _load() fills dailyEarnings starting at `today - 6 days`, so index 0 is
  /// whatever weekday fell six days ago -- only ever "Mon" when today
  /// happens to be Sunday. The previous hardcoded list therefore mislabelled
  /// every bar on six days out of seven, silently attributing each day's
  /// earnings to the wrong weekday. Formatting the real date also means the
  /// names follow the device locale instead of being hardcoded English.
  static String _labelFor(int index) {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: 6 - index));
    return DateFormat.E().format(day);
  }

  @override
  Widget build(BuildContext context) {
    final peak = dailyEarnings.fold<double>(0, (m, v) => v > m ? v : m);
    // A headroom-padded ceiling keeps the tallest bar off the top edge, and
    // the fallback keeps the grid sensible on a week with no earnings.
    final maxY = peak <= 0 ? 100.0 : peak * 1.2;

    final barTop = AppTheme.primary;
    final barBottom = context.isDark ? AppTheme.primary.withValues(alpha: 0.5) : AppTheme.primaryDark;

    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        barGroups: [
          for (int i = 0; i < dailyEarnings.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: dailyEarnings[i],
                  gradient: LinearGradient(
                    colors: [barTop, barBottom],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  width: 18,
                  borderRadius: BorderRadius.circular(AppTheme.s2),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: context.faintFill,
                  ),
                ),
              ],
            ),
        ],
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                return Padding(
                  padding: const EdgeInsets.only(top: AppTheme.s2),
                  child: Text(
                    i >= 0 && i < dailyEarnings.length ? _labelFor(i) : '',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: context.subtleText,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) => FlLine(color: context.hairline, strokeWidth: 1),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipRoundedRadius: AppTheme.rSm,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: AppTheme.s3,
              vertical: AppTheme.s2,
            ),
            getTooltipColor: (_) => context.isDark ? AppTheme.surfaceCard : const Color(0xFF1F2937),
            tooltipBorder: BorderSide(color: context.hairline),
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              '${rod.toY.toStringAsFixed(0)} ETB',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final double value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      accent: color,
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 38),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.subtleText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: CountUpText(
                    value: value,
                    suffix: ' ETB',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Layout-stable loading state so the chart and tiles fade into their final
/// positions instead of the whole screen jumping in behind a lone spinner.
class _ReportsSkeleton extends StatelessWidget {
  const _ReportsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppTheme.s4, AppTheme.s2, AppTheme.s4, AppTheme.s8),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        SkeletonBox(height: 236, radius: AppTheme.rXl),
        SizedBox(height: AppTheme.s3),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 76, radius: AppTheme.rLg)),
            SizedBox(width: AppTheme.s3),
            Expanded(child: SkeletonBox(height: 76, radius: AppTheme.rLg)),
          ],
        ),
        SizedBox(height: AppTheme.s3),
        SkeletonBox(height: 76, radius: AppTheme.rLg),
        SizedBox(height: AppTheme.s6),
        SkeletonBox(height: 20, width: 170),
        SizedBox(height: AppTheme.s3),
        SkeletonBox(height: 66, radius: AppTheme.rLg),
        SizedBox(height: AppTheme.s2),
        SkeletonBox(height: 66, radius: AppTheme.rLg),
        SizedBox(height: AppTheme.s2),
        SkeletonBox(height: 66, radius: AppTheme.rLg),
      ],
    );
  }
}

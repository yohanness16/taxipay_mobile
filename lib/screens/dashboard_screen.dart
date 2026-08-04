import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../models/payment.dart';
import '../services/auth_service.dart';
import '../services/driver_settings_service.dart';
import '../services/expense_tracker.dart';
import '../services/ride_manager.dart';
import '../services/sms_reader.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_widgets.dart';
import '../widgets/offline_banner.dart';
import 'expense_screen.dart';
import 'payment_history_screen.dart';
import 'reports_screen.dart';
import 'ride_list_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.showAppBar = true, this.onQuickNav});

  /// Whether this screen renders its own AppBar. Set false when embedded as
  /// a tab body inside [MainShell], which owns a single shared AppBar.
  final bool showAppBar;

  /// When provided (i.e. embedded in the shell), tapping a quick-action card
  /// for a destination that's also a bottom-nav tab (Rides/Expenses/Reports)
  /// switches to that tab instead of pushing a second stacked screen.
  final void Function(int tabIndex)? onQuickNav;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double _todayEarnings = 0;
  double _todayTelebirr = 0;
  double _todayCash = 0;
  int _todayRideCount = 0;
  double _todayExpenses = 0;
  double _dailyGoal = DriverSettingsService.defaultDailyGoal;
  double _kmSinceService = 0;
  double _serviceIntervalKm = DriverSettingsService.defaultServiceIntervalKm;
  List<Payment> _recentPayments = [];
  String? _driverName;
  bool _loading = true;
  bool _smsListening = false;

  @override
  void initState() {
    super.initState();
    _load();
    _maybeStartSmsListening();
  }

  /// Starts the live SMS listener if permission is already granted. Calling
  /// requestPermissions() when permission was already granted resolves
  /// immediately without showing any dialog — so this is safe to call on
  /// every dashboard load and won't nag the driver. It only shows a real
  /// prompt the first time, from the Settings screen.
  Future<void> _maybeStartSmsListening() async {
    if (_smsListening) return;
    final smsReader = context.read<SmsReader>();
    final granted = await smsReader.requestPermissions();
    if (!granted) return;

    smsReader.startListening(_onIncomingPayment);
    _smsListening = true;
  }

  Future<void> _logCashFare() async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final strings = context.read<AppStrings>();

    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.t('log_cash_fare')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: strings.t('amount'), suffixText: 'ETB'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(labelText: strings.t('note_optional')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(strings.t('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(amountCtrl.text)),
            child: Text(strings.t('save')),
          ),
        ],
      ),
    );

    if (amount == null || amount <= 0) return;
    if (!mounted) return;
    await context.read<RideManager>().logCashPayment(
          amount: amount,
          note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        );
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.t('cash_fare_logged'))),
    );
  }

  /// By the time this fires, [payment] has already been saved (with the
  /// correct active-ride link), the sound notification has already shown,
  /// and the overlay bubble has already been pushed an update -- all via
  /// the single shared code path in sms_reader.dart that both this
  /// foreground listener and the background isolate go through. This
  /// callback exists purely to refresh what's on screen right now.
  Future<void> _onIncomingPayment(Payment payment) async {
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rideManager = context.read<RideManager>();
    final expenseTracker = context.read<ExpenseTracker>();
    final driverSettings = context.read<DriverSettingsService>();
    final auth = context.read<AuthService>();

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final rides = await rideManager.getRideHistory(from: startOfDay);
    final payments = await rideManager.getAllPayments(from: startOfDay);
    final recentPayments = await rideManager.getAllPayments();
    final expenses = await expenseTracker.getTotalExpenses(startOfDay, now);
    final goal = await driverSettings.getDailyGoal();
    final serviceInterval = await driverSettings.getServiceIntervalKm();
    final lastServiceOdometer = await driverSettings.getLastServiceOdometerKm();
    final totalDistance = await rideManager.getTotalDistanceKm();
    final name = await auth.name;

    final telebirrTotal =
        payments.where((p) => p.method == PaymentMethod.telebirr).fold<double>(0, (s, p) => s + p.amount);
    final cashTotal = payments.where((p) => p.method == PaymentMethod.cash).fold<double>(0, (s, p) => s + p.amount);

    if (!mounted) return;
    setState(() {
      _todayEarnings = telebirrTotal + cashTotal;
      _todayTelebirr = telebirrTotal;
      _todayCash = cashTotal;
      _todayRideCount = rides.length;
      _todayExpenses = expenses;
      _dailyGoal = goal;
      _serviceIntervalKm = serviceInterval;
      _kmSinceService = totalDistance - lastServiceOdometer;
      _recentPayments = recentPayments.take(4).toList();
      _driverName = name;
      _loading = false;
    });
  }

  String _greetingKey() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'greeting_morning';
    if (hour < 17) return 'greeting_afternoon';
    return 'greeting_evening';
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<AppStrings>();
    final netProfit = _todayEarnings - _todayExpenses;
    final goalProgress = _dailyGoal > 0 ? (_todayEarnings / _dailyGoal).clamp(0.0, 1.0) : 0.0;
    final serviceDue = _kmSinceService >= _serviceIntervalKm && _serviceIntervalKm > 0;

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Telebirr Driver Assistant'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))
                      .then((_) => _load()),
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          OfflineBanner(message: strings.t('offline_mode')),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const _DashboardSkeleton()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                          AppTheme.s4, AppTheme.s2, AppTheme.s4, AppTheme.s8),
                      children: [
                        FadeSlideIn(
                          index: 0,
                          child: Text(
                            '${strings.t(_greetingKey())}${_driverName != null && _driverName!.isNotEmpty ? ', ${_driverName!.split(' ').first}' : ''} 👋',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        const SizedBox(height: AppTheme.s1),
                        Text(
                          DateFormat.yMMMMEEEEd().format(DateTime.now()),
                          style: TextStyle(color: context.subtleText, fontSize: 13),
                        ),
                        const SizedBox(height: AppTheme.s5),

                        // Hero earnings card with goal progress + cash/Telebirr split.
                        FadeSlideIn(
                          index: 1,
                          child: Container(
                            padding: const EdgeInsets.all(AppTheme.s5),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppTheme.primaryDark, AppTheme.primary],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(AppTheme.rXl),
                              boxShadow: AppTheme.shadow(
                                  tint: AppTheme.primaryDark, opacity: 0.30, blur: 22, y: 10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(strings.t('todays_earnings'),
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.2)),
                                const SizedBox(height: AppTheme.s1),
                                CountUpText(
                                  value: _todayEarnings,
                                  suffix: ' ETB',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 36,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1),
                                ),
                                const SizedBox(height: AppTheme.s4),
                                Row(
                                  children: [
                                    _MiniBreakdown(icon: Icons.phone_android, label: strings.t('telebirr'), value: _todayTelebirr),
                                    const SizedBox(width: AppTheme.s5),
                                    _MiniBreakdown(icon: Icons.payments_rounded, label: strings.t('cash'), value: _todayCash),
                                  ],
                                ),
                                const SizedBox(height: AppTheme.s4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(AppTheme.s2),
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0, end: goalProgress.toDouble()),
                                    duration: AppTheme.dSlow,
                                    curve: AppTheme.ease,
                                    builder: (context, v, _) => LinearProgressIndicator(
                                      value: v,
                                      minHeight: 8,
                                      backgroundColor: Colors.white24,
                                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppTheme.s2),
                                Text(
                                  '${strings.t('daily_goal')}: ${_dailyGoal.toStringAsFixed(0)} ETB  ·  ${(goalProgress * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppTheme.s3),

                        FadeSlideIn(
                          index: 2,
                          child: Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  label: strings.t('net_profit'),
                                  value: '${netProfit.toStringAsFixed(0)} ETB',
                                  icon: Icons.trending_up_rounded,
                                  color: netProfit >= 0 ? AppTheme.primaryDark : AppTheme.danger,
                                ),
                              ),
                              const SizedBox(width: AppTheme.s3),
                              Expanded(
                                child: _StatCard(
                                  label: strings.t('rides'),
                                  value: '$_todayRideCount',
                                  icon: Icons.local_taxi_rounded,
                                  color: AppTheme.info,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppTheme.s3),
                        FadeSlideIn(
                          index: 3,
                          child: _StatCard(
                            label: strings.t('expenses_today'),
                            value: '${_todayExpenses.toStringAsFixed(0)} ETB',
                            icon: Icons.receipt_long_rounded,
                            color: AppTheme.accentAmber,
                            fullWidth: true,
                          ),
                        ),

                        if (serviceDue) ...[
                          const SizedBox(height: AppTheme.s3),
                          FadeSlideIn(
                            index: 4,
                            child: CalloutBanner(
                              icon: Icons.build_circle_outlined,
                              accent: AppTheme.accentAmber,
                              message:
                                  '${strings.t('service_due')} (${_kmSinceService.toStringAsFixed(0)} km since last service)',
                            ),
                          ),
                        ],

                        const SizedBox(height: AppTheme.s6),
                        Text(strings.t('quick_actions'), style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: AppTheme.s3),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: AppTheme.s3,
                          crossAxisSpacing: AppTheme.s3,
                          childAspectRatio: 2.4,
                          children: [
                            _ActionCard(
                              icon: Icons.add_road_rounded,
                              label: strings.t('new_ride'),
                              color: AppTheme.info,
                              onTap: () => widget.onQuickNav != null
                                  ? widget.onQuickNav!(1)
                                  : Navigator.of(context)
                                      .push(MaterialPageRoute(builder: (_) => const RideListScreen()))
                                      .then((_) => _load()),
                            ),
                            _ActionCard(
                              icon: Icons.add_card_rounded,
                              label: strings.t('add_expense'),
                              color: AppTheme.accentAmber,
                              onTap: () => widget.onQuickNav != null
                                  ? widget.onQuickNav!(2)
                                  : Navigator.of(context)
                                      .push(MaterialPageRoute(builder: (_) => const ExpenseScreen()))
                                      .then((_) => _load()),
                            ),
                            _ActionCard(
                              icon: Icons.payments_outlined,
                              label: strings.t('payment_history'),
                              color: AppTheme.primaryDark,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const PaymentHistoryScreen()),
                              ),
                            ),
                            _ActionCard(
                              icon: Icons.insights_rounded,
                              label: strings.t('reports'),
                              color: AppTheme.violet,
                              onTap: () => widget.onQuickNav != null
                                  ? widget.onQuickNav!(3)
                                  : Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const ReportsScreen()),
                                    ),
                            ),
                            _ActionCard(
                              icon: Icons.payments_rounded,
                              label: strings.t('log_cash_fare'),
                              color: AppTheme.teal,
                              onTap: _logCashFare,
                            ),
                          ],
                        ),

                        if (_recentPayments.isNotEmpty) ...[
                          const SizedBox(height: AppTheme.s6),
                          SectionHeader(
                            title: strings.t('recent_payments'),
                            action: strings.t('view_all'),
                            onAction: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const PaymentHistoryScreen()),
                            ),
                          ),
                          const SizedBox(height: AppTheme.s2),
                          ..._recentPayments.asMap().entries.map((entry) {
                            final p = entry.value;
                            final isCash = p.method == PaymentMethod.cash;
                            return FadeSlideIn(
                              index: entry.key,
                              delayStepMs: 25,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: AppTheme.s2),
                                child: SoftCard(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppTheme.s3, vertical: AppTheme.s3),
                                  child: Row(
                                    children: [
                                      IconBadge(
                                        icon: isCash
                                            ? Icons.payments_rounded
                                            : Icons.arrow_downward_rounded,
                                        color: isCash ? AppTheme.teal : AppTheme.primaryDark,
                                      ),
                                      const SizedBox(width: AppTheme.s3),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('${p.amount.toStringAsFixed(0)} ETB',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w700, fontSize: 15)),
                                            const SizedBox(height: 2),
                                            Text(
                                              isCash ? strings.t('cash') : p.payerPhone,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: context.subtleText, fontSize: 12.5),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        DateFormat.MMMd().add_jm().format(p.receivedAt),
                                        style: TextStyle(fontSize: 11, color: context.faintText),
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
            ),
          ),
        ],
      ),
    );
  }
}

/// Layout-stable loading state. A bare centred spinner made the whole
/// dashboard pop into existence at once and shifted everything as it
/// landed; these blocks occupy roughly the real content's footprint so the
/// transition is a fade rather than a jump.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.s4, AppTheme.s2, AppTheme.s4, AppTheme.s8),
      children: const [
        SkeletonBox(height: 26, width: 190),
        SizedBox(height: AppTheme.s2),
        SkeletonBox(height: 14, width: 150),
        SizedBox(height: AppTheme.s5),
        SkeletonBox(height: 186, radius: AppTheme.rXl),
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
        SkeletonBox(height: 20, width: 130),
        SizedBox(height: AppTheme.s3),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 58, radius: AppTheme.rMd)),
            SizedBox(width: AppTheme.s3),
            Expanded(child: SkeletonBox(height: 58, radius: AppTheme.rMd)),
          ],
        ),
        SizedBox(height: AppTheme.s3),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 58, radius: AppTheme.rMd)),
            SizedBox(width: AppTheme.s3),
            Expanded(child: SkeletonBox(height: 58, radius: AppTheme.rMd)),
          ],
        ),
      ],
    );
  }
}

class _MiniBreakdown extends StatelessWidget {
  const _MiniBreakdown({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 15),
        const SizedBox(width: 5),
        Text('$label ${value.toStringAsFixed(0)}',
            style: const TextStyle(
                color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, required this.color, this.fullWidth = false});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool fullWidth;

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
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4),
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

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: SoftCard(
        accent: color,
        radius: AppTheme.rMd,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: AppTheme.s3),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 13, height: 1.25),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

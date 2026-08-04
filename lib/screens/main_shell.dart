import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../services/auth_service.dart';
import '../services/overlay_service.dart';
import '../services/subscription_manager.dart';
import '../services/sync_manager.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'expense_screen.dart';
import 'payment_history_screen.dart';
import 'registration_screen.dart';
import 'reports_screen.dart';
import 'ride_list_screen.dart';
import 'settings_screen.dart';
import 'subscription_payment_screen.dart';

/// The app's post-login home. Owns a single shared AppBar (with the burger
/// menu / Drawer), a Material 3 bottom [NavigationBar] for the five primary
/// destinations, and keeps each tab's state alive via [IndexedStack] so
/// switching tabs doesn't reload data every time.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  Timer? _lockCheckTimer;
  bool _checkingLock = false;
  SubscriptionSnapshot? _snapshot;

  static const _titleKeys = ['dashboard', 'rides', 'expenses', 'reports', 'settings'];

  void _goToTab(int i) => setState(() => _index = i);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureOverlayReady();
      _checkSubscriptionLock();
    });
    // The internal subscription countdown ticks locally with no network at
    // all, but this periodic check is what re-syncs it against the backend
    // the moment connectivity is available, and is also what actually
    // enforces the lock the instant time runs out while the app is
    // sitting open (not just at the next cold start).
    _lockCheckTimer = Timer.periodic(const Duration(minutes: 2), (_) => _checkSubscriptionLock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockCheckTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The overlay permission screen is a separate system Settings page --
    // there's no callback for "the driver just flipped the toggle", only
    // "the app regained focus". Re-check here so the bubble can auto-start
    // the moment they come back, without needing to open Settings tab.
    if (state == AppLifecycleState.resumed) {
      _ensureOverlayReady();
      _checkSubscriptionLock();
    }
  }

  /// Onboarding already walked the driver through granting this -- so by
  /// the time MainShell is reached, this just silently (re)starts the
  /// bubble if it isn't already running. No dialog, no interruption.
  Future<void> _ensureOverlayReady() async {
    if (!mounted) return;
    final overlay = context.read<OverlayService>();
    if (await overlay.isPermissionGranted() && !await overlay.isActive()) {
      await overlay.start();
    }
  }

  Future<void> _checkSubscriptionLock() async {
    if (_checkingLock || !mounted) return;
    _checkingLock = true;
    try {
      final auth = context.read<AuthService>();
      final phone = await auth.phone;
      if (phone == null || !mounted) return;
      final subscriptionManager = context.read<SubscriptionManager>();
      final snapshot = await context.read<SyncManager>().syncWithServer(phone);
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
      if (subscriptionManager.shouldLock(snapshot)) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => SubscriptionPaymentScreen(snapshot: snapshot)),
          (route) => false,
        );
      }
    } finally {
      _checkingLock = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<AppStrings>();

    final tabs = <Widget>[
      DashboardScreen(showAppBar: false, onQuickNav: _goToTab),
      const RideListScreen(showAppBar: false),
      const ExpenseScreen(showAppBar: false),
      const ReportsScreen(showAppBar: false),
      const SettingsScreen(showAppBar: false),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.t(_titleKeys[_index])),
        centerTitle: false,
      ),
      drawer: const _AppDrawer(),
      body: Column(
        children: [
          if (_snapshot?.isNearExpiry == true) _ExpiryWarningBanner(snapshot: _snapshot!),
          // Deliberately a plain IndexedStack with no transition wrapper.
          // Every tab stays alive and keeps its scroll position and loaded
          // data, which is the whole point of IndexedStack here; wrapping
          // it in an AnimatedSwitcher keyed on the index would rebuild the
          // entire subtree on every tab change and throw that away.
          Expanded(child: IndexedStack(index: _index, children: tabs)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goToTab,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: strings.t('dashboard'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.local_taxi_outlined),
            selectedIcon: const Icon(Icons.local_taxi),
            label: strings.t('rides'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: strings.t('expenses'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: const Icon(Icons.insights),
            label: strings.t('reports'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: strings.t('settings'),
          ),
        ],
      ),
    );
  }
}

/// Non-blocking "renew soon" strip shown starting 5 days before expiry --
/// still fully usable, just a nudge. Once expiry actually passes, this
/// stops applying and the hard lock (SubscriptionPaymentScreen) takes over
/// instead.
class _ExpiryWarningBanner extends StatelessWidget {
  const _ExpiryWarningBanner({required this.snapshot});
  final SubscriptionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final days = snapshot.daysRemaining;
    // The previous hand-picked dark-goldenrod/olive pair was tuned for a
    // pale amber strip and turned muddy and low-contrast once the strip sat
    // on a near-black surface, so both the icon and the label now derive
    // from the accent itself and lift in dark mode.
    final onAmber = context.isDark ? AppTheme.accentAmber : const Color(0xFF7A5B00);

    return Material(
      color: context.tintedSurface(AppTheme.accentAmber),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SubscriptionPaymentScreen(snapshot: snapshot)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.s4, vertical: AppTheme.s2 + 2),
          child: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: onAmber, size: 18),
              const SizedBox(width: AppTheme.s2),
              Expanded(
                child: Text(
                  days <= 0
                      ? 'Your subscription expires today — renew now to avoid losing access.'
                      : 'Subscription expires in $days day${days == 1 ? '' : 's'} — renew to keep access.',
                  style: TextStyle(color: onAmber, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right, color: onAmber, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hamburger-menu Drawer. Primary destinations (Dashboard/Rides/
/// Expenses/Reports/Settings) jump straight to the matching bottom-nav tab;
/// secondary ones (Payment history, Log out) push/act directly since they
/// don't have a permanent home in the bottom bar.
class _AppDrawer extends StatefulWidget {
  const _AppDrawer();

  @override
  State<_AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<_AppDrawer> {
  String? _name;
  String? _phone;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final auth = context.read<AuthService>();
    final name = await auth.name;
    final phone = await auth.phone;
    if (!mounted) return;
    setState(() {
      _name = name;
      _phone = phone;
    });
  }

  Future<void> _confirmLogout() async {
    Navigator.of(context).pop(); // close the drawer first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You\'ll need to log in again to access your data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await context.read<AuthService>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RegistrationScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<AppStrings>();
    final shell = context.findAncestorStateOfType<_MainShellState>();
    final initials = (_name != null && _name!.trim().isNotEmpty)
        ? _name!.trim().split(RegExp(r'\s+')).map((p) => p[0]).take(2).join().toUpperCase()
        : 'D';

    void goToTabAndClose(int index) {
      Navigator.of(context).pop();
      shell?._goToTab(index);
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                  AppTheme.s5, AppTheme.s6, AppTheme.s5, AppTheme.s5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryDark, AppTheme.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: AppTheme.shadow(
                    tint: AppTheme.primaryDark, opacity: 0.28, blur: 16, y: 6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white,
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: AppTheme.primaryDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.s3),
                  Text(
                    (_name != null && _name!.isNotEmpty) ? _name! : 'Telebirr Driver',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3),
                  ),
                  if (_phone != null && _phone!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(_phone!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                    vertical: AppTheme.s2, horizontal: AppTheme.s2),
                children: [
                  _DrawerItem(
                    icon: Icons.dashboard_outlined,
                    label: strings.t('dashboard'),
                    onTap: () => goToTabAndClose(0),
                  ),
                  _DrawerItem(
                    icon: Icons.local_taxi_outlined,
                    label: strings.t('rides'),
                    onTap: () => goToTabAndClose(1),
                  ),
                  _DrawerItem(
                    icon: Icons.receipt_long_outlined,
                    label: strings.t('expenses'),
                    onTap: () => goToTabAndClose(2),
                  ),
                  _DrawerItem(
                    icon: Icons.payments_outlined,
                    label: strings.t('payment_history'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PaymentHistoryScreen()),
                      );
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.insights_outlined,
                    label: strings.t('reports'),
                    onTap: () => goToTabAndClose(3),
                  ),
                  const Divider(height: AppTheme.s6, indent: AppTheme.s4, endIndent: AppTheme.s4),
                  _DrawerItem(
                    icon: Icons.settings_outlined,
                    label: strings.t('settings'),
                    onTap: () => goToTabAndClose(4),
                  ),
                  _DrawerItem(
                    icon: Icons.logout,
                    label: strings.t('log_out'),
                    color: AppTheme.danger,
                    onTap: _confirmLogout,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.s4),
              child: Text(
                'Telebirr Driver Assistant',
                style: TextStyle(color: context.faintText, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.s2, vertical: 2),
      child: ListTile(
        leading: Icon(icon, color: color ?? context.subtleText, size: 22),
        title: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 14.5,
          ),
        ),
        onTap: onTap,
        dense: true,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.rSm)),
      ),
    );
  }
}

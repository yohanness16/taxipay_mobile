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
      if (phone == null) return;
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
    return Material(
      color: AppTheme.accentAmber.withOpacity(0.16),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SubscriptionPaymentScreen(snapshot: snapshot)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFB8860B), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  days <= 0
                      ? 'Your subscription expires today — renew now to avoid losing access.'
                      : 'Subscription expires in $days day${days == 1 ? '' : 's'} — renew to keep access.',
                  style: const TextStyle(color: Color(0xFF7A5B00), fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFFB8860B), size: 18),
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
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF00A651), Color(0xFF00C766)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Color(0xFF00A651),
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    (_name != null && _name!.isNotEmpty) ? _name! : 'Telebirr Driver',
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  if (_phone != null && _phone!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(_phone!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
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
                  const Divider(height: 24),
                  _DrawerItem(
                    icon: Icons.settings_outlined,
                    label: strings.t('settings'),
                    onTap: () => goToTabAndClose(4),
                  ),
                  _DrawerItem(
                    icon: Icons.logout,
                    label: strings.t('log_out'),
                    color: Colors.redAccent,
                    onTap: _confirmLogout,
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Telebirr Driver Assistant',
                style: TextStyle(color: Colors.grey, fontSize: 12),
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
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
    );
  }
}

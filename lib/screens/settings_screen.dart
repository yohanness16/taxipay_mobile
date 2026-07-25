import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/driver_settings_service.dart';
import '../services/overlay_service.dart';
import '../services/ride_manager.dart';
import '../services/sms_reader.dart';
import '../services/subscription_manager.dart';
import '../theme/theme_controller.dart';
import 'registration_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  String? _name;
  String? _phone;
  SubscriptionSnapshot? _subscription;
  bool _smsPermissionGranted = false;
  bool _overlayPermissionGranted = false;
  bool _overlayActive = false;
  double _dailyGoal = DriverSettingsService.defaultDailyGoal;
  double _serviceIntervalKm = DriverSettingsService.defaultServiceIntervalKm;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _loadOverlayStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // requestPermission() below isn't reliable across every Android version
    // at telling us the moment the user grants "Display over other apps" in
    // system Settings — some devices resolve that future too early or too
    // late. Re-checking here, when the app actually regains focus after the
    // user backs out of Settings, is the reliable signal.
    if (state == AppLifecycleState.resumed) {
      _loadOverlayStatus();
    }
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final driverSettings = context.read<DriverSettingsService>();
    final name = await auth.name;
    final phone = await auth.phone;
    final subscription = await context.read<SubscriptionManager>().checkSubscriptionStatus(phone ?? '');
    final goal = await driverSettings.getDailyGoal();
    final interval = await driverSettings.getServiceIntervalKm();
    final smsGranted = await context.read<SmsReader>().hasPermissions();
    if (!mounted) return;
    setState(() {
      _name = name;
      _phone = phone;
      _subscription = subscription;
      _dailyGoal = goal;
      _serviceIntervalKm = interval;
      _smsPermissionGranted = smsGranted;
    });
  }

  Future<void> _loadOverlayStatus() async {
    final overlay = context.read<OverlayService>();
    final permGranted = await overlay.isPermissionGranted();
    final active = await overlay.isActive();
    if (!mounted) return;
    setState(() {
      _overlayPermissionGranted = permGranted;
      _overlayActive = active;
    });
  }

  bool _smsPermissionBusy = false;

  Future<void> _requestSmsPermission() async {
    if (_smsPermissionBusy) return;
    setState(() => _smsPermissionBusy = true);
    try {
      final granted = await context.read<SmsReader>().requestPermissions();
      if (!mounted) return;
      setState(() => _smsPermissionGranted = granted);
    } finally {
      if (mounted) setState(() => _smsPermissionBusy = false);
    }
  }

  bool _overlayBusy = false;

  Future<void> _toggleOverlay() async {
    if (_overlayBusy) return; // ignore rapid re-taps while a toggle is in flight
    setState(() => _overlayBusy = true);
    final overlay = context.read<OverlayService>();

    try {
      if (!_overlayPermissionGranted) {
        await overlay.requestPermission();
        if (!mounted) return;
        final actuallyGranted = await overlay.isPermissionGranted();
        setState(() => _overlayPermissionGranted = actuallyGranted);
        if (!actuallyGranted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Overlay permission was not granted.')),
          );
          return;
        }
      }

      if (_overlayActive) {
        await overlay.stop();
      } else {
        await overlay.start();
      }

      final nowActive = await overlay.isActive();

      if (!mounted) return;
      setState(() => _overlayActive = nowActive);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nowActive ? 'Overlay started' : 'Overlay stopped')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Overlay error: $e')),
      );
    } finally {
      if (mounted) setState(() => _overlayBusy = false);
    }
  }
  Future<void> _scanInboxNow() async {
    setState(() => _scanning = true);
    try {
      final smsReader = context.read<SmsReader>();
      final rideManager = context.read<RideManager>();

      final granted = await smsReader.requestPermissions();
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SMS permission is required to scan the inbox.')),
        );
        return;
      }

      final found = await smsReader.scanInbox();
      int added = 0;
      for (final payment in found) {
        final id = await rideManager.linkPaymentToRide(payment);
        if (id != null) added++;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scanned inbox: found ${found.length}, added $added new payment(s).')),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _editDailyGoal() async {
    final ctrl = TextEditingController(text: _dailyGoal.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daily earnings goal'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'ETB'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result <= 0) return;
    await context.read<DriverSettingsService>().setDailyGoal(result);
    setState(() => _dailyGoal = result);
  }

  Future<void> _editServiceInterval() async {
    final ctrl = TextEditingController(text: _serviceIntervalKm.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Service interval'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'km'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result <= 0) return;
    await context.read<DriverSettingsService>().setServiceIntervalKm(result);
    setState(() => _serviceIntervalKm = result);
  }

  Future<void> _markServiceDone() async {
    final rideManager = context.read<RideManager>();
    final driverSettings = context.read<DriverSettingsService>();
    final totalDistance = await rideManager.getTotalDistanceKm();
    await driverSettings.markServiceDoneAt(totalDistance);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Service reminder reset.')),
    );
  }

  Future<void> _exportData() async {
    final backup = context.read<BackupService>();
    await backup.exportAll();
  }

  Future<void> _logout() async {
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

    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: Text(strings.t('settings'))) : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(_name ?? '...'),
              subtitle: Text(_phone ?? ''),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(
                _subscription?.paid == true ? Icons.verified : Icons.warning_amber,
                color: _subscription?.paid == true ? Colors.green : Colors.orange,
              ),
              title: Text(_subscription?.paid == true ? 'Subscription active' : 'Subscription inactive'),
              subtitle: Text(
                _subscription?.expires != null
                    ? 'Expires ${DateFormat.yMMMd().format(_subscription!.expires!)}'
                    : 'No subscription data',
              ),
            ),
          ),

          const SizedBox(height: 20),
          Text('Payments', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sms_outlined),
              title: const Text('SMS reading permission'),
              subtitle: Text(_smsPermissionGranted ? 'Granted' : 'Required to auto-capture Telebirr payments'),
              trailing: FilledButton(
                onPressed: _smsPermissionBusy ? null : _requestSmsPermission,
                child: _smsPermissionBusy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_smsPermissionGranted ? 'Granted' : 'Grant'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.search),
              title: Text(strings.t('scan_inbox')),
              subtitle: const Text('Pull in any existing Telebirr messages already in your inbox'),
              trailing: _scanning
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : FilledButton(onPressed: _scanInboxNow, child: const Text('Scan')),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.blur_circular),
              title: const Text('Floating payment bubble'),
              subtitle: Text(
                !_overlayPermissionGranted
                    ? 'Requires "Display over other apps" permission'
                    : _overlayActive
                        ? 'Active — shows over other apps'
                        : 'Off',
              ),
              value: _overlayActive,
              onChanged: _overlayBusy ? null : (_) => _toggleOverlay(),
            ),
          ),

          const SizedBox(height: 20),
          Text('Goals & vehicle', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(strings.t('daily_goal')),
              subtitle: Text('${_dailyGoal.toStringAsFixed(0)} ETB / day'),
              trailing: TextButton(onPressed: _editDailyGoal, child: const Text('Edit')),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.build_outlined),
              title: const Text('Service interval'),
              subtitle: Text('Every ${_serviceIntervalKm.toStringAsFixed(0)} km'),
              trailing: TextButton(onPressed: _editServiceInterval, child: const Text('Edit')),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Just had your vehicle serviced?'),
              trailing: OutlinedButton(onPressed: _markServiceDone, child: const Text('Reset reminder')),
            ),
          ),

          const SizedBox(height: 20),
          Text('App', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.dark_mode_outlined),
                      const SizedBox(width: 12),
                      Text('Theme', style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Builder(builder: (context) {
                    final themeController = context.watch<ThemeController>();
                    return SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
                        ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Light')),
                        ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Auto')),
                      ],
                      selected: {themeController.mode},
                      onSelectionChanged: (s) => themeController.setMode(s.first),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.language),
              title: Text(strings.t('language')),
              trailing: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'en', label: Text('English')),
                  ButtonSegment(value: 'am', label: Text('አማርኛ')),
                ],
                selected: {strings.languageCode},
                onSelectionChanged: (s) => strings.setLanguage(s.first),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.ios_share),
              title: Text(strings.t('export_backup')),
              subtitle: const Text('Share your rides/payments/expenses as CSV files'),
              trailing: FilledButton(onPressed: _exportData, child: const Text('Export')),
            ),
          ),

          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: Text(strings.t('log_out')),
          ),
        ],
      ),
    );
  }
}

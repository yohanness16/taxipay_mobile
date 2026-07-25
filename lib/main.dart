import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_config.dart';
import 'localization/app_strings.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/backup_service.dart';
import 'services/driver_settings_service.dart';
import 'services/expense_tracker.dart';
import 'services/overlay_service.dart';
import 'services/report_service.dart';
import 'services/ride_manager.dart';
import 'services/sms_reader.dart';
import 'services/subscription_manager.dart';
import 'services/sync_manager.dart';
import 'screens/splash_screen.dart';
import 'overlay/payment_overlay.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fire-and-forget: creates the Android notification channel up front so
  // it exists (with sound/vibration configured) before the first payment
  // ever arrives, rather than lazily on first use.
  NotificationService.instance.init();
  runApp(const TelebirrDriverApp());
}

/// Entry point for the overlay's separate isolate/engine. Must be declared
/// directly in main.dart (not in payment_overlay.dart or any other file) --
/// flutter_overlay_window's native side resolves this function by name
/// within the app's main entrypoint library, and a top-level function
/// declared in a different Dart file lives in a different library, so it
/// can't be found from there even though it's still imported/compiled in.
/// The actual overlay UI (PaymentOverlayApp) can and does live in its own
/// file -- only this thin entrypoint function itself needs to be here.
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PaymentOverlayApp());
}

class TelebirrDriverApp extends StatelessWidget {
  const TelebirrDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    final apiService = ApiService(baseUrl: AppConfig.backendBaseUrl);
    final authService = AuthService(api: apiService);
    final subscriptionManager = SubscriptionManager(api: apiService);
    final rideManager = RideManager();
    final expenseTracker = ExpenseTracker();
    final driverSettings = DriverSettingsService();

    return MultiProvider(
      providers: [
        Provider<ApiService>.value(value: apiService),
        Provider<AuthService>.value(value: authService),
        Provider<SubscriptionManager>.value(value: subscriptionManager),
        Provider<SyncManager>(create: (_) => SyncManager(subscriptionManager: subscriptionManager)),
        Provider<RideManager>.value(value: rideManager),
        Provider<ExpenseTracker>.value(value: expenseTracker),
        Provider<SmsReader>(create: (_) => SmsReader()),
        Provider<OverlayService>(create: (_) => OverlayService()),
        Provider<DriverSettingsService>.value(value: driverSettings),
        Provider<BackupService>(
          create: (_) => BackupService(rideManager: rideManager, expenseTracker: expenseTracker),
        ),
        Provider<ReportService>(
          create: (_) => ReportService(rideManager: rideManager, expenseTracker: expenseTracker),
        ),
        ChangeNotifierProvider<AppStrings>(create: (_) => AppStrings(settings: driverSettings)),
        ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()..load()),
      ],
      child: Consumer<ThemeController>(
        builder: (context, themeController, _) => MaterialApp(
          title: 'Telebirr Driver Assistant',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeController.mode,
          home: const SplashScreen(),
        ),
      ),
    );
  }
}

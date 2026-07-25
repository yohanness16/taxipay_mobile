import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around `flutter_local_notifications` dedicated to the
/// "Telebirr payment received" alert. Kept deliberately separate from
/// [OverlayService]'s own notification-*permission* handling: this class
/// owns the actual channel + the act of showing a notification, and is
/// safe to call from either the main isolate (foreground SMS listener) or
/// the background isolate spawned for [backgroundMessageHandler] -- both
/// paths call [init] first, which is idempotent.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'telebirr_payments';
  static const String _channelName = 'Payment alerts';
  static const String _channelDescription =
      'Notifies you with a sound whenever a new Telebirr payment SMS arrives.';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _notificationId = 1000;

  Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings);

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// Shows the "payment received" alert. Safe to call repeatedly -- each
  /// call gets its own notification id so consecutive payments stack
  /// instead of replacing one another.
  Future<void> showPaymentReceived({
    required double amount,
    required String payerPhone,
  }) async {
    await init();
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      _notificationId++,
      'Payment received',
      '+${amount.toStringAsFixed(0)} ETB from $payerPhone',
      details,
    );
  }
}

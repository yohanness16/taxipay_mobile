import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:telephony/telephony.dart';

import '../db/database_helper.dart';
import '../models/payment.dart';
import 'notification_service.dart';
import 'overlay_service.dart';
import 'ride_manager.dart';
import 'subscription_payment_queue.dart';
import 'telebirr_sms_parser.dart';

/// Reads incoming SMS on-device and extracts Telebirr payment notifications
/// sent from short code 127. This is Android-only (the `telephony` package
/// has no iOS support — iOS restricts third-party SMS access entirely).
///
/// This is always-on: [startListening] registers both a foreground
/// callback (while the app is open) and a background isolate entry point
/// (`backgroundMessageHandler`, below) that Android invokes even if the
/// app process isn't running, so a message from 127 never needs a manual
/// "scan inbox" tap to be picked up.
class SmsReader {
  final Telephony telephony = Telephony.instance;

  static const String telebirrSenderId = '127';

  // IMPORTANT: permissions are requested through `permission_handler`
  // (a maintained package), never through `telephony`'s own
  // `requestSmsPermissions` / `requestPhoneAndSmsPermissions`. The
  // `telephony` package (shounakmulay/Telephony) is archived -- no more
  // fixes will ever land -- and its native permission-request handler has
  // a long-standing, widely reported bug: Android can call
  // `onRequestPermissionsResult` a second time for the same request (this
  // has nothing to do with our own code calling it twice), and the plugin
  // tries to reply to that one platform-channel call twice, which throws
  // `IllegalStateException: Reply already submitted` and takes down the
  // whole app. It reproduces exactly as reported: permission dialog #1 is
  // granted fine, then the crash hits on the *second* prompt/callback.
  //
  // The fix is to never call telephony's request methods at all. Once
  // `Permission.sms` is already granted (checked via permission_handler),
  // `telephony`'s own internal `ContextCompat.checkSelfPermission` check
  // short-circuits and it skips its buggy request path entirely -- so the
  // rest of this class (startListening/scanInbox) is completely unaffected
  // and untouched.
  Future<bool>? _pendingRequest;

  Future<bool> requestPermissions() {
    final pending = _pendingRequest;
    if (pending != null) return pending;

    final request = _requestPermissionsOnce();
    _pendingRequest = request;
    request.whenComplete(() => _pendingRequest = null);
    return request;
  }

  Future<bool> _requestPermissionsOnce() async {
    final status = await ph.Permission.sms.request();
    return status.isGranted;
  }

  /// Checks current OS permission status without ever showing a dialog --
  /// use this to initialize UI state (e.g. Settings' "Granted"/"Grant"
  /// label) instead of assuming "not granted" until the user taps a button.
  Future<bool> hasPermissions() async {
    return (await ph.Permission.sms.status).isGranted;
  }

  void startListening(void Function(Payment payment) onPaymentSaved) {
    telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) async {
        if (!_isFromTelebirr(message.address)) return;
        await _handleMessage(message.body ?? '', onPaymentSaved: onPaymentSaved);
      },
      onBackgroundMessage: backgroundMessageHandler,
      listenInBackground: true,
    );
  }

  /// One-off scan of existing inbox messages from 127 (useful right after
  /// permission grant, or for a manual "re-scan" action in Settings) --
  /// this is a convenience extra, not required for normal operation since
  /// [startListening] already catches everything live.
  Future<List<Payment>> scanInbox({int limit = 200}) async {
    final messages = await telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      filter: SmsFilter.where(SmsColumn.ADDRESS).equals(telebirrSenderId),
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );

    final payments = <Payment>[];
    for (final m in messages.take(limit)) {
      final parsed = TelebirrSmsParser.parse(m.body ?? '');
      if (parsed != null && parsed.kind == TelebirrMessageKind.received) {
        payments.add(_toPayment(parsed, m.body ?? ''));
      }
    }
    return payments;
  }

  bool _isFromTelebirr(String? address) {
    if (address == null) return false;
    return address.contains(telebirrSenderId) || address.toLowerCase().contains('telebirr');
  }

  Payment _toPayment(ParsedTelebirrMessage parsed, String rawMessage) => Payment(
        amount: parsed.amount,
        payerPhone: parsed.maskedPhone ?? 'Unknown',
        payerName: parsed.payerName,
        transactionId: parsed.transactionId,
        receivedAt: parsed.transactionDate ?? DateTime.now(),
        telebirrMessage: rawMessage,
      );
}

/// Shared by both the foreground listener and the background isolate:
/// classifies the message, and either treats it as ride revenue or as a
/// candidate subscription-payment confirmation. Kept as a bare top-level
/// function (not a method) so it has zero dependency on BuildContext or
/// Provider, since the background isolate has neither. [onPaymentSaved], if
/// given, is fired purely as a "refresh your UI" signal for a foreground
/// screen that's already showing -- the actual save always goes through
/// [saveRidePayment] regardless of whether the app is foregrounded, so
/// there's exactly one code path (and one set of duplicate-SMS guards) for
/// both cases.
Future<void> _handleMessage(String body, {void Function(Payment payment)? onPaymentSaved}) async {
  final parsed = TelebirrSmsParser.parse(body);
  if (parsed == null) return;

  if (parsed.kind == TelebirrMessageKind.received) {
    final payment = Payment(
      amount: parsed.amount,
      payerPhone: parsed.maskedPhone ?? 'Unknown',
      payerName: parsed.payerName,
      transactionId: parsed.transactionId,
      receivedAt: parsed.transactionDate ?? DateTime.now(),
      telebirrMessage: body,
    );
    final savedId = await saveRidePayment(payment);
    if (savedId != null) onPaymentSaved?.call(payment);
    return;
  }

  // Not ride revenue (a "sent"/"transferred"/other Telebirr notification).
  // Only worth acting on if the driver is actively waiting on their own
  // subscription payment to confirm -- otherwise, ignore it entirely so
  // random Telebirr chatter never gets sent to the backend.
  if (parsed.transactionId == null) return;
  if (!await SubscriptionPaymentQueue.instance.isAwaitingPayment()) return;
  await SubscriptionPaymentQueue.instance.enqueue(amount: parsed.amount, smsText: body);
}

/// Saves a parsed ride payment (linking it to whatever ride is currently
/// active, if any), fires the sound notification, and nudges the overlay
/// bubble if it's on-screen. Returns the new local row id, or null if this
/// exact SMS body was already stored (duplicate).
Future<int?> saveRidePayment(Payment payment) async {
  final rideManager = RideManager();
  final activeRideId = await DatabaseHelper.instance.getActiveRideId();
  final savedId = await rideManager.linkPaymentToRide(payment, rideId: activeRideId);
  if (savedId == null) return null; // duplicate SMS, ignore

  try {
    await NotificationService.instance.showPaymentReceived(
      amount: payment.amount,
      payerPhone: payment.payerPhone,
    );
  } catch (_) {
    // Non-fatal: the payment is already saved regardless of whether the
    // notification/sound successfully shows on this device.
  }

  try {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final todayTotal = await rideManager.getTotalEarnings(from: startOfDay);
    final todayPayments = await rideManager.getAllPayments(from: startOfDay);

    final overlay = OverlayService();
    if (await overlay.isActive()) {
      await overlay.pushPaymentUpdate(
        todayCount: todayPayments.length,
        todayTotal: todayTotal,
        recentPayments: todayPayments,
      );
    }
  } catch (_) {
    // Best-effort nudge to the bubble -- payment is already safely saved.
  }

  return savedId;
}

/// Runs in a separate background isolate that Android spawns specifically to
/// handle this callback — it exists independently of your main app's widget
/// tree/Provider setup, which is why everything it touches ([RideManager],
/// [DatabaseHelper], [SubscriptionPaymentQueue]) only needs plain SQLite
/// access, not BuildContext.
@pragma('vm:entry-point')
Future<void> backgroundMessageHandler(SmsMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();

  final address = message.address;
  if (address == null) return;
  if (!address.contains(SmsReader.telebirrSenderId) && !address.toLowerCase().contains('telebirr')) return;

  await _handleMessage(message.body ?? '');
}

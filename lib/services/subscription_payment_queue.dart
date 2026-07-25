import 'package:connectivity_plus/connectivity_plus.dart';

import '../app_config.dart';
import '../db/database_helper.dart';
import 'api_service.dart';
import 'subscription_manager.dart';

/// Local, offline-first queue of "the driver just paid their subscription
/// via Telebirr, here's the confirmation SMS" attempts.
///
/// Why a queue instead of calling the backend directly and hoping: the
/// driver may be offline (no data, weak signal) at the exact moment the
/// confirmation SMS arrives. Every attempt is persisted to SQLite first,
/// then flushed opportunistically -- so nothing is ever lost, and the app
/// can show an accurate "N payments pending verification" counter no
/// matter what the network is doing. Callable from any isolate (no
/// BuildContext/Provider dependency), so both the foreground app and the
/// SMS background isolate can enqueue into the same table.
class SubscriptionPaymentQueue {
  SubscriptionPaymentQueue._();
  static final SubscriptionPaymentQueue instance = SubscriptionPaymentQueue._();

  final _dbHelper = DatabaseHelper.instance;

  static const _awaitingKey = 'awaiting_subscription_payment';
  static const _awaitingAmountKey = 'awaiting_subscription_amount';
  static const _awaitingUntilKey = 'awaiting_subscription_until';
  static const _driverIdKey = 'driver_id'; // mirrored by AuthService

  /// Call when the driver taps "I've sent the payment" -- arms a 15-minute
  /// window during which any non-ride-revenue Telebirr SMS gets treated as
  /// a candidate subscription-payment confirmation and auto-submitted,
  /// with no further taps required.
  Future<void> markAwaitingPayment(double amount) async {
    final until = DateTime.now().add(const Duration(minutes: 15));
    await _dbHelper.setSetting(_awaitingKey, 'true');
    await _dbHelper.setSetting(_awaitingAmountKey, amount.toString());
    await _dbHelper.setSetting(_awaitingUntilKey, until.toIso8601String());
  }

  Future<void> clearAwaiting() async {
    await _dbHelper.deleteSetting(_awaitingKey);
    await _dbHelper.deleteSetting(_awaitingAmountKey);
    await _dbHelper.deleteSetting(_awaitingUntilKey);
  }

  Future<bool> isAwaitingPayment() async {
    final flag = await _dbHelper.getSetting(_awaitingKey);
    if (flag != 'true') return false;
    final untilStr = await _dbHelper.getSetting(_awaitingUntilKey);
    final until = untilStr != null ? DateTime.tryParse(untilStr) : null;
    if (until == null || DateTime.now().isAfter(until)) {
      await clearAwaiting();
      return false;
    }
    return true;
  }

  /// Queues a candidate confirmation SMS and immediately tries to flush it
  /// (best-effort -- if offline, it just stays queued for later).
  Future<void> enqueue({required double amount, required String smsText}) async {
    final db = await _dbHelper.database;
    await db.insert('pending_subscription_payments', {
      'amount': amount,
      'sms_text': smsText,
      'status': 'queued',
      'attempts': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    await flush();
  }

  Future<int> pendingCount() async {
    final db = await _dbHelper.database;
    final rows = await db.query('pending_subscription_payments', where: "status = 'queued'");
    return rows.length;
  }

  Future<bool> _isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// Attempts to verify every queued payment against the backend. Safe to
  /// call opportunistically (app resume, connectivity restored, a timer
  /// while the payment screen is open) -- it's a no-op when there's
  /// nothing queued or the driver isn't logged in yet.
  ///
  /// Returns the freshest [SubscriptionSnapshot] if any attempt succeeded,
  /// so callers can immediately unlock the UI without waiting for the next
  /// periodic subscription re-check.
  Future<SubscriptionSnapshot?> flush() async {
    if (!await _isOnline()) return null;

    final driverIdStr = await _dbHelper.getSetting(_driverIdKey);
    final driverId = driverIdStr != null ? int.tryParse(driverIdStr) : null;
    if (driverId == null) return null;

    final db = await _dbHelper.database;
    final rows = await db.query('pending_subscription_payments', where: "status = 'queued'");
    if (rows.isEmpty) return null;

    final api = ApiService(baseUrl: AppConfig.backendBaseUrl);
    SubscriptionSnapshot? latest;

    for (final row in rows) {
      final id = row['id'] as int;
      final amount = (row['amount'] as num).toDouble();
      final smsText = row['sms_text'] as String;

      try {
        final res = await api.verifyTelebirrPayment(driverId: driverId, amount: amount, smsText: smsText);
        final success = res['success'] == true;

        if (success) {
          await db.delete('pending_subscription_payments', where: 'id = ?', whereArgs: [id]);
          await clearAwaiting();

          final extendedUntil = (res['data'] as Map?)?['extendedUntil']?.toString();
          final expires = extendedUntil != null ? DateTime.tryParse(extendedUntil) : null;
          if (expires != null) {
            latest = await SubscriptionManager.persistConfirmedPayment(expires);
          }
        } else {
          // 404 (no matching notification yet -- gateway webhook may just
          // not have caught up) is worth retrying; 409/422 (duplicate /
          // unparseable) never will be, so stop wasting attempts on those.
          final statusCode = res['_statusCode'] as int?;
          final permanent = statusCode == 409 || statusCode == 422;
          await db.update(
            'pending_subscription_payments',
            {
              'status': permanent ? 'rejected' : 'queued',
              'attempts': (row['attempts'] as int) + 1,
              'last_error': res['message']?.toString(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      } catch (_) {
        // Network/server error -- leave queued, will retry next flush.
        await db.update(
          'pending_subscription_payments',
          {'attempts': (row['attempts'] as int) + 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }

    return latest;
  }
}

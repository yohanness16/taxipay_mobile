import '../db/database_helper.dart';
import '../models/payment.dart';
import '../models/ride.dart';

class RideManager {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> createRide(Ride ride) async {
    final db = await _dbHelper.database;
    return db.insert('rides', ride.toMap()..remove('id'));
  }

  Future<void> endRide(int rideId, {DateTime? endTime}) async {
    final db = await _dbHelper.database;
    await db.update(
      'rides',
      {'end_time': (endTime ?? DateTime.now()).toIso8601String()},
      where: 'id = ?',
      whereArgs: [rideId],
    );
  }

  /// Manually logs a cash fare -- passengers who paid cash (very common on
  /// minibus/shared-taxi routes) never generate a Telebirr SMS, so without
  /// this every cash fare would be invisible to earnings/reports. Counts
  /// toward the same totals as Telebirr payments (getTotalEarnings,
  /// getAllPayments, reports) since they all just read from the same
  /// `payments` table regardless of method.
  Future<int> logCashPayment({required double amount, String? note, int? rideId}) async {
    final db = await _dbHelper.database;
    final payment = Payment(
      amount: amount,
      payerPhone: 'Cash',
      payerName: note,
      receivedAt: DateTime.now(),
      method: PaymentMethod.cash,
    );
    return db.insert('payments', payment.toMap()
      ..remove('id')
      ..['ride_id'] = rideId ?? await _dbHelper.getActiveRideId());
  }

  /// Saves an incoming Telebirr payment and (optionally) links it to a ride.
  /// Returns the local payment row id, or null if it was a duplicate
  /// (same SMS body already stored — the unique index on telebirr_message
  /// enforces this at the DB level).
  Future<int?> linkPaymentToRide(Payment payment, {int? rideId}) async {
    final db = await _dbHelper.database;
    try {
      return await db.insert('payments', payment.toMap()
        ..remove('id')
        ..['ride_id'] = rideId);
    } on Exception {
      // Unique constraint violation -> duplicate SMS, ignore.
      return null;
    }
  }

  Future<Ride?> getRide(int rideId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('rides', where: 'id = ?', whereArgs: [rideId]);
    if (rows.isEmpty) return null;
    return Ride.fromMap(rows.first);
  }

  Future<List<Ride>> getRideHistory({DateTime? from, DateTime? to}) async {
    final db = await _dbHelper.database;
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('start_time >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('start_time <= ?');
      args.add(to.toIso8601String());
    }
    final rows = await db.query(
      'rides',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'start_time DESC',
    );
    return rows.map(Ride.fromMap).toList();
  }

  Future<List<Payment>> getPaymentsForRide(int rideId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('payments', where: 'ride_id = ?', whereArgs: [rideId]);
    return rows.map(Payment.fromMap).toList();
  }

  Future<List<Payment>> getAllPayments({DateTime? from, DateTime? to}) async {
    final db = await _dbHelper.database;
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('received_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('received_at <= ?');
      args.add(to.toIso8601String());
    }
    final rows = await db.query(
      'payments',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'received_at DESC',
    );
    return rows.map(Payment.fromMap).toList();
  }

  Future<double> getTotalEarnings({DateTime? from, DateTime? to}) async {
    final payments = await getAllPayments(from: from, to: to);
    return payments.fold<double>(0.0, (sum, p) => sum + p.amount);
  }

  /// All-time (or ranged) total distance driven, used for service/maintenance
  /// interval reminders (e.g. "service due every 5,000 km").
  Future<double> getTotalDistanceKm({DateTime? from, DateTime? to}) async {
    final rides = await getRideHistory(from: from, to: to);
    return rides.fold<double>(0.0, (sum, r) => sum + r.distanceKm);
  }
}

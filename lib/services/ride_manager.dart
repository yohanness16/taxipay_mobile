import '../db/database_helper.dart';
import '../models/payment.dart';
import '../models/ride.dart';
import 'sms_reader.dart';

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
  ///
  /// Routes through [saveRidePayment] with `notify: false` so the overlay
  /// totals and badge update immediately, without firing an unnecessary
  /// system notification sound for a fare the driver just manually entered.
  Future<int> logCashPayment({required double amount, String? note, int? rideId}) async {
    final payment = Payment(
      amount: amount,
      payerPhone: 'Cash',
      payerName: note,
      receivedAt: DateTime.now(),
      method: PaymentMethod.cash,
    );
    final savedId = await saveRidePayment(
      payment,
      notify: false,
      explicitRideId: rideId,
    );
    return savedId ?? 0;
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

  /// Payments in a date range, newest first.
  ///
  /// [byArrival] switches which of the two timestamps on a payment is used,
  /// for both the range filter and the ordering:
  ///
  ///  * `false` (default) uses `received_at` -- the transaction time printed
  ///    inside the Telebirr SMS. This is what earnings, reports, history and
  ///    CSV export want: "the money that moved on this date", in the order
  ///    the driver remembers it happening.
  ///  * `true` uses `arrived_at` -- when the row was written on this device.
  ///    This is what the overlay wants. Using `received_at` there had two
  ///    consequences: the list order disagreed with the order things actually
  ///    popped up, and a payment transacted just before midnight but
  ///    delivered just after it fell outside "today" entirely, so it never
  ///    entered the overlay's window and was never counted as an arrival.
  ///
  /// `arrived_at` is read as a plain column rather than
  /// `IFNULL(arrived_at, received_at)` so the index on it stays usable. That
  /// is safe because the v4 migration backfills every pre-existing row and
  /// [Payment.toMap] always writes the column, so there is no path that
  /// produces a NULL.
  Future<List<Payment>> getAllPayments(
      {DateTime? from, DateTime? to, bool byArrival = false}) async {
    final db = await _dbHelper.database;
    final column = byArrival ? 'arrived_at' : 'received_at';
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('$column >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('$column <= ?');
      args.add(to.toIso8601String());
    }
    final rows = await db.query(
      'payments',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: '$column DESC',
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

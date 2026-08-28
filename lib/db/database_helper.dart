import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Central helper for the local, offline-first SQLite database.
/// All ride, payment, and expense data lives here on-device; only
/// registration + subscription data goes to the backend/Supabase.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const int _dbVersion = 4;

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'telebirr_driver.db');

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE rides (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        driver_phone TEXT,
        start_time TEXT NOT NULL,
        end_time TEXT,
        distance REAL DEFAULT 0,
        notes TEXT,
        created_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ride_id INTEGER,
        amount REAL NOT NULL,
        payer_phone TEXT,
        payer_name TEXT,
        transaction_id TEXT,
        received_at TEXT NOT NULL,
        -- Device-clock stamp for when the row was created, as opposed to
        -- received_at which is the timestamp printed inside the Telebirr
        -- SMS body. Declared nullable purely so this matches the shape the
        -- v4 upgrade path can produce (SQLite cannot add a NOT NULL column
        -- without a constant default). Dart always populates it, and
        -- Payment.fromMap falls back to received_at if it is ever missing.
        arrived_at TEXT,
        telebirr_message TEXT,
        payment_method TEXT NOT NULL DEFAULT 'telebirr',
        synced INTEGER DEFAULT 0,
        FOREIGN KEY (ride_id) REFERENCES rides (id)
      );
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT,
        expense_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        synced INTEGER DEFAULT 0
      );
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      );
    ''');

    // Local queue of subscription-payment SMS confirmations that still need
    // to be verified against the backend -- this is what powers the
    // "pending" counter in the payment UI, and lets the app work offline:
    // entries just sit here, retried automatically whenever connectivity
    // returns, instead of the payment attempt being lost.
    await db.execute('''
      CREATE TABLE pending_subscription_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        sms_text TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'queued', -- queued | rejected
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL
      );
    ''');

    // Dedupe guard so the same SMS is never parsed into two payments.
    await db.execute('''
      CREATE UNIQUE INDEX idx_payments_message ON payments (telebirr_message)
      WHERE telebirr_message IS NOT NULL;
    ''');

    // The overlay's "what is new since I last looked" query orders by
    // arrival, and the reports/history screens order by transaction time.
    await db.execute(
        'CREATE INDEX idx_payments_arrived_at ON payments (arrived_at);');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE payments ADD COLUMN payer_name TEXT');
      await db.execute('ALTER TABLE payments ADD COLUMN transaction_id TEXT');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_subscription_payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          amount REAL NOT NULL,
          sms_text TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'queued',
          attempts INTEGER NOT NULL DEFAULT 0,
          last_error TEXT,
          created_at TEXT NOT NULL
        );
      ''');
    }
    if (oldVersion < 3) {
      await db.execute("ALTER TABLE payments ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'telebirr'");
    }
    if (oldVersion < 4) {
      // Separates "when the money moved" (received_at, read out of the SMS
      // text) from "when this device saw it" (arrived_at, device clock at
      // insert). The overlay's new-payment detection needs the latter:
      // received_at can go backwards between two consecutive arrivals when
      // SMS delivery reorders, which made genuinely new payments compare as
      // "not newer" and get silently dropped from the badge.
      //
      // Added nullable because SQLite cannot add a NOT NULL column without a
      // constant default, and the correct value is per-row. Backfilled from
      // received_at immediately, which is the best estimate available for
      // history that predates the column.
      await db.execute('ALTER TABLE payments ADD COLUMN arrived_at TEXT');
      await db.execute(
          'UPDATE payments SET arrived_at = received_at WHERE arrived_at IS NULL');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_payments_arrived_at ON payments (arrived_at)');
    }
  }

  // ---- Settings key/value helpers (JWT token cache, cached subscription, etc.) ----

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> deleteSetting(String key) async {
    final db = await database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  // ---- Active-ride pointer, shared across the main isolate, the SMS ----
  // background isolate, and the overlay isolate (all three talk to the
  // same SQLite file via sqflite's native channel, so a plain settings
  // row is enough -- no need for a separate IPC mechanism).
  static const String activeRideIdKey = 'active_ride_id';

  Future<int?> getActiveRideId() async {
    final raw = await getSetting(activeRideIdKey);
    return raw != null ? int.tryParse(raw) : null;
  }

  Future<void> setActiveRideId(int? rideId) async {
    if (rideId == null) {
      await deleteSetting(activeRideIdKey);
    } else {
      await setSetting(activeRideIdKey, rideId.toString());
    }
  }
}

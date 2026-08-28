import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../db/database_helper.dart';
import 'api_service.dart';
import 'device_identity.dart';

/// Handles driver registration/login against the backend and securely
/// caches the JWT + phone number on-device for subsequent app launches.
class AuthService {
  AuthService({required this.api, DeviceIdentity? deviceIdentity}) : _deviceIdentity = deviceIdentity ?? DeviceIdentity();

  final ApiService api;
  final DeviceIdentity _deviceIdentity;
  final _secureStorage = const FlutterSecureStorage();
  final _dbHelper = DatabaseHelper.instance;

  static const _tokenKey = 'jwt_token';
  static const _phoneKey = 'driver_phone';
  static const _nameKey = 'driver_name';
  static const _driverIdKey = 'driver_id';

  Future<void> register({
    required String phone,
    required String name,
    String? vehicleNumber,
    required String password,
  }) async {
    final deviceId = await _deviceIdentity.getId();
    final res = await api.register(
      phone: phone,
      name: name,
      vehicleNumber: vehicleNumber,
      password: password,
      deviceId: deviceId,
    );
    await _persistSession(
      token: _requireToken(res),
      phone: phone,
      name: name,
      driverId: _requireDriverId(res),
    );
  }

  Future<void> login({required String phone, required String password}) async {
    final deviceId = await _deviceIdentity.getId();
    final res = await api.login(phone: phone, password: password, deviceId: deviceId);
    await _persistSession(
      token: _requireToken(res),
      phone: phone,
      name: res['name']?.toString() ?? '',
      driverId: _requireDriverId(res),
    );
  }

  /// Reads `token` defensively. A blind `res['token'] as String` threw a raw
  /// TypeError (not an ApiException) whenever the field was missing, which
  /// slipped past the UI's `on ApiException` handler and surfaced as an
  /// opaque "something went wrong" with the real cause swallowed.
  String _requireToken(Map<String, dynamic> res) {
    final token = res['token'];
    if (token is! String || token.isEmpty) {
      throw ApiException('Sign-in succeeded but no session token was returned.', res['_statusCode'] as int? ?? 0);
    }
    return token;
  }

  /// `driverId` arrives as a JSON number; decoding can yield int or double
  /// depending on the payload, so normalise instead of casting straight to
  /// int (which throws on a double).
  int _requireDriverId(Map<String, dynamic> res) {
    final raw = res['driverId'];
    final id = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    if (id == null) {
      throw ApiException('Sign-in succeeded but no account id was returned.', res['_statusCode'] as int? ?? 0);
    }
    return id;
  }

  Future<void> _persistSession({
    required String token,
    required String phone,
    required String name,
    required int driverId,
  }) async {
    await _secureStorage.write(key: _tokenKey, value: token);
    await _secureStorage.write(key: _phoneKey, value: phone);
    await _secureStorage.write(key: _nameKey, value: name);
    await _secureStorage.write(key: _driverIdKey, value: driverId.toString());

    // Mirrored into the plain SQLite settings table (not secret -- just a
    // phone number + numeric id) so the SMS background isolate and overlay
    // isolate can read it synchronously via plain SQL, without depending on
    // flutter_secure_storage's platform channel being ready in whichever
    // isolate context Android decided to spawn.
    await _dbHelper.setSetting(_phoneKey, phone);
    await _dbHelper.setSetting(_driverIdKey, driverId.toString());
  }

  Future<String?> get token => _secureStorage.read(key: _tokenKey);
  Future<String?> get phone => _secureStorage.read(key: _phoneKey);
  Future<String?> get name => _secureStorage.read(key: _nameKey);

  Future<int?> get driverId async {
    final raw = await _secureStorage.read(key: _driverIdKey);
    if (raw != null) return int.tryParse(raw);
    // Fall back to the mirrored copy if secure storage isn't reachable yet.
    final mirrored = await _dbHelper.getSetting(_driverIdKey);
    return mirrored != null ? int.tryParse(mirrored) : null;
  }

  Future<bool> get isLoggedIn async => (await token) != null;

  Future<void> logout() async {
    await _secureStorage.deleteAll();
    await _dbHelper.deleteSetting(_phoneKey);
    await _dbHelper.deleteSetting(_driverIdKey);
  }
}

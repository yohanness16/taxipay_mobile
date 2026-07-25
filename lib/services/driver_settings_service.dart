import '../db/database_helper.dart';

/// Small driver-configurable preferences, stored in the same local
/// `settings` key/value table used for cached subscription status. All of
/// these are personal, on-device settings — nothing here touches the
/// backend.
class DriverSettingsService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  static const _dailyGoalKey = 'daily_goal_etb';
  static const _languageKey = 'language_code'; // 'en' | 'am'
  static const _serviceIntervalKmKey = 'service_interval_km';
  static const _lastServiceOdometerKey = 'last_service_odometer_km';

  static const double defaultDailyGoal = 500;
  static const double defaultServiceIntervalKm = 5000;

  Future<double> getDailyGoal() async {
    final v = await _db.getSetting(_dailyGoalKey);
    return double.tryParse(v ?? '') ?? defaultDailyGoal;
  }

  Future<void> setDailyGoal(double value) => _db.setSetting(_dailyGoalKey, value.toString());

  Future<String> getLanguageCode() async {
    return await _db.getSetting(_languageKey) ?? 'en';
  }

  Future<void> setLanguageCode(String code) => _db.setSetting(_languageKey, code);

  Future<double> getServiceIntervalKm() async {
    final v = await _db.getSetting(_serviceIntervalKmKey);
    return double.tryParse(v ?? '') ?? defaultServiceIntervalKm;
  }

  Future<void> setServiceIntervalKm(double value) => _db.setSetting(_serviceIntervalKmKey, value.toString());

  Future<double> getLastServiceOdometerKm() async {
    final v = await _db.getSetting(_lastServiceOdometerKey);
    return double.tryParse(v ?? '') ?? 0;
  }

  Future<void> markServiceDoneAt(double totalDistanceKm) =>
      _db.setSetting(_lastServiceOdometerKey, totalDistanceKm.toString());
}

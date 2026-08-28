import 'package:connectivity_plus/connectivity_plus.dart';

import '../app_config.dart';
import '../db/database_helper.dart';
import 'api_service.dart';

enum SubscriptionStatus { trial, active, expired, unknown }

class SubscriptionSnapshot {
  SubscriptionSnapshot({required this.status, required this.expires, this.lastSyncedAt, this.clockTampered = false});

  final SubscriptionStatus status;
  final DateTime? expires;
  final DateTime? lastSyncedAt;

  /// True when the device's own clock appears to have been wound
  /// backwards since the last time we knew a trustworthy "now" (see
  /// [SubscriptionManager._checkClockTamper]). When true, [paid] is
  /// forced to false regardless of what the (now-untrustworthy) date math
  /// would otherwise say -- this is what stops "set the phone's clock
  /// back a month" from faking an unexpired subscription.
  final bool clockTampered;

  /// Strictly `now < expires` -- no grace period added. The moment expiry
  /// passes, this flips to false and the app locks, full stop. Also false
  /// whenever [clockTampered] is true, since "now" can't be trusted then.
  bool get paid => !clockTampered && expires != null && DateTime.now().isBefore(expires!);

  /// Whole days left before lock, rounded up (so "20 hours left" reads as
  /// "1 day left" rather than confusingly "0 days left"). 0 once expired.
  int get daysRemaining {
    if (expires == null) return 0;
    final diff = expires!.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return (diff.inHours / 24).ceil();
  }

  /// True during the window where the app should show a soft "renew soon"
  /// warning but NOT lock yet -- i.e. still paid, but within
  /// [AppConfig.expiryWarningDays] of running out.
  bool get isNearExpiry => paid && daysRemaining <= AppConfig.expiryWarningDays;
}

/// Tracks whether the driver's monthly subscription is paid.
///
/// Policy: warn starting [AppConfig.expiryWarningDays] days before expiry,
/// lock the exact instant `expires` passes -- no grace period after. This
/// is computed the *same way* whether the check just came from a live
/// server response or from the offline cache, so the two can never
/// disagree: only `expires` (and the current time) ever decide `paid`. The
/// backend is still the source of truth for *what `expires` is* -- every
/// online check re-syncs it -- but *whether that means locked right now*
/// is always decided locally, which is what lets the lock trigger exactly
/// on time even with no network at all.
class SubscriptionManager {
  SubscriptionManager({required this.api});

  final ApiService api;
  static final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  static const _cacheStatusKey = 'subscription_status';
  static const _cacheExpiresKey = 'subscription_expires';
  static const _cacheSyncedAtKey = 'subscription_last_synced';

  // Highest wall-clock time this app has ever observed (from the server
  // when online, from the device otherwise), persisted and only ever
  // moved forward. If DateTime.now() is ever seen *behind* this mark by
  // more than [_clockTolerance], the device's clock has been wound
  // backwards since we last knew a trustworthy "now" -- the classic
  // "set your phone back a month" way to fake an unexpired subscription.
  // A small tolerance absorbs harmless NTP/timezone jitter, not a
  // month-long rollback.
  static const _clockHighWaterMarkKey = 'clock_high_water_mark';
  static const _clockTolerance = Duration(minutes: 10);

  Future<bool> _isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// Checks [referenceNow] against the stored high-water mark and advances
  /// the mark forward if [referenceNow] is newer. Returns true if this
  /// looks like a clock rollback. Callers pass the server's own clock when
  /// available (online path) -- that's what lets a *previously* tampered
  /// device clock self-heal the instant the app is back online, since the
  /// mark then jumps forward to the real, trustworthy server time.
  Future<bool> _checkClockTamper(DateTime referenceNow) async {
    final stored = await _dbHelper.getSetting(_clockHighWaterMarkKey);
    final storedTime = stored != null ? DateTime.tryParse(stored) : null;

    if (storedTime != null && referenceNow.isBefore(storedTime.subtract(_clockTolerance))) {
      return true;
    }
    if (storedTime == null || referenceNow.isAfter(storedTime)) {
      await _dbHelper.setSetting(_clockHighWaterMarkKey, referenceNow.toIso8601String());
    }
    return false;
  }

  Future<SubscriptionSnapshot> checkSubscriptionStatus(String phone) async {
    // An empty phone would build ".../subscription/check/" -- a different
    // route that 404s -- so skip the pointless round trip and read the cache.
    if (phone.trim().isEmpty) return _cachedSnapshot();

    if (await _isOnline()) {
      try {
        final res = await api.checkSubscription(phone);
        final status = _statusFromString(res['status']?.toString());
        final expires = res['expires'] != null ? DateTime.tryParse(res['expires'].toString()) : null;
        final serverTime = res['serverTime'] != null ? DateTime.tryParse(res['serverTime'].toString()) : null;
        // Prefer the server's own clock for the tamper check -- it's the
        // one "now" a device clock change can never affect, and using it
        // here also self-heals the high-water mark if this device's clock
        // was previously rolled back while offline.
        final referenceNow = serverTime ?? DateTime.now();
        final tampered = await _checkClockTamper(referenceNow);

        await _dbHelper.setSetting(_cacheStatusKey, status.name);
        await _dbHelper.setSetting(_cacheSyncedAtKey, referenceNow.toIso8601String());
        if (expires != null) {
          await _dbHelper.setSetting(_cacheExpiresKey, expires.toIso8601String());
        }

        // Deliberately NOT using res['paid'] here -- the backend applies
        // its own grace period to that field, which would let a lapsed
        // subscription silently stay "unlocked" for a few more days. Our
        // own paid/daysRemaining/isNearExpiry getters recompute strictly
        // from `expires`, so online and offline always agree.
        return SubscriptionSnapshot(status: status, expires: expires, lastSyncedAt: referenceNow, clockTampered: tampered);
      } catch (_) {
        // fall through to cached value below
      }
    }
    return _cachedSnapshot();
  }

  Future<SubscriptionSnapshot> _cachedSnapshot() async {
    final statusStr = await _dbHelper.getSetting(_cacheStatusKey);
    final expiresStr = await _dbHelper.getSetting(_cacheExpiresKey);
    final syncedStr = await _dbHelper.getSetting(_cacheSyncedAtKey);
    final expires = expiresStr != null ? DateTime.tryParse(expiresStr) : null;

    // Offline: the device's own clock is all we have. Check it against
    // the high-water mark rather than trusting it outright.
    final tampered = await _checkClockTamper(DateTime.now());

    return SubscriptionSnapshot(
      status: _statusFromString(statusStr),
      expires: expires,
      lastSyncedAt: syncedStr != null ? DateTime.tryParse(syncedStr) : null,
      clockTampered: tampered,
    );
  }

  SubscriptionStatus _statusFromString(String? s) {
    switch (s) {
      case 'trial':
        return SubscriptionStatus.trial;
      case 'active':
        return SubscriptionStatus.active;
      case 'expired':
        return SubscriptionStatus.expired;
      default:
        return SubscriptionStatus.unknown;
    }
  }

  /// Called by [SubscriptionPaymentQueue] the moment a Telebirr payment is
  /// confirmed by the backend -- writes the new expiry straight into the
  /// cache so the UI can unlock immediately, without waiting for the next
  /// full [checkSubscriptionStatus] round trip.
  static Future<SubscriptionSnapshot> persistConfirmedPayment(DateTime newExpiry) async {
    final now = DateTime.now();
    await _dbHelper.setSetting(_cacheStatusKey, SubscriptionStatus.active.name);
    await _dbHelper.setSetting(_cacheExpiresKey, newExpiry.toIso8601String());
    await _dbHelper.setSetting(_cacheSyncedAtKey, now.toIso8601String());
    return SubscriptionSnapshot(status: SubscriptionStatus.active, expires: newExpiry, lastSyncedAt: now);
  }

  /// True when the app should block ride/expense features and show the
  /// payment screen.
  bool shouldLock(SubscriptionSnapshot snapshot) => !snapshot.paid;
}

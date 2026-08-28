/// Decides how many payments the overlay's unread badge should show.
///
/// Deliberately pure: no database, no plugin, no clock. Everything it needs
/// arrives as arguments and everything it remembers serialises to two
/// integers, which is what makes the rules below unit-testable and what lets
/// the count survive the overlay isolate being torn down.
///
/// ## Why this keys off row ids and not timestamps
///
/// The obvious implementation is a timestamp watermark: remember the newest
/// payment seen, and treat anything newer as new. That is what this replaced,
/// and it dropped real payments on the floor, because the timestamp it
/// compared (`Payment.receivedAt`) is read out of the Telebirr SMS body
/// rather than measured on the device:
///
///   * SMS delivery reorders. A payment transacted at 15:00 can arrive after
///     one transacted at 15:02. On the later arrival the newest-by-timestamp
///     payment is still the 15:02 one, so `isAfter(watermark)` is false and
///     the arrival counts for nothing -- no badge, no sound, no buzz.
///   * Two payments can share a timestamp to the second, and the second one
///     then fails the same strictly-after test.
///   * When the body has no parseable date the code falls back to the device
///     clock. A device clock running ahead stamps a payment in the future,
///     which pins the watermark there and suppresses *every* subsequent
///     payment until real time catches up.
///
/// `payments.id` is `INTEGER PRIMARY KEY AUTOINCREMENT`, so it increases
/// strictly monotonically in insertion order and is not derived from any
/// clock. Comparing ids removes all three failure modes rather than
/// patching them individually.
///
/// Only the highest id ever seen is retained -- not the set of seen ids --
/// because monotonicity makes "id > highWaterId" equivalent to set
/// membership, with bounded memory and a trivial serialised form.
class OverlayBadgeState {
  OverlayBadgeState({int highWaterId = 0, int unseenCount = 0})
      : _highWaterId = highWaterId,
        _unseenCount = unseenCount;

  int _highWaterId;
  int _unseenCount;

  /// Highest `payments.id` this state has ever been shown.
  int get highWaterId => _highWaterId;

  /// How many payments have arrived since the driver last opened the panel.
  int get unseenCount => _unseenCount;

  /// Records that [ids] are now on record and returns how many of them the
  /// driver has not seen yet, which is also how much [unseenCount] just grew.
  ///
  /// Ids at or below the high-water mark are ignored, so re-pushing the same
  /// list (which happens on every update, since each push carries the whole
  /// recent window rather than just the delta) never double-counts.
  ///
  /// Returns 0 for an empty list, and for a list containing nothing new --
  /// callers use that to decide whether to fire the pop animation, the
  /// haptic, and the sound, so "nothing new" must stay silent.
  int register(Iterable<int> ids) {
    if (ids.isEmpty) return 0;

    var maxBatchId = 0;
    var fresh = 0;
    for (final id in ids) {
      if (id > _highWaterId) fresh++;
      if (id > maxBatchId) maxBatchId = id;
    }

    // The id space went backwards: every id offered is below the mark we
    // already hold. That is not possible for an AUTOINCREMENT column within
    // one database, so the database itself was replaced -- a restore from
    // backup, or the app's data being cleared. Re-seed from what actually
    // exists instead of holding a mark no future insert can ever exceed
    // (which would silence the badge permanently), and count nothing, since
    // a restore is not an arrival.
    if (fresh == 0 && maxBatchId < _highWaterId) {
      _highWaterId = maxBatchId;
      return 0;
    }

    if (maxBatchId > _highWaterId) {
      _highWaterId = maxBatchId;
    }
    _unseenCount += fresh;
    return fresh;
  }

  /// Advances the high-water mark over [ids] without counting any of them as
  /// unseen. Used when seeding the panel with history that was already on
  /// record before this state existed and which the driver is not being
  /// notified about.
  void markSeen(Iterable<int> ids) {
    for (final id in ids) {
      if (id > _highWaterId) _highWaterId = id;
    }
  }

  /// The driver opened the panel, so everything counted so far is now seen.
  void clearUnseen() => _unseenCount = 0;

  // ---- Serialisation ----
  //
  // Stored in the `settings` table rather than held in memory, because the
  // overlay isolate's widget tree is destroyed and rebuilt independently of
  // the bubble being shown, and an in-memory count silently resets to zero
  // every time that happens.

  static const String highWaterIdKey = 'overlay_badge_high_water_id';
  static const String unseenCountKey = 'overlay_badge_unseen_count';

  /// Rebuilds state from two raw `settings` values, tolerating absent or
  /// malformed strings by falling back to a fresh state -- a corrupt
  /// preference should degrade the badge, not crash the overlay.
  static OverlayBadgeState fromSettings(
      {String? highWaterId, String? unseenCount}) {
    final high = int.tryParse(highWaterId ?? '') ?? 0;
    final unseen = int.tryParse(unseenCount ?? '') ?? 0;
    return OverlayBadgeState(
      highWaterId: high < 0 ? 0 : high,
      unseenCount: unseen < 0 ? 0 : unseen,
    );
  }

  @override
  String toString() =>
      'OverlayBadgeState(highWaterId: $_highWaterId, unseenCount: $_unseenCount)';
}

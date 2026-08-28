import 'package:flutter_test/flutter_test.dart';
import 'package:telebirr_driver_assistant/overlay/overlay_badge_state.dart';

/// Regression tests for the overlay's unread badge.
///
/// Each group below reproduces a way the previous timestamp-watermark
/// implementation lost a real payment. They are written as scenarios rather
/// than method-by-method unit tests because the bug was never in a single
/// method -- it was in the rule used to decide "is this new", and the only
/// way to keep that rule honest is to replay the arrival sequences that
/// broke it.
void main() {
  group('fresh state', () {
    test('starts with nothing seen and nothing unseen', () {
      final state = OverlayBadgeState();
      expect(state.highWaterId, 0);
      expect(state.unseenCount, 0);
    });

    test('first payment counts', () {
      final state = OverlayBadgeState();
      expect(state.register([1]), 1);
      expect(state.unseenCount, 1);
      expect(state.highWaterId, 1);
    });

    test('an empty push counts nothing and changes nothing', () {
      final state = OverlayBadgeState(highWaterId: 7, unseenCount: 2);
      expect(state.register(const []), 0);
      expect(state.highWaterId, 7);
      expect(state.unseenCount, 2);
    });
  });

  group('out-of-order SMS delivery (was: payment silently dropped)', () {
    // The failure this replaces: pushes carry the recent window ordered by
    // transaction time (received_at DESC), so when a payment transacted
    // earlier arrives later, it is NOT at the head of the list. The old code
    // only ever looked at payments.first and asked "is it after the
    // watermark", which for this sequence is false -- so the arrival
    // produced no badge, no sound and no haptic even though the row was
    // written to the database.
    test('a late-arriving, earlier-transacted payment still counts', () {
      final state = OverlayBadgeState();

      // 15:02 payment arrives first and is row 1.
      expect(state.register([1]), 1);
      state.clearUnseen();

      // The 15:00 payment now arrives and is row 2. Sorted by transaction
      // time, row 1 is still the head of the pushed list.
      expect(state.register([1, 2]), 1,
          reason: 'row 2 is new regardless of where it sorts by timestamp');
      expect(state.unseenCount, 1);
      expect(state.highWaterId, 2);
    });

    test('position within the pushed list is irrelevant', () {
      final state = OverlayBadgeState(highWaterId: 5);
      // New row buried in the middle of the window.
      expect(state.register([7, 3, 6, 1]), 2);
      expect(state.unseenCount, 2);
      expect(state.highWaterId, 7);
    });
  });

  group('same-timestamp payments (was: second one dropped)', () {
    // Two payments landing inside the same second produced identical
    // received_at values, and the old strictly-after comparison rejected
    // the second one.
    test('two payments sharing a transaction second both count', () {
      final state = OverlayBadgeState();
      expect(state.register([1]), 1);
      expect(state.register([2, 1]), 1);
      expect(state.unseenCount, 2);
    });

    test('both arriving in one push count as two', () {
      final state = OverlayBadgeState();
      expect(state.register([2, 1]), 2);
      expect(state.unseenCount, 2);
    });
  });

  group('device-clock skew (was: badge frozen indefinitely)', () {
    // When a Telebirr SMS has no parseable date the parser falls back to
    // DateTime.now(). On a device whose clock runs ahead, that stamped a
    // payment in the future, pinned the watermark there, and suppressed
    // every subsequent payment until real time caught up.
    //
    // There is no clock in this class at all, so the scenario reduces to
    // "ids keep counting no matter what any timestamp says" -- which is
    // exactly the property worth pinning down.
    test('a payment following a future-stamped one still counts', () {
      final state = OverlayBadgeState();
      expect(state.register([1]), 1, reason: 'the future-stamped payment');
      state.clearUnseen();

      for (var id = 2; id <= 5; id++) {
        expect(state.register([id]), 1, reason: 'row $id must still count');
      }
      expect(state.unseenCount, 4);
    });
  });

  group('repeated pushes', () {
    // Every push carries the whole recent window, not a delta, so the same
    // ids are offered over and over -- including by the 30-second refresh
    // and by a re-push triggered by an unrelated update.
    test('re-pushing an identical window counts nothing the second time', () {
      final state = OverlayBadgeState();
      expect(state.register([3, 2, 1]), 3);
      expect(state.register([3, 2, 1]), 0);
      expect(state.register([3, 2, 1]), 0);
      expect(state.unseenCount, 3);
    });

    test('a window that scrolls past old rows still only counts new ones', () {
      final state = OverlayBadgeState();
      state.register([2, 1]);
      state.clearUnseen();
      // Window has slid: row 1 aged out, row 3 is new.
      expect(state.register([3, 2]), 1);
      expect(state.unseenCount, 1);
    });
  });

  group('seeding history', () {
    // Starting the bubble mid-shift reads the day's existing payments out of
    // the database to fill the panel. Those are not arrivals and must not
    // buzz the driver's phone for work they already did.
    test('markSeen advances the mark without counting', () {
      final state = OverlayBadgeState();
      state.markSeen([4, 3, 2, 1]);
      expect(state.highWaterId, 4);
      expect(state.unseenCount, 0);
    });

    test('a payment arriving after seeding still counts', () {
      final state = OverlayBadgeState();
      state.markSeen([4, 3, 2, 1]);
      expect(state.register([5, 4, 3]), 1);
      expect(state.unseenCount, 1);
    });

    test('seeding never lowers an existing mark', () {
      // Ordering hazard: the seed read is asynchronous, so a push can land
      // first. If seeding could lower the mark, the pushed payment would be
      // re-counted on the next identical push.
      final state = OverlayBadgeState();
      expect(state.register([9]), 1);
      state.markSeen([4, 3, 2, 1]);
      expect(state.highWaterId, 9);
      expect(state.register([9]), 0);
    });
  });

  group('opening the panel', () {
    test('clears the count but keeps the mark', () {
      final state = OverlayBadgeState();
      state.register([2, 1]);
      state.clearUnseen();
      expect(state.unseenCount, 0);
      expect(state.highWaterId, 2);
      expect(state.register([2, 1]), 0, reason: 'seen rows stay seen');
    });
  });

  group('surviving process death', () {
    test('the count is restored from stored settings', () {
      final before = OverlayBadgeState();
      before.register([3, 2, 1]);
      before.clearUnseen();
      before.register([5, 4]);

      final after = OverlayBadgeState.fromSettings(
        highWaterId: before.highWaterId.toString(),
        unseenCount: before.unseenCount.toString(),
      );
      expect(after.highWaterId, before.highWaterId);
      expect(after.unseenCount, 2);

      // And the restored state does not re-count what it already saw.
      expect(after.register([5, 4, 3]), 0);
      expect(after.unseenCount, 2);
    });

    test('payments that arrived while the overlay was dead count on restore',
        () {
      final state =
          OverlayBadgeState.fromSettings(highWaterId: '3', unseenCount: '0');
      // Rows 4 and 5 were written by the background SMS isolate while the
      // overlay isolate was not running.
      expect(state.register([5, 4, 3, 2, 1]), 2);
      expect(state.unseenCount, 2);
    });

    test('absent settings give a fresh state', () {
      final state = OverlayBadgeState.fromSettings();
      expect(state.highWaterId, 0);
      expect(state.unseenCount, 0);
    });

    test('malformed settings degrade instead of throwing', () {
      final state = OverlayBadgeState.fromSettings(
          highWaterId: 'not-a-number', unseenCount: '');
      expect(state.highWaterId, 0);
      expect(state.unseenCount, 0);
    });

    test('negative stored values are floored at zero', () {
      final state =
          OverlayBadgeState.fromSettings(highWaterId: '-9', unseenCount: '-2');
      expect(state.highWaterId, 0);
      expect(state.unseenCount, 0);
      expect(state.register([1]), 1);
    });
  });

  group('database replaced underneath us', () {
    // A restore from backup, or the app's data being cleared, restarts the
    // id sequence. Holding the old mark would mean no future insert could
    // ever exceed it and the badge would never move again.
    test('a lower id space re-seeds the mark and counts nothing', () {
      final state = OverlayBadgeState(highWaterId: 900, unseenCount: 0);
      expect(state.register([3, 2, 1]), 0, reason: 'a restore is not arrival');
      expect(state.highWaterId, 3);
      // Recovered: the next genuine payment counts again.
      expect(state.register([4, 3, 2, 1]), 1);
      expect(state.unseenCount, 1);
    });

    test('re-seeding does not wipe a count earned before the restore', () {
      final state = OverlayBadgeState(highWaterId: 900, unseenCount: 2);
      state.register([3, 2, 1]);
      expect(state.unseenCount, 2);
    });
  });
}

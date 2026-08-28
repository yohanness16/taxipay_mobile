// Smoke tests for the pure logic behind the subscription payment flow.
//
// This file previously held the stock "counter increments" template test,
// which referenced a `MyApp` class that never existed in this project (the
// root widget is `TelebirrDriverApp`), so the suite failed to compile.
//
// The root widget itself isn't pumped here on purpose: it builds providers
// that reach for SQLite, secure storage and platform channels, none of
// which exist in a plain `flutter test` environment. The transaction-id
// extraction below is the part that actually has to stay correct, since it
// must agree byte-for-byte with the backend's own `extractTelebirrTxId`.

import 'package:flutter_test/flutter_test.dart';

import 'package:telebirr_driver_assistant/services/telebirr_sms_parser.dart';

void main() {
  group('TelebirrSmsParser', () {
    // The real message shape this was built against.
    const receivedSms = 'Dear Yohannes\n'
        'You have received ETB 5.00 from Alazar Fikadu(2519****4417)  on '
        '09/07/2026 15:21:34. Your transaction number is DG94OKBAZE. Your '
        'current E-Money Account balance is ETB 5.00.\n'
        'Thank you for using telebirr\n'
        'Ethio telecom';

    test('parses an incoming ride payment as revenue', () {
      final parsed = TelebirrSmsParser.parse(receivedSms);

      expect(parsed, isNotNull);
      expect(parsed!.kind, TelebirrMessageKind.received);
      expect(parsed.amount, 5.00);
      expect(parsed.transactionId, 'DG94OKBAZE');
      expect(parsed.payerName, 'Alazar Fikadu');
      expect(parsed.transactionDate, DateTime(2026, 7, 9, 15, 21, 34));
    });

    test('classifies an outgoing transfer as "other", not ride revenue', () {
      // What the driver's own phone receives after paying their own
      // subscription fee -- must NOT be counted as ride income.
      final parsed = TelebirrSmsParser.parse(
        'You have transferred ETB 50.00 to Telebirr Driver Assistant. '
        'Your transaction number is QQ11WW22EE.',
      );

      expect(parsed, isNotNull);
      expect(parsed!.kind, TelebirrMessageKind.other);
      expect(parsed.amount, 50.00);
      expect(parsed.transactionId, 'QQ11WW22EE');
    });

    test('extracts a 10-character transaction id the backend will also match', () {
      // The backend re-extracts the id from this same text and looks it up
      // against its own gateway records, so any drift here silently breaks
      // verification.
      final parsed = TelebirrSmsParser.parse('Your transaction number is ZX20296995.');

      expect(parsed?.transactionId, 'ZX20296995');
    });

    test('returns null for a message that is not a transaction at all', () {
      expect(TelebirrSmsParser.parse('Thank you for using telebirr'), isNull);
    });
  });
}

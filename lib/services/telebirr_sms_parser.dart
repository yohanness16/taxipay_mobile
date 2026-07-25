/// Everything to do with interpreting a raw Telebirr SMS body lives here,
/// isolated from the platform-specific listening code in [SmsReader] so it
/// can be unit-tested and reasoned about on its own.
///
/// Real Telebirr message this was built against:
///   "Dear Yohannes
///   You have received ETB 5.00 from Alazar Fikadu(2519****4417)  on
///   09/07/2026 15:21:34. Your transaction number is DG94OKBAZE. Your
///   current E-Money Account balance is ETB 5.00.
///   Thank you for using telebirr
///   Ethio telecom"
library telebirr_sms_parser;

enum TelebirrMessageKind {
  /// "You have received ETB X from NAME(PHONE)..." -- money coming IN from
  /// a customer. This is the only kind that counts as ride revenue.
  received,

  /// Any other Telebirr message that still contains a transaction number
  /// (e.g. a "you have transferred/sent ETB X to ..." confirmation, which
  /// is what shows up on the driver's own phone right after they pay their
  /// own subscription fee to the business account). Not ride revenue, but
  /// still potentially useful (subscription payment proof).
  other,
}

class ParsedTelebirrMessage {
  ParsedTelebirrMessage({
    required this.kind,
    required this.amount,
    this.payerName,
    this.maskedPhone,
    this.transactionDate,
    this.transactionId,
  });

  final TelebirrMessageKind kind;
  final double amount;
  final String? payerName;
  final String? maskedPhone;
  final DateTime? transactionDate;
  final String? transactionId;
}

class TelebirrSmsParser {
  // "ETB 5.00", "ETB5", "5.00 ETB", "Birr 5"
  static final _amountPattern = RegExp(r'ETB\s*([\d,]+\.?\d*)', caseSensitive: false);
  static final _amountFallbackPattern = RegExp(r'([\d,]+\.?\d*)\s*(?:ETB|Birr)', caseSensitive: false);

  // "from Alazar Fikadu(2519****4417)" -> name + masked phone
  static final _fromPattern = RegExp(r'from\s+(.+?)\s*\(([\d*]{6,})\)', caseSensitive: false);

  // "on 09/07/2026 15:21:34"
  static final _datePattern = RegExp(r'on\s+(\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}:\d{2})', caseSensitive: false);

  // Mirrors the backend's extractTelebirrTxId exactly, so a message either
  // app considers "matching" is consistent on both ends.
  static final _txIdPattern = RegExp(
    r"transaction number is\s*([A-Z0-9]{10})'?",
    caseSensitive: false,
  );

  // "You have received" -- the one phrase that distinguishes ride revenue
  // from every other Telebirr notification (sent/transferred/deducted/etc).
  static final _receivedPattern = RegExp(r'you\s+have\s+received', caseSensitive: false);

  /// Returns null if this text has neither a recognizable amount nor a
  /// transaction number -- i.e. it isn't a Telebirr transaction message at
  /// all (could be a promo text, balance check, etc from the same sender).
  static ParsedTelebirrMessage? parse(String message) {
    final amount = _extractAmount(message);
    final txId = _txIdPattern.firstMatch(message)?.group(1);
    if (amount == null && txId == null) return null;

    final fromMatch = _fromPattern.firstMatch(message);
    final isReceived = _receivedPattern.hasMatch(message) && fromMatch != null;

    final dateStr = _datePattern.firstMatch(message)?.group(1);

    return ParsedTelebirrMessage(
      kind: isReceived ? TelebirrMessageKind.received : TelebirrMessageKind.other,
      amount: amount ?? 0,
      payerName: fromMatch?.group(1)?.trim(),
      maskedPhone: fromMatch?.group(2)?.trim(),
      transactionDate: _parseDate(dateStr),
      transactionId: txId,
    );
  }

  static double? _extractAmount(String message) {
    final match = _amountPattern.firstMatch(message) ?? _amountFallbackPattern.firstMatch(message);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.replaceAll(',', ''));
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    // "09/07/2026 15:21:34" -> Telebirr uses DD/MM/YYYY.
    final parts = raw.split(RegExp(r'[/\s:]'));
    if (parts.length < 6) return null;
    try {
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      final hour = int.parse(parts[3]);
      final minute = int.parse(parts[4]);
      final second = int.parse(parts[5]);
      return DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }
}

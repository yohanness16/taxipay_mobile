enum PaymentMethod { telebirr, cash }

class Payment {
  final int? id;
  final int? rideId;
  final double amount;
  final String payerPhone; // Telebirr sends this pre-masked, e.g. "2519****4417"
  final String? payerName;
  final String? transactionId;

  /// When the transaction happened, as stated *inside the Telebirr SMS text*
  /// (or, for cash fares, when it was logged). This is what earnings,
  /// reports, and the payment history display — it is the number the driver
  /// recognises as "when the money moved".
  ///
  /// It is NOT a reliable clock. It comes from the message body, so it can
  /// be older than a payment that was already delivered (SMS delivery
  /// reorders on congested networks), it can collide to the second with
  /// another payment, and when the body has no parseable date it falls back
  /// to the device clock — which may be skewed. Never use it to decide
  /// whether something is newly arrived; use [arrivedAt], or better, the
  /// row id.
  final DateTime receivedAt;

  /// When this payment landed on *this device*, stamped from the device
  /// clock at the moment the row is created. Monotonic with respect to
  /// insertion order in a way [receivedAt] is not, so this is the field to
  /// order by when the question is "what is new since I last looked".
  final DateTime arrivedAt;

  final String? telebirrMessage;
  final PaymentMethod method;
  final bool synced;

  Payment({
    this.id,
    this.rideId,
    required this.amount,
    required this.payerPhone,
    this.payerName,
    this.transactionId,
    required this.receivedAt,
    DateTime? arrivedAt,
    this.telebirrMessage,
    this.method = PaymentMethod.telebirr,
    this.synced = false,
  }) : arrivedAt = arrivedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'ride_id': rideId,
        'amount': amount,
        'payer_phone': payerPhone,
        'payer_name': payerName,
        'transaction_id': transactionId,
        'received_at': receivedAt.toIso8601String(),
        'arrived_at': arrivedAt.toIso8601String(),
        'telebirr_message': telebirrMessage,
        'payment_method': method.name,
        'synced': synced ? 1 : 0,
      };

  factory Payment.fromMap(Map<String, dynamic> map) => Payment(
        id: map['id'] as int?,
        rideId: map['ride_id'] as int?,
        amount: (map['amount'] as num).toDouble(),
        payerPhone: map['payer_phone'] as String? ?? '',
        payerName: map['payer_name'] as String?,
        transactionId: map['transaction_id'] as String?,
        receivedAt: DateTime.parse(map['received_at'] as String),
        // Rows written before the v4 migration have no arrived_at. The
        // migration backfills them from received_at; this fallback covers
        // the same case defensively so a partially-migrated database can
        // still be read rather than throwing.
        arrivedAt: DateTime.parse(
            (map['arrived_at'] as String?) ?? map['received_at'] as String),
        telebirrMessage: map['telebirr_message'] as String?,
        method: (map['payment_method'] as String?) == 'cash' ? PaymentMethod.cash : PaymentMethod.telebirr,
        synced: (map['synced'] as int? ?? 0) == 1,
      );
}

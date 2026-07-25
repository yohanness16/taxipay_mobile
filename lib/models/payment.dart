enum PaymentMethod { telebirr, cash }

class Payment {
  final int? id;
  final int? rideId;
  final double amount;
  final String payerPhone; // Telebirr sends this pre-masked, e.g. "2519****4417"
  final String? payerName;
  final String? transactionId;
  final DateTime receivedAt;
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
    this.telebirrMessage,
    this.method = PaymentMethod.telebirr,
    this.synced = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'ride_id': rideId,
        'amount': amount,
        'payer_phone': payerPhone,
        'payer_name': payerName,
        'transaction_id': transactionId,
        'received_at': receivedAt.toIso8601String(),
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
        telebirrMessage: map['telebirr_message'] as String?,
        method: (map['payment_method'] as String?) == 'cash' ? PaymentMethod.cash : PaymentMethod.telebirr,
        synced: (map['synced'] as int? ?? 0) == 1,
      );
}

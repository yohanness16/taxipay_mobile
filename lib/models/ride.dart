class Ride {
  final int? id;
  final String driverPhone;
  final DateTime startTime;
  final DateTime? endTime;
  final double distanceKm;
  final String? notes;
  final DateTime createdAt;

  Ride({
    this.id,
    required this.driverPhone,
    required this.startTime,
    this.endTime,
    this.distanceKm = 0,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'driver_phone': driverPhone,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime?.toIso8601String(),
        'distance': distanceKm,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
      };

  factory Ride.fromMap(Map<String, dynamic> map) => Ride(
        id: map['id'] as int?,
        driverPhone: map['driver_phone'] as String? ?? '',
        startTime: DateTime.parse(map['start_time'] as String),
        endTime: map['end_time'] != null ? DateTime.parse(map['end_time'] as String) : null,
        distanceKm: (map['distance'] as num?)?.toDouble() ?? 0,
        notes: map['notes'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

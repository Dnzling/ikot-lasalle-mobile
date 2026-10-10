class BusLocation {
  const BusLocation({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.type,
    required this.speedKmh,
  });

  final String id;
  final String label;
  final double latitude;
  final double longitude;
  final String status;
  final String type;
  final double speedKmh;

  factory BusLocation.fromJson(Map<String, dynamic> json) => BusLocation(
    id: '${json['id'] ?? ''}',
    label: '${json['label'] ?? 'Bus'}',
    latitude:
        (json['latitude'] as num?)?.toDouble() ??
        double.tryParse('${json['latitude']}') ??
        0,
    longitude:
        (json['longitude'] as num?)?.toDouble() ??
        double.tryParse('${json['longitude']}') ??
        0,
    status: '${json['status'] ?? 'active'}',
    type: '${json['type'] ?? 'Jeep'}',
    speedKmh:
        (json['speedKmh'] as num?)?.toDouble() ??
        double.tryParse('${json['speedKmh']}') ??
        0,
  );
}

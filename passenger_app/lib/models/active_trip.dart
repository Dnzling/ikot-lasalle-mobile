class ActiveTrip {
  const ActiveTrip({
    required this.id,
    required this.destination,
    required this.passengerCount,
    required this.fare,
    required this.status,
    this.createdAt,
    this.pickupRouteId,
    this.destinationRouteId,
    this.pickup,
    this.vehicleId,
    this.boardedAt,
  });

  final String id;
  final String destination;
  final int passengerCount;
  final double fare;
  final String status;
  final DateTime? createdAt;
  final String? pickupRouteId;
  final String? destinationRouteId;
  final String? pickup;
  final String? vehicleId;
  final DateTime? boardedAt;

  bool get isOnboard => status == 'onboard' || status == 'boarded';
}

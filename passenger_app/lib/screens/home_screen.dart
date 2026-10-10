import 'dart:async';

import 'package:flutter/material.dart';

import 'booking_screen.dart';
import '../services/passenger_firebase_service.dart';
import '../models/app_session.dart';
import '../models/active_trip.dart';
import '../models/bus_location.dart';
import '../widgets/campus_map.dart';
import 'waiting_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.session, super.key});
  final AppSession session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool? firebaseAvailable;
  List<BusLocation> buses = const [];
  Timer? busRefreshTimer;
  late final Stream<ActiveTrip?> activeTripStream;

  @override
  void initState() {
    super.initState();
    activeTripStream = const PassengerFirebaseService().watchActiveTrip(
      widget.session.uid,
    );
    _checkApi();
    _loadBuses();
    busRefreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _loadBuses(),
    );
  }

  @override
  void dispose() {
    busRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBuses() async {
    try {
      final result = await const PassengerFirebaseService().getBusLocations();
      if (mounted) setState(() => buses = result);
    } catch (_) {
      // The connectivity label already reports Firebase availability. Keep the last
      // known bus positions if a refresh temporarily fails.
    }
  }

  Future<void> _checkApi() async {
    final available = await const PassengerFirebaseService().isAvailable(
      widget.session.uid,
    );
    if (mounted) setState(() => firebaseAvailable = available);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Hello, ${widget.session.passenger.firstName}',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 5),
          const Text(
            'Where are you going?',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF62A77D),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AVAILABLE CREDITS',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'PHP ${widget.session.passenger.balance.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 31,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Live campus map',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            firebaseAvailable == null
                ? 'Connecting to Location services...'
                : firebaseAvailable == true
                ? 'Location connected'
                : 'Location unavailable',
            style: TextStyle(
              color: firebaseAvailable == true
                  ? const Color(0xFF62A77D)
                  : Colors.black54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 255,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFE1F1E5),
              borderRadius: BorderRadius.circular(24),
            ),
            child: CampusMap(busLocations: buses),
          ),
          const SizedBox(height: 18),
          StreamBuilder<ActiveTrip?>(
            stream: activeTripStream,
            builder: (context, snapshot) {
              final trip = snapshot.data;
              return SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed:
                      snapshot.hasError ||
                          snapshot.connectionState == ConnectionState.waiting
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => trip == null
                                ? BookingScreen(session: widget.session)
                                : WaitingScreen(
                                    session: widget.session,
                                    bookingId: trip.id,
                                    destination: trip.destination,
                                    passengerCount: trip.passengerCount,
                                    fare: trip.fare,
                                    initialStatus: trip.status,
                                    createdAt: trip.createdAt,
                                    pickup: trip.pickup,
                                    pickupRouteId: trip.pickupRouteId,
                                    destinationRouteId: trip.destinationRouteId,
                                    vehicleId: trip.vehicleId,
                                    boardedAt: trip.boardedAt,
                                  ),
                          ),
                        ),
                  icon: Icon(
                    trip == null
                        ? Icons.directions_bus
                        : Icons.pending_actions_outlined,
                  ),
                  label: Text(
                    snapshot.hasError
                        ? 'Trip status unavailable'
                        : snapshot.connectionState == ConnectionState.waiting
                        ? 'Checking trip...'
                        : trip == null
                        ? 'Start Trip'
                        : 'View Pending Trip',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

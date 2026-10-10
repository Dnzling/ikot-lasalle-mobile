import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart' as geo;

import 'waiting_screen.dart';
import '../models/app_session.dart';
import '../services/passenger_firebase_service.dart';
import '../services/fare_direction.dart';
import '../widgets/campus_map.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({required this.session, super.key});
  final AppSession session;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  int quantity = 1;
  String? pickupRouteId;
  String? dropOffRouteId;
  List<Map<String, dynamic>> routes = [];
  bool loadingRoutes = true;
  String? routesError;
  bool loading = false;
  String? pickupMessage;
  double defaultFare = 15;
  double roundTripFare = 25;

  @override
  void initState() {
    super.initState();
    loadRoutes();
  }

  Future<void> loadRoutes() async {
    try {
      final service = const PassengerFirebaseService();
      final result = await service.getRoutes();
      final fares = await service.getFareSettings();
      if (!mounted) return;
      setState(() {
        routes = result;
        defaultFare = fares.defaultFare;
        roundTripFare = fares.roundTripFare;
        pickupRouteId = null;
        dropOffRouteId = null;
        routesError = null;
      });
      await _resolvePickup();
    } catch (error) {
      if (mounted) setState(() => routesError = '$error');
    } finally {
      if (mounted) setState(() => loadingRoutes = false);
    }
  }

  Future<void> _resolvePickup() async {
    var position = CampusMap.latestPosition;
    if (position == null ||
        DateTime.now().difference(position.timestamp) > const Duration(minutes: 5)) {
      try {
        position = await geo.Geolocator.getCurrentPosition(
          locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.high),
        );
      } catch (_) {
        if (mounted) setState(() => pickupMessage = 'Location unavailable. Enable GPS and retry.');
        return;
      }
    }
    Map<String, dynamic>? nearest;
    var nearestDistance = double.infinity;
    for (final route in routes) {
      final point = route['location'];
      if (point is! GeoPoint) continue;
      final radius = (route['proximityRadius'] as num?)?.toDouble() ?? 50;
      final distance = geo.Geolocator.distanceBetween(
        position.latitude, position.longitude, point.latitude, point.longitude,
      );
      if (distance <= radius && distance < nearestDistance) {
        nearest = route;
        nearestDistance = distance;
      }
    }
    if (!mounted) return;
    setState(() {
      pickupRouteId = nearest == null ? null : '${nearest['id']}';
      pickupMessage = nearest == null
          ? 'You are outside every registered pickup radius. Move to a route stop and retry.'
          : null;
      if (pickupRouteId == dropOffRouteId || dropOffRouteId == null) {
        dropOffRouteId = routes.where((route) => route['id'] != pickupRouteId)
            .map((route) => '${route['id']}').firstOrNull;
      }
    });
  }

  int get _pickupIndex =>
      routes.indexWhere((route) => route['id'] == pickupRouteId);
  int get _destinationIndex =>
      routes.indexWhere((route) => route['id'] == dropOffRouteId);
  bool get _validTrip =>
      _pickupIndex >= 0 &&
      _destinationIndex >= 0 &&
      _pickupIndex != _destinationIndex;
  bool get _isRoundTrip =>
      _validTrip &&
      fareDirectionForRouteOrder(_pickupIndex, _destinationIndex) ==
          FareDirection.roundTrip;
  double get _farePerPassenger => _isRoundTrip ? roundTripFare : defaultFare;

  Future<void> startBooking() async {
    if (loading || !_validTrip) return;
    await _resolvePickup();
    if (!_validTrip) return;
    final pickup = '${routes[_pickupIndex]['name']}';
    final destination = '${routes[_destinationIndex]['name']}';
    final fareType = _isRoundTrip ? 'roundTrip' : 'default';
    setState(() => loading = true);
    try {
      // Refresh immediately before saving so a recently edited admin fare wins.
      final service = const PassengerFirebaseService();
      final fares = await service.getFareSettings();
      final fare =
          (fareType == 'roundTrip' ? fares.roundTripFare : fares.defaultFare) *
          quantity;
      if (fare <= 0) throw StateError('Fare settings are not configured.');
      final id = await service.createBooking(
        uid: widget.session.uid,
        pickup: pickup,
        destination: destination,
        passengerCount: quantity,
        fare: fare,
        fareType: fareType,
        pickupRouteId: pickupRouteId!,
        destinationRouteId: dropOffRouteId!,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WaitingScreen(
            session: widget.session,
            bookingId: id,
            destination: destination,
            passengerCount: quantity,
            fare: fare,
            pickup: pickup,
            pickupRouteId: pickupRouteId,
            destinationRouteId: dropOffRouteId,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Book a ride',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      backgroundColor: Colors.transparent,
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Plan your trip',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Pickup is detected from your location inside a route stop radius. Select your destination.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 26),
        if (loadingRoutes)
          const Center(child: CircularProgressIndicator())
        else if (routesError != null)
          ListTile(
            title: const Text('Could not load routes or fares from Firebase.'),
            subtitle: Text(routesError!),
            trailing: IconButton(
              onPressed: () {
                setState(() => loadingRoutes = true);
                loadRoutes();
              },
              icon: const Icon(Icons.refresh),
            ),
          )
        else if (routes.length < 2)
          const Text('At least two active routes are needed to book a ride.')
        else ...[
          const Text('PICKUP LOCATION', style: _labelStyle),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.my_location),
            title: Text(_pickupIndex < 0 ? 'Detecting pickup...' : '${routes[_pickupIndex]['name']}'),
            subtitle: pickupMessage == null ? const Text('Detected from your location') : Text(pickupMessage!),
            trailing: IconButton(onPressed: _resolvePickup, icon: const Icon(Icons.refresh),
              tooltip: 'Retry pickup detection'),
          ),
          const SizedBox(height: 20),
          const Text('DROP-OFF LOCATION', style: _labelStyle),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('destination-$dropOffRouteId'),
            initialValue: dropOffRouteId,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.place_outlined),
              filled: true,
              fillColor: Colors.white,
            ),
            items: routes
                .where((route) => route['id'] != pickupRouteId)
                .map(
                  (route) => DropdownMenuItem(
                    value: '${route['id']}',
                    child: Text('${route['name']}'),
                  ),
                )
                .toList(),
            onChanged: loading
                ? null
                : (value) => setState(() => dropOffRouteId = value),
          ),
          const SizedBox(height: 20),
          const Text('PASSENGERS', style: _labelStyle),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Passenger quantity'),
              Row(
                children: [
                  IconButton(
                    onPressed: quantity > 1
                        ? () => setState(() => quantity--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$quantity'),
                  IconButton(
                    onPressed: quantity < 6
                        ? () => setState(() => quantity++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ],
          ),
          if (_validTrip) ...[
            const SizedBox(height: 12),
            Text(
              '${_isRoundTrip ? 'Round Trip Fare' : 'Default Fare'}: PHP ${_farePerPassenger.toStringAsFixed(2)} × $quantity = PHP ${(_farePerPassenger * quantity).toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: loading || !_validTrip ? null : startBooking,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                loading ? 'Saving booking...' : 'Start booking',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

const _labelStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.bold,
  letterSpacing: 1,
  color: Colors.black54,
);

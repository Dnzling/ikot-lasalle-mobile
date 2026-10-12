import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
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
  final emailController = TextEditingController();
  bool? firebaseAvailable;
  bool emailBusy = false;
  String pendingEmail = '';
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
    _refreshEmailVerification(silent: true);
    _loadBuses();
    busRefreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _loadBuses(),
    );
  }

  @override
  void dispose() {
    busRefreshTimer?.cancel();
    emailController.dispose();
    super.dispose();
  }

  Future<void> _sendEmailVerification() async {
    if (emailBusy) return;
    setState(() => emailBusy = true);
    try {
      final email = emailController.text.trim();
      final alreadyVerified = await const PassengerFirebaseService()
          .sendPassengerEmailVerification(
            uid: widget.session.uid,
            email: email,
          );
      if (!mounted) return;
      if (alreadyVerified) {
        widget.session.updatePassenger(
          widget.session.passenger.copyWith(email: email, emailVerified: true),
        );
        setState(() => pendingEmail = '');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email is already verified and saved.')),
        );
        return;
      }
      setState(() => pendingEmail = email);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification link sent to $email.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send verification link: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => emailBusy = false);
    }
  }

  Future<void> _refreshEmailVerification({bool silent = false}) async {
    if (emailBusy && !silent) return;
    if (!silent && mounted) setState(() => emailBusy = true);
    try {
      final status = await const PassengerFirebaseService()
          .refreshPassengerEmail(uid: widget.session.uid);
      if (!mounted) return;
      if (status.verified) {
        widget.session.updatePassenger(
          widget.session.passenger.copyWith(
            email: status.email,
            emailVerified: true,
          ),
        );
        setState(() => pendingEmail = '');
      }
    } on FirebaseAuthException catch (error) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not check email status: ${error.message ?? error.code}',
            ),
          ),
        );
      }
    } catch (error) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not check email status: $error')),
        );
      }
    } finally {
      if (!silent && mounted) setState(() => emailBusy = false);
    }
  }

  Future<void> _loadBuses() async {
    try {
      final result = await const PassengerFirebaseService().getBusLocations();
      if (mounted) setState(() => buses = result);
    } catch (_) {
      // Never keep displaying stale coordinates as live when a refresh fails.
      if (mounted) {
        setState(() => buses = buses.where((bus) => bus.hasFreshGps).toList());
      }
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
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) => SafeArea(
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
            if (!widget.session.passenger.emailVerified)
              _emailVerificationCard(),
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
              child: CampusMap(
                busLocations: buses.where((bus) => bus.hasFreshGps).toList(),
              ),
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
                                      destinationRouteId:
                                          trip.destinationRouteId,
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
      ),
    );
  }

  Widget _emailVerificationCard() => Card(
    color: const Color(0xFFFFF8E7),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.mark_email_unread_outlined, color: Color(0xFF9A6800)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Verify your email',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            pendingEmail.isEmpty
                ? 'Add an email address so you can recover your password. We will send a verification link.'
                : 'Open the verification link sent to $pendingEmail, then return here.',
          ),
          if (pendingEmail.isEmpty) ...[
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.email_outlined),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: emailBusy ? null : _sendEmailVerification,
                child: emailBusy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send verification link'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: emailBusy ? null : () => _refreshEmailVerification(),
                icon: const Icon(Icons.verified_outlined),
                label: Text(emailBusy ? 'Checking...' : 'I verified my email'),
              ),
            ),
            TextButton(
              onPressed: emailBusy
                  ? null
                  : () => setState(() => pendingEmail = ''),
              child: const Text('Use a different email'),
            ),
          ],
        ],
      ),
    ),
  );
}

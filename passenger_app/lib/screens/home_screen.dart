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
  StreamSubscription<List<BusLocation>>? busSubscription;
  Timer? freshnessTimer;
  late final Stream<ActiveTrip?> activeTripStream;

  @override
  void initState() {
    super.initState();
    activeTripStream = const PassengerFirebaseService().watchActiveTrip(
      widget.session.uid,
    );
    _checkApi();
    _refreshEmailVerification(silent: true);
    busSubscription = const PassengerFirebaseService()
        .watchBusLocations()
        .listen(
          (locations) {
            if (mounted) setState(() => buses = locations);
          },
          onError: (Object error) {
            if (mounted)
              setState(
                () => buses = buses.where((bus) => bus.hasFreshGps).toList(),
              );
          },
        );
    freshnessTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    busSubscription?.cancel();
    freshnessTimer?.cancel();
    emailController.dispose();
    super.dispose();
  }

  Future<void> _sendEmailVerification() async {
    if (emailBusy) return;
    setState(() => emailBusy = true);
    try {
      final email = emailController.text.trim();
      final alreadyVerified = await const PassengerFirebaseService()
          .sendRecoveryEmailVerification(
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
          .refreshRecoveryEmailStatus(uid: widget.session.uid);
      if (!mounted) return;
      if (status.verified) {
        widget.session.updatePassenger(
          widget.session.passenger.copyWith(
            email: status.email,
            emailVerified: true,
          ),
        );
        setState(() => pendingEmail = '');
        if (!status.profileSynced && !silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Recovery email verified and saved.',
              ),
            ),
          );
        }
      } else if (status.email.isNotEmpty) {
        setState(() => pendingEmail = status.email);
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
                if (snapshot.hasError) {
                  return const SizedBox(
                    height: 54,
                    child: Center(child: Text('Trip status unavailable')),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 54,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (trip != null) return _activeTripCard(trip);
                return SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BookingScreen(session: widget.session),
                      ),
                    ),
                    icon: const Icon(Icons.directions_bus),
                    label: const Text(
                      'Start Trip',
                      style: TextStyle(
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

  Widget _activeTripCard(ActiveTrip trip) {
    final onboard = trip.isOnboard;
    final accent = onboard ? const Color(0xFF176B45) : const Color(0xFF8A5A00);
    final background = onboard
        ? const Color(0xFFEAF5ED)
        : const Color(0xFFFFF6E3);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                onboard ? Icons.directions_bus_filled : Icons.bookmark_added,
                color: accent,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  onboard ? 'RIDE IN PROGRESS' : 'ACTIVE BOOKING',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (onboard)
                const Icon(Icons.circle, size: 9, color: Color(0xFF20A35B)),
            ],
          ),
          const SizedBox(height: 12),
          if (onboard) ...[
            const Text(
              'Your next stop',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 3),
            Text(
              trip.destination,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const Text(
              'You are onboard. Open your ride for live vehicle location and arrival updates.',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ] else ...[
            Text(
              '${trip.pickup ?? 'Pickup stop'} to ${trip.destination}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            const Text(
              'Waiting for boarding. Open your ride to scan the vehicle QR code.',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: () => _openActiveTrip(trip),
              icon: const Icon(Icons.open_in_new),
              label: const Text(
                'View ride',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(backgroundColor: accent),
            ),
          ),
        ],
      ),
    );
  }

  void _openActiveTrip(ActiveTrip trip) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WaitingScreen(
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
                  'Set password recovery email',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            pendingEmail.isEmpty
                ? 'Add an email address for password recovery. Verifying it will not change your passenger ID sign-in.'
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

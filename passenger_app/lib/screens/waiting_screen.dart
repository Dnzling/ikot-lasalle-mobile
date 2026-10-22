import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/app_session.dart';
import '../models/bus_location.dart';
import '../services/passenger_firebase_service.dart';
import '../widgets/campus_map.dart';

class WaitingScreen extends StatefulWidget {
  final String destination;
  final int passengerCount;
  final double fare;
  final String bookingId;
  final AppSession session;
  final String initialStatus;
  final DateTime? createdAt;
  final String? pickup;
  final String? pickupRouteId;
  final String? destinationRouteId;
  final String? vehicleId;
  final DateTime? boardedAt;

  const WaitingScreen({
    required this.destination,
    required this.passengerCount,
    required this.fare,
    required this.bookingId,
    required this.session,
    this.initialStatus = 'waiting',
    this.createdAt,
    this.pickup,
    this.pickupRouteId,
    this.destinationRouteId,
    this.vehicleId,
    this.boardedAt,
    super.key,
  });

  @override
  State<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends State<WaitingScreen> {
  static const _rideAlertChannel = MethodChannel('ikot_lasalle/ride_alert');
  bool boarded = false;
  bool canceled = false;
  bool canceling = false;
  Timer? expiryTimer;
  Timer? etaTimer;
  Timer? proximityTimer;
  Timer? phoneGpsTimer;
  bool phoneGpsRunning = false;
  late final Stream<List<BusLocation>> vehicleLocations;
  StreamSubscription<List<BusLocation>>? vehicleSubscription;
  StreamSubscription<int>? overstayPenaltySubscription;
  BusLocation? assignedVehicle;
  String? assignedVehicleId;
  DateTime? boardedAt;
  ({double latitude, double longitude, double radiusMeters})? destinationStop;
  ({double latitude, double longitude, double radiusMeters})? pickupStop;
  int insideFixes = 0;
  bool completingArrival = false;
  bool arrived = false;
  double? boardedFare;
  bool stopsLoaded = false;
  String? firstRouteName;
  String? lastRouteName;
  List<String> routeNames = const [];
  bool stopReached = false;
  bool overstayAlerted = false;
  int overstayPenaltyCredits = 10;

  @override
  void initState() {
    super.initState();
    boarded =
        widget.initialStatus == 'onboard' || widget.initialStatus == 'boarded';
    if (boarded) boardedFare = widget.fare;
    assignedVehicleId = widget.vehicleId;
    boardedAt = widget.boardedAt ?? (boarded ? widget.createdAt : null);
    vehicleLocations = const PassengerFirebaseService()
        .watchBusLocations()
        .asBroadcastStream();
    vehicleSubscription = vehicleLocations.listen(
      _onVehicleLocations,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Could not monitor vehicle location: $error');
      },
    );
    overstayPenaltySubscription = const PassengerFirebaseService()
        .watchOverstayingPenaltyCredits()
        .listen(
          (credits) {
            if (mounted && credits != overstayPenaltyCredits) {
              setState(() => overstayPenaltyCredits = credits);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Could not load overstaying penalty: $error');
          },
        );
    _loadStops();
    etaTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && boarded && !arrived) setState(() {});
    });
    proximityTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && assignedVehicle != null && !assignedVehicle!.hasFreshGps) {
        setState(() => assignedVehicle = null);
      }
      _checkMissedStop();
    });
    phoneGpsTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _publishPhoneGps();
    });
    if (!boarded) {
      final elapsed = widget.createdAt == null
          ? Duration.zero
          : DateTime.now().difference(widget.createdAt!);
      final remaining = const Duration(minutes: 10) - elapsed;
      expiryTimer = Timer(
        remaining > Duration.zero ? remaining : Duration.zero,
        () => _cancel(expired: true),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_stopAlertSound());
    expiryTimer?.cancel();
    etaTimer?.cancel();
    proximityTimer?.cancel();
    phoneGpsTimer?.cancel();
    vehicleSubscription?.cancel();
    overstayPenaltySubscription?.cancel();
    super.dispose();
  }

  Future<void> _publishPhoneGps() async {
    final vehicleId = assignedVehicleId;
    if (!mounted || !boarded || arrived || completingArrival ||
        phoneGpsRunning || vehicleId == null) return;
    phoneGpsRunning = true;
    try {
      final service = const PassengerFirebaseService();
      if (!await service.isSelectedPhoneReporter(uid: widget.session.uid,
          bookingId: widget.bookingId, vehicleId: vehicleId)) return;
      final position = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.high),
      ).timeout(const Duration(seconds: 5));
      if (!mounted || !boarded || arrived) return;
      await service.publishOnboardPhoneLocation(
        uid: widget.session.uid, bookingId: widget.bookingId,
        vehicleId: vehicleId, position: position);
    } catch (error) {
      debugPrint('Phone GPS update unavailable: $error');
    } finally {
      phoneGpsRunning = false;
    }
  }

  Future<void> _playAlertSound(String kind) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _rideAlertChannel.invokeMethod<void>('play', {'kind': kind});
    } catch (error) {
      debugPrint('Could not play ride alert: $error');
    }
  }

  Future<void> _stopAlertSound() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _rideAlertChannel.invokeMethod<void>('stop');
    } catch (error) {
      debugPrint('Could not stop ride alert: $error');
    }
  }

  Future<void> _loadStops() async {
    final service = const PassengerFirebaseService();
    try {
      final destination = await service.getRouteStop(
        routeId: widget.destinationRouteId,
        name: widget.destination,
      );
      final pickup = widget.pickup == null
          ? null
          : await service.getRouteStop(
              routeId: widget.pickupRouteId,
              name: widget.pickup!,
            );
      List<Map<String, dynamic>> routes = [];
      try {
        routes = await service.getRoutes();
      } catch (_) {
        // Stop coordinates can still be used when the route list is unavailable.
      }
      if (!mounted) return;
      setState(() {
        destinationStop = destination;
        pickupStop = pickup;
        firstRouteName = routes.firstOrNull?['name'] as String?;
        lastRouteName = routes.lastOrNull?['name'] as String?;
        routeNames = routes.map((route) => '${route['name'] ?? ''}').toList();
        stopsLoaded = true;
      });
      _checkArrivalGeofence();
    } catch (error) {
      debugPrint('Could not load route stop locations: $error');
      if (mounted) setState(() => stopsLoaded = true);
    }
  }

  void _onVehicleLocations(List<BusLocation> vehicles) {
    final id = assignedVehicleId;
    if (!mounted || id == null) return;
    final vehicle = vehicles.where((bus) => bus.id == id).firstOrNull;
    if (vehicle == null || !vehicle.hasFreshGps) {
      if (assignedVehicle != null) setState(() => assignedVehicle = null);
      return;
    }
    setState(() => assignedVehicle = vehicle);
    _checkArrivalGeofence();
  }

  double? get _distanceToDestination {
    final stop = destinationStop;
    final vehicle = assignedVehicle;
    if (stop == null || vehicle == null || !vehicle.hasFreshGps) return null;
    return geo.Geolocator.distanceBetween(
      vehicle.latitude,
      vehicle.longitude,
      stop.latitude,
      stop.longitude,
    );
  }

  int? get _etaMinutes {
    final stop = destinationStop;
    if (stop == null) return null;
    final distance = _distanceToDestination;
    if (distance != null) {
      final speed = assignedVehicle!.speedKmh > 3
          ? assignedVehicle!.speedKmh
          : 10.0;
      return (distance / (speed * 1000 / 60)).ceil().clamp(0, 999);
    }
    final start = pickupStop;
    final began = boardedAt;
    if (start == null || began == null) return null;
    final tripMeters = geo.Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      stop.latitude,
      stop.longitude,
    );
    final totalMinutes = (tripMeters / (10 * 1000 / 60)).ceil();
    final elapsedMinutes = DateTime.now().difference(began).inMinutes;
    return (totalMinutes - elapsedMinutes).clamp(0, 999);
  }

  void _checkArrivalGeofence() {
    if (!boarded || arrived || completingArrival) return;
    if (assignedVehicle?.locationSource != 'hardware') return;
    final stop = destinationStop;
    final distance = _distanceToDestination;
    if (stop == null || distance == null) return;
    if (distance > stop.radiusMeters) {
      insideFixes = 0;
    } else if (!stopReached && ++insideFixes >= 1) {
      _notifyDestinationReached();
    }
  }

  Future<void> _notifyDestinationReached() async {
    if (!mounted || stopReached) return;
    setState(() => stopReached = true);
    try {
      await HapticFeedback.vibrate();
    } catch (_) {
      // Some web browsers and devices do not provide vibration.
    }
    if (!mounted) return;
    await _playAlertSound('notification');
    if (!mounted) {
      await _stopAlertSound();
      return;
    }
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your stop is here'),
        content: Text(
          'The jeep has reached ${widget.destination}. Tap I have arrived only after you get off.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Still onboard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('I have arrived'),
          ),
        ],
      ),
      );
    } finally {
      await _stopAlertSound();
    }
    if (confirmed == true && mounted) {
      await showArrival();
    }
  }

  Future<void> _checkMissedStop() async {
    if (!mounted ||
        !boarded ||
        !stopReached ||
        completingArrival ||
        arrived ||
        overstayAlerted) {
      return;
    }
    final stop = destinationStop;
    final vehicle = assignedVehicle;
    if (stop == null ||
        vehicle == null ||
        vehicle.locationSource != 'hardware' ||
        geo.Geolocator.distanceBetween(
              vehicle.latitude,
              vehicle.longitude,
              stop.latitude,
              stop.longitude,
            ) <=
            stop.radiusMeters + 15) {
      return;
    }
    overstayAlerted = true;
    try {
      if (!mounted) return;
      try {
        await HapticFeedback.vibrate();
      } catch (_) {
        // Vibration is unavailable on some web browsers and devices.
      }
      if (!mounted) return;
      await _playAlertSound('alarm');
      if (!mounted) {
        await _stopAlertSound();
        return;
      }
      try {
        final destinationIndex = routeNames.indexOf(widget.destination);
        final nextIndex = assignedVehicle?.routeDirection == 'towardFirstStop'
            ? destinationIndex - 1 : destinationIndex + 1;
        final nextRoute = nextIndex >= 0 && nextIndex < routeNames.length
            ? routeNames[nextIndex] : 'the next stop';
        await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('You are overstaying'),
          content: Text(
            'You are overstaying. $overstayPenaltyCredits credits will be deducted. Please drop off at $nextRoute. If you already got off, tap I have arrived.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Still onboard'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                showArrival();
              },
              child: const Text('I have arrived'),
            ),
          ],
        ),
        );
      } finally {
        await _stopAlertSound();
      }
    } catch (_) {
      // The server still evaluates the penalty from hardware GPS.
    }
  }

  Future<void> _cancel({bool expired = false}) async {
    if (boarded || canceled || canceling) return;
    if (!expired) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancel this booking?'),
          content: const Text('You can create a new booking afterward.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep waiting'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel booking'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    setState(() => canceling = true);
    try {
      await const PassengerFirebaseService().cancelBooking(
        widget.session.uid,
        widget.bookingId,
        expired: expired,
      );
      if (!mounted) return;
      setState(() {
        canceled = true;
        canceling = false;
      });
      expiryTimer?.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            expired
                ? 'Booking canceled after 10 minutes of waiting.'
                : 'Booking canceled.',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => canceling = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> scanQr() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _BoardingScanner()),
    );
    if (code == null || !mounted) return;
    try {
      final payload = jsonDecode(code);
      if (payload is! Map<String, dynamic> ||
          payload['status'] != 'Onboard' ||
          !const {'Jeep', 'E-Jeep'}.contains(payload['type']) ||
          payload['vehicleId'] is! String ||
          (payload['vehicleId'] as String).isEmpty) {
        throw const FormatException('Not a valid boarding QR code.');
      }
      final service = const PassengerFirebaseService();
      final preview = await service.previewBoardingFare(
        widget.bookingId, payload['vehicleId'] as String);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm boarding fare'),
          content: Text('${preview.fareType} fare for ${widget.passengerCount} '
              'passenger${widget.passengerCount == 1 ? '' : 's'}: '
              'PHP ${preview.fare.toStringAsFixed(2)}. '
              'Vehicle direction: ${preview.directionLabel}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm and board')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final passenger = await service.boardRide(
        widget.session.uid,
        widget.bookingId,
        payload['vehicleId'] as String,
        payload['type'] as String,
        confirmedFare: preview.fare,
        confirmedDirection: preview.direction,
      );
      widget.session.updatePassenger(passenger);
      expiryTimer?.cancel();
      if (mounted) {
        setState(() {
          boarded = true;
          boardedFare = preview.fare;
          assignedVehicleId = payload['vehicleId'] as String;
          boardedAt = DateTime.now();
          assignedVehicle = null;
          insideFixes = 0;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> showArrival() async {
    if (completingArrival || arrived || !boarded || !stopReached) return;
    setState(() => completingArrival = true);
    try {
      await const PassengerFirebaseService().completeRide(
        widget.session.uid,
        widget.bookingId,
      );
    } catch (error) {
      if (mounted) {
        setState(() => completingArrival = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
      return;
    }
    if (!mounted) return;
    setState(() => arrived = true);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Ride completed'),
        content: Text('You arrived at ${widget.destination}.'),
        actions: [
          FilledButton(
            onPressed: () =>
                Navigator.popUntil(context, (route) => route.isFirst),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Your ride',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          boarded ? 'You are onboard' : 'Waiting for your ride',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          boarded
              ? 'Payment is recorded for this ride.'
              : 'Scan the vehicle QR code when you board. Waiting expires after 10 minutes.',
          style: const TextStyle(color: Colors.black54),
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
              boarded ? 'PAID FARE' : 'FARE',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 8),
              Text(
                boarded ? 'PHP ${(boardedFare ?? widget.fare).toStringAsFixed(2)}'
                    : 'Calculated when you board',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: boarded ? 30 : 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              if (!boarded)
                Text(
                  'Review the fare before confirming boarding.',
                  style: TextStyle(color: Colors.white70),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          height: 250,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFE1F1E5),
            borderRadius: BorderRadius.circular(24),
          ),
          child: StreamBuilder<List<BusLocation>>(
            stream: vehicleLocations,
            builder: (context, snapshot) => Stack(
              fit: StackFit.expand,
              children: [
                CampusMap(
                  destination: widget.destination,
                  destinationLatitude: destinationStop?.latitude,
                  destinationLongitude: destinationStop?.longitude,
                  busLocations:
                      snapshot.data?.where((bus) => bus.hasFreshGps).toList() ??
                      const [],
                  onboardVehicleId: boarded ? assignedVehicleId : null,
                ),
                if (snapshot.hasError)
                  const Align(
                    alignment: Alignment.bottomCenter,
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Vehicle GPS is temporarily unavailable.'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Destination: ${widget.destination} · ${widget.passengerCount} passenger${widget.passengerCount > 1 ? 's' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (boarded) ...[
          const SizedBox(height: 8),
          Text(
            'Overstaying is punishable with $overstayPenaltyCredits credits.',
            style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            assignedVehicle?.routeDirection == 'towardLastStop'
                ? 'Vehicle direction: ${firstRouteName ?? 'First stop'} → ${lastRouteName ?? 'Last stop'}'
                : assignedVehicle?.routeDirection == 'towardFirstStop'
                    ? 'Vehicle direction: ${lastRouteName ?? 'Last stop'} → ${firstRouteName ?? 'First stop'}'
                    : 'Vehicle direction: waiting for GPS',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            destinationStop == null
                ? stopsLoaded
                      ? 'Destination stop location unavailable. Ask the admin to check this route.'
                      : 'Loading the registered destination stop...'
                : _etaMinutes == null
                ? 'Waiting for vehicle GPS to estimate arrival.'
                : 'Approx. ETA to drop-off: ${_etaMinutes!} min',
            style: const TextStyle(color: Colors.black54),
          ),
        ],
        const SizedBox(height: 20),
        if (!boarded || !arrived)
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: completingArrival || (boarded && !stopReached)
                  ? null
                  : boarded
                  ? () => showArrival()
                  : scanQr,
              icon: Icon(boarded ? Icons.flag : Icons.qr_code_scanner),
              label: Text(
                boarded ? 'I have arrived' : 'SCAN QR',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        if (!boarded && !canceled) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: canceling ? null : () => _cancel(),
            icon: const Icon(Icons.cancel_outlined),
            label: Text(canceling ? 'Canceling...' : 'Cancel booking'),
          ),
        ],
      ],
    ),
  );
}

class _BoardingScanner extends StatefulWidget {
  const _BoardingScanner();
  @override
  State<_BoardingScanner> createState() => _BoardingScannerState();
}

class _BoardingScannerState extends State<_BoardingScanner>
    with SingleTickerProviderStateMixin {
  bool captured = false;
  late final AnimationController scanAnimation;

  @override
  void initState() {
    super.initState();
    scanAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    scanAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan vehicle boarding QR')),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(
          300.0,
          math.min(constraints.maxWidth * .78, constraints.maxHeight * .54),
        );
        final scanWindow = Rect.fromCenter(
          center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
          width: side,
          height: side,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              // The web scanner currently detects across the camera preview.
              scanWindow: kIsWeb ? null : scanWindow,
              onDetect: (capture) {
                if (captured || capture.barcodes.isEmpty) return;
                final code = capture.barcodes.first.rawValue;
                if (code == null) return;
                captured = true;
                Navigator.pop(context, code);
              },
            ),
            IgnorePointer(
              child: AnimatedBuilder(
                animation: scanAnimation,
                builder: (context, _) => CustomPaint(
                  painter: _ScannerOverlayPainter(
                    window: scanWindow,
                    progress: scanAnimation.value,
                  ),
                ),
              ),
            ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xDD000000),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      'Align the vehicle QR code inside the box',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter({required this.window, required this.progress});

  final Rect window;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final opening = RRect.fromRectAndRadius(window, const Radius.circular(18));
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(opening);
    canvas.drawPath(shade, Paint()..color = const Color(0x99000000));
    canvas.drawRRect(
      opening,
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final corner = Paint()
      ..color = const Color(0xFF67E49B)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const length = 30.0;
    const inset = 4.0;
    final left = window.left + inset;
    final right = window.right - inset;
    final top = window.top + inset;
    final bottom = window.bottom - inset;
    for (final x in [left, right]) {
      for (final y in [top, bottom]) {
        final dx = x == left ? length : -length;
        final dy = y == top ? length : -length;
        canvas.drawLine(Offset(x, y), Offset(x + dx, y), corner);
        canvas.drawLine(Offset(x, y), Offset(x, y + dy), corner);
      }
    }

    final lineY = window.top + 14 + progress * (window.height - 28);
    final line = Rect.fromLTWH(window.left + 16, lineY, window.width - 32, 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(line, const Radius.circular(2)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.transparent, Color(0xFF67E49B), Colors.transparent],
        ).createShader(line),
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.window != window;
}

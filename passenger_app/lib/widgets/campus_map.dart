import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../config/mapbox_config.dart';
import '../models/bus_location.dart';
import 'vehicle_marker_art.dart';

class CampusMap extends StatefulWidget {
  static geo.Position? get latestPosition => _CampusMapState.recentPosition;
  const CampusMap({
    this.destination,
    this.destinationLatitude,
    this.destinationLongitude,
    this.busLocations = const [],
    this.onboardVehicleId,
    super.key,
  });
  final String? destination;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final List<BusLocation> busLocations;
  final String? onboardVehicleId;

  @override
  State<CampusMap> createState() => _CampusMapState();
}

class _CampusMapState extends State<CampusMap> {
  static const accessToken = MapboxConfig.accessToken;
  // The home map remains mounted while booking, so its latest GPS fix can be
  // reused by the ride map instead of waiting for another cold GPS request.
  static geo.Position? recentPosition;
  static final campusCenter = mb.Point(
    coordinates: mb.Position(120.9630, 14.3225),
  );
  static final campusStops = <String, mb.Point>{
    'Gate 1': mb.Point(coordinates: mb.Position(120.96382, 14.3215)),
    'Parking Polca': mb.Point(coordinates: mb.Position(120.9627, 14.3219)),
    'CBAA': mb.Point(coordinates: mb.Position(120.9621, 14.3227)),
    'Batibot': mb.Point(coordinates: mb.Position(120.9617, 14.3233)),
    'SHS Building': mb.Point(coordinates: mb.Position(120.9624, 14.3240)),
    'Covered Walk': mb.Point(coordinates: mb.Position(120.9632, 14.3231)),
    'Roundabout Gate 3': mb.Point(coordinates: mb.Position(120.9640, 14.3227)),
  };

  mb.MapboxMap? map;
  bool styleReady = false;
  bool fittedVehicleAndPassenger = false;
  static const _sourceId = 'passenger-live-locations';
  static const _routeSourceId = 'passenger-onboard-road-route';
  bool routeLoading = false;
  DateTime? lastRouteRequest;
  ({double latitude, double longitude})? lastRouteStart;
  int routeGeneration = 0;
  StreamSubscription<geo.Position>? positionSubscription;
  geo.Position? currentPosition;
  String? locationMessage;

  @override
  void initState() {
    super.initState();
    final cached = recentPosition;
    if (cached != null &&
        DateTime.now().difference(cached.timestamp) <
            const Duration(minutes: 5)) {
      currentPosition = cached;
    }
    enableLocation();
  }

  @override
  void dispose() {
    positionSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(CampusMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destination != widget.destination ||
        oldWidget.destinationLatitude != widget.destinationLatitude ||
        oldWidget.destinationLongitude != widget.destinationLongitude ||
        oldWidget.busLocations != widget.busLocations ||
        oldWidget.onboardVehicleId != widget.onboardVehicleId) {
      if (oldWidget.destinationLatitude != widget.destinationLatitude ||
          oldWidget.destinationLongitude != widget.destinationLongitude ||
          oldWidget.onboardVehicleId != widget.onboardVehicleId) {
        fittedVehicleAndPassenger = false;
        lastRouteRequest = null;
      }
      updateMarkers();
      fitVehicleAndPassenger();
      updateRoadRoute();
    }
  }

  Future<void> onMapCreated(mb.MapboxMap controller) async {
    map = controller;
    await controller.gestures.updateSettings(mb.GesturesSettings(
      pinchToZoomEnabled: true,
      doubleTouchToZoomOutEnabled: true,
      pinchPanEnabled: true,
    ));
  }

  Future<Uint8List> _finishIcon() async {
    const size = 56;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    paint.color = Colors.white;
    canvas.drawCircle(const Offset(28, 28), 27, paint);
    paint.color = const Color(0xFF08783E);
    canvas.drawCircle(const Offset(28, 28), 25, paint);
    paint.color = Colors.white;
    canvas.drawRect(const Rect.fromLTWH(17, 14, 3, 29), paint);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 4; col++) {
        paint.color = (row + col).isEven ? Colors.white : Colors.black;
        canvas.drawRect(Rect.fromLTWH(20 + col * 5.5, 15 + row * 5.5, 5.5, 5.5), paint);
      }
    }
    final image = await recorder.endRecording().toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  Future<void> onStyleLoaded(mb.StyleLoadedEventData _) async {
    final controller = map;
    if (controller == null) return;
    styleReady = false;
    try {
      await controller.addImage(
        'ikot-jeep-marker',
        2,
        mb.StyleImage.bytes(await VehicleMarkerArt.make(electric: false)),
      );
      await controller.addImage(
        'ikot-ejeep-marker',
        2,
        mb.StyleImage.bytes(await VehicleMarkerArt.make(electric: true)),
      );
      await controller.addImage('ikot-finish-marker', 2,
        mb.StyleImage.bytes(await _finishIcon()));
      await controller.addSource(mb.GeoJsonSource(id: _sourceId));
      await controller.addSource(mb.GeoJsonSource(id: _routeSourceId));
      await controller.addLayer(mb.LineLayer(
        id: 'passenger-road-route-outline', sourceId: _routeSourceId,
        lineColor: Colors.white.toARGB32(), lineWidth: 11,
      ));
      await controller.addLayer(mb.LineLayer(
        id: 'passenger-road-route-fill', sourceId: _routeSourceId,
        lineColor: const Color(0xFF08783E).toARGB32(), lineWidth: 7,
      ));
      await controller.addLayer(
        mb.CircleLayer(
          id: 'passenger-stop-layer',
          sourceId: _sourceId,
          filter: [
            '==',
            ['get', 'kind'],
            'stop',
          ],
          circleColor: const Color(0xFF1B8F4D).toARGB32(),
          circleRadius: 9,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 3,
        ),
      );
      await controller.addLayer(
        mb.CircleLayer(
          id: 'passenger-position-layer',
          sourceId: _sourceId,
          filter: [
            '==',
            ['get', 'kind'],
            'passenger',
          ],
          circleColor: const Color(0xFF2196F3).toARGB32(),
          circleRadius: 10,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 3,
        ),
      );
      await controller.addLayer(
        mb.SymbolLayer(
          id: 'passenger-vehicles-layer',
          sourceId: _sourceId,
          filter: [
            '==',
            ['get', 'kind'],
            'vehicle',
          ],
          iconImageExpression: ['get', 'icon'],
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );
      await controller.addLayer(mb.SymbolLayer(
        id: 'passenger-finish-layer', sourceId: _sourceId,
        filter: ['==', ['get', 'kind'], 'finish'],
        iconImage: 'ikot-finish-marker',
        iconAllowOverlap: true, iconIgnorePlacement: true,
      ));
      styleReady = true;
      await updateMarkers();
      await updateRoadRoute();
      fitVehicleAndPassenger();
    } catch (error) {
      debugPrint('Could not add live map markers: $error');
      if (mounted) {
        setState(() => locationMessage = 'Unable to display live map markers.');
      }
    }
  }

  void onMapLoadError(mb.MapLoadingErrorEventData event) {
    debugPrint('Mapbox map load error (${event.type}): ${event.message}');
  }

  Future<void> updateMarkers() async {
    final controller = map;
    if (!styleReady || controller == null) return;
    final features = <Map<String, Object?>>[];
    void addPoint(
      double latitude,
      double longitude,
      String kind, {
      String? icon,
      String? label,
    }) {
      features.add({
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [longitude, latitude],
        },
        'properties': {'kind': kind, 'icon': ?icon, 'label': ?label},
      });
    }

    final destination =
        widget.destinationLatitude != null &&
            widget.destinationLongitude != null
        ? mb.Point(
            coordinates: mb.Position(
              widget.destinationLongitude!,
              widget.destinationLatitude!,
            ),
          )
        : campusStops[widget.destination];
    if (destination != null) {
      addPoint(
        destination.coordinates.lat.toDouble(),
        destination.coordinates.lng.toDouble(),
        widget.onboardVehicleId == null ? 'stop' : 'finish',
      );
    }
    final user = currentPosition;
    if (user != null) {
      addPoint(user.latitude, user.longitude, 'passenger');
    }
    for (final bus in widget.busLocations) {
      addPoint(
        bus.latitude,
        bus.longitude,
        'vehicle',
        icon: bus.type.toLowerCase().contains('e-jeep')
            ? 'ikot-ejeep-marker'
            : 'ikot-jeep-marker',
        label: bus.label,
      );
    }
    try {
      await controller.setStyleSourceProperty(
        _sourceId,
        'data',
        jsonEncode({'type': 'FeatureCollection', 'features': features}),
      );
    } catch (error) {
      debugPrint('Could not update live map positions: $error');
    }
  }

  Future<void> updateRoadRoute() async {
    final controller = map;
    if (!styleReady || controller == null) return;
    final finishLatitude = widget.destinationLatitude;
    final finishLongitude = widget.destinationLongitude;
    final vehicleId = widget.onboardVehicleId;
    if (vehicleId == null || finishLatitude == null || finishLongitude == null) {
      routeGeneration++;
      await _setRoadGeometry(null);
      return;
    }
    final vehicle = widget.busLocations.where((bus) => bus.id == vehicleId).firstOrNull;
    final startLatitude = vehicle?.latitude ?? currentPosition?.latitude;
    final startLongitude = vehicle?.longitude ?? currentPosition?.longitude;
    if (startLatitude == null || startLongitude == null || routeLoading) return;
    final now = DateTime.now();
    final previous = lastRouteStart;
    if (previous != null && lastRouteRequest != null &&
        now.difference(lastRouteRequest!) < const Duration(seconds: 20) &&
         geo.Geolocator.distanceBetween(previous.latitude, previous.longitude,
           startLatitude, startLongitude) < 40) {
      return;
    }
    lastRouteRequest = now;
    lastRouteStart = (latitude: startLatitude, longitude: startLongitude);
    routeLoading = true;
    final generation = ++routeGeneration;
    try {
      final uri = Uri.https('api.mapbox.com',
        '/directions/v5/mapbox/driving/$startLongitude,$startLatitude;$finishLongitude,$finishLatitude', {
          'geometries': 'geojson', 'overview': 'full',
          'access_token': accessToken,
        });
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) throw StateError('Directions HTTP ${response.statusCode}');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = body['routes'] as List<dynamic>?;
      final geometry = routes?.firstOrNull is Map<String, dynamic>
          ? (routes!.first as Map<String, dynamic>)['geometry'] as Map<String, dynamic>?
          : null;
      if (body['code'] != 'Ok' || geometry == null) {
        throw StateError('No mapped road route is available.');
      }
      if (!mounted || generation != routeGeneration) return;
      await _setRoadGeometry(geometry);
    } catch (error) {
      debugPrint('Could not load onboard road directions: $error');
      if (mounted && generation == routeGeneration) {
        await _setRoadGeometry(null);
        setState(() => locationMessage = 'Road directions are unavailable for this stop.');
      }
    } finally {
      routeLoading = false;
    }
  }

  Future<void> _setRoadGeometry(Map<String, dynamic>? geometry) async {
    if (!styleReady || map == null) return;
    await map!.setStyleSourceProperty(_routeSourceId, 'data', jsonEncode({
      'type': 'FeatureCollection',
      'features': geometry == null ? [] : [{'type': 'Feature', 'geometry': geometry, 'properties': {}}],
    }));
  }

  Future<void> fitVehicleAndPassenger() async {
    final hasDestination = widget.onboardVehicleId != null &&
        widget.destinationLatitude != null && widget.destinationLongitude != null;
    if (fittedVehicleAndPassenger ||
        !styleReady ||
        map == null ||
        currentPosition == null ||
        (widget.busLocations.isEmpty && !hasDestination)) {
      return;
    }
    final passenger = currentPosition!;
    try {
      final camera = await map!.cameraForCoordinates(
        [
          mb.Point(
            coordinates: mb.Position(passenger.longitude, passenger.latitude),
          ),
          ...widget.busLocations.map(
            (bus) =>
                mb.Point(coordinates: mb.Position(bus.longitude, bus.latitude)),
          ),
          if (hasDestination)
            mb.Point(coordinates: mb.Position(
              widget.destinationLongitude!, widget.destinationLatitude!)),
        ],
        mb.MbxEdgeInsets(top: 55, left: 55, bottom: 55, right: 55),
        0,
        0,
      );
      if (!mounted) return;
      fittedVehicleAndPassenger = true;
      await map!.flyTo(camera, mb.MapAnimationOptions(duration: 900));
    } catch (error) {
      debugPrint('Could not fit live map locations: $error');
    }
  }

  Future<void> enableLocation() async {
    try {
      if (!await geo.Geolocator.isLocationServiceEnabled()) {
        recentPosition = null;
        if (mounted) {
          setState(() {
            currentPosition = null;
            locationMessage = 'Turn on GPS to show your location.';
          });
          updateMarkers();
        }
        return;
      }
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied ||
          permission == geo.LocationPermission.deniedForever) {
        recentPosition = null;
        if (mounted) {
          setState(() {
            currentPosition = null;
            locationMessage = 'Location permission is required for live GPS.';
          });
          updateMarkers();
        }
        return;
      }
      geo.Position? lastKnown;
      try {
        lastKnown = await geo.Geolocator.getLastKnownPosition();
      } catch (_) {
        // Some browser geolocation providers have no last-known-position API.
      }
      if (lastKnown != null &&
          DateTime.now().difference(lastKnown.timestamp) <
              const Duration(minutes: 5) &&
          (currentPosition == null ||
              lastKnown.timestamp.isAfter(currentPosition!.timestamp))) {
        updatePosition(lastKnown, moveCamera: currentPosition == null);
      }
      positionSubscription =
          geo.Geolocator.getPositionStream(
            locationSettings: const geo.LocationSettings(
              accuracy: geo.LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen(
            (position) =>
                updatePosition(position, moveCamera: currentPosition == null),
          );
      // The stream may take time to emit on some devices; request a fresh fix
      // independently without delaying the cached position already on screen.
      final current = await geo.Geolocator.getCurrentPosition();
      updatePosition(current, moveCamera: currentPosition == null);
    } catch (_) {
      if (mounted) {
        setState(
          () => locationMessage = 'Unable to read your current location.',
        );
      }
    }
  }

  void updatePosition(geo.Position next, {bool moveCamera = false}) {
    if (!mounted) return;
    if (currentPosition != null &&
        next.timestamp.isBefore(currentPosition!.timestamp)) {
      return;
    }
    recentPosition = next;
    setState(() {
      currentPosition = next;
      locationMessage = null;
    });
    updateMarkers();
    fitVehicleAndPassenger();
    updateRoadRoute();
    if (moveCamera && widget.busLocations.isEmpty) {
      map?.flyTo(
        mb.CameraOptions(
          center: mb.Point(
            coordinates: mb.Position(next.longitude, next.latitude),
          ),
          zoom: 17,
        ),
        mb.MapAnimationOptions(duration: 900),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (accessToken.isEmpty) {
      return const _MapMessage(
        message:
            'Set a public Mapbox token in the app configuration to display the live map.',
      );
    }
    return Stack(
      children: [
        mb.MapWidget(
          key: const ValueKey('ikot-mapbox-map'),
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
          },
          viewport: mb.CameraViewportState(
            center: currentPosition == null
                ? campusCenter
                : mb.Point(
                    coordinates: mb.Position(
                      currentPosition!.longitude,
                      currentPosition!.latitude,
                    ),
                  ),
            zoom: currentPosition == null ? 16.5 : 17,
            pitch: 45,
          ),
          onMapCreated: onMapCreated,
          onStyleLoadedListener: onStyleLoaded,
          onMapLoadErrorListener: onMapLoadError,
        ),
        Positioned(
          top: 10,
          left: 10,
          child: Material(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(10),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LegendDot(color: Colors.blue),
                  Text('You'),
                  SizedBox(width: 10),
                  _LegendDot(color: Color(0xFFF4A524)),
                  Text('Jeep'),
                  SizedBox(width: 10),
                  _LegendDot(color: Color(0xFF13A9A0)),
                  Text('E-Jeep'),
                  SizedBox(width: 10),
                  _LegendDot(color: Color(0xFF1B8F4D)),
                  Text('Stop'),
                ],
              ),
            ),
          ),
        ),
        if (locationMessage != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    const Icon(Icons.location_off, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        locationMessage!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: enableLocation,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    margin: const EdgeInsets.only(right: 4),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _MapMessage extends StatelessWidget {
  const _MapMessage({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

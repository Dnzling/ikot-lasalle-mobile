import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/mapbox_config.dart';
import 'vehicle_marker_art.dart';

typedef MapLocation = ({double latitude, double longitude});

class RealMap extends StatefulWidget {
  const RealMap({
    super.key,
    this.latitude,
    this.longitude,
    this.interactivePin = false,
    this.label = 'Location',
    this.showMarker = true,
    this.vehicleType,
    this.plateNumber,
    this.radiusMeters,
    this.onLocationChanged,
    this.additionalPins = const [],
    this.additionalRadii = const [],
    this.fitAllPins = false,
  });

  final double? latitude;
  final double? longitude;
  final bool interactivePin;
  final String label;
  final bool showMarker;
  final String? vehicleType;
  final String? plateNumber;
  final double? radiusMeters;
  final ValueChanged<MapLocation>? onLocationChanged;
  final List<({double latitude, double longitude, String label})>
  additionalPins;
  final List<({double latitude, double longitude, double radiusMeters})>
  additionalRadii;
  final bool fitAllPins;

  @override
  State<RealMap> createState() => _RealMapState();
}

class _RealMapState extends State<RealMap> with SingleTickerProviderStateMixin {
  static final Future<Uint8List> jeepMarker = VehicleMarkerArt.make(
    electric: false,
  );
  static final Future<Uint8List> eJeepMarker = VehicleMarkerArt.make(
    electric: true,
  );
  // DLSU-D campus center, matching the passenger application.
  static const campus = LatLng(14.3225, 120.9630);
  final controller = MapController();
  late final AnimationController _markerController;
  Animation<double>? _latitudeAnimation;
  Animation<double>? _longitudeAnimation;
  late LatLng marker;

  @override
  void initState() {
    super.initState();
    marker = _initialLocation;
    _markerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(_updateAnimatedMarker);
  }

  @override
  void didUpdateWidget(covariant RealMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      final target = _initialLocation;
      if (widget.interactivePin) {
        setState(() => marker = target);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) controller.move(target, 17);
        });
      } else {
        _latitudeAnimation =
            Tween<double>(begin: marker.latitude, end: target.latitude).animate(
              CurvedAnimation(
                parent: _markerController,
                curve: Curves.easeInOut,
              ),
            );
        _longitudeAnimation =
            Tween<double>(
              begin: marker.longitude,
              end: target.longitude,
            ).animate(
              CurvedAnimation(
                parent: _markerController,
                curve: Curves.easeInOut,
              ),
            );
        _markerController.forward(from: 0);
      }
    }
  }

  void _updateAnimatedMarker() {
    final latitude = _latitudeAnimation;
    final longitude = _longitudeAnimation;
    if (!mounted || latitude == null || longitude == null) return;
    setState(() => marker = LatLng(latitude.value, longitude.value));
  }

  @override
  void dispose() {
    _markerController
      ..removeListener(_updateAnimatedMarker)
      ..dispose();
    super.dispose();
  }

  LatLng get _initialLocation =>
      widget.latitude != null && widget.longitude != null
      ? LatLng(widget.latitude!, widget.longitude!)
      : campus;

  void _moveMarker(LatLng point) {
    if (!widget.interactivePin) return;
    setState(() => marker = point);
    widget.onLocationChanged?.call((
      latitude: point.latitude,
      longitude: point.longitude,
    ));
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: Stack(
      children: [
        FlutterMap(
          mapController: controller,
          options: MapOptions(
            initialCenter: marker,
            initialZoom: 17,
            initialCameraFit: widget.fitAllPins && widget.additionalPins.isNotEmpty
                ? CameraFit.coordinates(
                    coordinates: [marker,
                      ...widget.additionalPins.map((pin) =>
                          LatLng(pin.latitude, pin.longitude))],
                    padding: const EdgeInsets.all(110), maxZoom: 17)
                : null,
            minZoom: 3,
            maxZoom: 22,
            onTap: (_, point) => _moveMarker(point),
            onLongPress: (_, point) => _moveMarker(point),
          ),
          children: [
            TileLayer(
              urlTemplate: MapboxConfig.streetsTileUrl,
              userAgentPackageName: 'com.ikotlasalle.admin',
              tileSize: 512,
              zoomOffset: -1,
              maxNativeZoom: 22,
            ),
            if (widget.radiusMeters != null ||
                widget.additionalRadii.isNotEmpty)
              CircleLayer(
                circles: [
                  if (widget.radiusMeters != null)
                    CircleMarker(
                      point: marker,
                      radius: widget.radiusMeters!,
                      useRadiusInMeter: true,
                      color: const Color(0xFF08783E).withValues(alpha: .18),
                      borderColor: const Color(0xFF08783E),
                      borderStrokeWidth: 2,
                    ),
                  ...widget.additionalRadii.map(
                    (radius) => CircleMarker(
                      point: LatLng(radius.latitude, radius.longitude),
                      radius: radius.radiusMeters,
                      useRadiusInMeter: true,
                      color: const Color(0xFFC9D0CC).withValues(alpha: .20),
                      borderColor: const Color(0xFFB0B8B3),
                      borderStrokeWidth: 2,
                    ),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (widget.showMarker)
                  Marker(
                    point: marker,
                    width: 180,
                    height: widget.vehicleType == null ? 90 : 112,
                    alignment: widget.vehicleType == null
                        ? Alignment.center
                        : Alignment.bottomCenter,
                    child: widget.vehicleType == null
                        ? SizedBox.expand(
                            child: Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  color: Color(0xFF08783E),
                                  size: 34,
                                ),
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF073F28),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: Text(
                                        widget.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF073F28),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  widget.plateNumber?.trim().isNotEmpty == true
                                      ? widget.plateNumber!.trim()
                                      : 'Plate number unavailable',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              FutureBuilder<Uint8List>(
                                future:
                                    widget.vehicleType!.toLowerCase().contains(
                                      'e-jeep',
                                    )
                                    ? eJeepMarker
                                    : jeepMarker,
                                builder: (context, snapshot) => snapshot.hasData
                                    ? Image.memory(
                                        snapshot.data!,
                                        width: 90,
                                        height: 68,
                                        fit: BoxFit.contain,
                                      )
                                    : const SizedBox(height: 68),
                              ),
                            ],
                          ),
                  ),
                ...widget.additionalPins.map(
                  (pin) => Marker(
                    point: LatLng(pin.latitude, pin.longitude),
                    width: 140,
                    height: 60,
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDDE2DE),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            pin.label,
                            style: const TextStyle(
                              color: const Color(0xFF3F4B43),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.location_on,
                          color: Color(0xFFB0B8B3),
                          size: 30,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 10,
          bottom: 10,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Text(
                '© Mapbox  © OpenStreetMap',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        if (widget.interactivePin)
          Positioned(
            top: 10,
            left: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .92),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                child: Text(
                  'Click or long-press to move pin',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ),
          ),
        if (!widget.showMarker)
          Positioned(
            top: 10,
            left: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                child: Text(
                  'Waiting for vehicle GPS location',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

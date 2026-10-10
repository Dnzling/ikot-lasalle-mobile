import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/mapbox_config.dart';

typedef MapLocation = ({double latitude, double longitude});

class RealMap extends StatefulWidget {
  const RealMap({
    super.key,
    this.latitude,
    this.longitude,
    this.interactivePin = false,
    this.label = 'Location',
    this.showMarker = true,
    this.radiusMeters,
    this.onLocationChanged,
  });

  final double? latitude;
  final double? longitude;
  final bool interactivePin;
  final String label;
  final bool showMarker;
  final double? radiusMeters;
  final ValueChanged<MapLocation>? onLocationChanged;

  @override
  State<RealMap> createState() => _RealMapState();
}

class _RealMapState extends State<RealMap> {
  // DLSU-D campus center, matching the passenger application.
  static const campus = LatLng(14.3225, 120.9630);
  final controller = MapController();
  late LatLng marker;

  @override
  void initState() {
    super.initState();
    marker = _initialLocation;
  }

  @override
  void didUpdateWidget(covariant RealMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      setState(() => marker = _initialLocation);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.move(marker, 17);
      });
    }
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
            if (widget.radiusMeters != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: marker,
                    radius: widget.radiusMeters!,
                    useRadiusInMeter: true,
                    color: const Color(0xFF08783E).withValues(alpha: .18),
                    borderColor: const Color(0xFF08783E),
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            MarkerLayer(
              markers: widget.showMarker
                  ? [
                      Marker(
                        point: marker,
                        width: 180,
                        height: 78,
                        alignment: Alignment.topCenter,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
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
                            const Icon(
                              Icons.location_on,
                              color: Color(0xFF08783E),
                              size: 34,
                            ),
                          ],
                        ),
                      ),
                    ]
                  : const [],
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

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/firebase_service.dart';
import '../widgets/common.dart';
import '../widgets/real_map.dart';
import '../widgets/vehicle_marker_art.dart';

String _gpsUpdateTime(Object? value) {
  if (value is! Timestamp) return 'No GPS update yet';
  final date = value.toDate().toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour < 12 ? 'AM' : 'PM';
  return '${months[date.month - 1]} ${date.day}, ${date.year} $hour:$minute $period';
}

String _gpsUpdateAge(Object? value, DateTime now) {
  if (value is! Timestamp) return 'No interval available';
  final elapsed = now.difference(value.toDate());
  if (elapsed.isNegative) return 'Just now';
  if (elapsed.inDays > 0) {
    return '${elapsed.inDays}d ${elapsed.inHours % 24}h ago';
  }
  if (elapsed.inHours > 0) {
    return '${elapsed.inHours}h ${elapsed.inMinutes % 60}m ago';
  }
  if (elapsed.inMinutes > 0) {
    return '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s ago';
  }
  return '${elapsed.inSeconds}s ago';
}

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({super.key});
  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  static final Future<Uint8List> jeepIcon = VehicleMarkerArt.make(
    electric: false,
  );
  static final Future<Uint8List> eJeepIcon = VehicleMarkerArt.make(
    electric: true,
  );
  String? selectedId;
  bool showArchived = false;
  Timer? presenceTimer;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> vehicleStream =
      FirebaseService.instance.watch('vehicles');
  late final Stream<QuerySnapshot<Map<String, dynamic>>> tripStream =
      FirebaseService.instance.watch('trips');

  @override
  void initState() {
    super.initState();
    presenceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    presenceTimer?.cancel();
    super.dispose();
  }

  MapLocation? _location(Object? value) {
    if (value is Map) {
      final latitude = (value['latitude'] as num?)?.toDouble();
      final longitude = (value['longitude'] as num?)?.toDouble();
      if (latitude != null && longitude != null) {
        value = GeoPoint(latitude, longitude);
      }
    }
    if (value is! GeoPoint) return null;
    return (latitude: value.latitude, longitude: value.longitude);
  }

  MapLocation? _phoneMapLocation(String vehicleId, MapLocation? hardware,
      Timestamp? hardwareAt, QuerySnapshot<Map<String, dynamic>>? trips) {
    if (hardware == null || hardwareAt == null || trips == null ||
        DateTime.now().difference(hardwareAt.toDate()) > const Duration(seconds: 120)) return null;
    final candidates = trips.docs.where((doc) {
      final data = doc.data();
      return data['vehicleId'] == vehicleId && data['status'] == 'onboard' &&
          data['phoneLocation'] is GeoPoint && data['phoneGpsAt'] is Timestamp &&
          ((data['phoneGpsAccuracyMeters'] as num?)?.toDouble() ?? 999) <= 30;
    }).toList()..sort((a, b) =>
        ((a.data()['boardedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
            .compareTo((b.data()['boardedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
    for (final candidate in candidates) {
      final data = candidate.data();
      final at = (data['phoneGpsAt'] as Timestamp).toDate();
      if (!at.isAfter(hardwareAt.toDate()) ||
          DateTime.now().difference(at) > const Duration(seconds: 10)) continue;
      final point = data['phoneLocation'] as GeoPoint;
      final lat = point.latitude * math.pi / 180;
      final hardwareLat = hardware.latitude * math.pi / 180;
      final dLat = lat - hardwareLat;
      final dLon = (point.longitude - hardware.longitude) * math.pi / 180;
      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(lat) * math.cos(hardwareLat) *
          math.sin(dLon / 2) * math.sin(dLon / 2);
      if (12742000 * math.asin(math.sqrt(a)) <= 500) {
        return (latitude: point.latitude, longitude: point.longitude);
      }
    }
    return null;
  }

  void _register() {
    final capacity = TextEditingController();
    final plateNumber = TextEditingController();
    var type = 'Jeep';
    showFormDialog(
      context,
      title: 'Register vehicle',
      action: 'Register vehicle',
      fields: [
        DropdownButtonFormField<String>(
          initialValue: type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: const [
            DropdownMenuItem(value: 'Jeep', child: Text('Jeep')),
            DropdownMenuItem(value: 'E-Jeep', child: Text('E-Jeep')),
          ],
          onChanged: (value) => type = value ?? type,
        ),
        FormFieldBox('Passenger capacity', controller: capacity),
        FormFieldBox('Plate number', controller: plateNumber, maxLength: 7),
      ],
      onSave: () async {
        final seats = int.tryParse(capacity.text);
        if (seats == null || seats <= 0) {
          _notice('Enter a positive passenger capacity.');
          return;
        }
        try {
          await FirebaseService.instance.addVehicle(
            name: '$type ${plateNumber.text.trim().toUpperCase()}',
            capacity: seats,
            plateNumber: plateNumber.text,
            type: type,
          );
          _notice('Vehicle registered.');
        } on FirebaseException catch (error) {
          _notice('Request ${error.code}: ${error.message}');
        } on ArgumentError catch (error) {
          _notice(error.message?.toString() ?? 'Invalid vehicle plate number.');
        }
      },
    );
  }

  Future<void> _editVehicle(String id, Map<String, dynamic> data) async {
    final capacity = TextEditingController(
      text: '${data['passengerCapacity'] ?? ''}',
    );
    final plateNumber = TextEditingController(
      text: '${data['plateNumber'] ?? ''}',
    );
    var type = '${data['type'] ?? 'Jeep'}';
    if (type != 'Jeep' && type != 'E-Jeep') type = 'Jeep';
    String? validationError;
    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit registered vehicle'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: 'Jeep', child: Text('Jeep')),
                      DropdownMenuItem(value: 'E-Jeep', child: Text('E-Jeep')),
                    ],
                    onChanged: (value) => type = value ?? type,
                  ),
                  const SizedBox(height: 12),
                  FormFieldBox('Passenger capacity', controller: capacity),
                  const SizedBox(height: 12),
                  FormFieldBox('Plate number', controller: plateNumber, maxLength: 7),
                  if (validationError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      validationError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final seats = int.tryParse(capacity.text.trim());
                if (seats == null || seats <= 0) {
                  setDialogState(
                    () => validationError =
                        'Enter a positive passenger capacity.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
    if (updated == true) {
      try {
        await FirebaseService.instance.updateVehicle(
          id,
          name: '$type ${plateNumber.text.trim().toUpperCase()}',
          capacity: int.parse(capacity.text.trim()),
          plateNumber: plateNumber.text,
          type: type,
        );
        _notice('Vehicle updated.');
      } on FirebaseException catch (error) {
        _notice('Request ${error.code}: ${error.message}');
      } on ArgumentError catch (error) {
        _notice(error.message?.toString() ?? 'Invalid vehicle plate number.');
      }
    }
    capacity.dispose();
    plateNumber.dispose();
  }

  Future<void> _archive(String id, bool archived) async {
    try {
      await (archived
          ? FirebaseService.instance.restoreVehicle(id)
          : FirebaseService.instance.archiveVehicle(id));
      _notice(archived ? 'Vehicle restored.' : 'Vehicle archived.');
    } on FirebaseException catch (error) {
      _notice('Request ${error.code}: ${error.message}');
    }
  }

  Future<void> _delete(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete vehicle permanently?'),
        content: Text(
          'This will permanently delete $name. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseService.instance.deleteVehicle(id);
      _notice('Vehicle deleted.');
    } on FirebaseException catch (error) {
      _notice('Request ${error.code}: ${error.message}');
    }
  }

  Future<void> _linkGpsDevice(String vehicleId) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Link GPS tracker'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Use this vehicle document ID in the hardware code:'),
            const SizedBox(height: 12),
            Center(
              child: SelectableText(
                vehicleId,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF176B45),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: vehicleId));
              if (context.mounted) Navigator.pop(context);
              _notice('Vehicle document ID copied.');
            },
            child: const Text('Copy ID'),
          ),
        ],
      ),
    );
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _showBoardingQr(String id, Map<String, dynamic> data) {
    final type = '${data['type'] ?? 'Jeep'}';
    final payload = jsonEncode({
      'type': type,
      'status': 'Onboard',
      'vehicleId': id,
    });
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Boarding QR — ${data['name'] ?? type}'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 250,
                height: 250,
                child: QrImageView(data: payload, size: 250),
              ),
              Text('Type: $type  •  Status: Onboard'),
              const SizedBox(height: 8),
              const Text(
                'Passengers scan this code when boarding this vehicle.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: vehicleStream,
    builder: (context, snapshot) {
      final now = DateTime.now();
      if (snapshot.hasError) return _FirebaseError(error: snapshot.error);
      final allDocs = snapshot.data?.docs ?? [];
      final docs = allDocs
          .where((doc) => (doc.data()['archived'] == true) == showArchived)
          .toList();
      if (docs.isNotEmpty && !docs.any((doc) => doc.id == selectedId)) {
        selectedId = docs.first.id;
      }
      final selected = docs.where((doc) => doc.id == selectedId).firstOrNull;
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            PageIntro(
              title: 'Fleet tracking',
              subtitle: 'Live vehicle records from the server.',
              action: FilledButton.icon(
                onPressed: _register,
                icon: const Icon(Icons.add),
                label: const Text('Register vehicle'),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: (constraints.maxHeight - 295).clamp(500.0, 800.0),
              child: Row(
                children: [
                  SizedBox(
                    width: 320,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Registered vehicles',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: showArchived
                                      ? 'Show active vehicles'
                                      : 'Show archive',
                                  onPressed: () => setState(() {
                                    showArchived = !showArchived;
                                    selectedId = null;
                                  }),
                                  icon: Icon(
                                    showArchived
                                        ? Icons.directions_bus_outlined
                                        : Icons.archive_outlined,
                                  ),
                                ),
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting)
                                  const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: docs.isEmpty
                                  ? const _Empty(
                                      message: 'No vehicles registered.',
                                    )
                                  : ListView.builder(
                                      itemCount: docs.length,
                                      itemBuilder: (_, index) {
                                        final doc = docs[index];
                                        final data = doc.data();
                                        return ListTile(
                                          selected: doc.id == selectedId,
                                          selectedTileColor: const Color(
                                            0xFFE5F4EA,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          leading: SizedBox(
                                            width: 56,
                                            height: 48,
                                            child: FutureBuilder<Uint8List>(
                                              future:
                                                  '${data['type'] ?? ''}'
                                                      .toLowerCase()
                                                      .contains('e-jeep')
                                                  ? eJeepIcon
                                                  : jeepIcon,
                                              builder: (context, image) =>
                                                  image.hasData
                                                  ? Image.memory(
                                                      image.data!,
                                                      fit: BoxFit.contain,
                                                    )
                                                  : const Icon(
                                                      Icons.directions_bus,
                                                    ),
                                            ),
                                          ),
                                          title: Text(
                                            '${data['name'] ?? 'Unnamed'}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${data['plateNumber'] ?? 'No plate'} • ${data['type'] ?? 'Jeep'} • ${data['passengerCapacity'] ?? 0} seats',
                                          ),
                                          trailing: PopupMenuButton<String>(
                                            tooltip: 'Vehicle actions',
                                            onSelected: (action) {
                                              if (action == 'archive') {
                                                _archive(
                                                  doc.id,
                                                  data['archived'] == true,
                                                );
                                              } else if (action == 'delete') {
                                                _delete(
                                                  doc.id,
                                                  '${data['name'] ?? 'this vehicle'}',
                                                );
                                              } else if (action == 'gps') {
                                                _linkGpsDevice(doc.id);
                                              } else if (action == 'edit') {
                                                _editVehicle(doc.id, data);
                                              } else if (action == 'qr') {
                                                _showBoardingQr(doc.id, data);
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(
                                                value: 'edit',
                                                child: Text('Edit vehicle'),
                                              ),
                                              const PopupMenuItem(
                                                value: 'gps',
                                                child: Text('Link GPS tracker'),
                                              ),
                                              if (data['archived'] != true) ...[
                                                const PopupMenuItem(
                                                  value: 'qr',
                                                  child: Text(
                                                    'Show boarding QR',
                                                  ),
                                                ),
                                              ],
                                              PopupMenuItem(
                                                value: 'archive',
                                                child: Text(
                                                  data['archived'] == true
                                                      ? 'Restore'
                                                      : 'Archive',
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Text(
                                                  'Delete',
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          onTap: () => setState(
                                            () => selectedId = doc.id,
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: selected == null
                            ? const _Empty(
                                message:
                                    'Select a vehicle to view its location.',
                              )
                            : Builder(
                                builder: (_) {
                                  final location = _location(
                                    selected.data()['location'] ??
                                        selected.data()['currentLocation'],
                                  );
                                  final online = vehicleGpsIsFresh(
                                    selected.data(),
                                  );
                                  return Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: _VehicleRouteTimeline(
                                          compact: true,
                                          vehicleData: selected.data(),
                                          vehicleIcon: '${selected.data()['type'] ?? ''}'
                                                  .toLowerCase().contains('e-jeep')
                                              ? eJeepIcon : jeepIcon,
                                        ),
                                      ),
                                      if (!online)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                
                                        ),
                                      Expanded(
                                        child: Stack(
                                          children: [
                                            Positioned.fill(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                              stream: tripStream,
                                              builder: (context, trips) {
                                                final phone = _phoneMapLocation(selected.id, location,
                                                    selected.data()['lastGpsAt'] as Timestamp?, trips.data);
                                                final marker = phone ?? location;
                                                return Stack(fit: StackFit.expand, children: [RealMap(
                                                  key: ValueKey(selected.id),
                                                  latitude: marker?.latitude,
                                                  longitude: marker?.longitude,
                                                  showMarker: marker != null,
                                                  label: '${selected.data()['name'] ?? 'Vehicle'}',
                                                  vehicleType: '${selected.data()['type'] ?? 'Jeep'}',
                                                  plateNumber: '${selected.data()['plateNumber'] ?? ''}',
                                                ), if (phone != null)
                                                  Positioned(top: 12, left: 12,
                                                    child: Chip(label: const Text('Phone GPS'))),
                                                ]);
                                              },
                                            )),
                                            Positioned(
                                              top: 12,
                                              right: 12,
                                              child: _VehicleStatusBadge(
                                                status: vehicleDisplayStatus(selected.data()),
                                              ),
                                            ),
                                            Positioned(
                                              left: 12,
                                              right: 12,
                                              bottom: 12,
                                              child: Align(
                                                alignment: Alignment.bottomLeft,
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                                    child: Text(
                                                      'Last GPS update: ${_gpsUpdateTime(selected.data()['lastGpsAt'])}  •  '
                                                      'Elapsed: ${_gpsUpdateAge(selected.data()['lastGpsAt'], now)}',
                                                      style: const TextStyle(fontSize: 12),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (selected != null)
              Column(
                children: [
                  _VehicleDetails(
                    data: selected.data(),
                    vehicleId: selected.id,
                    tripStream: tripStream,
                  ),
                  const SizedBox(height: 16),
                ],
              )
            else
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: _Empty(
                    message: 'Vehicle trip details will appear here.',
                  ),
                ),
              ),
          ],
        ),
        ),
      );
    },
  );
}

class _VehicleRouteTimeline extends StatelessWidget {
  const _VehicleRouteTimeline({
    required this.vehicleData,
    required this.vehicleIcon,
    this.compact = false,
  });

  final Map<String, dynamic> vehicleData;
  final Future<Uint8List> vehicleIcon;
  final bool compact;

  MapLocation? _vehicleLocation() {
    final raw = vehicleData['location'] ?? vehicleData['currentLocation'];
    if (raw is GeoPoint) {
      return (latitude: raw.latitude, longitude: raw.longitude);
    }
    if (raw is Map) {
      final lat = (raw['latitude'] as num?)?.toDouble();
      final lng = (raw['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) return (latitude: lat, longitude: lng);
    }
    final lat = (vehicleData['latitude'] as num?)?.toDouble();
    final lng = (vehicleData['longitude'] as num?)?.toDouble();
    if (lat != null && lng != null) return (latitude: lat, longitude: lng);
    return null;
  }

  double _distanceMeters(MapLocation a, MapLocation b) {
    const earthRadius = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final deltaLat = (b.latitude - a.latitude) * math.pi / 180;
    final deltaLng = (b.longitude - a.longitude) * math.pi / 180;
    final haversine =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    return earthRadius *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseService.instance.watch('routes'),
    builder: (context, snapshot) {
      final theme = Theme.of(context);
      if (snapshot.hasError) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text('Could not load route stops: ${snapshot.error}'),
          ),
        );
      }
      final stops =
          [...?snapshot.data?.docs].where((stop) {
            final data = stop.data();
            return data['archived'] != true && data['active'] != false;
          }).toList()..sort((a, b) {
            final aOrder = (a.data()['order'] as num?)?.toInt() ?? 999999;
            final bOrder = (b.data()['order'] as num?)?.toInt() ?? 999999;
            return aOrder.compareTo(bOrder);
          });

      final location = _vehicleLocation();
      String? activeStopId;
      var nearestDistance = double.infinity;
      if (location != null) {
        for (final stop in stops) {
          final raw = stop.data()['location'];
          if (raw is! GeoPoint) continue;
          final stopLocation = (
            latitude: raw.latitude,
            longitude: raw.longitude,
          );
          final distance = _distanceMeters(location, stopLocation);
          final radius =
              (stop.data()['proximityRadius'] as num?)?.toDouble() ?? 50;
          if (distance <= radius && distance < nearestDistance) {
            activeStopId = stop.id;
            nearestDistance = distance;
          }
        }
      }

      return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 20,
            compact ? 8 : 16,
            compact ? 12 : 20,
            compact ? 8 : 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.route_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Route timeline',
                      style: TextStyle(
                        fontSize: compact ? 13 : 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    activeStopId == null
                        ? (location == null
                              ? 'Vehicle location unavailable'
                              : 'Between stops')
                        : 'At ${stops.firstWhere((stop) => stop.id == activeStopId).data()['name'] ?? 'route stop'}',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: compact ? 11 : 14,
                    ),
                  ),
                ],
              ),
              if (stops.length > 1 &&
                  const {'towardLastStop', 'towardFirstStop'}
                      .contains(vehicleData['routeDirection']))
                Text(
                  vehicleData['routeDirection'] == 'towardLastStop'
                      ? '${stops.first.data()['name']} → ${stops.last.data()['name']}'
                      : '${stops.last.data()['name']} → ${stops.first.data()['name']}',
                  style: TextStyle(fontSize: compact ? 11 : 13,
                      color: theme.colorScheme.primary),
                ),
              SizedBox(height: compact ? 6 : 18),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  stops.isEmpty)
                const LinearProgressIndicator()
              else if (stops.isEmpty)
                const Text('No active route stops are registered.')
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stopWidth = compact
                        ? ((constraints.maxWidth - (stops.length - 1) * 8) /
                                  stops.length)
                              .clamp(36.0, 76.0)
                        : 112.0;
                    final timeline = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var index = 0; index < stops.length; index++) ...[
                          _TimelineStop(
                            compact: compact,
                            width: stopWidth,
                            name:
                                '${stops[index].data()['name'] ?? 'Stop ${index + 1}'}',
                            order: index + 1,
                            isCurrent: stops[index].id == activeStopId,
                            vehicleIcon: vehicleIcon,
                          ),
                          if (index < stops.length - 1)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: compact ? 14 : 28,
                                ),
                                child: Container(
                                  height: 2,
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                            ),
                        ],
                      ],
                    );
                    final requiredWidth = stops.length * stopWidth;
                    if (!compact || requiredWidth <= constraints.maxWidth) {
                      return timeline;
                    }
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: requiredWidth + (stops.length - 1) * 8,
                        child: Row(
                          children: [
                            for (
                              var index = 0;
                              index < stops.length;
                              index++
                            ) ...[
                              _TimelineStop(
                                compact: compact,
                                width: stopWidth,
                                name:
                                    '${stops[index].data()['name'] ?? 'Stop ${index + 1}'}',
                                order: index + 1,
                                isCurrent: stops[index].id == activeStopId,
                                vehicleIcon: vehicleIcon,
                              ),
                              if (index < stops.length - 1)
                                const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
      );
    },
  );
}

class _TimelineStop extends StatelessWidget {
  const _TimelineStop({
    required this.compact,
    required this.width,
    required this.name,
    required this.order,
    required this.isCurrent,
    required this.vehicleIcon,
  });

  final bool compact;
  final double width;
  final String name;
  final int order;
  final bool isCurrent;
  final Future<Uint8List> vehicleIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Column(
        children: [
          SizedBox(
            width: compact ? 28 : 56,
            height: compact ? 28 : 56,
            child: isCurrent
                ? FutureBuilder<Uint8List>(
                    future: vehicleIcon,
                    builder: (context, snapshot) => snapshot.hasData
                        ? Image.memory(snapshot.data!, fit: BoxFit.contain)
                        : Icon(
                            Icons.directions_bus,
                            color: theme.colorScheme.primary,
                            size: compact ? 18 : 32,
                          ),
                  )
                : CircleAvatar(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    child: Text(
                      '$order',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
          ),
          SizedBox(height: compact ? 3 : 8),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 9 : 12,
              fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
              color: isCurrent ? theme.colorScheme.primary : null,
            ),
          ),
          if (isCurrent)
            Text(
              'VEHICLE HERE',
              style: TextStyle(
                fontSize: compact ? 7 : 9,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _VehicleDetails extends StatelessWidget {
  const _VehicleDetails({
    required this.data,
    required this.vehicleId,
    required this.tripStream,
  });
  final Map<String, dynamic> data;
  final String vehicleId;
  final Stream<QuerySnapshot<Map<String, dynamic>>> tripStream;

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: tripStream,
    builder: (context, snapshot) {
      final now = DateTime.now();
      final todayTrips = (snapshot.data?.docs ?? []).where((doc) {
        final trip = doc.data();
        final boardedAt = trip['boardedAt'];
        if (trip['vehicleId'] != vehicleId || boardedAt is! Timestamp) {
          return false;
        }
        final localDate = boardedAt.toDate().toLocal();
        return localDate.year == now.year &&
            localDate.month == now.month &&
            localDate.day == now.day;
      });
      final passengersToday = todayTrips.fold<int>(
        0,
        (total, trip) =>
            total + ((trip.data()['passengerCount'] as num?)?.toInt() ?? 1),
      );
      final revenueToday = todayTrips.fold<double>(
        0,
        (total, trip) =>
            total + ((trip.data()['fare'] as num?)?.toDouble() ?? 0),
      );
      final passengers = (data['onBoardPassengers'] as num?)?.toInt() ?? 0;
      final capacity = (data['passengerCapacity'] as num?)?.toInt() ?? 0;
      final loading =
          snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasData;
      return Row(
        children: [
          Expanded(
            child: _AssignedDriver(data: data),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _Info(
              'On board',
              '$passengers passengers',
              '${(capacity - passengers).clamp(0, capacity)} available seats',
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _Info(
              'Trip Passengers TODAY',
              loading ? 'Loading...' : '$passengersToday passengers',
              'Boarded today',
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _Info(
              'Trip Revenue',
              loading ? 'Loading...' : 'PHP ${revenueToday.toStringAsFixed(2)}',
              'Today only',
            ),
          ),
        ],
      );
    },
  );
}

class _VehicleStatusBadge extends StatelessWidget {
  const _VehicleStatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = status == 'OFFLINE'
        ? Colors.grey.shade800
        : status == 'ACTIVE'
            ? const Color(0xFF08783E)
            : Colors.orange.shade800;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(status, style: const TextStyle(
          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800,
        )),
      ),
    );
  }
}

class _AssignedDriver extends StatelessWidget {
  const _AssignedDriver({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final driverId = '${data['driverId'] ?? ''}'.trim();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: driverId.isEmpty ? null : FirebaseService.instance.db
          .collection('drivers').doc(driverId).snapshots(),
      builder: (context, snapshot) {
        final driver = snapshot.data?.data();
        final name = driver == null
            ? '${data['driverName'] ?? 'Not assigned'}'
            : '${driver['firstName'] ?? ''} ${driver['lastName'] ?? ''}'.trim();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Assigned driver', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(children: [
                  ClipOval(child: SizedBox.square(
                    dimension: 48,
                    child: driver == null ? const Icon(Icons.person_outline)
                        : _DriverAvatar(data: driver),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: Text(name, style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900,
                  ))),
                ]),
                Text(driverId.isEmpty ? 'No driver assigned' : 'Driver',
                    style: const TextStyle(color: Colors.black45)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DriverAvatar extends StatelessWidget {
  const _DriverAvatar({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final encoded = data['photoBase64'];
    if (encoded is String && encoded.isNotEmpty) {
      try {
        return Image.memory(base64Decode(encoded), fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.person_outline));
      } on FormatException {
        // Fall through to older photo fields.
      }
    }
    final url = '${data['photoUrl'] ?? ''}'.trim();
    if (url.startsWith('http')) {
      return Image.network(url, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.person_outline));
    }
    final path = url.isNotEmpty ? url : '${data['photoPath'] ?? ''}'.trim();
    if (path.isNotEmpty) {
      final ref = path.startsWith('gs://')
          ? FirebaseStorage.instance.refFromURL(path)
          : FirebaseStorage.instance.ref(path);
      return FutureBuilder<Uint8List?>(
        future: ref.getData(1024 * 1024),
        builder: (context, image) => image.hasData && image.data != null
            ? Image.memory(image.data!, fit: BoxFit.cover)
            : const Icon(Icons.person_outline),
      );
    }
    return const Icon(Icons.person_outline);
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value, this.detail);
  final String label, value, detail;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          Text(detail, style: const TextStyle(color: Colors.black45)),
        ],
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.black45),
    ),
  );
}

class _FirebaseError extends StatelessWidget {
  const _FirebaseError({required this.error});
  final Object? error;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        'Could not load vehicles from the server.\n$error',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

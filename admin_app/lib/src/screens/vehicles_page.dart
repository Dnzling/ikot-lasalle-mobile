import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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

  void _register() {
    final name = TextEditingController();
    final capacity = TextEditingController();
    final plateNumber = TextEditingController();
    var type = 'Jeep';
    showFormDialog(
      context,
      title: 'Register vehicle',
      action: 'Register vehicle',
      fields: [
        FormFieldBox('Vehicle name', controller: name),
        FormFieldBox('Passenger capacity', controller: capacity),
        FormFieldBox('Plate number', controller: plateNumber),
        DropdownButtonFormField<String>(
          initialValue: type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: const [
            DropdownMenuItem(value: 'Jeep', child: Text('Jeep')),
            DropdownMenuItem(value: 'E-Jeep', child: Text('E-Jeep')),
          ],
          onChanged: (value) => type = value ?? type,
        ),
      ],
      onSave: () async {
        final seats = int.tryParse(capacity.text);
        if (name.text.trim().isEmpty ||
            plateNumber.text.trim().isEmpty ||
            seats == null ||
            seats <= 0) {
          _notice('Enter a vehicle name and positive capacity.');
          return;
        }
        try {
          await FirebaseService.instance.addVehicle(
            name: name.text,
            capacity: seats,
            plateNumber: plateNumber.text,
            type: type,
          );
          _notice('Vehicle registered.');
        } on FirebaseException catch (error) {
          _notice('Firebase ${error.code}: ${error.message}');
        }
      },
    );
  }

  Future<void> _editVehicle(String id, Map<String, dynamic> data) async {
    final name = TextEditingController(text: '${data['name'] ?? ''}');
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
                  FormFieldBox('Vehicle name', controller: name),
                  const SizedBox(height: 12),
                  FormFieldBox('Passenger capacity', controller: capacity),
                  const SizedBox(height: 12),
                  FormFieldBox('Plate number', controller: plateNumber),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: 'Jeep', child: Text('Jeep')),
                      DropdownMenuItem(value: 'E-Jeep', child: Text('E-Jeep')),
                    ],
                    onChanged: (value) => type = value ?? type,
                  ),
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
                if (name.text.trim().isEmpty ||
                    plateNumber.text.trim().isEmpty ||
                    seats == null ||
                    seats <= 0) {
                  setDialogState(
                    () =>
                        validationError = 'Enter a name and positive capacity.',
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
          name: name.text,
          capacity: int.parse(capacity.text.trim()),
          plateNumber: plateNumber.text,
          type: type,
        );
        _notice('Vehicle updated.');
      } on FirebaseException catch (error) {
        _notice('Firebase ${error.code}: ${error.message}');
      }
    }
    name.dispose();
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
      _notice('Firebase ${error.code}: ${error.message}');
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
      _notice('Firebase ${error.code}: ${error.message}');
    }
  }

  Future<void> _linkGpsDevice(String vehicleId, String? currentUid) async {
    final controller = TextEditingController(text: currentUid ?? '');
    final uid = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Link GPS tracker'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText('Vehicle document ID: $vehicleId'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Firebase Authentication device UID',
                helperText: 'Use a separate account for each physical tracker.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (uid == null || uid.isEmpty) return;
    try {
      await FirebaseService.instance.linkVehicleGpsDevice(vehicleId, uid);
      _notice('GPS tracker linked.');
    } on FirebaseException catch (error) {
      _notice('Firebase ${error.code}: ${error.message}');
    }
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
      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            PageIntro(
              title: 'Fleet tracking',
              subtitle: 'Live vehicle records from Firebase.',
              action: FilledButton.icon(
                onPressed: _register,
                icon: const Icon(Icons.add),
                label: const Text('Register vehicle'),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 500,
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
                                            '${data['plateNumber'] ?? 'No plate'} • ${data['type'] ?? 'Jeep'} • ${data['passengerCapacity'] ?? 0} seats • ${vehicleDisplayStatus(data)}',
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
                                                _linkGpsDevice(
                                                  doc.id,
                                                  data['gpsDeviceUid']
                                                      as String?,
                                                );
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
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Text(
                                          'Last GPS update: ${_gpsUpdateTime(selected.data()['lastGpsAt'])}  •  '
                                          'Elapsed: ${_gpsUpdateAge(selected.data()['lastGpsAt'], now)}',
                                        ),
                                      ),
                                      if (!online)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: Text(
                                            location == null
                                                ? 'GPS offline. No vehicle coordinates have been received yet.'
                                                : 'GPS offline. Showing the last known position, not a live location.',
                                          ),
                                        ),
                                      Expanded(
                                        child: RealMap(
                                          key: ValueKey(selected.id),
                                          latitude: location?.latitude,
                                          longitude: location?.longitude,
                                          showMarker: location != null,
                                          label:
                                              '${selected.data()['name'] ?? 'Vehicle'}',
                                          vehicleType:
                                              '${selected.data()['type'] ?? 'Jeep'}',
                                          plateNumber:
                                              '${selected.data()['plateNumber'] ?? ''}',
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
                  _VehicleRouteTimeline(
                    vehicleData: selected.data(),
                    vehicleIcon:
                        '${selected.data()['type'] ?? ''}'
                            .toLowerCase()
                            .contains('e-jeep')
                        ? eJeepIcon
                        : jeepIcon,
                  ),
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
      );
    },
  );
}

class _VehicleRouteTimeline extends StatelessWidget {
  const _VehicleRouteTimeline({
    required this.vehicleData,
    required this.vehicleIcon,
  });

  final Map<String, dynamic> vehicleData;
  final Future<Uint8List> vehicleIcon;

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

      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.route_outlined),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Route timeline',
                      style: TextStyle(
                        fontSize: 17,
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
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  stops.isEmpty)
                const LinearProgressIndicator()
              else if (stops.isEmpty)
                const Text('No active route stops are registered.')
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < stops.length; index++) ...[
                        _TimelineStop(
                          name:
                              '${stops[index].data()['name'] ?? 'Stop ${index + 1}'}',
                          order:
                              (stops[index].data()['order'] as num?)?.toInt() ??
                              index + 1,
                          isCurrent: stops[index].id == activeStopId,
                          vehicleIcon: vehicleIcon,
                        ),
                        if (index < stops.length - 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 28),
                            child: Container(
                              width: 52,
                              height: 3,
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _TimelineStop extends StatelessWidget {
  const _TimelineStop({
    required this.name,
    required this.order,
    required this.isCurrent,
    required this.vehicleIcon,
  });

  final String name;
  final int order;
  final bool isCurrent;
  final Future<Uint8List> vehicleIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 112,
      child: Column(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: isCurrent
                ? FutureBuilder<Uint8List>(
                    future: vehicleIcon,
                    builder: (context, snapshot) => snapshot.hasData
                        ? Image.memory(snapshot.data!, fit: BoxFit.contain)
                        : Icon(
                            Icons.directions_bus,
                            color: theme.colorScheme.primary,
                            size: 32,
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
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
              color: isCurrent ? theme.colorScheme.primary : null,
            ),
          ),
          if (isCurrent)
            Text(
              'VEHICLE HERE',
              style: TextStyle(
                fontSize: 9,
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
            child: _Info(
              'Assigned driver',
              '${data['driverName'] ?? 'Not assigned'}',
              data['driverName'] == null ? 'No driver assigned' : 'Driver',
            ),
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
        'Could not load vehicles from Firebase.\n$error',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

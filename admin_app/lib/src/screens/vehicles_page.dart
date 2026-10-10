import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/firebase_service.dart';
import '../widgets/common.dart';
import '../widgets/real_map.dart';

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({super.key});
  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  String? selectedId;
  bool showArchived = false;

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
    final quota = TextEditingController();
    final salary = TextEditingController(text: '0');
    final plateNumber = TextEditingController();
    var type = 'Jeep';
    showFormDialog(
      context,
      title: 'Register vehicle',
      action: 'Register vehicle',
      fields: [
        FormFieldBox('Vehicle name', controller: name),
        FormFieldBox('Passenger capacity', controller: capacity),
        FormFieldBox('Daily revenue quota (PHP)', controller: quota),
        FormFieldBox('Daily driver salary (PHP)', controller: salary),
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
        final dailyQuota = double.tryParse(quota.text);
        final dailySalary = double.tryParse(salary.text);
        if (name.text.trim().isEmpty ||
            plateNumber.text.trim().isEmpty ||
            seats == null ||
            seats <= 0 ||
            dailyQuota == null ||
            dailyQuota < 0 ||
            dailySalary == null ||
            dailySalary < 0) {
          _notice('Enter a vehicle name, capacity, and valid daily quota.');
          return;
        }
        try {
          await FirebaseService.instance.addVehicle(
            name: name.text,
            capacity: seats,
            dailyQuota: dailyQuota,
            driverSalary: dailySalary,
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
    final quota = TextEditingController(text: '${data['dailyQuota'] ?? 0}');
    final salary = TextEditingController(text: '${data['driverSalary'] ?? 0}');
    final plateNumber = TextEditingController(text: '${data['plateNumber'] ?? ''}');
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
                  FormFieldBox('Daily revenue quota (PHP)', controller: quota),
                  const SizedBox(height: 12),
                  FormFieldBox('Daily driver salary (PHP)', controller: salary),
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
                final dailyQuota = double.tryParse(quota.text.trim());
                final dailySalary = double.tryParse(salary.text.trim());
                if (name.text.trim().isEmpty ||
                    plateNumber.text.trim().isEmpty ||
                    seats == null ||
                    seats <= 0 ||
                    dailyQuota == null ||
                    !dailyQuota.isFinite ||
                    dailyQuota < 0 ||
                    dailySalary == null ||
                    dailySalary < 0) {
                  setDialogState(
                    () => validationError =
                        'Enter a name, positive capacity and valid quota.',
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
          dailyQuota: double.parse(quota.text.trim()),
          driverSalary: double.parse(salary.text.trim()),
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
    quota.dispose();
    salary.dispose();
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
    stream: FirebaseService.instance.watch('vehicles'),
    builder: (context, snapshot) {
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
                                          leading: const CircleAvatar(
                                            child: Icon(Icons.directions_bus),
                                          ),
                                          title: Text(
                                            '${data['name'] ?? 'Unnamed'}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${data['type'] ?? 'Jeep'} • ${data['passengerCapacity'] ?? 0} seats • ${'${data['status'] ?? 'unknown'}'.toUpperCase()}',
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
                                  return RealMap(
                                    key: ValueKey(selected.id),
                                    latitude: location?.latitude,
                                    longitude: location?.longitude,
                                    showMarker: location != null,
                                    label:
                                        '${selected.data()['name'] ?? 'Vehicle'}',
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
              _VehicleDetails(data: selected.data())
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

class _VehicleDetails extends StatelessWidget {
  const _VehicleDetails({required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    final passengers = (data['onBoardPassengers'] as num?)?.toInt() ?? 0;
    final capacity = (data['passengerCapacity'] as num?)?.toInt() ?? 0;
    return Row(
      children: [
        Expanded(
          child: _Info(
            'Assigned driver',
            '${data['driverName'] ?? 'Not assigned'}',
            '${data['driverId'] ?? 'No driver ID'}',
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
            'Trip passengers',
            '${data['tripPassengerCount'] ?? 0} recorded',
            'Current trip total',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Info(
            'Income & salary',
            'PHP ${data['tripIncome'] ?? 0}',
            'Daily quota: PHP ${data['dailyQuota'] ?? 0} • Salary: PHP ${data['driverSalary'] ?? 0}',
          ),
        ),
      ],
    );
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
        'Could not load vehicles from Firebase.\n$error',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

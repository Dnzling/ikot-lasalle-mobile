import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../widgets/common.dart';

class DriversPage extends StatelessWidget {
  const DriversPage({super.key});

  Future<void> _edit(
    BuildContext context,
    String id,
    Map<String, dynamic> data,
  ) async {
    final first = TextEditingController(text: '${data['firstName'] ?? ''}');
    final last = TextEditingController(text: '${data['lastName'] ?? ''}');
    final contact = TextEditingController(
      text: '${data['contactNumber'] ?? ''}',
    );
    var vehicleId = data['vehicleId'] as String?;
    var active = data['active'] != false;
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: const Text('Edit driver'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FormFieldBox('First name', controller: first),
                  const SizedBox(height: 12),
                  FormFieldBox('Last name', controller: last),
                  const SizedBox(height: 12),
                  FormFieldBox('Contact number', controller: contact),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseService.instance.watch('vehicles'),
                    builder: (_, snapshot) => DropdownButtonFormField<String>(
                      initialValue: vehicleId ?? 'Unassigned',
                      decoration: const InputDecoration(
                        labelText: 'Assigned vehicle',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'Unassigned',
                          child: Text('Unassigned'),
                        ),
                        if (vehicleId != null &&
                            snapshot.data?.docs.any(
                                  (doc) =>
                                      doc.id == vehicleId &&
                                      doc.data()['archived'] != true &&
                                      (doc.data()['driverId'] == null ||
                                          doc.data()['driverId'] == id),
                                ) !=
                                true)
                          DropdownMenuItem(
                            value: vehicleId,
                            child: Text(
                              '${data['vehicleName'] ?? 'Assigned vehicle'}',
                            ),
                          ),
                        ...?snapshot.data?.docs
                            .where(
                              (doc) =>
                                  doc.data()['archived'] != true &&
                                  (doc.data()['driverId'] == null ||
                                      doc.data()['driverId'] == id),
                            )
                            .map(
                              (doc) => DropdownMenuItem(
                                value: doc.id,
                                child: Text(
                                  '${doc.data()['name'] ?? 'Unnamed vehicle'}',
                                ),
                              ),
                            ),
                      ],
                      onChanged: (value) => refresh(
                        () => vehicleId = value == 'Unassigned' ? null : value,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Active'),
                    value: active,
                    onChanged: (value) => refresh(() => active = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (first.text.trim().isEmpty ||
                          last.text.trim().isEmpty) {
                        _notice(context, 'First and last name are required.');
                        return;
                      }
                      refresh(() => saving = true);
                      try {
                        await FirebaseService.instance.updateDriver(id, {
                          'firstName': first.text.trim(),
                          'lastName': last.text.trim(),
                          'contactNumber': contact.text.trim(),
                          'vehicleId': vehicleId,
                          'active': active,
                        });
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        if (context.mounted) {
                          _notice(context, 'Driver updated.');
                        }
                      } catch (error) {
                        if (context.mounted) {
                          _notice(context, '$error');
                        }
                        if (dialogContext.mounted) {
                          refresh(() => saving = false);
                        }
                      }
                    },
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
    first.dispose();
    last.dispose();
    contact.dispose();
  }

  void _register(BuildContext context) {
    final first = TextEditingController(),
        last = TextEditingController(),
        contact = TextEditingController();
    final vehicle = ValueNotifier<String?>('Unassigned');
    showFormDialog(
      context,
      title: 'Register driver',
      action: 'Register driver',
      fields: [
        Row(
          children: [
            Expanded(child: FormFieldBox('First name', controller: first)),
            const SizedBox(width: 12),
            Expanded(child: FormFieldBox('Last name', controller: last)),
          ],
        ),
        FormFieldBox('Contact number', controller: contact),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseService.instance.watch('vehicles'),
          builder: (_, snapshot) => DropdownButtonFormField<String>(
            initialValue: 'Unassigned',
            decoration: const InputDecoration(labelText: 'Assign vehicle'),
            items: [
              const DropdownMenuItem(
                value: 'Unassigned',
                child: Text('Unassigned'),
              ),
              ...?snapshot.data?.docs
                  .where(
                    (doc) =>
                        doc.data()['archived'] != true &&
                        doc.data()['driverId'] == null,
                  )
                  .map(
                    (doc) => DropdownMenuItem(
                      value: doc.id,
                      child: Text('${doc.data()['name'] ?? 'Unnamed vehicle'}'),
                    ),
                  ),
            ],
            onChanged: (value) => vehicle.value = value,
          ),
        ),
      ],
      onSave: () async {
        if (first.text.trim().isEmpty || last.text.trim().isEmpty) {
          _notice(context, 'First name and last name are required.');
          return;
        }
        try {
          await FirebaseService.instance.addDriver({
            'firstName': first.text.trim(),
            'lastName': last.text.trim(),
            'contactNumber': contact.text.trim(),
            'vehicleId': vehicle.value == 'Unassigned' ? null : vehicle.value,
            'trips': 0,
            'passengers': 0,
            'rating': 0.0,
            'earnings': 0.0,
          });
          if (context.mounted) {
            _notice(context, 'Driver registered.');
          }
        } on FirebaseException catch (error) {
          if (context.mounted) {
            _notice(context, 'Firebase ${error.code}: ${error.message}');
          }
        }
      },
    );
  }

  void _notice(BuildContext context, String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseService.instance.watch('drivers'),
    builder: (context, driverSnapshot) {
      if (driverSnapshot.hasError) {
        return Center(
          child: Text(
            'Could not load drivers from Firebase.\n${driverSnapshot.error}',
          ),
        );
      }
      final allDrivers = driverSnapshot.data?.docs ?? [];
      final drivers = allDrivers.where((doc) => doc.data()['archived'] != true).toList();
      final totalTrips = drivers.fold<int>(
        0,
        (total, doc) => total + ((doc.data()['trips'] as num?)?.toInt() ?? 0),
      );
      final passengers = drivers.fold<int>(
        0,
        (total, doc) =>
            total + ((doc.data()['passengers'] as num?)?.toInt() ?? 0),
      );
      final ratings = drivers
          .map((doc) => (doc.data()['rating'] as num?)?.toDouble() ?? 0)
          .where((rating) => rating > 0)
          .toList();
      final average = ratings.isEmpty
          ? 0.0
          : ratings.reduce((a, b) => a + b) / ratings.length;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            PageIntro(
              title: 'Drivers',
              subtitle: 'Driver records and performance from Firebase.',
              action: FilledButton.icon(
                onPressed: () => _register(context),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Register driver'),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    'ACTIVE DRIVERS',
                    '${drivers.where((doc) => doc.data()['active'] != false).length}',
                    Icons.badge_outlined,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _Metric(
                    'TOTAL TRIPS',
                    '$totalTrips',
                    Icons.route_outlined,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _Metric(
                    'PASSENGERS CARRIED',
                    '$passengers',
                    Icons.groups_outlined,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _Metric(
                    'AVG. RATING',
                    average.toStringAsFixed(1),
                    Icons.star_outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Driver performance',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (driverSnapshot.connectionState ==
                            ConnectionState.waiting)
                          const CircularProgressIndicator(),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const _DriverHeader(),
                    const Divider(height: 1),
                    if (drivers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Text(
                          'No drivers registered.',
                          style: TextStyle(color: Colors.black45),
                        ),
                      )
                    else
                      for (final driver in drivers)
                        _DriverRow(
                          data: driver.data(),
                          onEdit: () =>
                              _edit(context, driver.id, driver.data()),
                          onArchive: () async {
                            final confirmed = await showDialog<bool>(context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Archive driver?'),
                                content: Text('Archive ${driver.data()['firstName']} ${driver.data()['lastName']}?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                                  FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Archive')),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            try {
                              await FirebaseService.instance.archiveDriver(driver.id);
                              if (context.mounted) _notice(context, 'Driver archived.');
                            } catch (error) {
                              if (context.mounted) _notice(context, '$error');
                            }
                          },
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseService.instance.watch('trips'),
              builder: (context, tripSnapshot) {
                final trips = tripSnapshot.data?.docs ?? [];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recent driver trips',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (trips.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'No trips recorded in Firebase.',
                              style: TextStyle(color: Colors.black45),
                            ),
                          )
                        else
                          for (final trip in trips.take(8))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                child: Icon(Icons.route),
                              ),
                              title: Text(
                                '${trip.data()['routeName'] ?? 'Trip'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${trip.data()['driverName'] ?? 'Unassigned'} • ${trip.data()['vehicleName'] ?? 'No vehicle'} • ${trip.data()['passengerCount'] ?? 0} passengers',
                              ),
                              trailing: Text(
                                'PHP ${trip.data()['income'] ?? 0}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
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

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFE5F4EA),
            child: Icon(icon, color: const Color(0xFF08783E)),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.black45,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DriverHeader extends StatelessWidget {
  const _DriverHeader();
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(flex: 2, child: Text('DRIVER', style: _head)),
      Expanded(child: Text('VEHICLE', style: _head)),
      Expanded(child: Text('ID', style: _head)),
      Expanded(child: Text('TRIPS', style: _head)),
      Expanded(child: Text('PASSENGERS', style: _head)),
      Expanded(child: Text('RATING', style: _head)),
      Expanded(child: Text('EARNINGS', style: _head)),
      SizedBox(width: 80),
    ],
  );
}

class _DriverRow extends StatelessWidget {
  const _DriverRow({required this.data, required this.onEdit, required this.onArchive});
  final Map<String, dynamic> data;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: Text('${data['vehicleName'] ?? 'Unassigned'}')),
        Expanded(child: Text('${data['driverId'] ?? ''}')),
        Expanded(child: Text('${data['trips'] ?? 0}')),
        Expanded(child: Text('${data['passengers'] ?? 0}')),
        Expanded(child: Text('${data['rating'] ?? 0}')),
        Expanded(
          child: Text(
            'PHP ${data['earnings'] ?? 0}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          width: 80,
          child: Row(children: [IconButton(
            tooltip: 'Edit driver',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ), IconButton(tooltip: 'Archive driver', onPressed: onArchive,
            icon: const Icon(Icons.archive_outlined))]),
        ),
      ],
    ),
  );
}

const _head = TextStyle(
  fontSize: 10,
  color: Colors.black45,
  fontWeight: FontWeight.w700,
);

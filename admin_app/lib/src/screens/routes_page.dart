import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../widgets/common.dart';
import '../widgets/real_map.dart';

class RoutesPage extends StatefulWidget {
  const RoutesPage({super.key});
  @override
  State<RoutesPage> createState() => _RoutesPageState();
}

class _RoutesPageState extends State<RoutesPage> {
  String? selectedId;
  bool showArchived = false;

  void _addRoute() {
    final name = TextEditingController();
    var radius = 50.0;
    var point = const GeoPoint(14.3225, 120.9630);
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add route point'),
          content: SizedBox(
            width: 700,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FormFieldBox('Route name', controller: name),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text(
                      'Proximity radius',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(
                      '${radius.round()} meters',
                      style: const TextStyle(
                        color: Color(0xFF08783E),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: radius,
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: '${radius.round()} m',
                  onChanged: (value) => setDialogState(() => radius = value),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Click or drag the pin to set the GeoPoint.',
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 300,
                  child: RealMap(
                    interactivePin: true,
                    radiusMeters: radius,
                    onLocationChanged: (location) =>
                        point = GeoPoint(location.latitude, location.longitude),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) {
                  _notice('Enter a route name.');
                  return;
                }
                Navigator.pop(dialogContext);
                try {
                  await FirebaseService.instance.addRoute(
                    name: name.text,
                    radius: radius,
                    location: point,
                  );
                  _notice('Route saved.');
                } on FirebaseException catch (error) {
                  _notice('Firebase ${error.code}: ${error.message}');
                }
              },
              child: const Text('Save route'),
            ),
          ],
        ),
      ),
    );
  }

  // Kept only to read legacy per-route fare data; the UI now uses global fares.
  // ignore: unused_element
  void _editFares(QueryDocumentSnapshot<Map<String, dynamic>> route) {
    final data = route.data();
    final standard = TextEditingController(
      text: '${data['defaultFare'] ?? 15}',
    );
    final round = TextEditingController(text: '${data['roundFare'] ?? 25}');
    showFormDialog(
      context,
      title: 'Fare settings - ${data['name'] ?? 'Route'}',
      action: 'Save fares',
      fields: [
        FormFieldBox('Default fare', controller: standard),
        FormFieldBox('Round fare', controller: round),
        const Text(
          'Round fare applies when a passenger travels against the linear A → E → A direction.',
        ),
      ],
      onSave: () async {
        final defaultFare = double.tryParse(standard.text),
            roundFare = double.tryParse(round.text);
        if (defaultFare == null ||
            roundFare == null ||
            defaultFare < 0 ||
            roundFare < 0) {
          _notice('Enter valid fare amounts.');
          return;
        }
        try {
          await FirebaseService.instance.updateFares(
            route.id,
            defaultFare,
            roundFare,
          );
          _notice('Fare settings saved.');
        } on FirebaseException catch (error) {
          _notice('Firebase ${error.code}: ${error.message}');
        }
      },
    );
  }

  void _editRoute(QueryDocumentSnapshot<Map<String, dynamic>> route) {
    final data = route.data();
    final name = TextEditingController(text: '${data['name'] ?? ''}');
    var radius = ((data['proximityRadius'] as num?)?.toDouble() ?? 50)
        .clamp(1, 100)
        .toDouble();
    var point = data['location'] is GeoPoint
        ? data['location'] as GeoPoint
        : const GeoPoint(14.3225, 120.9630);
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit route'),
          content: SizedBox(
            width: 700,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FormFieldBox('Route name', controller: name),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text(
                      'Proximity radius',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(
                      '${radius.round()} meters',
                      style: const TextStyle(
                        color: Color(0xFF08783E),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: radius,
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: '${radius.round()} m',
                  onChanged: (value) => setDialogState(() => radius = value),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 300,
                  child: RealMap(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    interactivePin: true,
                    radiusMeters: radius,
                    label: name.text.isEmpty ? 'Route' : name.text,
                    onLocationChanged: (location) =>
                        point = GeoPoint(location.latitude, location.longitude),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (data['archived'] != true)
              TextButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: dialogContext,
                    builder: (confirmationContext) => AlertDialog(
                      title: const Text('Archive route?'),
                      content: Text(
                        '${data['name'] ?? 'This route'} will no longer be available for new passenger trips. Past trip records will remain.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmationContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(confirmationContext, true),
                          child: const Text('Archive'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true || !dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  try {
                    await FirebaseService.instance.archiveRoute(route.id);
                    if (mounted) setState(() => selectedId = null);
                    _notice('Route archived.');
                  } on FirebaseException catch (error) {
                    _notice('Firebase ${error.code}: ${error.message}');
                  }
                },
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archive'),
              )
            else
              TextButton.icon(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  try {
                    await FirebaseService.instance.restoreRoute(route.id);
                    _notice('Route restored as inactive. Enable it when ready.');
                  } on FirebaseException catch (error) {
                    _notice('Firebase ${error.code}: ${error.message}');
                  }
                },
                icon: const Icon(Icons.unarchive_outlined),
                label: const Text('Restore'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: data['archived'] == true ? null : () async {
                if (name.text.trim().isEmpty) {
                  _notice('Enter a route name.');
                  return;
                }
                Navigator.pop(dialogContext);
                try {
                  await FirebaseService.instance.updateRoute(
                    route.id,
                    name: name.text,
                    radius: radius,
                    location: point,
                  );
                  _notice('Route updated.');
                } on FirebaseException catch (error) {
                  _notice('Firebase ${error.code}: ${error.message}');
                }
              },
              child: const Text('Save changes'),
            ),
          ],
        ),
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

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseService.instance.watch('routes'),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Text(
            'Could not load routes from Firebase.\n${snapshot.error}',
          ),
        );
      }
      final routes = [...?snapshot.data?.docs]
          .where((route) => (route.data()['archived'] == true) == showArchived)
          .toList();
      routes.sort((a, b) {
        final aOrder = (a.data()['order'] as num?)?.toInt();
        final bOrder = (b.data()['order'] as num?)?.toInt();
        if (aOrder != null || bOrder != null) {
          return (aOrder ?? 999999).compareTo(bOrder ?? 999999);
        }
        final aCreated = a.data()['createdAt'] as Timestamp?;
        final bCreated = b.data()['createdAt'] as Timestamp?;
        return (aCreated?.millisecondsSinceEpoch ?? 0).compareTo(
          bCreated?.millisecondsSinceEpoch ?? 0,
        );
      });
      if (!routes.any((route) => route.id == selectedId)) {
        selectedId = routes.firstOrNull?.id;
      }
      final selected = routes
          .where((route) => route.id == selectedId)
          .firstOrNull;
      final selectedData = selected?.data();
      final geoPoint = selectedData?['location'] is GeoPoint
          ? selectedData!['location'] as GeoPoint
          : null;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            PageIntro(
              title: 'Routes',
              subtitle: 'Route points and geofences.',
              action: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: selected == null
                        ? null
                        : () => _editRoute(selected),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit route'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _addRoute,
                    icon: const Icon(Icons.add_location_alt),
                    label: const Text('Add route'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 500,
              child: Row(
                children: [
                  SizedBox(
                    width: 350,
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
                                    'Route points',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: showArchived ? 'Show active routes' : 'Show archived routes',
                                  onPressed: () => setState(() {
                                    showArchived = !showArchived;
                                    selectedId = null;
                                  }),
                                  icon: Icon(showArchived ? Icons.route_outlined : Icons.archive_outlined),
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
                              child: routes.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No routes saved.',
                                        style: TextStyle(color: Colors.black45),
                                      ),
                                    )
                                  : ReorderableListView.builder(
                                      buildDefaultDragHandles: false,
                                      itemCount: routes.length,
                                      onReorderItem: (oldIndex, newIndex) async {
                                        final ids = routes
                                            .map((route) => route.id)
                                            .toList();
                                        final moved = ids.removeAt(oldIndex);
                                        ids.insert(newIndex, moved);
                                        try {
                                          await FirebaseService.instance
                                              .reorderRoutes(ids);
                                          _notice('Route order updated.');
                                        } on FirebaseException catch (error) {
                                          _notice(
                                            'Firebase ${error.code}: ${error.message}',
                                          );
                                        }
                                      },
                                      itemBuilder: (_, index) {
                                        final route = routes[index],
                                            data = route.data();
                                        return ListTile(
                                          key: ValueKey(route.id),
                                          selected: route.id == selectedId,
                                          selectedTileColor: const Color(
                                            0xFFE5F4EA,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          leading: CircleAvatar(
                                            child: Text(
                                              '${index + 1}',
                                            ),
                                          ),
                                          title: Text(
                                            '${data['name'] ?? 'Unnamed route'}',
                                          ),
                                          subtitle: Text(
                                            '${data['proximityRadius'] ?? 0} m radius • ${data['active'] == false ? 'Inactive' : 'Active'}',
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (!showArchived) Switch(
                                                value: data['active'] != false,
                                                onChanged: (active) async {
                                                  try {
                                                    await FirebaseService
                                                        .instance
                                                        .setRouteActive(
                                                          route.id,
                                                          active,
                                                        );
                                                  } on FirebaseException catch (
                                                    error
                                                  ) {
                                                    _notice(
                                                      'Firebase ${error.code}: ${error.message}',
                                                    );
                                                  }
                                                },
                                              ),
                                              ReorderableDragStartListener(
                                                index: index,
                                                child: const Padding(
                                                  padding: EdgeInsets.all(8),
                                                  child: Icon(
                                                    Icons.drag_indicator,
                                                    color: Colors.black45,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          onTap: () => setState(
                                            () => selectedId = route.id,
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
                            ? const Center(
                                child: Text(
                                  'Select a route to view its location.',
                                ),
                              )
                            : RealMap(
                                key: ValueKey(selected.id),
                                latitude: geoPoint?.latitude,
                                longitude: geoPoint?.longitude,
                                radiusMeters:
                                    (selectedData?['proximityRadius'] as num?)
                                        ?.toDouble(),
                                label: '${selectedData?['name'] ?? 'Route'}',
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
           
          ],
        ),
      );
    },
  );
}

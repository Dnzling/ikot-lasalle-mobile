import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/firebase_service.dart';
import '../widgets/common.dart';
import '../widgets/real_map.dart';
import 'audit_logs_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _seconds = TextEditingController();
  final _registrationCredits = TextEditingController();
  final _minimumTopUp = TextEditingController();
  bool _creditSettingsLoaded = false;
  bool _savingCredits = false;
  bool _savingTiming = false;
  bool _timingLoaded = false;
  bool _savingFuel = false;

  @override
  void dispose() {
    _seconds.dispose();
    _registrationCredits.dispose();
    _minimumTopUp.dispose();
    super.dispose();
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _saveTiming() async {
    final seconds = int.tryParse(_seconds.text.trim());
    if (seconds == null || seconds < 10 || seconds > 3600) {
      _message('Enter a timeout between 10 and 3600 seconds.');
      return;
    }
    setState(() => _savingTiming = true);
    try {
      await FirebaseService.instance.updateVehicleStatusTimeout(seconds);
      _message('Vehicle status timing saved.');
    } on FirebaseException catch (error) {
      _message('Could not save setting: ${error.message ?? error.code}');
    } finally {
      if (mounted) setState(() => _savingTiming = false);
    }
  }

  Future<void> _saveCredits() async {
    final registration = double.tryParse(_registrationCredits.text.trim());
    final minimum = double.tryParse(_minimumTopUp.text.trim());
    if (registration == null || minimum == null ||
        registration < 0 || registration > 10000 ||
        minimum < 0.01 || minimum > 10000 ||
        (registration * 100 - (registration * 100).round()).abs() > 0.000001 ||
        (minimum * 100 - (minimum * 100).round()).abs() > 0.000001) {
      _message('Enter valid amounts up to 10,000 with at most two decimals. Minimum top-up must be at least 0.01.');
      return;
    }
    setState(() => _savingCredits = true);
    try {
      await FirebaseService.instance.updateCreditSettings(
        registration: registration, minimumTopUp: minimum);
      _message('Credit settings saved.');
    } catch (error) {
      _message('Could not save credit settings: $error');
    } finally {
      if (mounted) setState(() => _savingCredits = false);
    }
  }

  Future<void> _editFuelLocations(Map<String, dynamic>? data) async {
    final defaultEntry = const GeoPoint(14.322621555762716, 120.96376350989355);
    final defaultExit = const GeoPoint(14.32056586315423, 120.96333703866406);
    var entry = data?['entrance'] is GeoPoint
        ? data!['entrance'] as GeoPoint
        : defaultEntry;
    var exit = data?['exit'] is GeoPoint
        ? data!['exit'] as GeoPoint
        : defaultExit;
    var entranceRadius =
        ((data?['entranceRadiusMeters'] as num?)?.toDouble() ?? 40)
            .clamp(5, 200)
            .toDouble();
    var exitRadius = ((data?['exitRadiusMeters'] as num?)?.toDouble() ?? 40)
        .clamp(5, 200)
        .toDouble();
    var editingEntrance = true;
    final latitude = TextEditingController(
      text: entry.latitude.toStringAsFixed(6),
    );
    final longitude = TextEditingController(
      text: entry.longitude.toStringAsFixed(6),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final point = editingEntrance ? entry : exit;
          return AlertDialog(
            title: const Text('Fueling entrance and exit'),
            content: SizedBox(
              width: 700,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('Entrance'),
                        icon: Icon(Icons.login),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('Exit'),
                        icon: Icon(Icons.logout),
                      ),
                    ],
                    selected: {editingEntrance},
                    onSelectionChanged: (selection) => setDialogState(() {
                      editingEntrance = selection.first;
                      final selectedPoint = editingEntrance ? entry : exit;
                      latitude.text = selectedPoint.latitude.toStringAsFixed(6);
                      longitude.text = selectedPoint.longitude.toStringAsFixed(
                        6,
                      );
                    }),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: latitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                          ),
                          onChanged: (value) {
                            final latitude = double.tryParse(value);
                            final parsedLongitude = double.tryParse(
                              longitude.text,
                            );
                            if (latitude == null ||
                                parsedLongitude == null ||
                                latitude < -90 ||
                                latitude > 90 ||
                                parsedLongitude < -180 ||
                                parsedLongitude > 180)
                              return;
                            setDialogState(() {
                              if (editingEntrance) {
                                entry = GeoPoint(latitude, parsedLongitude);
                              } else {
                                exit = GeoPoint(latitude, parsedLongitude);
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: longitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                          ),
                          onChanged: (value) {
                            final parsedLatitude = double.tryParse(
                              latitude.text,
                            );
                            final parsedLongitude = double.tryParse(value);
                            if (parsedLatitude == null ||
                                parsedLongitude == null ||
                                parsedLatitude < -90 ||
                                parsedLatitude > 90 ||
                                parsedLongitude < -180 ||
                                parsedLongitude > 180)
                              return;
                            setDialogState(() {
                              if (editingEntrance) {
                                entry = GeoPoint(
                                  parsedLatitude,
                                  parsedLongitude,
                                );
                              } else {
                                exit = GeoPoint(
                                  parsedLatitude,
                                  parsedLongitude,
                                );
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        'Proximity radius',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        '${(editingEntrance ? entranceRadius : exitRadius).round()} meters',
                        style: const TextStyle(
                          color: Color(0xFF08783E),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: editingEntrance ? entranceRadius : exitRadius,
                    min: 5,
                    max: 200,
                    divisions: 195,
                    label:
                        '${(editingEntrance ? entranceRadius : exitRadius).round()} m',
                    onChanged: (value) => setDialogState(() {
                      if (editingEntrance) {
                        entranceRadius = value;
                      } else {
                        exitRadius = value;
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Click or drag the pin to set this gate location.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 300,
                    child: RealMap(
                      latitude: point.latitude,
                      longitude: point.longitude,
                      interactivePin: true,
                      radiusMeters: editingEntrance
                          ? entranceRadius
                          : exitRadius,
                      label: editingEntrance
                          ? 'Fueling entrance'
                          : 'Fueling exit',
                      onLocationChanged: (location) => setDialogState(() {
                        final moved = GeoPoint(
                          location.latitude,
                          location.longitude,
                        );
                        if (editingEntrance) {
                          entry = moved;
                        } else {
                          exit = moved;
                        }
                        latitude.text = location.latitude.toStringAsFixed(6);
                        longitude.text = location.longitude.toStringAsFixed(6);
                      }),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final lat = double.tryParse(latitude.text);
                  final lon = double.tryParse(longitude.text);
                  if (lat == null ||
                      lon == null ||
                      lat < -90 ||
                      lat > 90 ||
                      lon < -180 ||
                      lon > 180) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Enter valid latitude and longitude coordinates.',
                        ),
                      ),
                    );
                    return;
                  }
                  if (editingEntrance) {
                    entry = GeoPoint(lat, lon);
                  } else {
                    exit = GeoPoint(lat, lon);
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Save locations'),
              ),
            ],
          );
        },
      ),
    );
    latitude.dispose();
    longitude.dispose();
    if (saved != true || !mounted) return;
    final centerLatitude = (entry.latitude + exit.latitude) / 2;
    final centerLongitude = (entry.longitude + exit.longitude) / 2;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (confirmationContext) => AlertDialog(
        title: const Text('Confirm fueling gate locations'),
        content: SizedBox(
          width: 700,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Entrance: ${entry.latitude.toStringAsFixed(6)}, ${entry.longitude.toStringAsFixed(6)} | ${entranceRadius.round()} m radius',
              ),
              const SizedBox(height: 4),
              Text(
                'Exit: ${exit.latitude.toStringAsFixed(6)}, ${exit.longitude.toStringAsFixed(6)} | ${exitRadius.round()} m radius',
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: RealMap(
                  latitude: centerLatitude,
                  longitude: centerLongitude,
                  showMarker: false,
                  additionalPins: [
                    (
                      latitude: entry.latitude,
                      longitude: entry.longitude,
                      label: 'Entrance',
                    ),
                    (
                      latitude: exit.latitude,
                      longitude: exit.longitude,
                      label: 'Exit',
                    ),
                  ],
                  additionalRadii: [
                    (
                      latitude: entry.latitude,
                      longitude: entry.longitude,
                      radiusMeters: entranceRadius,
                    ),
                    (
                      latitude: exit.latitude,
                      longitude: exit.longitude,
                      radiusMeters: exitRadius,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Check that both pins are on the correct school gates before confirming.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmationContext, false),
            child: const Text('Review locations'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(confirmationContext, true),
            child: const Text('Confirm and save'),
          ),
        ],
      ),
    );
    if (confirmed == false && mounted) {
      await _editFuelLocations({
        'entrance': entry,
        'exit': exit,
        'entranceRadiusMeters': entranceRadius,
        'exitRadiusMeters': exitRadius,
      });
      return;
    }
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _savingFuel = true);
    try {
      await FirebaseService.instance.updateFuelingLocations(
        entrance: entry,
        exit: exit,
        entranceRadiusMeters: entranceRadius,
        exitRadiusMeters: exitRadius,
      );
      _message('Fueling gate locations saved.');
    } on FirebaseException catch (error) {
      _message('Could not save locations: ${error.message ?? error.code}');
    } finally {
      if (mounted) setState(() => _savingFuel = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageIntro(
          title: 'Settings',
          subtitle:
              'Manage credits, vehicle status timing, fueling gates, and admin activity.',
        ),
        const SizedBox(height: 20),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseService.instance.watchDocument('settings', 'credits'),
          builder: (context, snapshot) {
            final registration =
                (snapshot.data?.data()?['registrationCredits'] as num?)?.toDouble() ?? 100;
            final minimum =
                (snapshot.data?.data()?['minimumTopUpCredits'] as num?)?.toDouble() ?? 1;
            if (!_creditSettingsLoaded && snapshot.hasData) {
              _registrationCredits.text = registration.toStringAsFixed(2);
              _minimumTopUp.text = minimum.toStringAsFixed(2);
              _creditSettingsLoaded = true;
            }
            return SizedBox(
              width: 700,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Credit settings', style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      const Text('Registration credits are given to new accounts created by an admin. The minimum applies to GCash and manual top-ups.'),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(child: TextField(
                          controller: _registrationCredits,
                          enabled: !_savingCredits && _creditSettingsLoaded,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          decoration: const InputDecoration(labelText: 'Registration credits',
                              border: OutlineInputBorder()),
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: TextField(
                          controller: _minimumTopUp,
                          enabled: !_savingCredits && _creditSettingsLoaded,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          decoration: const InputDecoration(labelText: 'Minimum top-up credits',
                              border: OutlineInputBorder()),
                        )),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _savingCredits || !_creditSettingsLoaded ? null : _saveCredits,
                          icon: const Icon(Icons.save_outlined), label: const Text('Save'),
                        ),
                      ]),
                      if (snapshot.hasError) Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('Could not load credit settings: ${snapshot.error}'),
                      ) else Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('Saved: ${registration.toStringAsFixed(2)} registration credits · ${minimum.toStringAsFixed(2)} minimum top-up'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseService.instance.watchDocument(
            'settings',
            'vehicleStatus',
          ),
          builder: (context, snapshot) {
            final timeout =
                (snapshot.data?.data()?['offlineAfterSeconds'] as num?)
                    ?.toInt() ??
                120;
            if (timeout >= 10 && timeout <= 3600) {
              vehicleGpsStaleAfter = Duration(seconds: timeout);
            }
            if (!_timingLoaded && snapshot.hasData) {
              _seconds.text = '$timeout';
              _timingLoaded = true;
            }
            return SizedBox(
              width: 700,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.timer_outlined),
                          SizedBox(width: 12),
                          Text(
                            'Vehicle status timing',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Mark a vehicle offline when its last GPS update is older than this duration.',
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          SizedBox(
                            width: 180,
                            child: TextField(
                              controller: _seconds,
                              enabled: !_savingTiming,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Offline after (seconds)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          FilledButton.icon(
                            onPressed: _savingTiming ? null : _saveTiming,
                            icon: _savingTiming
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: const Text('Save'),
                          ),
                        ],
                      ),
                      if (snapshot.hasError)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Could not load saved timing: ${snapshot.error}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (!snapshot.hasError)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Current saved threshold: $timeout seconds',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseService.instance.watchDocument(
            'settings',
            'fuelingLocations',
          ),
          builder: (context, snapshot) {
            final data = snapshot.data?.data();
            final entrance = data?['entrance'];
            final exit = data?['exit'];
            final entranceRadius =
                (data?['entranceRadiusMeters'] as num?)?.toDouble() ?? 40;
            final exitRadius =
                (data?['exitRadiusMeters'] as num?)?.toDouble() ?? 40;
            return SizedBox(
              width: 700,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_gas_station_outlined),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Fueling entrance and exit',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _savingFuel
                                ? null
                                : () => _editFuelLocations(data),
                            icon: const Icon(Icons.edit_location_alt_outlined),
                            label: Text(
                              _savingFuel ? 'Saving…' : 'Edit locations',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _coordinateLabel('Entrance', entrance, entranceRadius),
                      ),
                      const SizedBox(height: 4),
                      Text(_coordinateLabel('Exit', exit, exitRadius)),
                      const SizedBox(height: 8),
                      Text(
                        'Saved in system settings for the fueling location configuration.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: 700,
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: const Text(
                'Audit logs',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Review recorded admin changes and report exports.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AuditLogsPage())),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const SizedBox(
          width: 700,
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.admin_panel_settings_outlined),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Admin accounts cannot be created in this app. The system owner must provision admin accounts in the authentication system and assign an Admin profile.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  String _coordinateLabel(String label, dynamic value, double radius) {
    if (value is! GeoPoint) return '$label: Not configured';
    return '$label: ${value.latitude.toStringAsFixed(6)}, ${value.longitude.toStringAsFixed(6)} | ${radius.round()} m radius';
  }
}

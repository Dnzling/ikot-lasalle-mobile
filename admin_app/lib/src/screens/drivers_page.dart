import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/firebase_service.dart';
import '../widgets/common.dart';

class DriversPage extends StatefulWidget {
  const DriversPage({super.key});

  @override
  State<DriversPage> createState() => _DriversPageState();
}

class _DriverDailySummary {
  _DriverDailySummary({
    required this.date,
    required this.driverName,
    required this.vehicleName,
    required this.vehicleType,
  });

  final DateTime date;
  final String driverName;
  final String vehicleName;
  final String vehicleType;
  int passengers = 0;
  double fare = 0;
}

class _DriversPageState extends State<DriversPage> {
  static final _namePattern = RegExp(r'^[A-Za-z]+(?: [A-Za-z]+)*$');
  static final _moneyPattern = RegExp(r'^\d+(?:\.\d{1,2})?$');
  static final _nameFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z ]')),
  ];
  static final _phoneFormatters = [FilteringTextInputFormatter.digitsOnly];
  static final _moneyFormatters = [
    TextInputFormatter.withFunction(
      (oldValue, newValue) =>
          RegExp(r'^\d*(?:\.\d{0,2})?$').hasMatch(newValue.text)
          ? newValue
          : oldValue,
    ),
  ];

  String? _driverInputError(
    TextEditingController first,
    TextEditingController last,
    TextEditingController contact,
    TextEditingController salary,
    TextEditingController quota,
  ) {
    if (!_namePattern.hasMatch(first.text.trim()) ||
        !_namePattern.hasMatch(last.text.trim())) {
      return 'First and last name must contain letters only.';
    }
    if (!RegExp(r'^\d{11}$').hasMatch(contact.text.trim())) {
      return 'Contact number must be exactly 11 digits.';
    }
    if (!_moneyPattern.hasMatch(salary.text.trim()) ||
        !_moneyPattern.hasMatch(quota.text.trim())) {
      return 'Daily salary and daily quota must be non-negative numbers.';
    }
    return null;
  }

  final selectedDriverIds = <String>{};
  late final Stream<QuerySnapshot<Map<String, dynamic>>> tripStream =
      FirebaseService.instance.watch('trips').asBroadcastStream();
  int recentPage = 0;
  static const recentPageSize = 8;
  final dailySearchController = TextEditingController();
  String dailySearch = '';
  DateTime? dailyDate;
  String dailyVehicleType = 'All types';
  bool bulkSaving = false;

  @override
  void dispose() {
    dailySearchController.dispose();
    super.dispose();
  }

  Future<void> _bulkInactivateDrivers(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> drivers,
  ) async {
    final selected = drivers
        .where(
          (doc) =>
              selectedDriverIds.contains(doc.id) &&
              doc.data()['active'] != false,
        )
        .toList();
    if (selected.isEmpty) return;
    var reason = 'Resigned';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: const Text('Inactivate selected drivers?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${selected.length} driver(s) will be marked inactive. Their history will remain.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: reason,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: const [
                  DropdownMenuItem(value: 'Resigned', child: Text('Resigned')),
                  DropdownMenuItem(
                    value: 'Terminated',
                    child: Text('Terminated'),
                  ),
                ],
                onChanged: (value) => refresh(() => reason = value ?? reason),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Inactivate'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => bulkSaving = true);
    try {
      final count = await FirebaseService.instance.bulkInactivate(
        collection: 'drivers',
        ids: selected.map((doc) => doc.id).toList(),
        reason: reason,
      );
      if (mounted) {
        setState(selectedDriverIds.clear);
        _notice(context, '$count driver(s) marked $reason.');
      }
    } catch (error) {
      if (mounted) _notice(context, 'Could not inactivate drivers: $error');
    } finally {
      if (mounted) setState(() => bulkSaving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    FirebaseService.instance.migrateDriverCompensationFromVehicles().catchError(
      (Object error) {
        if (mounted)
          _notice(context, 'Could not migrate older salary/quota data: $error');
      },
    );
  }

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
    final salary = TextEditingController(text: '${data['dailySalary'] ?? 0}');
    final quota = TextEditingController(text: '${data['targetMoney'] ?? 0}');
    var vehicleId = data['vehicleId'] as String?;
    var active = data['active'] != false;
    var saving = false;
    var photoChanged = false;
    DriverPhoto? selectedPhoto;
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
                  _DriverPhotoPicker(
                    initialUrl: _driverPhotoSource(data),
                    initialBytes: _driverPhotoBytes(data),
                    onChanged: (photo) {
                      photoChanged = true;
                      selectedPhoto = photo;
                    },
                  ),
                  const SizedBox(height: 12),
                  FormFieldBox(
                    'First name',
                    controller: first,
                    inputFormatters: _nameFormatters,
                  ),
                  const SizedBox(height: 12),
                  FormFieldBox(
                    'Last name',
                    controller: last,
                    inputFormatters: _nameFormatters,
                  ),
                  const SizedBox(height: 12),
                  FormFieldBox(
                    'Contact number',
                    controller: contact,
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                    inputFormatters: _phoneFormatters,
                  ),
                  const SizedBox(height: 12),
                  FormFieldBox(
                    'Daily salary (PHP)',
                    controller: salary,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: _moneyFormatters,
                  ),
                  const SizedBox(height: 12),
                  FormFieldBox(
                    'Daily quota (PHP)',
                    controller: quota,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: _moneyFormatters,
                  ),
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
                      final inputError = _driverInputError(
                        first,
                        last,
                        contact,
                        salary,
                        quota,
                      );
                      if (inputError != null) {
                        _notice(context, inputError);
                        return;
                      }
                      final dailySalary = double.tryParse(salary.text.trim());
                      final targetMoney = double.tryParse(quota.text.trim());
                      if (dailySalary == null ||
                          !dailySalary.isFinite ||
                          dailySalary < 0 ||
                          targetMoney == null ||
                          !targetMoney.isFinite ||
                          targetMoney < 0) {
                        _notice(
                          context,
                          'Enter valid non-negative salary and quota.',
                        );
                        return;
                      }
                      refresh(() => saving = true);
                      try {
                        await FirebaseService.instance.updateDriver(id, {
                          'firstName': first.text.trim(),
                          'lastName': last.text.trim(),
                          'contactNumber': contact.text.trim(),
                          'dailySalary': dailySalary,
                          'targetMoney': targetMoney,
                          'vehicleId': vehicleId,
                          'active': active,
                        });
                        if (photoChanged) {
                          await FirebaseService.instance.updateDriverPhoto(
                            driverId: id,
                            photoBytes: selectedPhoto?.bytes,
                            photoContentType:
                                selectedPhoto?.contentType ?? 'image/jpeg',
                          );
                        }
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
    salary.dispose();
    quota.dispose();
  }

  void _register(BuildContext context) {
    final first = TextEditingController(),
        last = TextEditingController(),
        contact = TextEditingController(),
        salary = TextEditingController(text: '0'),
        quota = TextEditingController(text: '0');
    final vehicle = ValueNotifier<String?>('Unassigned');
    DriverPhoto? selectedPhoto;
    showFormDialog(
      context,
      title: 'Register driver',
      action: 'Register driver',
      fields: [
        _DriverPhotoPicker(onChanged: (photo) => selectedPhoto = photo),
        Row(
          children: [
            Expanded(
              child: FormFieldBox(
                'First name',
                controller: first,
                inputFormatters: _nameFormatters,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FormFieldBox(
                'Last name',
                controller: last,
                inputFormatters: _nameFormatters,
              ),
            ),
          ],
        ),
        FormFieldBox(
          'Contact number',
          controller: contact,
          keyboardType: TextInputType.phone,
          maxLength: 11,
          inputFormatters: _phoneFormatters,
        ),
        FormFieldBox(
          'Daily salary (PHP)',
          controller: salary,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _moneyFormatters,
        ),
        FormFieldBox(
          'Daily quota (PHP)',
          controller: quota,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _moneyFormatters,
        ),
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
        final inputError = _driverInputError(
          first,
          last,
          contact,
          salary,
          quota,
        );
        if (inputError != null) {
          _notice(context, inputError);
          return;
        }
        final dailySalary = double.tryParse(salary.text.trim());
        final targetMoney = double.tryParse(quota.text.trim());
        if (dailySalary == null ||
            !dailySalary.isFinite ||
            dailySalary < 0 ||
            targetMoney == null ||
            !targetMoney.isFinite ||
            targetMoney < 0) {
          _notice(context, 'Enter valid non-negative salary and quota.');
          return;
        }
        try {
          await FirebaseService.instance.addDriver(
            {
              'firstName': first.text.trim(),
              'lastName': last.text.trim(),
              'contactNumber': contact.text.trim(),
              'vehicleId': vehicle.value == 'Unassigned' ? null : vehicle.value,
              'dailySalary': dailySalary,
              'targetMoney': targetMoney,
              'trips': 0,
            },
            photoBytes: selectedPhoto?.bytes,
            photoContentType: selectedPhoto?.contentType ?? 'image/jpeg',
          );
          if (context.mounted) {
            _notice(context, 'Driver registered.');
          }
        } catch (error) {
          if (context.mounted) {
            _notice(context, '$error');
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
            'Could not load drivers from the server.\n${driverSnapshot.error}',
          ),
        );
      }
      final allDrivers = driverSnapshot.data?.docs ?? [];
      final drivers = allDrivers
          .where((doc) => doc.data()['archived'] != true)
          .toList();
      selectedDriverIds.removeWhere(
        (id) => !drivers.any(
          (doc) => doc.id == id && doc.data()['active'] != false,
        ),
      );
      final totalSalary = drivers.fold<double>(
        0,
        (total, doc) =>
            total + ((doc.data()['dailySalary'] as num?)?.toDouble() ?? 0),
      );
      final totalQuota = drivers.fold<double>(
        0,
        (total, doc) =>
            total + ((doc.data()['targetMoney'] as num?)?.toDouble() ?? 0),
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            PageIntro(
              title: 'Drivers',
              subtitle: 'Driver records and performance from the server.',
              action: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: bulkSaving || selectedDriverIds.isEmpty
                        ? null
                        : () => _bulkInactivateDrivers(drivers),
                    icon: const Icon(Icons.person_off_outlined),
                    label: Text(
                      'Inactivate selected (${selectedDriverIds.length})',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _register(context),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Register driver'),
                  ),
                ],
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
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: tripStream,
                    builder: (context, snapshot) {
                      final ids = drivers.map((driver) => driver.id).toSet();
                      final count = (snapshot.data?.docs ?? [])
                          .where(
                            (trip) =>
                                ids.contains(trip.data()['driverId']) &&
                                trip.data()['boardedAt'] is Timestamp,
                          )
                          .length;
                      return _Metric(
                        'TOTAL FARES',
                        '$count',
                        Icons.route_outlined,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _Metric(
                    'DAILY SALARIES',
                    'PHP ${totalSalary.toStringAsFixed(2)}',
                    Icons.payments_outlined,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _Metric(
                    'DAILY QUOTAS',
                    'PHP ${totalQuota.toStringAsFixed(2)}',
                    Icons.flag_outlined,
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
                          driverId: driver.id,
                          tripStream: tripStream,
                          data: driver.data(),
                          selected: selectedDriverIds.contains(driver.id),
                          onSelected:
                              driver.data()['active'] != false && !bulkSaving
                              ? (value) => setState(() {
                                  if (value == true) {
                                    selectedDriverIds.add(driver.id);
                                  } else {
                                    selectedDriverIds.remove(driver.id);
                                  }
                                })
                              : null,
                          onEdit: () =>
                              _edit(context, driver.id, driver.data()),
                          onCompute: () => showDialog<void>(
                            context: context,
                            builder: (_) => _DriverSalaryReceiptDialog(
                              driverId: driver.id,
                              driver: driver.data(),
                            ),
                          ),
                          onArchive: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Archive driver?'),
                                content: Text(
                                  'Archive ${driver.data()['firstName']} ${driver.data()['lastName']}?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, true),
                                    child: const Text('Archive'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            try {
                              await FirebaseService.instance.archiveDriver(
                                driver.id,
                              );
                              if (context.mounted)
                                _notice(context, 'Driver archived.');
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
              stream: tripStream,
              builder: (context, tripSnapshot) {
                final summaries = <String, _DriverDailySummary>{};
                for (final trip
                    in tripSnapshot.data?.docs ??
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
                  final data = trip.data();
                  final boardedAt = data['boardedAt'];
                  final driverId = '${data['driverId'] ?? ''}'.trim();
                  if (boardedAt is! Timestamp || driverId.isEmpty) continue;
                  final boarded = boardedAt.toDate().toLocal();
                  final date = DateTime(
                    boarded.year,
                    boarded.month,
                    boarded.day,
                  );
                  final vehicleId = '${data['vehicleId'] ?? ''}'.trim();
                  final key =
                      '${date.year}-${date.month}-${date.day}|$driverId|$vehicleId';
                  final summary = summaries.putIfAbsent(
                    key,
                    () => _DriverDailySummary(
                      date: date,
                      driverName: '${data['driverName'] ?? 'Unknown driver'}',
                      vehicleName:
                          '${data['vehicleName'] ?? 'Unknown vehicle'}',
                      vehicleType: '${data['vehicleType'] ?? 'Unknown'}',
                    ),
                  );
                  summary.passengers +=
                      (data['passengerCount'] as num?)?.toInt() ?? 1;
                  summary.fare += (data['fare'] as num?)?.toDouble() ?? 0;
                }
                final types =
                    summaries.values
                        .map((row) => row.vehicleType)
                        .toSet()
                        .toList()
                      ..sort();
                final selectedType = types.contains(dailyVehicleType)
                    ? dailyVehicleType
                    : 'All types';
                final query = dailySearch.trim().toLowerCase();
                final rows =
                    summaries.values.where((row) {
                      if (dailyDate != null &&
                          (row.date.year != dailyDate!.year ||
                              row.date.month != dailyDate!.month ||
                              row.date.day != dailyDate!.day))
                        return false;
                      if (selectedType != 'All types' &&
                          row.vehicleType != selectedType)
                        return false;
                      if (query.isNotEmpty &&
                          !row.driverName.toLowerCase().contains(query) &&
                          !row.vehicleName.toLowerCase().contains(query))
                        return false;
                      return true;
                    }).toList()..sort((a, b) {
                      final byDate = b.date.compareTo(a.date);
                      return byDate != 0
                          ? byDate
                          : a.driverName.compareTo(b.driverName);
                    });
                final pageCount =
                    (rows.length + recentPageSize - 1) ~/ recentPageSize;
                final page = pageCount == 0
                    ? 0
                    : recentPage.clamp(0, pageCount - 1);
                final pageRows = rows
                    .skip(page * recentPageSize)
                    .take(recentPageSize);
                String dateLabel(DateTime date) =>
                    '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Daily driver summary',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 250,
                              child: TextField(
                                controller: dailySearchController,
                                decoration: const InputDecoration(
                                  labelText: 'Search',
                                  hintText: 'Driver or vehicle',
                                  prefixIcon: Icon(Icons.search),
                                ),
                                onChanged: (value) => setState(() {
                                  dailySearch = value;
                                  recentPage = 0;
                                }),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: dailyDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null && mounted) {
                                  setState(() {
                                    dailyDate = picked;
                                    recentPage = 0;
                                  });
                                }
                              },
                              icon: const Icon(Icons.calendar_today_outlined),
                              label: Text(
                                dailyDate == null
                                    ? 'All dates'
                                    : dateLabel(dailyDate!),
                              ),
                            ),
                            if (dailyDate != null)
                              IconButton(
                                tooltip: 'Clear date filter',
                                onPressed: () => setState(() {
                                  dailyDate = null;
                                  recentPage = 0;
                                }),
                                icon: const Icon(Icons.close),
                              ),
                            SizedBox(
                              width: 170,
                              child: DropdownButtonFormField<String>(
                                key: ValueKey(dailyVehicleType),
                                initialValue: selectedType,
                                decoration: const InputDecoration(
                                  labelText: 'Vehicle type',
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: 'All types',
                                    child: Text('All types'),
                                  ),
                                  for (final type in types)
                                    DropdownMenuItem(
                                      value: type,
                                      child: Text(type),
                                    ),
                                ],
                                onChanged: (value) => setState(() {
                                  dailyVehicleType = value ?? 'All types';
                                  recentPage = 0;
                                }),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (rows.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'No daily driver records match the filters.',
                            ),
                          )
                        else ...[
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('DATE')),
                                DataColumn(label: Text('VEHICLE')),
                                DataColumn(label: Text('DRIVER')),
                                DataColumn(label: Text('PASSENGERS CARRIED')),
                                DataColumn(label: Text('FARE COLLECTED')),
                              ],
                              rows: [
                                for (final row in pageRows)
                                  DataRow(
                                    cells: [
                                      DataCell(Text(dateLabel(row.date))),
                                      DataCell(Text(row.vehicleName)),
                                      DataCell(Text(row.driverName)),
                                      DataCell(Text('${row.passengers}')),
                                      DataCell(
                                        Text(
                                          'PHP ${row.fare.toStringAsFixed(2)}',
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                'Page ${page + 1} of $pageCount • ${rows.length} daily records',
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: page > 0
                                    ? () =>
                                          setState(() => recentPage = page - 1)
                                    : null,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              IconButton(
                                onPressed: page + 1 < pageCount
                                    ? () =>
                                          setState(() => recentPage = page + 1)
                                    : null,
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
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

typedef DriverPhoto = ({Uint8List bytes, String contentType});

String _driverPhotoSource(Map<String, dynamic> data) {
  final url = '${data['photoUrl'] ?? ''}'.trim();
  return url.isNotEmpty ? url : '${data['photoPath'] ?? ''}'.trim();
}

Uint8List? _driverPhotoBytes(Map<String, dynamic> data) {
  final encoded = data['photoBase64'];
  if (encoded is! String || encoded.isEmpty) return null;
  try {
    return base64Decode(encoded);
  } on FormatException {
    return null;
  }
}

Widget _driverPhotoDisplay({
  required String source,
  required Uint8List? bytes,
  required double iconSize,
}) {
  if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover);
  if (source.startsWith('http')) {
    return Image.network(
      source,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Icon(Icons.person, size: iconSize),
    );
  }
  if (source.isNotEmpty) {
    return _StoredDriverPhoto(path: source, iconSize: iconSize);
  }
  return Icon(Icons.person, size: iconSize, color: const Color(0xFF08783E));
}

class _StoredDriverPhoto extends StatelessWidget {
  const _StoredDriverPhoto({required this.path, required this.iconSize});

  final String path;
  final double iconSize;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: FirebaseStorage.instance.ref(path).getData(5 * 1024 * 1024),
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover);
      return Icon(Icons.person, size: iconSize, color: const Color(0xFF08783E));
    },
  );
}

class _DriverPhotoPicker extends StatefulWidget {
  const _DriverPhotoPicker({
    this.initialUrl = '',
    this.initialBytes,
    required this.onChanged,
  });

  final String initialUrl;
  final Uint8List? initialBytes;
  final ValueChanged<DriverPhoto?> onChanged;

  @override
  State<_DriverPhotoPicker> createState() => _DriverPhotoPickerState();
}

class _DriverPhotoPickerState extends State<_DriverPhotoPicker> {
  DriverPhoto? selected;
  bool removed = false;
  bool picking = false;
  String? error;

  Future<void> _pick() async {
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        setState(() => error = 'Choose an image smaller than 5 MB.');
        return;
      }
      final extension = file.name.toLowerCase().split('.').last;
      final contentType =
          file.mimeType ??
          switch (extension) {
            'png' => 'image/png',
            'webp' => 'image/webp',
            'gif' => 'image/gif',
            _ => 'image/jpeg',
          };
      if (!contentType.startsWith('image/')) {
        setState(() => error = 'Choose an image file.');
        return;
      }
      setState(() {
        selected = (bytes: bytes, contentType: contentType);
        removed = false;
      });
      widget.onChanged(selected);
    } catch (exception) {
      if (mounted) setState(() => error = 'Could not read image: $exception');
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  void _remove() {
    setState(() {
      selected = null;
      removed = true;
      error = null;
    });
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.initialUrl.trim();
    final hasImage =
        selected != null ||
        (!removed && (widget.initialBytes != null || imageUrl.isNotEmpty));
    return Row(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: const Color(0xFFE7F2EA),
          child: ClipOval(
            child: SizedBox.square(
              dimension: 68,
              child: selected != null
                  ? Image.memory(selected!.bytes, fit: BoxFit.cover)
                  : hasImage
                  ? _driverPhotoDisplay(
                      source: imageUrl,
                      bytes: widget.initialBytes,
                      iconSize: 36,
                    )
                  : const Icon(
                      Icons.person,
                      size: 36,
                      color: Color(0xFF08783E),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: picking ? null : _pick,
                icon: picking
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_outlined),
                label: Text(hasImage ? 'Change photo' : 'Attach photo'),
              ),
              if (hasImage)
                TextButton.icon(
                  onPressed: picking ? null : _remove,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove photo'),
                ),
              if (error != null)
                Text(
                  error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DriverHeader extends StatelessWidget {
  const _DriverHeader();
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      SizedBox(width: 48),
      Expanded(flex: 2, child: Text('DRIVER', style: _head)),
      Expanded(child: Text('STATUS', style: _head)),
      Expanded(child: Text('VEHICLE', style: _head)),
      Expanded(child: Text('REVENUE TODAY', style: _head)),
      Expanded(child: Text('DAILY SALARY', style: _head)),
      Expanded(child: Text('TARGET MONEY', style: _head)),
      SizedBox(width: 120),
    ],
  );
}

class _DriverRow extends StatelessWidget {
  const _DriverRow({
    required this.driverId,
    required this.tripStream,
    required this.data,
    required this.selected,
    required this.onSelected,
    required this.onEdit,
    required this.onCompute,
    required this.onArchive,
  });
  final Map<String, dynamic> data;
  final String driverId;
  final Stream<QuerySnapshot<Map<String, dynamic>>> tripStream;
  final bool selected;
  final ValueChanged<bool?>? onSelected;
  final VoidCallback onEdit;
  final VoidCallback onCompute;
  final VoidCallback onArchive;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Row(
      children: [
        SizedBox(
          width: 48,
          child: Checkbox(value: selected, onChanged: onSelected),
        ),
        Expanded(
          flex: 2,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFE7F2EA),
                child: ClipOval(
                  child: SizedBox.square(
                    dimension: 36,
                    child: _driverPhotoDisplay(
                      source: _driverPhotoSource(data),
                      bytes: _driverPhotoBytes(data),
                      iconSize: 21,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Text(
            data['active'] != false
                ? 'Active'
                : '${data['inactiveReason'] ?? 'Inactive'}',
          ),
        ),
        Expanded(child: Text('${data['vehicleName'] ?? 'Unassigned'}')),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: tripStream,
            builder: (context, snapshot) {
              final total = (snapshot.data?.docs ?? []).fold<double>(0, (
                sum,
                trip,
              ) {
                final row = trip.data();
                final boarded = row['boardedAt'];
                final date = boarded is Timestamp
                    ? boarded.toDate().toLocal()
                    : null;
                final now = DateTime.now();
                return row['driverId'] == driverId &&
                        date != null &&
                        date.year == now.year &&
                        date.month == now.month &&
                        date.day == now.day
                    ? sum + ((row['fare'] as num?)?.toDouble() ?? 0)
                    : sum;
              });
              return Text(
                'PHP ${total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              );
            },
          ),
        ),
        Expanded(child: Text('PHP ${data['dailySalary'] ?? 0}')),
        Expanded(child: Text('PHP ${data['dailyQuota'] ?? 0}')),
        SizedBox(
          width: 120,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Edit driver',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Compute salary',
                onPressed: onCompute,
                icon: const Icon(Icons.calculate_outlined),
              ),
              IconButton(
                tooltip: 'Archive driver',
                onPressed: onArchive,
                icon: const Icon(Icons.archive_outlined),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DriverSalaryDialog extends StatefulWidget {
  const _DriverSalaryDialog({required this.driverId, required this.driver});
  final String driverId;
  final Map<String, dynamic> driver;

  @override
  State<_DriverSalaryDialog> createState() => _DriverSalaryDialogState();
}

class _DriverSalaryDialogState extends State<_DriverSalaryDialog> {
  int period = 0;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> tripsStream =
      FirebaseService.instance.watch('trips');

  bool _withinPeriod(DateTime date, DateTime today) => switch (period) {
    0 =>
      date.year == today.year &&
          date.month == today.month &&
          date.day == today.day,
    1 => date.year == today.year && date.month == today.month,
    _ => date.year == today.year,
  };

  String _money(num value) => 'PHP ${value.toStringAsFixed(2)}';
  double _bonus(double earnings, double target) =>
      earnings > target ? (earnings - target) / 10 : 0;

  @override
  Widget build(BuildContext context) {
    final name =
        '${widget.driver['firstName'] ?? ''} ${widget.driver['lastName'] ?? ''}'
            .trim();
    final dailySalary = (widget.driver['dailySalary'] as num?)?.toDouble() ?? 0;
    final targetMoney = (widget.driver['targetMoney'] as num?)?.toDouble() ?? 0;
    return AlertDialog(
      title: Text('$name — salary computation'),
      content: SizedBox(
        width: 760,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Today')),
                ButtonSegment(value: 1, label: Text('This Month')),
                ButtonSegment(value: 2, label: Text('This Year')),
              ],
              selected: {period},
              onSelectionChanged: (selection) =>
                  setState(() => period = selection.first),
            ),
            const SizedBox(height: 12),
            Text(
              'Each recorded workday: salary + max(0, (earnings − target money) ÷ 10).',
            ),
            Text(
              'Daily target: ${_money(targetMoney)}  •  Daily base salary: ${_money(dailySalary)}',
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: tripsStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text('Could not load trips: ${snapshot.error}');
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final now = DateTime.now();
                  final earningsByDay = <String, double>{};
                  final ridesByDay = <String, int>{};
                  final vehicleId = '${widget.driver['vehicleId'] ?? ''}';
                  for (final tripDoc in snapshot.data!.docs) {
                    final trip = tripDoc.data();
                    final boarded = trip['boardedAt'];
                    if (boarded is! Timestamp) continue;
                    final date = boarded.toDate().toLocal();
                    if (!_withinPeriod(date, now)) continue;
                    final tripDriverId = '${trip['driverId'] ?? ''}';
                    if (tripDriverId.isNotEmpty
                        ? tripDriverId != widget.driverId
                        : vehicleId.isEmpty || trip['vehicleId'] != vehicleId) {
                      continue;
                    }
                    final key =
                        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                    earningsByDay[key] =
                        (earningsByDay[key] ?? 0) +
                        ((trip['fare'] as num?)?.toDouble() ?? 0);
                    ridesByDay[key] = (ridesByDay[key] ?? 0) + 1;
                  }
                  final days = earningsByDay.keys.toList()..sort();
                  final earnings = earningsByDay.values.fold<double>(
                    0,
                    (a, b) => a + b,
                  );
                  final basePay = dailySalary * days.length;
                  final target = targetMoney * days.length;
                  final bonus = days.fold<double>(
                    0,
                    (sum, day) =>
                        sum + _bonus(earningsByDay[day]!, targetMoney),
                  );
                  final total = basePay + bonus;
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recorded workdays: ${days.length}  •  Rides: ${ridesByDay.values.fold<int>(0, (a, b) => a + b)}',
                        ),
                        Text(
                          'Earnings: ${_money(earnings)}  •  Target: ${_money(target)}',
                        ),
                        Text(
                          'Base salary: ${_money(basePay)}  •  Bonus: ${_money(bonus)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Computed salary: ${_money(total)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (days.isEmpty)
                          const Text(
                            'No boarded trips in this period; no workday can be verified from trip records.',
                          )
                        else
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Day')),
                                DataColumn(label: Text('Rides')),
                                DataColumn(label: Text('Earnings')),
                                DataColumn(label: Text('Target')),
                                DataColumn(label: Text('Base')),
                                DataColumn(label: Text('Bonus')),
                                DataColumn(label: Text('Total pay')),
                              ],
                              rows: [
                                for (final day in days)
                                  DataRow(
                                    cells: [
                                      DataCell(Text(day)),
                                      DataCell(Text('${ridesByDay[day]}')),
                                      DataCell(
                                        Text(_money(earningsByDay[day]!)),
                                      ),
                                      DataCell(Text(_money(targetMoney))),
                                      DataCell(Text(_money(dailySalary))),
                                      DataCell(
                                        Text(
                                          _money(
                                            _bonus(
                                              earningsByDay[day]!,
                                              targetMoney,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          _money(
                                            dailySalary +
                                                _bonus(
                                                  earningsByDay[day]!,
                                                  targetMoney,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
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
    );
  }
}

class _DriverSalaryReceiptDialog extends StatefulWidget {
  const _DriverSalaryReceiptDialog({
    required this.driverId,
    required this.driver,
  });
  final String driverId;
  final Map<String, dynamic> driver;

  @override
  State<_DriverSalaryReceiptDialog> createState() =>
      _DriverSalaryReceiptDialogState();
}

class _DriverSalaryReceiptDialogState
    extends State<_DriverSalaryReceiptDialog> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> tripsStream =
      FirebaseService.instance.watch('trips');

  String _money(num value) => 'PHP ${value.toStringAsFixed(2)}';

  Future<void> _printReceipt({
    required String name,
    required String dateLabel,
    required double earning,
    required double target,
    required double basicSalary,
    required double quotaAmount,
    required double totalSalary,
    required int rides,
  }) async {
    final printedAt = DateTime.now();
    final printDate =
        '${printedAt.month.toString().padLeft(2, '0')}/${printedAt.day.toString().padLeft(2, '0')}/${printedAt.year} '
        '${(printedAt.hour % 12 == 0 ? 12 : printedAt.hour % 12).toString().padLeft(2, '0')}:${printedAt.minute.toString().padLeft(2, '0')} ${printedAt.hour < 12 ? 'AM' : 'PM'}';
    try {
      await Printing.layoutPdf(
        name: 'driver_salary_receipt_${widget.driverId}.pdf',
        onLayout: (format) async {
          final document = pw.Document();
          document.addPage(
            pw.MultiPage(
              pageFormat: format,
              margin: const pw.EdgeInsets.all(28),
              build: (_) => [
                pw.Center(
                  child: pw.Text(
                    'DRIVER SALARY RECEIPT',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Center(child: pw.Text('Printed: $printDate')),
                pw.Center(child: pw.Text('Date: $dateLabel')),
                pw.Center(child: pw.Text('Driver: $name')),
                pw.Center(child: pw.Text('Recorded rides today: $rides')),
                pw.Divider(height: 24),
                _pdfReceiptLine('Total Earning', _money(earning)),
                _pdfReceiptLine('Target Money', _money(target)),
                _pdfReceiptLine('Fare Rate', 'PHP 10.00'),
                _pdfReceiptLine('BASIC SALARY (quota)', _money(basicSalary)),
                pw.Divider(height: 24),
                pw.Text(
                  'COMPUTATION',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'QUOTA = (EARNING - TARGET MONEY) / 10 (FARE) + SALARY',
                ),
                if (earning == 0)
                  pw.Text(
                    'No earning recorded today. Total salary is set to PHP 0.00.',
                  )
                else ...[
                  pw.Text(
                    '(${_money(earning)} - ${_money(target)}) / 10 + ${_money(basicSalary)}',
                  ),
                  pw.Text(
                    '${_money(earning - target)} / 10 + ${_money(basicSalary)}',
                  ),
                  pw.Text('${_money(quotaAmount)} + ${_money(basicSalary)}'),
                ],
                pw.Divider(height: 24),
                pw.Center(
                  child: pw.Text(
                    'TOTAL SALARY: ${_money(totalSalary)}',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
          return document.save();
        },
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not print receipt: $error')),
        );
      }
    }
  }

  pw.Widget _pdfReceiptLine(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Row(
      children: [
        pw.Expanded(child: pw.Text(label)),
        pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final name =
        '${widget.driver['firstName'] ?? ''} ${widget.driver['lastName'] ?? ''}'
            .trim();
    final target = (widget.driver['dailyQuota'] as num?)?.toDouble() ?? 0;
    final basicSalary = (widget.driver['dailySalary'] as num?)?.toDouble() ?? 0;
    final now = DateTime.now();
    return AlertDialog(
      title: Text('$name — today\'s salary receipt'),
      content: SizedBox(
        width: 440,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: tripsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Could not load today\'s trips: ${snapshot.error}');
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final vehicleId = '${widget.driver['vehicleId'] ?? ''}';
            var earning = 0.0;
            var rides = 0;
            for (final doc in snapshot.data!.docs) {
              final trip = doc.data();
              final boarded = trip['boardedAt'];
              if (boarded is! Timestamp) continue;
              final date = boarded.toDate().toLocal();
              if (date.year != now.year ||
                  date.month != now.month ||
                  date.day != now.day) {
                continue;
              }
              final tripDriverId = '${trip['driverId'] ?? ''}';
              if (tripDriverId.isNotEmpty
                  ? tripDriverId != widget.driverId
                  : vehicleId.isEmpty || trip['vehicleId'] != vehicleId) {
                continue;
              }
              earning += (trip['fare'] as num?)?.toDouble() ?? 0;
              rides++;
            }
            final quotaAmount = (earning - target) / 10;
            final totalSalary = earning == 0 ? 0.0 : quotaAmount + basicSalary;
            final dateLabel =
                '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}/${now.year}';
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAF7),
                border: Border.all(color: const Color(0xFFD9D9D0)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'DRIVER SALARY RECEIPT',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Date: $dateLabel', textAlign: TextAlign.center),
                    Text('Driver: $name', textAlign: TextAlign.center),
                    Text(
                      'Recorded rides today: $rides',
                      textAlign: TextAlign.center,
                    ),
                    const Divider(height: 26),
                    _ReceiptLine(
                      label: 'Total Earning',
                      value: _money(earning),
                    ),
                    _ReceiptLine(label: 'Target Money', value: _money(target)),
                    const _ReceiptLine(label: 'Fare Rate', value: 'PHP 10.00'),
                    _ReceiptLine(
                      label: 'BASIC SALARY (quota)',
                      value: _money(basicSalary),
                    ),
                    const Divider(height: 26),
                    const Text(
                      'COMPUTATION',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'QUOTA = (EARNING − TARGET MONEY) ÷ 10 (FARE) + SALARY',
                    ),
                    const SizedBox(height: 8),
                    if (earning == 0)
                      const Text(
                        'No earning recorded today. Total salary is set to PHP 0.00.',
                      )
                    else ...[
                      Text(
                        '(${_money(earning)} − ${_money(target)}) ÷ 10 + ${_money(basicSalary)}',
                      ),
                      Text(
                        '${_money(earning - target)} ÷ 10 + ${_money(basicSalary)}',
                      ),
                      Text('${_money(quotaAmount)} + ${_money(basicSalary)}'),
                    ],
                    const Divider(height: 26),
                    const Text(
                      'TOTAL SALARY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _money(totalSalary),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF146C43),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => _printReceipt(
                        name: name,
                        dateLabel: dateLabel,
                        earning: earning,
                        target: target,
                        basicSalary: basicSalary,
                        quotaAmount: quotaAmount,
                        totalSalary: totalSalary,
                        rides: rides,
                      ),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Print receipt'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  const _ReceiptLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

const _head = TextStyle(
  fontSize: 10,
  color: Colors.black45,
  fontWeight: FontWeight.w700,
);

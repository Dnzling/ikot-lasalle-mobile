import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/export_service.dart';
import '../services/firebase_service.dart';
import '../services/date_display.dart';
import '../widgets/common.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageIntro(
          title: 'Reports & exports',
          subtitle: 'Filter, review, and export live records.',
        ),
        const SizedBox(height: 22),
        _ReportSection(
          title: 'Transaction history',
          subtitle: 'Passenger credits, fares, and approved top-ups.',
          icon: Icons.receipt_long_outlined,
          collection: 'transactions',
          headers: const [
            'Date & time',
            'Transaction ID',
            'User ID',
            'Full name',
            'Type',
            'Title',
            'Amount',
            'Reference',
          ],
          row: (doc) {
            final d = doc.data();
            return [
              _transactionDate(d['createdAt']),
              doc.id,
              '${d['userId'] ?? ''}',
              '${d['passengerName'] ?? d['fullName'] ?? d['userId'] ?? ''}',
              '${d['type'] ?? ''}',
              '${d['title'] ?? d['description'] ?? ''}',
              '${d['amount'] ?? 0}',
              '${d['referenceNumber'] ?? ''}',
            ];
          },
        ),
        const SizedBox(height: 18),
        const VehicleDailyPerformance(),
        const SizedBox(height: 18),
        _ReportSection(
          title: 'Boarding history',
          subtitle: 'Passenger bookings and boarding/completion status.',
          icon: Icons.confirmation_number_outlined,
          collection: 'trips',
          headers: const [
            'Booking ID',
            'Passenger',
            'Vehicle',
            'Pickup',
            'Destination',
            'Passengers',
            'Fare',
            'Status',
            'Booked',
            'Boarded',
            'Completed',
          ],
          row: (doc) {
            final d = doc.data();
            return [
              doc.id,
              '${d['passengerName'] ?? d['userId'] ?? ''}',
              '${d['vehicleName'] ?? 'Not boarded'}',
              '${d['pickup'] ?? ''}',
              '${d['destination'] ?? ''}',
              '${d['passengerCount'] ?? 0}',
              '${d['fare'] ?? 0}',
              switch ('${d['status'] ?? ''}') {
                'boarded' => 'onboard',
                'completed' => 'arrived',
                final status => status,
              },
              _dateText(d['createdAt']),
              _dateText(d['boardedAt']),
              _dateText(d['completedAt']),
            ];
          },
        ),
      ],
    ),
  );
}

typedef ReportRow =
    List<String> Function(QueryDocumentSnapshot<Map<String, dynamic>> doc);

class VehicleDailyPerformance extends StatefulWidget {
  const VehicleDailyPerformance({super.key});
  @override
  State<VehicleDailyPerformance> createState() =>
      _VehicleDailyPerformanceState();
}

class _VehicleDailyPerformanceState extends State<VehicleDailyPerformance> {
  DateTimeRange? range;

  Future<void> _chooseDates() async {
    final result = await _showReportDateFilter(context, range);
    if (result != null && mounted) setState(() => range = result.range);
  }
  static const headers = [
    'Date',
    'Vehicle',
    'Recorded rides',
    'Passengers',
    'Fare revenue',
    'Driver salary',
    'Net after salary',
  ];

  Future<void> export(List<List<String>> rows) async {
    try {
      await ExportService.pdf(
        fileName: 'vehicle_daily_performance.pdf',
        title: 'Vehicle daily performance',
        headers: headers,
        rows: rows,
      );
      await FirebaseService.instance.logExportActivity(
        report: 'Vehicle daily performance',
        format: 'PDF',
        rowCount: rows.length,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseService.instance.watch('trips'),
    builder: (context, tripsSnapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseService.instance.watch('vehicles'),
      builder: (context, vehiclesSnapshot) =>
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseService.instance.watch('drivers'),
            builder: (context, driversSnapshot) {
              final vehicles = {
                for (final doc
                    in vehiclesSnapshot.data?.docs ??
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  doc.id: doc.data(),
              };
              final drivers = {
                for (final doc
                    in driversSnapshot.data?.docs ??
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  doc.id: doc.data(),
              };
              final totals =
                  <
                    String,
                    ({
                      String date,
                      String vehicle,
                      int rides,
                      int passengers,
                      double revenue,
                      double salary,
                    })
                  >{};
              for (final doc
                  in tripsSnapshot.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
                final trip = doc.data();
                final vehicleId = '${trip['vehicleId'] ?? ''}';
                if (vehicleId.isEmpty) continue;
                final time = trip['boardedAt'];
                if (time is! Timestamp) continue;
                final date = time.toDate().toLocal();
                if (range != null &&
                    (date.isBefore(
                          DateTime(
                            range!.start.year,
                            range!.start.month,
                            range!.start.day,
                          ),
                        ) ||
                        date.isAfter(
                          DateTime(
                            range!.end.year,
                            range!.end.month,
                            range!.end.day,
                            23,
                            59,
                            59,
                            999,
                          ),
                        ))) {
                  continue;
                }
                final day =
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                final key = '$day|$vehicleId';
                final previous = totals[key];
                final vehicle = vehicles[vehicleId];
                totals[key] = (
                  date: day,
                  vehicle:
                      '${trip['vehicleName'] ?? vehicle?['name'] ?? vehicleId}',
                  rides: (previous?.rides ?? 0) + 1,
                  passengers:
                      (previous?.passengers ?? 0) +
                      ((trip['passengerCount'] as num?)?.toInt() ?? 1),
                  revenue:
                      (previous?.revenue ?? 0) +
                      ((trip['fare'] as num?)?.toDouble() ?? 0),
                  salary:
                      (drivers['${vehicle?['driverId'] ?? ''}']?['dailySalary']
                              as num?)
                          ?.toDouble() ??
                      0,
                );
              }
              final rows =
                  totals.values
                      .map(
                        (v) => [
                          v.date,
                          v.vehicle,
                          '${v.rides}',
                          '${v.passengers}',
                          v.revenue.toStringAsFixed(2),
                          v.salary.toStringAsFixed(2),
                          (v.revenue - v.salary).toStringAsFixed(2),
                        ],
                      )
                      .toList()
                    ..sort((a, b) => b[0].compareTo(a[0]));
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Vehicle daily performance',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'Recorded passenger rides and fare revenue per vehicle/day. Full vehicle loops are not tracked yet.',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _chooseDates,
                            icon: const Icon(Icons.date_range_outlined),
                            label: Text(_dateFilterLabel(range)),
                          ),
                          FilledButton(
                            onPressed: rows.isEmpty ? null : () => export(rows),
                            child: const Text('PDF'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (tripsSnapshot.hasError ||
                          vehiclesSnapshot.hasError ||
                          driversSnapshot.hasError)
                        Text(
                          'Could not load performance: ${tripsSnapshot.error ?? vehiclesSnapshot.error ?? driversSnapshot.error}',
                        )
                      else if (rows.isEmpty)
                        const Text('No boarded rides for the selected dates.')
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: headers
                                .map((h) => DataColumn(label: Text(h)))
                                .toList(),
                            rows: rows
                                .map(
                                  (r) => DataRow(
                                    cells: r
                                        .map((v) => DataCell(Text(v)))
                                        .toList(),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
    ),
  );
}

class _ReportSection extends StatefulWidget {
  const _ReportSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.collection,
    required this.headers,
    required this.row,
  });
  final String title, subtitle, collection;
  final IconData icon;
  final List<String> headers;
  final ReportRow row;
  @override
  State<_ReportSection> createState() => _ReportSectionState();
}

class _ReportSectionState extends State<_ReportSection> {
  DateTimeRange? range;

  DateTime? _dateOf(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final value = doc.data()['createdAt'] ?? doc.data()['submittedAt'];
    if (value is Timestamp) return value.toDate().toLocal();
    return value is DateTime ? value.toLocal() : null;
  }

  Future<void> _chooseDates() async {
    final result = await _showReportDateFilter(context, range);
    if (result != null && mounted) setState(() => range = result.range);
  }

  Future<void> _export(List<List<String>> rows) async {
    try {
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      await ExportService.pdf(
        fileName: '${widget.collection}_history_$stamp.pdf',
        title: widget.title,
        headers: widget.headers,
        rows: rows,
      );
      try {
        await FirebaseService.instance.logExportActivity(
          report: widget.title,
          format: 'PDF',
          rowCount: rows.length,
        );
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.title} exported successfully.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseService.instance.watch(widget.collection),
    builder: (context, snapshot) {
      final docs =
          (snapshot.data?.docs ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              .where((doc) {
                if (range == null) return true;
                final date = _dateOf(doc);
                if (date == null) return false;
                final start = DateTime(
                  range!.start.year,
                  range!.start.month,
                  range!.start.day,
                );
                final end = DateTime(
                  range!.end.year,
                  range!.end.month,
                  range!.end.day,
                  23,
                  59,
                  59,
                  999,
                );
                return !date.isBefore(start) && !date.isAfter(end);
              })
              .toList();
      final rows = docs
          .map(widget.row)
          .map((cells) => normalizeReportCells(cells, widget.headers.length))
          .toList();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFE5F4EA),
                    child: Icon(widget.icon, color: const Color(0xFF08783E)),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 310,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.subtitle,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _chooseDates,
                    icon: const Icon(Icons.date_range_outlined),
                    label: Text(_dateFilterLabel(range)),
                  ),
                  FilledButton.icon(
                    onPressed: rows.isEmpty ? null : () => _export(rows),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (snapshot.hasError)
                Text('Could not load records: ${snapshot.error}')
              else if (snapshot.connectionState == ConnectionState.waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (rows.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No records found for the selected dates.'),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: const WidgetStatePropertyAll(
                        Color(0xFFF3F7F4),
                      ),
                      columns: widget.headers
                          .map(
                            (header) => DataColumn(
                              label: Text(
                                header,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      rows: rows
                          .map(
                            (cells) => DataRow(
                              cells: cells
                                  .map(
                                    (cell) => DataCell(
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 220,
                                        ),
                                        child: Text(
                                          cell,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                '${rows.length} record${rows.length == 1 ? '' : 's'} displayed',
                style: const TextStyle(color: Colors.black45),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _shortDate(DateTime date) => '${date.month}/${date.day}/${date.year}';

String _dateFilterLabel(DateTimeRange? range) => range == null
    ? 'Filter dates'
    : '${_shortDate(range.start)} - ${_shortDate(range.end)}';

Future<({DateTimeRange? range})?> _showReportDateFilter(
  BuildContext context,
  DateTimeRange? currentRange,
) {
  DateTimeRange? selected = currentRange;
  String preset = currentRange == null ? 'All dates' : 'Custom';
  return showDialog<({DateTimeRange? range})>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, refresh) => AlertDialog(
        title: const Text('Filter by date'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Choose which dates to show in this report.'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in const [
                    'All dates',
                    'Today',
                    'Last 7 days',
                    'Last 30 days',
                  ])
                    ChoiceChip(
                      label: Text(option),
                      selected: preset == option,
                      onSelected: (_) => refresh(() {
                        preset = option;
                        final today = DateTime.now();
                        selected = switch (option) {
                          'Today' => DateTimeRange(start: today, end: today),
                          'Last 7 days' => DateTimeRange(
                            start: today.subtract(const Duration(days: 6)),
                            end: today,
                          ),
                          'Last 30 days' => DateTimeRange(
                            start: today.subtract(const Duration(days: 29)),
                            end: today,
                          ),
                          _ => null,
                        };
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDateRangePicker(
                    context: dialogContext,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(now.year + 1, 12, 31),
                    initialDateRange: selected,
                  );
                  if (picked != null && dialogContext.mounted) {
                    refresh(() {
                      selected = picked;
                      preset = 'Custom';
                    });
                  }
                },
                icon: const Icon(Icons.date_range_outlined),
                label: Text(preset == 'Custom' && selected != null
                    ? _dateFilterLabel(selected)
                    : 'Custom date range'),
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
            onPressed: () => Navigator.pop(dialogContext, (range: selected)),
            child: const Text('Apply'),
          ),
        ],
      ),
    ),
  );
}

/// DataTable requires every row to have exactly one cell per column.
List<String> normalizeReportCells(List<String> cells, int columnCount) => [
  for (var index = 0; index < columnCount; index++)
    index < cells.length ? cells[index] : '',
];

String _dateText(Object? value) {
  DateTime? date;
  if (value is Timestamp) date = value.toDate();
  if (value is DateTime) date = value;
  if (date == null) return '';
  final local = date.toLocal();
  return '${local.month}/${local.day}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _transactionDate(Object? value) => transactionDateTime(
  value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : null,
);

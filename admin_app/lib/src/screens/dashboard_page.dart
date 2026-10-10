import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../services/date_display.dart';
import '../widgets/common.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final subscriptions = <StreamSubscription>[];
  int activeUsers = 0, activeVehicles = 0, totalVehicles = 0;
  double todayIncome = 0, monthIncome = 0;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> transactions = [];
  String revenuePeriod = 'week';

  @override
  void initState() {
    super.initState();
    subscriptions.add(
      FirebaseService.instance.watch('users').listen((s) {
        if (mounted) {
          setState(
            () => activeUsers = s.docs
                .where((d) => d.data()['active'] != false)
                .length,
          );
        }
      }),
    );
    subscriptions.add(
      FirebaseService.instance.watch('vehicles').listen((s) {
        if (mounted) {
          setState(() {
            final operatingVehicles = s.docs
                .where((d) => d.data()['archived'] != true)
                .toList();
            totalVehicles = operatingVehicles.length;
            activeVehicles = operatingVehicles
                .where(
                  (d) =>
                      d.data()['status'] == 'active' ||
                      d.data()['status'] == 'onRoute',
                )
                .length;
          });
        }
      }),
    );
    subscriptions.add(
      FirebaseService.instance.watch('transactions').listen((s) {
        final now = DateTime.now();
        var today = 0.0, month = 0.0;
        for (final doc in s.docs) {
          final data = doc.data();
          final timestamp = data['createdAt'];
          final date = timestamp is Timestamp ? timestamp.toDate() : null;
          final type = '${data['type'] ?? data['title'] ?? ''}'.toLowerCase();
          if (!type.contains('fare')) continue;
          final amount = ((data['amount'] as num?)?.toDouble() ?? 0).abs();
          if (date != null &&
              date.year == now.year &&
              date.month == now.month) {
            month += amount;
            if (date.day == now.day) today += amount;
          }
        }
        if (mounted) {
          setState(() {
            todayIncome = today;
            monthIncome = month;
            transactions = s.docs;
          });
        }
      }),
    );
  }

  @override
  void dispose() {
    for (final item in subscriptions) {
      item.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageIntro(
          title: 'Good morning, Admin',
          subtitle: 'Here is what is happening across the fleet today.',
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _Metric(
                icon: Icons.account_balance_wallet_outlined,
                label: 'TODAY’S EARNINGS',
                value: 'PHP ${todayIncome.toStringAsFixed(2)}',
                note: '',
                color: Color(0xFF08783E),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _Metric(
                icon: Icons.calendar_month_outlined,
                label: 'INCOME THIS MONTH',
                value: 'PHP ${monthIncome.toStringAsFixed(2)}',
                note: 'Current calendar month',
                color: Color(0xFF3867D6),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _Metric(
                icon: Icons.people_outline,
                label: 'ACTIVE USERS',
                value: '$activeUsers',
                note: 'Enabled Firebase profiles',
                color: Color(0xFFF2994A),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _Metric(
                icon: Icons.directions_bus_outlined,
                label: 'VEHICLES ON ROUTE',
                value: '$activeVehicles / $totalVehicles',
                note: '${totalVehicles - activeVehicles} currently idle',
                color: Color(0xFF9B51E0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Revenue overview',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Daily earnings from Jeep and E-Jeep',
                                  style: TextStyle(color: Colors.black45),
                                ),
                              ],
                            ),
                          ),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'week', label: Text('Week')),
                              ButtonSegment(
                                value: 'month',
                                label: Text('Month'),
                              ),
                            ],
                            selected: {revenuePeriod},
                            onSelectionChanged: (value) =>
                                setState(() => revenuePeriod = value.first),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      MiniChart(values: _revenueChartValues(), height: 205),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: _revenueLabels()
                            .map((label) => Text(label))
                            .toList(),
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
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Today by vehicle type',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F7F4),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'PHP ${_todayByType().$1.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                              ),
                            ),
                            const Text(
                              'fare revenue today',
                              style: TextStyle(color: Colors.black45),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _Legend(
                        color: const Color(0xFF08783E),
                        label: 'Traditional Jeep',
                        value: 'PHP ${_todayByType().$2.toStringAsFixed(2)}',
                      ),
                      const SizedBox(height: 14),
                      _Legend(
                        color: const Color(0xFF4FA9DD),
                        label: 'E-Jeep',
                        value: 'PHP ${_todayByType().$3.toStringAsFixed(2)}',
                      ),
                      const SizedBox(height: 12),
                      _Legend(
                        color: const Color(0xFF98A29B),
                        label: 'Vehicle type not recorded',
                        value: 'PHP ${_todayByType().$4.toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Recent transactions',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${transactions.length} total',
                      style: const TextStyle(color: Colors.black45),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const _TransactionHead(),
                const Divider(height: 1),
                if (transactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No transactions yet.')),
                  )
                else
                  ...transactions.take(6).map(_Transaction.fromDocument),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  List<double> _revenueValues() {
    final now = DateTime.now();
    final count = revenuePeriod == 'week'
        ? 7
        : DateTime(now.year, now.month + 1, 0).day;
    final values = List<double>.filled(count, 0);
    for (final doc in transactions) {
      final data = doc.data();
      final value = data['createdAt'];
      final date = value is Timestamp ? value.toDate() : null;
      final type = '${data['type'] ?? data['title'] ?? ''}'.toLowerCase();
      if (!type.contains('fare')) continue;
      final amount = ((data['amount'] as num?)?.toDouble() ?? 0).abs();
      if (date == null) continue;
      if (revenuePeriod == 'month' &&
          date.year == now.year &&
          date.month == now.month) {
        values[date.day - 1] += amount;
      } else if (revenuePeriod == 'week') {
        final start = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: now.weekday - 1));
        final index = DateTime(
          date.year,
          date.month,
          date.day,
        ).difference(start).inDays;
        if (index >= 0 && index < 7) values[index] += amount;
      }
    }
    return values;
  }

  List<double> _revenueChartValues() {
    final values = _revenueValues();
    final maximum = values.fold<double>(
      0,
      (current, value) => value > current ? value : current,
    );
    if (maximum == 0) return values;
    return values.map((value) => value / maximum * 100).toList();
  }

  List<String> _revenueLabels() => revenuePeriod == 'week'
      ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
      : List.generate(
          _revenueValues().length,
          (index) => index == 0 || (index + 1) % 5 == 0 ? '${index + 1}' : '',
        );

  (double, double, double, double) _todayByType() {
    final now = DateTime.now();
    var jeep = 0.0;
    var eJeep = 0.0;
    var other = 0.0;
    for (final doc in transactions) {
      final data = doc.data();
      final value = data['createdAt'];
      final date = value is Timestamp ? value.toDate() : null;
      if (date == null ||
          date.year != now.year ||
          date.month != now.month ||
          date.day != now.day) {
        continue;
      }
      final amount = ((data['amount'] as num?)?.toDouble() ?? 0).abs();
      final type = '${data['vehicleType'] ?? data['vehicleName'] ?? ''}'
          .toLowerCase();
      if (type.contains('e-jeep') || type.contains('ejeep')) {
        eJeep += amount;
      } else if (type.contains('jeep')) {
        jeep += amount;
      } else {
        other += amount;
      }
    }
    return (jeep + eJeep + other, jeep, eJeep, other);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.note,
    required this.color,
  });
  final IconData icon;
  final String label, value, note;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 18),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: .7,
              color: Colors.black54,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            note,
            style: TextStyle(
              fontSize: 11,
              color: note.startsWith('↑') || note.startsWith('+')
                  ? const Color(0xFF08783E)
                  : Colors.black45,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.value,
  });
  final Color color;
  final String label, value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(label)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );
}

class _TransactionHead extends StatelessWidget {
  const _TransactionHead();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 11),
    child: Row(
      children: [
        Expanded(flex: 2, child: Text('DATE & TIME', style: _head)),
        Expanded(flex: 2, child: Text('TRANSACTION ID', style: _head)),
        Expanded(flex: 2, child: Text('USER', style: _head)),
        Expanded(child: Text('TYPE', style: _head)),
        Expanded(child: Text('AMOUNT', style: _head)),
        SizedBox(width: 70, child: Text('STATUS', style: _head)),
      ],
    ),
  );
  static const _head = TextStyle(
    fontSize: 10,
    color: Colors.black45,
    fontWeight: FontWeight.w700,
  );
}

class _Transaction extends StatelessWidget {
  const _Transaction({required this.data});
  factory _Transaction.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final value = data['createdAt'];
    final date = value is Timestamp ? value.toDate().toLocal() : null;
    return _Transaction(
      data: (
        transactionDateTime(date),
        doc.id,
        '${data['passengerName'] ?? data['userName'] ?? data['userId'] ?? 'Unknown user'}',
        '${data['title'] ?? data['type'] ?? 'Transaction'}',
        'PHP ${((data['amount'] as num?)?.toDouble() ?? 0).abs().toStringAsFixed(2)}',
        '${data['status'] ?? 'Completed'}',
      ),
    );
  }
  final (String, String, String, String, String, String) data;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 13),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFEEF2EF))),
    ),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            data.$1,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(data.$2),
        ),
        Expanded(flex: 2, child: Text(data.$3)),
        Expanded(child: Text(data.$4)),
        Expanded(
          child: Text(
            data.$5,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          width: 70,
          child: StatusPill(
            data.$6,
            good: !{
              'failed',
              'rejected',
              'cancelled',
            }.contains(data.$6.toLowerCase()),
          ),
        ),
      ],
    ),
  );
}

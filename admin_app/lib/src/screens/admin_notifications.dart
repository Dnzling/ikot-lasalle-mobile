import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/firebase_service.dart';
import '../services/notification_read_storage.dart';

class AdminNotificationButton extends StatefulWidget {
  const AdminNotificationButton({this.onNavigate, super.key});
  final ValueChanged<int>? onNavigate;

  @override
  State<AdminNotificationButton> createState() =>
      _AdminNotificationButtonState();
}

class _AdminNotificationButtonState extends State<AdminNotificationButton> {
  late Future<List<AdminAlert>> alertsFuture;
  List<AdminAlert> latestAlerts = const [];
  Timer? refreshTimer;
  final readAlertIds = <String>{};

  String get readKey =>
      'admin.notifications.read.${FirebaseService.instance.auth.currentUser?.uid ?? 'unknown'}';

  @override
  void initState() {
    super.initState();
    alertsFuture = AdminNotificationCenter.load();
    alertsFuture.then((alerts) {
      if (mounted) setState(() => latestAlerts = alerts);
    });
    _loadReadAlerts();
    refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refresh();
    });
  }

  void _loadReadAlerts() {
    try {
      final saved = readNotificationState(readKey);
      if (saved == null) return;
      final ids = (jsonDecode(saved) as List<dynamic>).whereType<String>();
      readAlertIds.addAll(ids);
    } catch (_) {
      // Notifications remain usable if local storage is unavailable.
    }
  }

  void _markAsRead(AdminAlert alert) {
    if (!mounted) return;
    setState(() {
      readAlertIds.add(alert.id);
    });
    _refresh();
    writeNotificationState(readKey, jsonEncode(readAlertIds.toList()));
  }

  void _refresh() {
    final refreshed = AdminNotificationCenter.load();
    refreshed.then((alerts) {
      if (mounted) setState(() => latestAlerts = alerts);
    });
    if (mounted) {
      setState(() {
        alertsFuture = refreshed;
      });
    }
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    final future = alertsFuture;
    future.then((alerts) {
      if (!mounted) return;
      setState(() {
        latestAlerts = alerts;
        readAlertIds.addAll(alerts.map((alert) => alert.id));
      });
      writeNotificationState(readKey, jsonEncode(readAlertIds.toList()));
    });
    await showDialog<void>(
      context: context,
      builder: (_) => AdminNotificationDialog(
        future: future,
        onNavigate: widget.onNavigate,
        onAlertOpened: _markAsRead,
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<AdminAlert>>(
    future: alertsFuture,
    builder: (context, snapshot) {
      final count =
          snapshot.data
              ?.where((alert) => !readAlertIds.contains(alert.id))
              .length ??
          0;
      return IconButton(
        tooltip: 'Admin notifications',
        onPressed: _open,
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          child: const Icon(Icons.notifications_none_rounded),
        ),
      );
    },
  );
}

class AdminNotificationDialog extends StatelessWidget {
  const AdminNotificationDialog({
    required this.future,
    this.onNavigate,
    this.onAlertOpened,
    super.key,
  });
  final Future<List<AdminAlert>> future;
  final ValueChanged<int>? onNavigate;
  final ValueChanged<AdminAlert>? onAlertOpened;

  Future<void> _preview(BuildContext context, AdminAlert alert) async {
    onAlertOpened?.call(alert);
    final navigate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(alert.title),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: math.min(420, MediaQuery.sizeOf(context).height * .55),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.category,
                  style: TextStyle(
                    color: alert.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(alert.message),
                if (alert.date != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    alert.date!.toLocal().toString(),
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
          if (alert.destination != null)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('View page'),
            ),
        ],
      ),
    );
    if (navigate == true && context.mounted && alert.destination != null) {
      Navigator.pop(context);
      onNavigate?.call(alert.destination!);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Admin notifications'),
    content: SizedBox(
      width: math.min(640, MediaQuery.sizeOf(context).width - 80),
      height: math.min(520, MediaQuery.sizeOf(context).height * .65),
      child: FutureBuilder<List<AdminAlert>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Could not load notifications: ${snapshot.error}'),
            );
          }
          final alerts = snapshot.data ?? const <AdminAlert>[];
          if (alerts.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Center(child: Text('No new admin notifications.')),
            );
          }
          return ListView.separated(
            itemCount: alerts.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final alert = alerts[index];
              return ListTile(
                onTap: () => _preview(context, alert),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                leading: CircleAvatar(
                  backgroundColor: alert.color.withValues(alpha: .12),
                  child: Icon(alert.icon, color: alert.color),
                ),
                title: Text(
                  alert.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(alert.message),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      alert.category,
                      style: TextStyle(
                        fontSize: 11,
                        color: alert.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              );
            },
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

class AdminAlert {
  const AdminAlert({
    required this.id,
    required this.category,
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    this.date,
    this.destination,
  });

  final String id;
  final String category;
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final DateTime? date;
  final int? destination;
}

class AdminNotificationCenter {
  const AdminNotificationCenter._();

  static final _db = FirebaseService.instance.db;

  static Future<List<AdminAlert>> load() async {
    final reads = await Future.wait([
      _read('topUpRequests'), _read('passwordResetRequests'), _read('users'),
      _read('vehicles'), _read('fuelingRequests'), _read('fueling'),
      _read('exportLogs'), _read('quotaFulfilments'), _read('quotaRequests'),
    ]);
    final topUps = reads[0];
    final passwordResets = reads[1];
    final users = reads[2];
    final vehicles = reads[3];
    final fueling = [...reads[4], ...reads[5]];
    final exports = reads[6];
    final quotas = [...reads[7], ...reads[8]];
    final alerts = <AdminAlert>[];

    for (final doc in topUps) {
      final data = doc.data();
      if ('${data['status'] ?? 'pending'}'.toLowerCase() != 'pending') continue;
      alerts.add(
        AdminAlert(
          id: 'topUp:${doc.reference.path}',
          category: 'Top Up',
          title: 'Top-up request needs review',
          message:
              '${data['passengerName'] ?? data['passengerId'] ?? 'Passenger'} • PHP ${data['amount'] ?? 0}',
          icon: Icons.account_balance_wallet_outlined,
          color: const Color(0xFF08783E),
          date: _date(data['submittedAt']),
          destination: 5,
        ),
      );
    }

    for (final doc in passwordResets) {
      final data = doc.data();
      if (data['status'] != 'pending') continue;
      alerts.add(
        AdminAlert(
          id: 'passwordReset:${doc.reference.path}',
          category: 'Password resets',
          title: 'Password reset needs review',
          message:
              '${data['firstName'] ?? ''} ${data['lastName'] ?? ''} • ${data['idNumber'] ?? ''}',
          icon: Icons.lock_reset_outlined,
          color: const Color(0xFF9A6100),
          date: _date(data['createdAt']),
          destination: 4,
        ),
      );
    }

    for (final doc in users) {
      final data = doc.data();
      if (data['mustChangePassword'] != true &&
          data['passwordChangeRequested'] != true) {
        continue;
      }
      alerts.add(
        AdminAlert(
          id: 'passwordChange:${doc.reference.path}',
          category: 'Change Password Requests',
          title: 'Password change request',
          message:
              '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                  .trim()
                  .isEmpty
              ? 'A passenger must change the default password.'
              : '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim(),
          icon: Icons.lock_reset_outlined,
          color: const Color(0xFF9A6100),
          date: _date(data['createdAt']),
          destination: 3,
        ),
      );
    }

    for (final doc in [...vehicles, ...fueling]) {
      final data = doc.data();
      final status =
          '${data['fuelStatus'] ?? data['gasStatus'] ?? data['status'] ?? ''}'
              .toLowerCase();
      if (!status.contains('fuel') &&
          !status.contains('gas') &&
          !status.contains('empty') &&
          !status.contains('low') &&
          !status.contains('refill')) {
        continue;
      }
      alerts.add(
        AdminAlert(
          id: 'fueling:${doc.reference.path}',
          category: 'Fueling Gas Status',
          title: 'Fueling status update',
          message:
              '${data['vehicleName'] ?? data['name'] ?? 'Vehicle'}: ${data['fuelStatus'] ?? data['gasStatus'] ?? data['status']}',
          icon: Icons.local_gas_station_outlined,
          color: const Color(0xFF3867D6),
          date: _date(data['updatedAt'] ?? data['createdAt']),
          destination: 1,
        ),
      );
    }

    for (final doc in exports) {
      final data = doc.data();
      alerts.add(
        AdminAlert(
          id: 'export:${doc.reference.path}',
          category: 'Excel/PDF Log Activity',
          title: '${data['format'] ?? 'File'} export completed',
          message:
              '${data['report'] ?? 'Report'} • ${data['rowCount'] ?? 0} records',
          icon: Icons.file_download_outlined,
          color: const Color(0xFF7A4FB5),
          date: _date(data['createdAt']),
          destination: 7,
        ),
      );
    }

    for (final doc in quotas) {
      final data = doc.data();
      final status = '${data['status'] ?? ''}'.toLowerCase();
      if (status == 'fulfilled' ||
          status == 'complete' ||
          status == 'completed') {
        continue;
      }
      alerts.add(
        AdminAlert(
          id: 'quota:${doc.reference.path}',
          category: 'Quota Fulfilment',
          title: 'Quota fulfilment update',
          message:
              '${data['name'] ?? data['routeName'] ?? data['quotaName'] ?? 'Quota'}: ${data['status'] ?? 'pending'}',
          icon: Icons.task_alt_outlined,
          color: const Color(0xFFB3261E),
          date: _date(data['updatedAt'] ?? data['createdAt']),
          destination: 1,
        ),
      );
    }

    // Vehicle daily earnings are the live source for quota fulfilment. Some
    // deployments also store explicit quota request records, included above.
    for (final doc in vehicles) {
      final data = doc.data();
      final quota = (data['dailyQuota'] as num?)?.toDouble() ?? 0;
      final earnings =
          (data['tripIncome'] as num?)?.toDouble() ??
          (data['todayIncome'] as num?)?.toDouble() ??
          0;
      if (quota <= 0 || earnings < quota) continue;
      alerts.add(
        AdminAlert(
          id: 'vehicleQuota:${doc.reference.path}',
          category: 'Quota Fulfilment',
          title: 'Daily quota fulfilled',
          message:
              '${data['name'] ?? 'Vehicle'} reached PHP ${earnings.toStringAsFixed(2)} of its PHP ${quota.toStringAsFixed(2)} quota.',
          icon: Icons.task_alt_outlined,
          color: const Color(0xFFB3261E),
          date: _date(data['updatedAt'] ?? data['createdAt']),
          destination: 1,
        ),
      );
    }

    alerts.sort(
      (a, b) => (b.date ?? DateTime(1970)).compareTo(a.date ?? DateTime(1970)),
    );
    return alerts;
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _read(
    String collection,
  ) async {
    try {
      return (await _db.collection(collection).limit(50).get()
          .timeout(const Duration(seconds: 8))).docs;
    } catch (_) {
      return const [];
    }
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

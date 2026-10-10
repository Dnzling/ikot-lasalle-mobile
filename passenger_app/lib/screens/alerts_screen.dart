import 'package:flutter/material.dart';

import '../models/app_session.dart';
import '../services/passenger_firebase_service.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({required this.session, super.key});

  final AppSession session;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<Map<String, dynamic>> notifications = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    loadNotifications();
  }

  Future<void> loadNotifications() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await const PassengerFirebaseService().getNotifications(
        widget.session.uid,
      );
      if (mounted) setState(() => notifications = result);
    } catch (exception) {
      if (mounted) setState(() => error = '$exception');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  IconData iconFor(String type) => switch (type) {
    'topUp' => Icons.account_balance_wallet,
    'booking' => Icons.confirmation_number,
    'boarded' => Icons.directions_bus,
    'completed' => Icons.location_on,
    _ => Icons.notifications,
  };

  @override
  Widget build(BuildContext context) => SafeArea(
    child: RefreshIndicator(
      onRefresh: loadNotifications,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Alerts',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Updates from your actual rides and credit activity.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null)
            _MessageState(
              icon: Icons.cloud_off,
              message: error!,
              actionLabel: 'Retry',
              onPressed: loadNotifications,
            )
          else if (notifications.isEmpty)
            const _MessageState(
              icon: Icons.notifications_none,
              message:
                  'No notifications yet. Your ride and credit updates will appear here.',
            )
          else
            ...notifications.map(
              (notification) => Card(
                color: Colors.white,
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFE1F1E5),
                    child: Icon(
                      iconFor('${notification['type'] ?? ''}'),
                      color: const Color(0xFF62A77D),
                    ),
                  ),
                  title: Text(
                    '${notification['title'] ?? 'Update'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text('${notification['message'] ?? ''}'),
                  ),
                  trailing: Text(
                    '${notification['date'] ?? ''}',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onPressed,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
    child: Column(
      children: [
        Icon(icon, size: 50, color: Colors.black38),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 14),
          TextButton(onPressed: onPressed, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

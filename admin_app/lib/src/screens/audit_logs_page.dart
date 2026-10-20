import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/firebase_service.dart';
import '../widgets/common.dart';

class AuditLogsPage extends StatelessWidget {
  const AuditLogsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Audit logs')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageIntro(
            title: 'Audit logs',
            subtitle:
                'Review changes to routes, vehicles, drivers, users, fares, top-ups, settings, and report exports.',
          ),
          const SizedBox(height: 18),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseService.instance.watch('adminAuditLogs'),
              builder: (context, adminSnapshot) {
                if (adminSnapshot.hasError)
                  return Center(
                    child: Text(
                      'Could not load admin activity: ${adminSnapshot.error}',
                    ),
                  );
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseService.instance.watch('exportLogs'),
                  builder: (context, exportSnapshot) {
                    if (exportSnapshot.hasError)
                      return Center(
                        child: Text(
                          'Could not load export activity: ${exportSnapshot.error}',
                        ),
                      );
                    if (!adminSnapshot.hasData || !exportSnapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final logs =
                        <_AuditEntry>[
                          ...adminSnapshot.data!.docs.map(
                            (doc) => _AuditEntry(
                              action:
                                  '${doc.data()['action'] ?? 'Admin activity'}',
                              details: '${doc.data()['details'] ?? ''}',
                              adminId:
                                  '${doc.data()['adminId'] ?? 'Unknown admin'}',
                              date: (doc.data()['createdAt'] as Timestamp?)
                                  ?.toDate(),
                              icon: Icons.manage_accounts_outlined,
                            ),
                          ),
                          ...exportSnapshot.data!.docs.map(
                            (doc) => _AuditEntry(
                              action:
                                  'Exported ${doc.data()['report'] ?? 'report'}',
                              details:
                                  '${doc.data()['format'] ?? 'file'} export with ${doc.data()['rowCount'] ?? 0} records',
                              adminId:
                                  '${doc.data()['adminId'] ?? 'Unknown admin'}',
                              date: (doc.data()['createdAt'] as Timestamp?)
                                  ?.toDate(),
                              icon: Icons.file_download_outlined,
                            ),
                          ),
                        ]..sort(
                          (a, b) =>
                              (b.date ?? DateTime.fromMillisecondsSinceEpoch(0))
                                  .compareTo(
                                    a.date ??
                                        DateTime.fromMillisecondsSinceEpoch(0),
                                  ),
                        );
                    if (logs.isEmpty)
                      return const Center(
                        child: Text('No audit activity has been recorded yet.'),
                      );
                    return ListView.separated(
                      itemCount: logs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Icon(log.icon)),
                            title: Text(
                              log.action,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text(
                                '${log.details}\nAdmin: ${log.adminId}\n${_formatDate(log.date)}',
                              ),
                            ),
                            isThreeLine: true,
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: Text(log.action),
                                content: SelectableText(
                                  'Details: ${log.details}\n\nAdmin ID: ${log.adminId}\n\nTime: ${_formatDate(log.date)}',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  static String _formatDate(DateTime? value) {
    if (value == null) return 'Time pending';
    final date = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }
}

class _AuditEntry {
  const _AuditEntry({
    required this.action,
    required this.details,
    required this.adminId,
    required this.date,
    required this.icon,
  });

  final String action;
  final String details;
  final String adminId;
  final DateTime? date;
  final IconData icon;
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/firebase_service.dart';
import '../widgets/common.dart';

class PasswordResetsPage extends StatelessWidget {
  const PasswordResetsPage({super.key});

  Future<void> _reject(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject reset request?'),
        content: const Text('The passenger will need to submit a new request.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseService.instance.db
          .collection('passwordResetRequests')
          .doc(id)
          .update({
            'status': 'rejected',
            'reviewedBy': FirebaseService.instance.auth.currentUser?.uid,
            'reviewedAt': FieldValue.serverTimestamp(),
          });
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not reject request: $error')),
        );
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseService.instance.db
        .collection('passwordResetRequests')
        .orderBy('createdAt', descending: true)
        .snapshots(),
    builder: (context, snapshot) {
      final requests = snapshot.data?.docs ?? [];
      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageIntro(
              title: 'Password resets',
              subtitle:
                  'Verify the passenger in person, then run the office reset tool.',
            ),
            const SizedBox(height: 20),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Office workflow: 1. Check the passenger’s physical ID. '
                  '2. Copy the reset command below. 3. Run it in the trusted '
                  'admin-office terminal. 4. Give the temporary password to '
                  'the passenger in person. Keep the service-account key out '
                  'of this app and the EXE.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (snapshot.hasError)
              Text('Could not load reset requests: ${snapshot.error}')
            else if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator())
            else if (requests.isEmpty)
              const Text('No reset requests yet.')
            else
              for (final request in requests)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${request.data()['firstName'] ?? ''} ${request.data()['lastName'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('ID: ${request.data()['idNumber'] ?? ''}'),
                        Text(
                          'Contact: ${request.data()['contactNumber'] ?? ''}',
                        ),
                        Text(
                          'Status: ${request.data()['status'] ?? 'pending'}',
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Request ID (enter this in the local reset tool):',
                        ),
                        SelectableText(request.id),
                        if (request.data()['status'] == 'pending')
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(
                                      text: 'npm.cmd run reset -- ${request.id}',
                                    ));
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Reset command copied. Run it inside admin_reset_tool on the trusted office computer.')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.copy_outlined),
                                  label: const Text('Copy reset command'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _reject(context, request.id),
                                  icon: const Icon(Icons.close),
                                  label: const Text('Reject'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      );
    },
  );
}

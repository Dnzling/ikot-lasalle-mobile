import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/firebase_service.dart';
import '../widgets/common.dart';
import '../widgets/table_pagination.dart';

Widget _receiptImage(
  Map<String, dynamic> data, {
  double? height,
  BoxFit fit = BoxFit.contain,
}) {
  final bytes = data['receiptBytes'];
  if (bytes is Blob) return Image.memory(bytes.bytes, height: height, fit: fit);
  final url = '${data['screenshotUrl'] ?? ''}';
  if (url.isNotEmpty) {
    return Image.network(
      url,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) =>
          const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
  return const Center(child: Icon(Icons.image_not_supported_outlined));
}

class TopUpPage extends StatefulWidget {
  const TopUpPage({super.key});

  @override
  State<TopUpPage> createState() => _TopUpPageState();
}

class _TopUpPageState extends State<TopUpPage> {
  final searchController = TextEditingController();
  String searchQuery = '';
  int page = 0;
  int rowsPerPage = 15;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseService.instance.watchTopUpRequests(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Text(
            'Could not load top-up requests from Firebase.\n${snapshot.error}',
          ),
        );
      }
      final requests =
          snapshot.data?.docs ??
          const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      final pending = requests.where((doc) => _status(doc) == 'pending').length;
      final approved = requests
          .where((doc) => _status(doc) == 'approved')
          .length;
      final rejected = requests
          .where((doc) => _status(doc) == 'rejected')
          .length;
      final query = searchQuery.trim().toLowerCase();
      final filtered = requests.where((request) {
        if (query.isEmpty) return true;
        final data = request.data();
        return '${data['passengerName'] ?? ''}'.toLowerCase().contains(query) ||
            '${data['referenceNumber'] ?? ''}'.toLowerCase().contains(query);
      }).toList();
      final lastPage = filtered.isEmpty
          ? 0
          : (filtered.length - 1) ~/ rowsPerPage;
      final currentPage = page.clamp(0, lastPage);
      final visible = filtered
          .skip(currentPage * rowsPerPage)
          .take(rowsPerPage);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            PageIntro(
              title: 'Top-up requests',
              subtitle:
                  'Review passenger GCash payments and credit approved requests.',
              action: FilledButton.icon(
                onPressed: () => _configureGcash(context),
                icon: const Icon(Icons.settings_phone_outlined),
                label: const Text('GCash account'),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    'PENDING',
                    '$pending',
                    Icons.pending_actions_outlined,
                    const Color(0xFF9A6100),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _Metric(
                    'APPROVED',
                    '$approved',
                    Icons.check_circle_outline,
                    const Color(0xFF08783E),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _Metric(
                    'REJECTED',
                    '$rejected',
                    Icons.cancel_outlined,
                    const Color(0xFFB3261E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Padding(
                        padding: EdgeInsets.all(42),
                        child: CircularProgressIndicator(),
                      )
                    : Column(
                        children: [
                          TextField(
                            controller: searchController,
                            onChanged: (value) => setState(() {
                              searchQuery = value;
                              page = 0;
                            }),
                            decoration: InputDecoration(
                              labelText: 'Search top-ups',
                              hintText: 'Passenger name or reference number',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: searchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      onPressed: () {
                                        searchController.clear();
                                        setState(() {
                                          searchQuery = '';
                                          page = 0;
                                        });
                                      },
                                      icon: const Icon(Icons.close),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (filtered.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(42),
                              child: Text(
                                requests.isEmpty
                                    ? 'No top-up requests yet.'
                                    : 'No top-up requests match your search.',
                              ),
                            )
                          else ...[
                            const _RequestHeader(),
                            const Divider(height: 1),
                            for (final request in visible)
                              _RequestRow(id: request.id, data: request.data()),
                          ],
                          const SizedBox(height: 12),
                          TablePagination(
                            totalRows: filtered.length,
                            page: currentPage,
                            rowsPerPage: rowsPerPage,
                            onPageChanged: (value) =>
                                setState(() => page = value),
                            onRowsPerPageChanged: (value) => setState(() {
                              rowsPerPage = value;
                              page = 0;
                            }),
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

  static String _status(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      '${doc.data()['status'] ?? 'pending'}'.toLowerCase();

  static Future<void> _configureGcash(BuildContext context) async {
    final nameController = TextEditingController();
    final controller = TextEditingController();
    try {
      final settings = await FirebaseService.instance.getGcashSettings();
      nameController.text = settings['accountName'] ?? '';
      controller.text = settings['gcashNumber'] ?? '';
    } catch (_) {
      // Start with an empty field when the setting has not been created yet.
    }
    if (!context.mounted) {
      nameController.dispose();
      controller.dispose();
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('GCash account configuration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'GCash account name',
                hintText: 'Account holder name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'GCash account number',
                hintText: '09XXXXXXXXX',
                prefixIcon: Icon(Icons.phone_android),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final accountName = nameController.text.trim();
    final number = controller.text.trim();
    nameController.dispose();
    controller.dispose();
    if (saved != true || !context.mounted) return;
    if (accountName.isEmpty || number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the GCash account name and number.'),
        ),
      );
      return;
    }
    try {
      await FirebaseService.instance.updateGcashSettings(
        accountName: accountName,
        gcashNumber: number,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GCash account configuration saved.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save GCash account: $error')),
        );
      }
    }
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(icon, color: color),
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

class _RequestHeader extends StatelessWidget {
  const _RequestHeader();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      SizedBox(width: 84),
      Expanded(flex: 3, child: Text('PASSENGER', style: _head)),
      Expanded(child: Text('AMOUNT', style: _head)),
      Expanded(flex: 2, child: Text('REFERENCE NUMBER', style: _head)),
      Expanded(flex: 2, child: Text('TIME', style: _head)),
      SizedBox(width: 120, child: Text('STATUS', style: _head)),
    ],
  );
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final status = '${data['status'] ?? 'pending'}'.toLowerCase();
    final passengerName = '${data['passengerName'] ?? 'Unknown passenger'}';
    final passengerId =
        '${data['passengerId'] ?? data['idNumber'] ?? data['userId'] ?? ''}';
    final amount =
        (data['amount'] as num?)?.toDouble() ??
        double.tryParse('${data['amount']}') ??
        0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            height: 64,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _receiptImage(data, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  passengerName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  passengerId,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          Expanded(child: Text('PHP ${amount.toStringAsFixed(2)}')),
          Expanded(
            flex: 2,
            child: Text('${data['referenceNumber'] ?? 'Not detected'}'),
          ),
          Expanded(flex: 2, child: Text(_dateText(data['submittedAt']))),
          SizedBox(
            width: 120,
            child: Row(
              children: [
                StatusPill(status.toUpperCase(), good: status == 'approved'),
                IconButton(
                  tooltip: status == 'pending'
                      ? 'Review request'
                      : 'View request',
                  onPressed: () =>
                      _review(context, allowDecision: status == 'pending'),
                  icon: Icon(
                    status == 'pending'
                        ? Icons.rate_review_outlined
                        : Icons.visibility_outlined,
                    size: 19,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _review(
    BuildContext context, {
    required bool allowDecision,
  }) async {
    final noteController = TextEditingController();
    final approve = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Review top-up request'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data['receiptBytes'] is Blob ||
                    '${data['screenshotUrl'] ?? ''}'.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _receiptImage(
                      data,
                      height: 280,
                      fit: BoxFit.contain,
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Passenger: ${data['passengerName'] ?? 'Unknown'}'),
                Text(
                  'Passenger ID: ${data['passengerId'] ?? data['userId'] ?? ''}',
                ),
                Text('Amount: PHP ${data['amount'] ?? 0}'),
                Text(
                  'Reference number: ${data['referenceNumber'] ?? 'Not detected'}',
                ),
                Text(
                  'Status: ${'${data['status'] ?? 'pending'}'.toUpperCase()}',
                ),
                Text('Submitted: ${_dateText(data['submittedAt'])}'),
                if ('${data['adminNote'] ?? ''}'.trim().isNotEmpty)
                  Text('Admin note: ${data['adminNote']}'),
                if ('${data['ocrText'] ?? ''}'.trim().isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('OCR text'),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText('${data['ocrText']}'),
                      ),
                    ],
                  ),
                const SizedBox(height: 14),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Admin note (optional)',
                    hintText: 'Add a note for the passenger',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: allowDecision
            ? [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Reject'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Approve and credit'),
                ),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
      ),
    );
    final note = noteController.text;
    noteController.dispose();
    if (approve == null || !context.mounted) return;
    var reviewNote = note;
    if (!approve) {
      final rejection = await _confirmRejection(context);
      if (rejection == null || !context.mounted) return;
      reviewNote = rejection;
    }
    try {
      await FirebaseService.instance.reviewTopUpRequest(
        id,
        approve: approve,
        adminNote: reviewNote,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve
                  ? 'Top-up approved and credited.'
                  : 'Top-up request rejected.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<String?> _confirmRejection(BuildContext context) async {
    const reasons = ['Payment not received', 'Other'];
    var reason = reasons.first;
    final descriptionController = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Confirm rejection'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The passenger will be notified that this top-up was rejected.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: [
                    for (final value in reasons)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => reason = value);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: descriptionController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    hintText: 'Explain why the receipt was rejected.',
                    errorText: error,
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
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                final description = descriptionController.text.trim();
                if (description.isEmpty) {
                  setDialogState(
                    () => error = 'Enter a description before rejecting.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, '$reason: $description');
              },
              child: const Text('Confirm rejection'),
            ),
          ],
        ),
      ),
    );
    descriptionController.dispose();
    return result;
  }
}

String _dateText(Object? value) {
  final date = value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : DateTime.tryParse('$value');
  if (date == null) return 'Pending timestamp';
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

const _head = TextStyle(
  fontSize: 10,
  color: Colors.black45,
  fontWeight: FontWeight.w700,
);

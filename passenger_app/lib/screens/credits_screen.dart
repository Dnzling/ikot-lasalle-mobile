
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/app_session.dart';
import '../models/top_up_request.dart';
import '../services/passenger_firebase_service.dart';
import 'top_up_screen.dart';

class CreditsScreen extends StatefulWidget {
  const CreditsScreen({required this.session, super.key});
  final AppSession session;

  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends State<CreditsScreen> {
  var transactions = <Map<String, dynamic>>[];
  var requests = <TopUpRequest>[];
  String gcashNumber = '';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final service = const PassengerFirebaseService();
      final passenger = await service.getProfile(widget.session.uid);
      final transactionRows = await service.getTransactions(widget.session.uid);
      final requestRows = await service.getTopUpRequests(widget.session.uid);
      final number = await service.getGcashNumber();
      widget.session.updatePassenger(passenger);
      if (mounted) {
        setState(() {
          transactions = transactionRows;
          requests = requestRows;
          gcashNumber = number;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> showTopUpModal() async {
    final amountController = TextEditingController();
    Uint8List? screenshot;
    String? fileName;
    String mimeType = 'image/jpeg';
    bool submitting = false;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Request credit top-up',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Send your payment to this GCash account:',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: SelectableText(
                  gcashNumber.isEmpty
                      ? 'GCash number is not configured'
                      : gcashNumber,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B8F4D),
                  ),
                )),
                IconButton(
                  tooltip: 'Copy GCash number',
                  onPressed: gcashNumber.replaceAll(RegExp(r'\D'), '').isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(
                            text: gcashNumber.replaceAll(RegExp(r'\D'), ''),
                          ));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('GCash number copied.')),
                            );
                          }
                        },
                  icon: const Icon(Icons.copy_outlined),
                ),
              ]),
              const SizedBox(height: 20),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  prefixText: 'PHP ',
                  labelText: 'Amount paid',
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: submitting
                    ? null
                    : () async {
                        final image = await ImagePicker().pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 70,
                          maxWidth: 1400,
                        );
                        if (image == null) return;
                        final bytes = await image.readAsBytes();
                        if (bytes.length > 3 * 1024 * 1024) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Screenshot must be smaller than 3 MB.',
                                ),
                              ),
                            );
                          }
                          return;
                        }
                        setModalState(() {
                          screenshot = bytes;
                          fileName = image.name;
                          mimeType = image.mimeType ?? 'image/jpeg';
                        });
                      },
                child: Container(
                  width: double.infinity,
                  height: screenshot == null ? 120 : 190,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: screenshot == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 38,
                              color: Color(0xFF62A77D),
                            ),
                            SizedBox(height: 8),
                            Text('Upload payment screenshot'),
                            Text(
                              'Required · JPG or PNG · Max 3 MB',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(screenshot!, fit: BoxFit.cover),
                            const Positioned(
                              right: 8,
                              top: 8,
                              child: CircleAvatar(
                                backgroundColor: Colors.white,
                                child: Icon(Icons.edit, size: 18),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: submitting || gcashNumber.isEmpty
                      ? null
                      : () async {
                          final amount = double.tryParse(
                            amountController.text.trim(),
                          );
                          if (amount == null ||
                              amount <= 0 ||
                              screenshot == null ||
                              fileName == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Enter the amount and attach your payment screenshot.',
                                ),
                              ),
                            );
                            return;
                          }
                          setModalState(() => submitting = true);
                          try {
                            await const PassengerFirebaseService()
                                .createTopUpRequest(
                                  uid: widget.session.uid,
                                  amount: amount,
                                  fileName: fileName!,
                                  mimeType: mimeType,
                                  screenshotBytes: screenshot!,
                                  referenceNumber:
                                      'legacy-${DateTime.now().millisecondsSinceEpoch}',
                                  ocrText: '',
                                );
                            if (context.mounted) Navigator.pop(context, true);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$error')));
                            }
                            setModalState(() => submitting = false);
                          }
                        },
                  icon: const Icon(Icons.send),
                  label: Text(
                    submitting ? 'Submitting...' : 'Submit for admin approval',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    amountController.dispose();
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Top-up request sent to the admin.')),
      );
      await refresh();
    }
  }

  Future<void> openTopUpPage() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TopUpScreen(session: widget.session)),
    );
    if (submitted == true && mounted) await refresh();
  }

  Color statusColor(String status) => switch (status.toLowerCase()) {
    'approved' => Colors.green,
    'rejected' => Colors.red,
    _ => Colors.orange,
  };

  @override
  Widget build(BuildContext context) => SafeArea(
    child: RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Transaction Records',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF62A77D),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AVAILABLE CREDITS',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'PHP ${widget.session.passenger.balance.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 31,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: openTopUpPage,
                  icon: const Icon(Icons.add),
                  label: const Text('Request top up'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!loading) ...[
            const SizedBox(height: 28),
            const Text(
              'Top-up requests',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (requests.isEmpty)
              const Text(
                'No top-up requests yet.',
                style: TextStyle(color: Colors.black54),
              ),
            ...requests.map(
              (request) => Card(
                color: Colors.white,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: request.receiptBytes != null
                              ? Image.memory(
                                  request.receiptBytes!,
                                  fit: BoxFit.cover,
                                )
                              : request.screenshotUrl.isNotEmpty
                              ? Image.network(
                                  request.screenshotUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const ColoredBox(
                                    color: Color(0xFFEFEFEF),
                                    child: Icon(
                                      Icons.image_not_supported_outlined,
                                    ),
                                  ),
                                )
                              : const ColoredBox(
                                  color: Color(0xFFEFEFEF),
                                  child: Icon(
                                    Icons.image_not_supported_outlined,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PHP ${request.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              request.submittedAt,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                            if (request.referenceNumber.isNotEmpty)
                              Text(
                                'Ref: ${request.referenceNumber}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                            if (request.adminNote.isNotEmpty)
                              Text(
                                request.adminNote,
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      Chip(
                        label: Text(
                          request.status.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                        backgroundColor: statusColor(request.status),
                        side: BorderSide.none,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Transactions',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (transactions.isEmpty)
              const Text(
                'No completed transactions yet.',
                style: TextStyle(color: Colors.black54),
              ),
            ...transactions.map(
              (transaction) => Card(
                color: Colors.white,
                elevation: 0,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE1F1E5),
                    child: Icon(Icons.receipt_long, color: Color(0xFF62A77D)),
                  ),
                  title: Text(
                    '${transaction['title'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('${transaction['date'] ?? ''}'),
                  trailing: Text(
                    '${transaction['amount'] ?? ''}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: '${transaction['amount']}'.startsWith('+')
                          ? const Color(0xFF62A77D)
                          : Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

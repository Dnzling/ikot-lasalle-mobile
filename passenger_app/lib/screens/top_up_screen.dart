import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/app_session.dart';
import '../services/passenger_firebase_service.dart';

class TopUpScreen extends StatefulWidget {
  const TopUpScreen({required this.session, super.key});
  final AppSession session;

  @override
  State<TopUpScreen> createState() => _TopUpScreenState();
}

class _TopUpScreenState extends State<TopUpScreen> {
  static const _ocrEndpoint = 'https://api.ocr.space/parse/image';
  static const _ocrApiKey = 'K86129484388957';

  final amountController = TextEditingController();
  final referenceController = TextEditingController();
  XFile? receipt;
  Uint8List? receiptBytes;
  String mimeType = 'image/jpeg';
  String referenceNumber = '';
  String ocrText = '';
  double? ocrAmount;
  String gcashAccountName = '';
  String gcashNumber = '';
  double minimumTopUpCredits = 1;
  String? message;
  bool scanning = false;
  bool submitting = false;

  @override
  void initState() {
    super.initState();
    _loadPaymentDetails();
    _loadMinimumTopUp();
  }

  @override
  void dispose() {
    amountController.dispose();
    referenceController.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentDetails() async {
    try {
      final settings = await const PassengerFirebaseService()
          .getGcashPaymentDetails();
      if (mounted) {
        setState(() {
          gcashAccountName = settings['accountName'] ?? '';
          gcashNumber = settings['gcashNumber'] ?? '';
        });
      }
    } catch (_) {
      // The payment number is helpful but does not prevent showing the form.
    }
  }

  Future<void> _loadMinimumTopUp() async {
    try {
      final minimum = await const PassengerFirebaseService().getMinimumTopUpCredits();
      if (mounted) setState(() => minimumTopUpCredits = minimum);
    } catch (_) {
      // Submission reads the setting again and fails if it is unavailable.
    }
  }

  Future<void> _copyGcashNumber() async {
    final digits = gcashNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: digits));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GCash number copied.')),
      );
    }
  }

  Future<void> _chooseReceipt() async {
    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 45,
        maxWidth: 1100,
      );
      if (selected == null) return;
      final bytes = await selected.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty || bytes.length > 800 * 1024) {
        if (mounted) {
          setState(
            () => message =
                'Receipt image must be smaller than 800 KB. Crop the screenshot and select it again.',
          );
        }
        return;
      }
      setState(() {
        receipt = selected;
        receiptBytes = bytes;
        mimeType = selected.mimeType ?? 'image/jpeg';
        referenceNumber = '';
        ocrText = '';
        ocrAmount = null;
        amountController.clear();
        referenceController.clear();
        message = null;
      });
      await _scanReceipt(bytes, selected.name);
    } catch (error) {
      if (mounted) setState(() => message = 'Could not open receipt: $error');
    }
  }

  Future<void> _scanReceipt(Uint8List bytes, String fileName) async {
    setState(() {
      scanning = true;
      message = 'Scanning receipt for the amount and GCash reference number...';
    });
    final client = http.Client();
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_ocrEndpoint))
        ..headers['apikey'] = _ocrApiKey
        ..fields['language'] = 'eng'
        ..fields['isOverlayRequired'] = 'false'
        // Engine 1 matches OCR.space's web portal output for GCash receipts.
        ..fields['OCREngine'] = '1'
        ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: fileName),
        );
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 25));
      final body = await response.stream.bytesToString().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        throw StateError('OCR service returned HTTP ${response.statusCode}.');
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['IsErroredOnProcessing'] == true) {
        final errors = json['ErrorMessage'];
        throw StateError('$errors');
      }
      final results = (json['ParsedResults'] as List<dynamic>? ?? const []);
      final text = results
          .map(
            (result) =>
                '${(result as Map<String, dynamic>)['ParsedText'] ?? ''}',
          )
          .join('\n')
          .trim();
      debugPrint('OCR.space parsed receipt text:\n$text');
      final reference = _extractReference(text);
      final amount = _extractAmount(text);
      if (mounted) {
        setState(() {
          ocrText = text;
          referenceNumber = reference;
          ocrAmount = amount;
          message = reference.isEmpty && amount == null
              ? 'OCR could not read the amount or reference number. Enter both from your receipt below.'
              : reference.isEmpty
              ? 'Amount detected. Enter the 13-digit reference number from your receipt below.'
              : amount == null
              ? 'Reference detected. Enter the amount from your receipt below.'
              : 'Reference and amount detected automatically.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          ocrText = '';
          referenceNumber = '';
          ocrAmount = null;
          message = 'Could not scan the receipt: $error Enter the amount and 13-digit reference number from your receipt below.';
        });
      }
    } finally {
      client.close();
      if (mounted) setState(() => scanning = false);
    }
  }

  String _extractReference(String text) {
    final label = RegExp(
      r'(?:reference|ref|transaction)\s*(?:(?:number|no|id)\s*)?(?:[.#:]\s*)?(?:#\s*)?',
      caseSensitive: false,
    );
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    for (var index = 0; index < lines.length; index++) {
      final labeled = label.firstMatch(lines[index]);
      if (labeled == null) continue;
      var candidate = lines[index]
          .substring(labeled.end)
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      var next = index + 1;
      // OCR.space can split a GCash reference such as "3043 282 799417"
      // over spaces and line breaks. Join only numeric continuation lines so
      // the following date/time is not accidentally included.
      while (next < lines.length &&
          RegExp(r'^\d[\d\s-]*$').hasMatch(lines[next])) {
        candidate += lines[next].replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
        next++;
      }
      if (RegExp(r'^\d{13}$').hasMatch(candidate)) return candidate;
    }
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final numeric = RegExp(r'\b\d{13}\b').firstMatch(normalized);
    return numeric?.group(0) ?? '';
  }

  double? _extractAmount(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    const labels = ['total amount sent', 'amount sent', 'amount', 'total'];
    for (final label in labels) {
      final labelPattern = RegExp(RegExp.escape(label), caseSensitive: false);
      for (var index = 0; index < lines.length; index++) {
        final match = labelPattern.firstMatch(lines[index]);
        if (match == null) continue;
        final candidates = <String>[
          lines[index].substring(match.end),
          if (index + 1 < lines.length) lines[index + 1],
          if (index + 2 < lines.length) lines[index + 2],
        ];
        for (final candidate in candidates) {
          final amountMatch = RegExp(
            r'(?:PHP|P|₱)?\s*([0-9][0-9,]*(?:\.\d{1,2})?)',
            caseSensitive: false,
          ).firstMatch(candidate);
          final amount = double.tryParse(
            amountMatch?.group(1)?.replaceAll(',', '') ?? '',
          );
          if (amount != null && amount > 0 && amount <= 10000) return amount;
        }
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final amount = ocrAmount ?? double.tryParse(amountController.text.trim());
    final bytes = receiptBytes;
    final file = receipt;
    if (amount == null || amount <= 0 || amount > 10000) {
      setState(
        () => message = 'Enter a valid amount between PHP 1 and PHP 10,000.',
      );
      return;
    }
    if (amount < minimumTopUpCredits) {
      setState(() => message =
          'Minimum top-up is PHP ${minimumTopUpCredits.toStringAsFixed(2)}.');
      return;
    }
    if (bytes == null || file == null) {
      setState(() => message = 'Attach your GCash receipt first.');
      return;
    }
    final reference = referenceNumber.isNotEmpty
        ? referenceNumber
        : referenceController.text.trim();
    if (!RegExp(r'^\d{13}$').hasMatch(reference)) {
      setState(
        () => message =
            'Enter the 13-digit GCash reference number shown on your receipt.',
      );
      return;
    }
    setState(() {
      submitting = true;
      message = 'Preparing top-up request...';
    });
    try {
      await const PassengerFirebaseService().createTopUpRequest(
        uid: widget.session.uid,
        amount: amount,
        fileName: file.name,
        mimeType: mimeType,
        screenshotBytes: bytes,
        referenceNumber: reference,
        ocrText: ocrText,
        onProgress: (stage) {
          if (mounted) setState(() => message = stage);
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          submitting = false;
          message = error is TimeoutException
              ? 'The request timed out. Check Transaction Records before retrying, in case it was saved.'
              : '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Top up credits')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          const Text(
            'Add credits with GCash',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Send the exact amount to the account below, then upload the receipt. If OCR cannot read the amount or reference number, enter the missing details from your receipt.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 18),
          Text(
            'Minimum top-up: PHP ${minimumTopUpCredits.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFFE5F4EA),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.phone_android, color: Color(0xFF08783E)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (gcashAccountName.isNotEmpty)
                          Text(
                            gcashAccountName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF08783E),
                            ),
                          ),
                        const Text(
                          'GCash account number',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        SelectableText(
                          gcashNumber.isEmpty
                              ? 'Not configured by admin'
                              : gcashNumber,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF08783E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy GCash number',
                    onPressed: gcashNumber.replaceAll(RegExp(r'\D'), '').isEmpty
                        ? null : _copyGcashNumber,
                    icon: const Icon(Icons.copy_outlined, color: Color(0xFF08783E)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (ocrAmount != null)
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Amount detected from receipt',
                prefixIcon: Icon(Icons.receipt_long_outlined),
                prefixText: 'PHP ',
                filled: true,
                fillColor: Color(0xFFE5F4EA),
              ),
              child: Text(
                ocrAmount!.toStringAsFixed(2),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          else if (receiptBytes != null && !scanning)
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount (OCR could not read it)',
                prefixText: 'PHP ',
                prefixIcon: Icon(Icons.edit_outlined),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          const SizedBox(height: 20),
          InkWell(
            onTap: scanning || submitting ? null : _chooseReceipt,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: receiptBytes == null ? 150 : 240,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black26),
              ),
              clipBehavior: Clip.antiAlias,
              child: receiptBytes == null
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 42,
                          color: Color(0xFF62A77D),
                        ),
                        SizedBox(height: 8),
                        Text('Upload GCash receipt'),
                        Text(
                          'JPG or PNG · max 800 KB',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(receiptBytes!, fit: BoxFit.contain),
                        Positioned(
                          right: 10,
                          top: 10,
                          child: CircleAvatar(
                            backgroundColor: Colors.white,
                            child: scanning
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.edit, size: 18),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
          if (referenceNumber.isNotEmpty)
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Detected reference number',
                prefixIcon: Icon(Icons.verified_outlined),
                filled: true,
                fillColor: Color(0xFFE5F4EA),
              ),
              child: Text(
                referenceNumber,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          if (receiptBytes != null && !scanning && referenceNumber.isEmpty) ...[
            const SizedBox(height: 12),
            TextField(
              controller: referenceController,
              keyboardType: TextInputType.number,
              maxLength: 13,
              decoration: const InputDecoration(
                labelText: 'Reference number (OCR could not read it)',
                helperText: 'Enter exactly 13 digits from your GCash receipt',
                prefixIcon: Icon(Icons.edit_outlined),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ],
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              style: TextStyle(
                color:
                    submitting ||
                        (referenceNumber.isNotEmpty &&
                            !message!.startsWith('StateError') &&
                            !message!.startsWith('Could not'))
                    ? const Color(0xFF08783E)
                    : Colors.red,
              ),
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: scanning || submitting ? null : _submit,
              icon: const Icon(Icons.send),
              label: Text(
                submitting ? 'Submitting...' : 'Submit top-up request',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

class TopUpRequest {
  const TopUpRequest({
    required this.id,
    required this.userId,
    required this.passengerId,
    required this.passengerName,
    required this.amount,
    required this.referenceNumber,
    required this.ocrText,
    required this.status,
    required this.submittedAt,
    required this.screenshotUrl,
    required this.receiptBytes,
    required this.adminNote,
  });

  final String id;
  final String userId;
  final String passengerId;
  final String passengerName;
  final double amount;
  final String referenceNumber;
  final String ocrText;
  final String status;
  final String submittedAt;
  final String screenshotUrl;
  final Uint8List? receiptBytes;
  final String adminNote;

  factory TopUpRequest.fromJson(Map<String, dynamic> json) => TopUpRequest(
    id: '${json['id'] ?? ''}',
    userId: '${json['userId'] ?? ''}',
    passengerId: '${json['passengerId'] ?? json['idNumber'] ?? ''}',
    passengerName: '${json['passengerName'] ?? ''}',
    amount:
        (json['amount'] as num?)?.toDouble() ??
        double.tryParse('${json['amount']}') ??
        0,
    referenceNumber: '${json['referenceNumber'] ?? json['reference'] ?? ''}',
    ocrText: '${json['ocrText'] ?? ''}',
    status: '${json['status'] ?? 'pending'}',
    submittedAt: '${json['submittedAt'] ?? ''}',
    screenshotUrl: '${json['screenshotUrl'] ?? ''}',
    receiptBytes: json['receiptBytes'] is Blob
        ? (json['receiptBytes'] as Blob).bytes
        : null,
    adminNote: '${json['adminNote'] ?? ''}',
  );
}

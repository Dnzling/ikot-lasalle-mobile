import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'download.dart';

class ExportService {
  const ExportService._();

  static Future<void> excel({
    required String fileName,
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final workbook = Excel.createExcel();
    final sheet = workbook['Report'];
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    for (final row in rows) {
      sheet.appendRow(row.map(TextCellValue.new).toList());
    }
    final bytes = workbook.encode();
    if (bytes == null) throw StateError('Could not create the Excel file.');
    downloadBytes(
      Uint8List.fromList(bytes),
      fileName.endsWith('.xlsx') ? fileName : '$fileName.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  static Future<void> pdf({
    required String fileName,
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (_) => [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.all(5),
            border: pw.TableBorder.all(color: PdfColors.grey300),
          ),
        ],
      ),
    );
    downloadBytes(
      Uint8List.fromList(await document.save()),
      fileName.endsWith('.pdf') ? fileName : '$fileName.pdf',
      'application/pdf',
    );
  }
}

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List?> pickExcelBytes() async {
  final input = html.FileUploadInputElement()..accept = '.xlsx';
  input.click();
  await input.onChange.first;
  final file = input.files?.firstOrNull;
  if (file == null) return null;
  final reader = html.FileReader()..readAsArrayBuffer(file);
  await reader.onLoad.first;
  final result = reader.result;
  if (result is ByteBuffer) return result.asUint8List();
  if (result is Uint8List) return result;
  throw StateError('Could not read the selected Excel file.');
}

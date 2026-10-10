import 'package:admin_page/src/screens/reports_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('report rows match the header count', (tester) async {
    final cells = normalizeReportCells(const [
      'id',
      'user',
      'type',
      'title',
      'amount',
      'reference',
    ], 7);
    expect(cells, hasLength(7));
    expect(cells.last, isEmpty);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: List.generate(
                7,
                (index) => DataColumn(label: Text('Column $index')),
              ),
              rows: [
                DataRow(
                  cells: cells.map((cell) => DataCell(Text(cell))).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}

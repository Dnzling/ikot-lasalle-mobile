import 'package:flutter/material.dart';

class TablePagination extends StatelessWidget {
  const TablePagination({
    required this.totalRows,
    required this.page,
    required this.rowsPerPage,
    required this.onPageChanged,
    required this.onRowsPerPageChanged,
    super.key,
  });

  final int totalRows;
  final int page;
  final int rowsPerPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRowsPerPageChanged;

  @override
  Widget build(BuildContext context) {
    final pageCount = totalRows == 0
        ? 1
        : (totalRows + rowsPerPage - 1) ~/ rowsPerPage;
    final current = page.clamp(0, pageCount - 1);
    final first = totalRows == 0 ? 0 : current * rowsPerPage + 1;
    final last = (current * rowsPerPage + rowsPerPage).clamp(0, totalRows);
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        const Text('Rows per page:'),
        DropdownButton<int>(
          value: rowsPerPage,
          items: const [15, 25, 50]
              .map(
                (count) =>
                    DropdownMenuItem(value: count, child: Text('$count')),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onRowsPerPageChanged(value);
          },
        ),
        Text('$first–$last of $totalRows'),
        IconButton(
          tooltip: 'Previous page',
          onPressed: current == 0 ? null : () => onPageChanged(current - 1),
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: 'Next page',
          onPressed: current >= pageCount - 1
              ? null
              : () => onPageChanged(current + 1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

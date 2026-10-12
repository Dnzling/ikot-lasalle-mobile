import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import '../services/export_service.dart';
import '../services/firebase_service.dart';
import '../services/pick_excel.dart';
import '../widgets/common.dart';
import '../widgets/table_pagination.dart';

typedef AppUser = ({
  String first,
  String last,
  String id,
  String type,
  String contact,
});

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  static const _headers = ['First name', 'Last name', 'ID number', 'User type'];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;
  final users = <AppUser>[];
  final searchController = TextEditingController();
  String searchQuery = '';
  int page = 0;
  int rowsPerPage = 15;
  bool importing = false;
  String? importStatus;

  @override
  void initState() {
    super.initState();
    subscription = FirebaseService.instance.watch('users').listen((snapshot) {
      if (!mounted) return;
      setState(() {
        users
          ..clear()
          ..addAll(
            snapshot.docs.map((doc) {
              final data = doc.data();
              return (
                first: data['firstName'] as String? ?? '',
                last: data['lastName'] as String? ?? '',
                id: data['idNumber'] as String? ?? '',
                type: data['userType'] as String? ?? 'Student',
                contact: data['contactNumber'] as String? ?? '',
              );
            }),
          );
      });
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    searchController.dispose();
    super.dispose();
  }

  void _create() {
    final first = TextEditingController();
    final last = TextEditingController();
    final id = TextEditingController();
    var type = 'Student';
    showFormDialog(
      context,
      title: 'Create user account',
      action: 'Create account',
      fields: [
        FormFieldBox('First name', controller: first),
        FormFieldBox('Last name', controller: last),
        FormFieldBox('Passenger ID number', controller: id),
        DropdownButtonFormField<String>(
          initialValue: 'Student',
          decoration: const InputDecoration(labelText: 'User type'),
          items: const [
            DropdownMenuItem(value: 'Student', child: Text('Student')),
            DropdownMenuItem(value: 'Teacher', child: Text('Teacher')),
            DropdownMenuItem(value: 'Visitor', child: Text('Visitor')),
            DropdownMenuItem(value: 'Staff', child: Text('Staff')),
          ],
          onChanged: (value) => type = value ?? 'Student',
        ),
        const Text(
          'Initial password: LAST NAME in uppercase.',
          style: TextStyle(
            color: Color(0xFF08783E),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
      onSave: () => unawaited(
        _saveUser({
          'firstName': first.text,
          'lastName': last.text,
          'idNumber': id.text,
          'userType': type,
        }),
      ),
    );
  }

  Future<void> _saveUser(Map<String, dynamic> data) async {
    try {
      await FirebaseService.instance.createUserAccount(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passenger account created.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create account: $error')),
        );
      }
    }
  }

  Future<void> _exportUsers() async {
    try {
      await ExportService.excel(
        fileName: 'passenger_users.xlsx',
        title: 'Passenger users',
        headers: _headers,
        rows: users.map((u) => [u.first, u.last, u.id, u.type]).toList(),
      );
    } catch (error) {
      if (mounted) _notice('Could not export users: $error');
    }
  }

  String _cell(List<Data?> row, int index) {
    if (index >= row.length) return '';
    final value = row[index]?.value;
    if (value is TextCellValue) return value.value.toString().trim();
    return value?.toString().trim() ?? '';
  }

  Future<void> _importUsers() async {
    if (importing) return;
    try {
      final bytes = await pickExcelBytes();
      if (bytes == null) return;
      final workbook = Excel.decodeBytes(bytes);
      final sheet =
          workbook.tables['Report'] ??
          workbook.tables.values
              .where((table) => table.rows.isNotEmpty)
              .firstOrNull;
      if (sheet == null ||
          sheet.rows.isEmpty ||
          List.generate(
                _headers.length,
                (i) => _cell(sheet.rows.first, i),
              ).join('|').toLowerCase() !=
              _headers.join('|').toLowerCase()) {
        throw const FormatException(
          'Use the exported Excel format: First name, Last name, ID number, User type.',
        );
      }
      final entries = <Map<String, dynamic>>[];
      final errors = <String>[];
      final seen = <String>{};
      for (var i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        final values = List.generate(_headers.length, (j) => _cell(row, j));
        if (values.every((v) => v.isEmpty)) continue;
        final [first, last, id, type] = values;
        if (first.isEmpty ||
            last.isEmpty ||
            id.isEmpty ||
            !const {'Student', 'Teacher', 'Visitor', 'Staff'}.contains(type)) {
          errors.add('Row ${i + 1}: missing field or invalid user type');
          continue;
        }
        if (!seen.add(id.toUpperCase()) ||
            users.any((u) => u.id.toUpperCase() == id.toUpperCase())) {
          errors.add('Row ${i + 1}: duplicate ID $id');
          continue;
        }
        entries.add({
          'firstName': first,
          'lastName': last,
          'idNumber': id,
          'userType': type,
        });
      }
      if (entries.isEmpty) {
        _notice(
          errors.isEmpty
              ? 'No users found in the file.'
              : errors.take(3).join('\n'),
        );
        return;
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import passenger accounts?'),
          content: Text(
            '${entries.length} account(s) will be created. ${errors.length} row(s) will be skipped. '
            'Each initial password is the last name in uppercase, with a required change at first login.'
            '${errors.isEmpty ? '' : '\n\n${errors.take(5).join('\n')}'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() {
        importing = true;
        importStatus = 'Creating 0 of ${entries.length} accounts...';
      });
      var created = 0;
      for (final entry in entries) {
        try {
          await FirebaseService.instance.createUserAccount(entry);
          created++;
        } catch (error) {
          errors.add('${entry['idNumber']}: $error');
        }
        if (mounted) {
          setState(
            () => importStatus =
                'Created $created of ${entries.length} accounts...',
          );
        }
      }
      if (mounted) {
        setState(() {
          importing = false;
          importStatus = null;
        });
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Import complete'),
            content: SingleChildScrollView(
              child: Text(
                '$created created, ${errors.length} skipped or failed.'
                '${errors.isEmpty ? '' : '\n\n${errors.join('\n')}'}',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          importing = false;
          importStatus = null;
        });
        _notice('Could not import users: $error');
      }
    }
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final query = searchQuery.trim().toLowerCase();
    final filtered = users.where((user) {
      if (query.isEmpty) return true;
      final name = '${user.first} ${user.last}'.toLowerCase();
      return name.contains(query) ||
          user.id.toLowerCase().contains(query) ||
          user.contact.toLowerCase().contains(query);
    }).toList();
    final lastPage = filtered.isEmpty
        ? 0
        : (filtered.length - 1) ~/ rowsPerPage;
    final currentPage = page.clamp(0, lastPage);
    final visible = filtered.skip(currentPage * rowsPerPage).take(rowsPerPage);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          PageIntro(
            title: 'Users',
            subtitle: 'Manage passenger accounts and account access.',
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: importing ? null : _exportUsers,
                  icon: const Icon(Icons.download),
                  label: const Text('Export Excel / template'),
                ),
                OutlinedButton.icon(
                  onPressed: importing ? null : _importUsers,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import Excel'),
                ),
                FilledButton.icon(
                  onPressed: importing ? null : _create,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Create account'),
                ),
              ],
            ),
          ),
          if (importStatus != null) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            Text(importStatus!),
          ],
          const SizedBox(height: 22),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    onChanged: (value) => setState(() {
                      searchQuery = value;
                      page = 0;
                    }),
                    decoration: InputDecoration(
                      labelText: 'Search users',
                      hintText: 'Name, ID number, or contact',
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
                  const Row(
                    children: [
                      Expanded(child: Text('Full name', style: _head)),
                      Expanded(child: Text('ID number', style: _head)),
                      Expanded(child: Text('User type', style: _head)),
                      Expanded(child: Text('Contact', style: _head)),
                      Expanded(child: Text('Password policy', style: _head)),
                    ],
                  ),
                  const Divider(),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No users match your search.'),
                    ),
                  for (final user in visible)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${user.first} ${user.last}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(child: Text(user.id)),
                          Expanded(child: StatusPill(user.type)),
                          Expanded(child: Text(user.contact)),
                          const Expanded(child: Text('Change on first login')),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  TablePagination(
                    totalRows: filtered.length,
                    page: currentPage,
                    rowsPerPage: rowsPerPage,
                    onPageChanged: (value) => setState(() => page = value),
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
  }
}

const _head = TextStyle(
  fontSize: 11,
  color: Colors.black45,
  fontWeight: FontWeight.w800,
);

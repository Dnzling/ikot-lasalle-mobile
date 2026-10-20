import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/export_service.dart';
import '../services/firebase_service.dart';
import '../services/pick_excel.dart';
import '../widgets/common.dart';
import '../widgets/table_pagination.dart';

typedef AppUser = ({
  String uid,
  String first,
  String last,
  String id,
  String type,
  String contact,
  bool active,
  bool archived,
  String inactiveReason,
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
  final selectedIds = <String>{};
  bool bulkSaving = false;
  bool showArchived = false;

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
                uid: doc.id,
                first: data['firstName'] as String? ?? '',
                last: data['lastName'] as String? ?? '',
                id: data['idNumber'] as String? ?? '',
                type: data['userType'] as String? ?? 'Student',
                contact: data['contactNumber'] as String? ?? '',
                active: data['active'] != false,
                archived: data['archived'] == true ||
                    (data['active'] == false && data['inactiveReason'] == 'Graduated'),
                inactiveReason: '${data['inactiveReason'] ?? ''}',
              );
            }),
          );
        selectedIds.removeWhere(
          (id) => !users.any((u) => u.uid == id && !u.archived),
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
      onSave: () {
        final cleanId = id.text.trim().toUpperCase();
        if (!validPassengerIdNumber(cleanId)) {
          _notice('Passenger ID number must be exactly 9 digits.');
          return;
        }
        if (users.any((user) => user.id.trim().toUpperCase() == cleanId)) {
          _notice('Passenger ID number is already registered.');
          return;
        }
        unawaited(
          _saveUser({
            'firstName': first.text,
            'lastName': last.text,
            'idNumber': id.text,
            'userType': type,
          }),
        );
      },
      fields: [
        FormFieldBox(
          'First name',
          controller: first,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[0-9]'))],
        ),
        FormFieldBox(
          'Last name',
          controller: last,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[0-9]'))],
        ),
        FormFieldBox(
          'Passenger ID number',
          controller: id,
          maxLength: passengerIdNumberLength,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
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
          'Initial password: LAST NAME in uppercase. Names shorter than 6 characters are padded with 0.',
          style: TextStyle(
            color: Color(0xFF08783E),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  void _edit(AppUser user) {
    final first = TextEditingController(text: user.first);
    final last = TextEditingController(text: user.last);
    final id = TextEditingController(text: user.id);
    final contact = TextEditingController(text: user.contact);
    var type = user.type;
    showFormDialog(
      context,
      title: 'Edit passenger account',
      action: 'Save changes',
      fields: [
        FormFieldBox(
          'First name',
          controller: first,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[0-9]'))],
        ),
        FormFieldBox(
          'Last name',
          controller: last,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[0-9]'))],
        ),
        FormFieldBox(
          'Passenger ID number',
          controller: id,
          maxLength: passengerIdNumberLength,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        FormFieldBox('Contact number', controller: contact),
        DropdownButtonFormField<String>(
          initialValue:
              const {'Student', 'Teacher', 'Visitor', 'Staff'}.contains(type)
              ? type
              : 'Student',
          decoration: const InputDecoration(labelText: 'User type'),
          items: const [
            DropdownMenuItem(value: 'Student', child: Text('Student')),
            DropdownMenuItem(value: 'Teacher', child: Text('Teacher')),
            DropdownMenuItem(value: 'Visitor', child: Text('Visitor')),
            DropdownMenuItem(value: 'Staff', child: Text('Staff')),
          ],
          onChanged: (value) => type = value ?? 'Student',
        ),
      ],
      onSave: () {
        if (!validPassengerIdNumber(id.text)) {
          _notice('Passenger ID number must be exactly 9 digits.');
          return;
        }
        unawaited(
          _saveEdit(user.uid, {
            'firstName': first.text,
            'lastName': last.text,
            'idNumber': id.text,
            'contactNumber': contact.text,
            'userType': type,
          }),
        );
      },
    );
  }

  Future<void> _saveEdit(String uid, Map<String, dynamic> data) async {
    try {
      await FirebaseService.instance.updatePassengerAccount(
        userId: uid,
        data: data,
      );
      if (mounted) _notice('Passenger account updated.');
    } catch (error) {
      if (mounted) _notice('Could not update account: $error');
    }
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
      await ExportService.pdf(
        fileName: 'passenger_users.pdf',
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
        if (!validPassengerIdNumber(id)) {
          errors.add('Row ${i + 1}: ID number must be exactly 9 digits');
          continue;
        }
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

  Future<void> _bulkArchive() async {
    final selected = users
        .where((u) => selectedIds.contains(u.uid) && !u.archived)
        .toList();
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
          title: const Text('Archive selected users?'),
          content: Text(
            '${selected.length} account(s) will lose access. Their history will remain and they can be restored later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Archive'),
            ),
          ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => bulkSaving = true);
    try {
      final count = await FirebaseService.instance.archivePassengers(
        selected.map((u) => u.uid).toList(),
      );
      if (mounted) {
        setState(selectedIds.clear);
        _notice('$count account(s) archived.');
      }
    } catch (error) {
      if (mounted) _notice('Could not archive users: $error');
    } finally {
      if (mounted) setState(() => bulkSaving = false);
    }
  }

  Future<void> _restore(AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore account?'),
        content: Text('Restore ${user.first} ${user.last} as ${user.type}? '
            'To restore a graduate as a visitor, edit the user type to Visitor first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseService.instance.restorePassenger(user.uid);
      if (mounted) _notice('Account restored. The user can sign in again.');
    } catch (error) {
      if (mounted) _notice('Could not restore account: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = searchQuery.trim().toLowerCase();
    final filtered = users.where((user) {
      if (user.archived != showArchived) return false;
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
                  label: const Text('Export PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: importing ? null : _importUsers,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: bulkSaving || selectedIds.isEmpty || showArchived
                      ? null
                      : _bulkArchive,
                  icon: const Icon(Icons.archive_outlined),
                  label: Text('Archive selected (${selectedIds.length})'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() { showArchived = !showArchived; page = 0; selectedIds.clear(); }),
                  icon: Icon(showArchived ? Icons.people_outline : Icons.archive_outlined),
                  label: Text(showArchived ? 'Show active users' : 'Show archive'),
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
                  Row(
                    children: [
                      const SizedBox(width: 96),
                      Expanded(flex: 3, child: Text('Full name', style: _head)),
                      Expanded(child: Text('ID number', style: _head)),
                      Expanded(child: Text('User type', style: _head)),
                      Expanded(child: Text('Contact', style: _head)),
                      Expanded(child: Text('Password policy', style: _head)),
                      const Expanded(child: Text('Status', style: _head)),
                      const SizedBox(width: 96),
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
                          SizedBox(
                            width: 48,
                            child: Checkbox(
                              value: selectedIds.contains(user.uid),
                              onChanged: !user.archived && !bulkSaving
                                  ? (value) => setState(() {
                                      if (value == true) {
                                        selectedIds.add(user.uid);
                                      } else {
                                        selectedIds.remove(user.uid);
                                      }
                                    })
                                  : null,
                            ),
                          ),
                          Expanded(
                            flex: 3,
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
                          Expanded(
                            child: Text(
                              user.archived
                                  ? 'Archived'
                                  : user.active
                                  ? 'Active'
                                  : user.inactiveReason.isEmpty
                                  ? 'Inactive'
                                  : user.inactiveReason,
                            ),
                          ),
                          SizedBox(
                            width: 96,
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'Edit user',
                                  onPressed: () => _edit(user),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                if (user.archived)
                                  IconButton(
                                    tooltip: 'Restore user',
                                    onPressed: () => _restore(user),
                                    icon: const Icon(Icons.unarchive_outlined),
                                  ),
                              ],
                            ),
                          ),
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

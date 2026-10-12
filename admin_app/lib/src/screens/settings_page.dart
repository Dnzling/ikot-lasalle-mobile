import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../widgets/common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final first = TextEditingController();
  final last = TextEditingController();
  final idNumber = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool saving = false;
  String? message;

  @override
  void dispose() {
    first.dispose();
    last.dispose();
    idNumber.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (first.text.trim().isEmpty ||
        last.text.trim().isEmpty ||
        idNumber.text.trim().isEmpty ||
        email.text.trim().isEmpty ||
        password.text.length < 6) {
      setState(
        () => message =
            'Enter both names, an ID number, an email, and a password of at least 6 characters.',
      );
      return;
    }
    setState(() {
      saving = true;
      message = null;
    });
    try {
      await FirebaseService.instance.createAdditionalAdmin(
        first.text,
        last.text,
        idNumber.text,
        email.text,
        password.text,
      );
      if (mounted) {
        setState(() {
          message = 'Admin account created.';
          first.clear();
          last.clear();
          idNumber.clear();
          email.clear();
          password.clear();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => message = 'Could not create admin: $error');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageIntro(
          title: 'Settings',
          subtitle: 'Temporary admin account creation.',
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 480,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add admin',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: first,
                    decoration: const InputDecoration(labelText: 'First name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: last,
                    decoration: const InputDecoration(labelText: 'Last name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: idNumber,
                    decoration: const InputDecoration(labelText: 'ID number'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: 16),
                  if (message != null) Text(message!),
                  FilledButton(
                    onPressed: saving ? null : _create,
                    child: Text(saving ? 'Creating...' : 'Create admin'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

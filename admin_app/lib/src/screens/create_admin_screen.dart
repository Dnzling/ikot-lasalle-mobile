import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/firebase_service.dart';
import 'shell_screen.dart';

class CreateAdminScreen extends StatefulWidget {
  const CreateAdminScreen({super.key});

  @override
  State<CreateAdminScreen> createState() => _CreateAdminScreenState();
}

class _CreateAdminScreenState extends State<CreateAdminScreen> {
  final _id = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _checking = true;
  bool _available = false;
  bool _hidePassword = true;
  bool _hideConfirm = true;
  String? _setupError;

  @override
  void initState() {
    super.initState();
    _refreshAvailability();
  }

  @override
  void dispose() {
    _id.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _refreshAvailability() async {
    try {
      final available = await FirebaseService.instance.canCreateInitialAdmin();
      if (mounted) setState(() => _available = available);
    } on FirebaseException catch (error) {
      if (mounted) setState(() => _setupError = error.message ?? error.code);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _create() async {
    final id = _id.text.trim();
    final password = _password.text;
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(id)) {
      _show('Enter an ID using letters and numbers only.');
      return;
    }
    if (password.length < 6) {
      _show('Password must contain at least 6 characters.');
      return;
    }
    if (password != _confirm.text) {
      _show('Passwords do not match.');
      return;
    }

    setState(() => _loading = true);
    try {
      await FirebaseService.instance.createInitialAdmin(
        idNumber: id,
        password: password,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AdminShell()),
        (_) => false,
      );
    } on FirebaseAuthException catch (error) {
      _show(switch (error.code) {
        'configuration-not-found' =>
          'Firebase Authentication is not initialized for ikot-lasalle-2bed1. Open Firebase Console → Authentication → Get started, then enable Email/Password.',
        'operation-not-allowed' =>
          'Enable Email/Password sign-in in Firebase Authentication, then try again.',
        'email-already-in-use' =>
          'This ID already has an Authentication account. Contact the system administrator.',
        'weak-password' => 'Choose a stronger password (at least 6 characters).',
        'network-request-failed' => 'Check the internet connection and try again.',
        _ => 'Could not create account: ${error.message ?? error.code}',
      });
    } on FirebaseException catch (error) {
      _show(error.code == 'permission-denied'
          ? 'Admin setup is blocked by the Firestore rules. Publish the latest rules and retry.'
          : 'Could not save the admin account: ${error.message ?? error.code}');
      await _refreshAvailability();
    } catch (error) {
      _show('Could not create account: ${error.toString().replaceFirst('Exception: ', '')}');
      await _refreshAvailability();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Create admin account')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _checking
                    ? const Center(child: CircularProgressIndicator())
                    : !_available
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _setupError == null
                                    ? 'Admin setup is already complete.'
                                    : 'Could not check admin setup.',
                                style: theme.textTheme.titleLarge,
                              ),
                              if (_setupError != null) ...[
                                const SizedBox(height: 8),
                                Text(_setupError!),
                              ],
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Set up the first admin account',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'This one-time setup closes after the account is created.',
                              ),
                              const SizedBox(height: 24),
                              TextField(
                                controller: _id,
                                keyboardType: TextInputType.text,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[A-Za-z0-9]'),
                                  ),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'ID',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _password,
                                obscureText: _hidePassword,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(
                                      () => _hidePassword = !_hidePassword,
                                    ),
                                    icon: Icon(_hidePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _confirm,
                                obscureText: _hideConfirm,
                                onSubmitted: (_) => _create(),
                                decoration: InputDecoration(
                                  labelText: 'Confirm password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(
                                      () => _hideConfirm = !_hideConfirm,
                                    ),
                                    icon: Icon(_hideConfirm
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                height: 48,
                                child: FilledButton(
                                  onPressed: _loading ? null : _create,
                                  child: _loading
                                      ? const SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Create admin account'),
                                ),
                              ),
                            ],
                          ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

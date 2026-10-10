import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_session.dart';
import '../services/passenger_firebase_service.dart';
import '../services/password_policy.dart';

class ProfileChangePasswordScreen extends StatefulWidget {
  const ProfileChangePasswordScreen({required this.session, super.key});

  final AppSession session;

  @override
  State<ProfileChangePasswordScreen> createState() =>
      _ProfileChangePasswordScreenState();
}

class _ProfileChangePasswordScreenState
    extends State<ProfileChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();
  final _newPasswordKey = GlobalKey<FormFieldState<String>>();
  final _confirmPasswordKey = GlobalKey<FormFieldState<String>>();
  bool _saving = false;
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _current.dispose();
    _newPassword.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await const PassengerFirebaseService().changePassword(
        uid: widget.session.uid,
        currentPassword: _current.text,
        newPassword: _newPassword.text,
        clearMustChangePassword: false,
      );
      if (mounted) Navigator.pop(context, true);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'wrong-password' ||
        'invalid-credential' => 'Your current password is incorrect.',
        'requires-recent-login' =>
          'Please sign out and sign in again before changing your password.',
        _ => error.message ?? 'Could not change your password.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Change password')),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Secure your account',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your current password, then create and confirm a new one.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _current,
              obscureText: !_showCurrent,
              autofillHints: const [AutofillHints.password],
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your current password.'
                  : null,
              decoration: InputDecoration(
                labelText: 'Current password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _showCurrent ? 'Hide password' : 'Show password',
                  onPressed: () => setState(() => _showCurrent = !_showCurrent),
                  icon: Icon(
                    _showCurrent
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Focus(
              onFocusChange: (focused) {
                if (!focused) _newPasswordKey.currentState?.validate();
              },
              child: TextFormField(
                key: _newPasswordKey,
                controller: _newPassword,
                obscureText: !_showNew,
                autofillHints: const [AutofillHints.newPassword],
                validator: (value) {
                  final error = PasswordPolicy.validate(value);
                  if (error != null) return error;
                  if (value == _current.text) {
                    return 'Choose a password different from your current one.';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  labelText: 'New password',
                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                  suffixIcon: IconButton(
                    tooltip: _showNew ? 'Hide password' : 'Show password',
                    onPressed: () => setState(() => _showNew = !_showNew),
                    icon: Icon(
                      _showNew
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Focus(
              onFocusChange: (focused) {
                if (!focused) _confirmPasswordKey.currentState?.validate();
              },
              child: TextFormField(
                key: _confirmPasswordKey,
                controller: _confirm,
                obscureText: !_showConfirm,
                autofillHints: const [AutofillHints.newPassword],
                validator: (value) => value != _newPassword.text
                    ? 'Passwords do not match.'
                    : null,
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: const Icon(Icons.verified_user_outlined),
                  suffixIcon: IconButton(
                    tooltip: _showConfirm ? 'Hide password' : 'Show password',
                    onPressed: () =>
                        setState(() => _showConfirm = !_showConfirm),
                    icon: Icon(
                      _showConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save new password'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

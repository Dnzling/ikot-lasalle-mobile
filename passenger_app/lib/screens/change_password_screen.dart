import 'package:flutter/material.dart';

import '../models/app_session.dart';
import '../services/passenger_firebase_service.dart';
import '../services/password_policy.dart';
import 'passenger_shell.dart';
import 'session_guard.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({required this.session, super.key});
  final AppSession session;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final formKey = GlobalKey<FormState>();
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();
  final newPasswordKey = GlobalKey<FormFieldState<String>>();
  final confirmPasswordKey = GlobalKey<FormFieldState<String>>();
  bool loading = false;
  bool obscurePassword = true;
  bool obscureConfirm = true;

  @override
  void dispose() {
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!formKey.currentState!.validate() || loading) return;
    setState(() => loading = true);
    try {
      await const PassengerFirebaseService().changePassword(
        uid: widget.session.uid,
        newPassword: passwordController.text,
      );
      widget.session.updatePassenger(
        widget.session.passenger.copyWith(mustChangePassword: false),
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => SessionGuard(
            session: widget.session,
            child: PassengerShell(session: widget.session),
          ),
        ),
        (_) => false,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Change your password'),
      ),
      body: SafeArea(
        child: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              const SizedBox(height: 54),
              const Icon(
                Icons.lock_reset_outlined,
                color: Color(0xFF62A77D),
                size: 62,
              ),
              const SizedBox(height: 24),
              const Text(
                'Set a new password',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your account is using its default password. Create a new password before continuing.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 34),
              Focus(
                onFocusChange: (focused) {
                  if (!focused) newPasswordKey.currentState?.validate();
                },
                child: TextFormField(
                  key: newPasswordKey,
                  controller: passwordController,
                  validator: PasswordPolicy.validate,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => obscurePassword = !obscurePassword),
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Focus(
                onFocusChange: (focused) {
                  if (!focused) confirmPasswordKey.currentState?.validate();
                },
                child: TextFormField(
                  key: confirmPasswordKey,
                  controller: confirmController,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Confirm your new password.';
                    }
                    if (value != passwordController.text) {
                      return 'Passwords do not match.';
                    }
                    return null;
                  },
                  obscureText: obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => obscureConfirm = !obscureConfirm),
                      icon: Icon(
                        obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: loading ? null : _changePassword,
                  child: loading
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save new password'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

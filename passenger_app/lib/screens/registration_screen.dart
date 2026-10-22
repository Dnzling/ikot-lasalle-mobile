import 'package:flutter/material.dart';

import '../services/passenger_firebase_service.dart';
import 'passenger_shell.dart';
import 'session_guard.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final formKey = GlobalKey<FormState>();
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final idNumberController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  bool loading = false;

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    idNumberController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> register() async {
    if (!formKey.currentState!.validate() || loading) return;
    setState(() => loading = true);
    try {
      final session = await const PassengerFirebaseService().register(
        firstName: firstNameController.text,
        lastName: lastNameController.text,
        idNumber: idNumberController.text,
        phone: phoneController.text,
        password: passwordController.text,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => SessionGuard(
            session: session,
            child: PassengerShell(session: session),
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

  String? requiredField(String? value) {
    return value == null || value.trim().isEmpty
        ? 'This field is required'
        : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Join Ikot',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create your passenger account to start booking rides.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: _field(
                    firstNameController,
                    'First name',
                    Icons.person_outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    lastNameController,
                    'Last name',
                    Icons.person_outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _field(
              idNumberController,
              'ID number',
              Icons.badge_outlined,
              keyboard: TextInputType.number,
              maxLength: 9,
            ),
            const SizedBox(height: 16),
            _field(
              phoneController,
              'Phone number',
              Icons.phone_outlined,
              keyboard: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            _field(
              passwordController,
              'Password',
              Icons.lock_outline,
              obscure: true,
              validator: (value) {
                final requiredError = requiredField(value);
                if (requiredError != null) return requiredError;
                return value!.length < 8
                    ? 'Password must contain at least 8 characters'
                    : null;
              },
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: loading ? null : register,
                child: loading
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Create account',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Already have an account? Sign in'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboard,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      maxLength: maxLength,
      validator: validator ?? requiredField,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        counterText: maxLength == null ? null : '',
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/passenger_firebase_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _id = TextEditingController();
  final _contact = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _id.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await const PassengerFirebaseService().requestPasswordReset(
        firstName: _first.text,
        lastName: _last.text,
        idNumber: _id.text,
        contactNumber: _contact.text,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Request submitted'),
          content: const Text(
            'Visit the admin office with your ID. Staff will verify your details and provide a temporary password. You must change it when you sign in.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit request: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Forgot password')),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Request a password reset',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your registered details. Admin staff will verify them before resetting your password.',
            ),
            const SizedBox(height: 24),
            _field(_first, 'First name'),
            _field(_last, 'Last name'),
            _field(_id, 'ID number'),
            _field(
              _contact,
              'Contact number',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(
                _submitting ? 'Submitting...' : 'Submit reset request',
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: keyboardType == null
          ? TextCapitalization.words
          : TextCapitalization.none,
      validator: (value) =>
          value == null || value.trim().isEmpty ? '$label is required.' : null,
      decoration: InputDecoration(labelText: label),
    ),
  );
}

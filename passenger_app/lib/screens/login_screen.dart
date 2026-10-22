import 'package:flutter/material.dart';

import '../services/passenger_firebase_service.dart';
import 'change_password_screen.dart';
import 'forgot_password_screen.dart';
import 'passenger_shell.dart';
import 'session_guard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final formKey = GlobalKey<FormState>();
  final idNumberController = TextEditingController();
  final passwordController = TextEditingController();
  bool loading = false;
  bool obscure = true;

  @override
  void dispose() {
    idNumberController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    if (!formKey.currentState!.validate() || loading) return;
    setState(() => loading = true);
    try {
      final session = await const PassengerFirebaseService().login(
        idNumberController.text,
        passwordController.text,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SessionGuard(
            session: session,
            child: session.passenger.mustChangePassword
                ? ChangePasswordScreen(session: session)
                : PassengerShell(session: session),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        if (error is NewDeviceDetectedException) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('New Device Detected, Logging Out'),
              content: const Text(
                'Another device was already signed in. Both sessions have been signed out. Please log in again.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String? validateRequired(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const SizedBox(height: 70),
            Image.asset(
              'assets/branding/jeep_launcher.png',
              width: 88,
              height: 88,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 28),
            const Text(
              'Welcome to Ikot',
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
            ),
            const Text(
              'Sign in using your registered passenger account.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 48),
            TextFormField(
              controller: idNumberController,
              validator: validateRequired,
              keyboardType: TextInputType.number,
              maxLength: 9,
              decoration: const InputDecoration(
                labelText: 'ID number',
                prefixIcon: Icon(Icons.badge_outlined),
                filled: true,
                fillColor: Colors.white,
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: passwordController,
              validator: validateRequired,
              obscureText: obscure,
              onFieldSubmitted: (_) => signIn(),
              decoration: InputDecoration(
                labelText: 'Password',
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => obscure = !obscure),
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined, // ✅ Fixed
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: loading ? null : signIn,
                child: loading
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sign in'),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: loading
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ForgotPasswordScreen(),
                        ),
                      ),
                child: const Text('Forgot password?'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

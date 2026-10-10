import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_service.dart';
import 'shell_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool register = false, obscure = true;
  bool loading = false;
  final first = TextEditingController();
  final last = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();

  Future<void> _submit() async {
    setState(() => loading = true);
    try {
      if (register) {
        await FirebaseService.instance.registerAdmin(
          first.text,
          last.text,
          email.text,
          password.text,
        );
      } else {
        await FirebaseService.instance.signIn(email.text, password.text);
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminShell()),
        );
      }
    } on AdminProfileWriteException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Account created, but Firestore could not save the admin profile (${error.code}). Check Firestore rules.',
            ),
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminShell()),
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_authMessage(error))));
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Firebase ${error.code}: ${error.message ?? 'request failed'}',
            ),
          ),
        );
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(error))));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _message(Object error) {
    final text = error.toString();
    if (text.contains('invalid-credential')) {
      return 'Incorrect email or password.';
    }
    if (text.contains('email-already-in-use')) {
      return 'That email already has an account.';
    }
    if (text.contains('weak-password')) {
      return 'Use a password with at least 6 characters.';
    }
    return 'Registration failed: $error';
  }

  String _authMessage(FirebaseAuthException error) => switch (error.code) {
    'invalid-email' => 'Enter a valid email address.',
    'email-already-in-use' =>
      'That email already has an account. Try signing in instead.',
    'weak-password' => 'Use a password with at least 6 characters.',
    'operation-not-allowed' =>
      'Email/Password sign-in is disabled in Firebase Authentication.',
    'network-request-failed' =>
      'Firebase could not reach the network. Check your connection.',
    'invalid-api-key' =>
      'The Firebase API key is invalid or restricted for this app.',
    'invalid-credential' => 'Incorrect email or password.',
    _ => 'Firebase Auth ${error.code}: ${error.message ?? 'request failed'}',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            flex: 6,
            child: Container(
              padding: const EdgeInsets.all(64),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF075B34), Color(0xFF0A8A4B)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Brand(light: true),
                  const Spacer(),
                  Text(
                    'Move smarter.\nManage better.',
                    style: theme.textTheme.displayMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'One command center for La Salle campus transport.',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 48),
                  const Wrap(
                    spacing: 28,
                    runSpacing: 16,
                    children: [
                      _Feature(
                        icon: Icons.location_on_outlined,
                        text: 'Live fleet tracking',
                      ),
                      _Feature(
                        icon: Icons.analytics_outlined,
                        text: 'Actionable insights',
                      ),
                      _Feature(
                        icon: Icons.shield_outlined,
                        text: 'Secure operations',
                      ),
                    ],
                  ),
                  const Spacer(),
                  const Text(
                    'IKOT LA SALLE',
                    style: TextStyle(
                      color: Colors.white54,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 72, vertical: 48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Brand(),
                    const SizedBox(height: 56),
                    Text(
                      register ? 'Create admin account' : 'Welcome back',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      register
                          ? 'Enter your details to get started.'
                          : 'Sign in to manage your transport network.',
                      style: const TextStyle(color: Color(0xFF68756E)),
                    ),
                    const SizedBox(height: 32),
                    if (register) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _Field(
                              label: 'First name',
                              icon: Icons.person_outline,
                              controller: first,
                            ),
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: _Field(
                              label: 'Last name',
                              icon: Icons.person_outline,
                              controller: last,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    _Field(
                      label: 'ID Number',
                      icon: Icons.person_outline,
                      controller: email,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: password,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: loading ? null : _submit,
                        child: loading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(register ? 'Create account' : 'Sign in'),
                      ),
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
}

class _Brand extends StatelessWidget {
  const _Brand({this.light = false});
  final bool light;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'IKOT LA SALLE',
        style: TextStyle(
          color: light ? Colors.white : const Color(0xFF164C32),
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    ],
  );
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: Colors.white70),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(color: Colors.white70)),
    ],
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.icon, this.controller});
  final String label;
  final IconData icon;
  final TextEditingController? controller;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
  );
}

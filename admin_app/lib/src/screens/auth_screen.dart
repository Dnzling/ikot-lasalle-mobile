import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_service.dart';
import 'create_admin_screen.dart';
import 'shell_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool obscure = true;
  bool loading = false;
  bool checkingSetup = true;
  bool setupAvailable = false;
  String? setupError;
  final idNumber = TextEditingController();
  final password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkAdminSetup();
  }

  Future<void> _checkAdminSetup() async {
    try {
      final available = await FirebaseService.instance.canCreateInitialAdmin();
      if (mounted) setState(() => setupAvailable = available);
    } on FirebaseException catch (error) {
      if (mounted) setState(() => setupError = error.message ?? error.code);
    } finally {
      if (mounted) setState(() => checkingSetup = false);
    }
  }

  Future<void> _submit() async {
    if (idNumber.text.trim().isEmpty || password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your ID number and password.')),
      );
      return;
    }
    setState(() => loading = true);
    try {
      await FirebaseService.instance.signIn(idNumber.text, password.text);
      if (mounted) {
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
              'Request ${error.code}: ${error.message ?? 'request failed'}',
            ),
          ),
        );
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sign-in failed: $error')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _authMessage(FirebaseAuthException error) => switch (error.code) {
    'invalid-email' => 'Enter a valid email address.',
    'email-already-in-use' =>
      'That email already has an account. Try signing in instead.',
    'weak-password' => 'Use a password with at least 6 characters.',
    'operation-not-allowed' =>
      'Email/Password sign-in is disabled for this app.',
    'network-request-failed' =>
      'The server could not be reached. Check your connection.',
    'invalid-api-key' =>
      'The app key is invalid or restricted for this app.',
    'invalid-credential' => 'Incorrect ID number or password.',
    _ => 'Sign-in ${error.code}: ${error.message ?? 'request failed'}',
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
                      'Welcome back',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in to manage your transport network.',
                      style: const TextStyle(color: Color(0xFF68756E)),
                    ),
                    const SizedBox(height: 32),
                    _Field(
                      label: 'ID number',
                      icon: Icons.badge_outlined,
                      controller: idNumber,
                      keyboardType: TextInputType.text,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9]'),
                        ),
                      ],
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
                            : const Text('Sign in'),
                      ),
                    ),
                    if (setupAvailable) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: loading
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const CreateAdminScreen(),
                                  ),
                                ).then((_) => _checkAdminSetup()),
                          child: const Text('Create first admin account'),
                        ),
                      ),
                    ] else if (!checkingSetup && setupError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Admin setup status unavailable: $setupError',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
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
      Image.asset(
        'assets/branding/jeep_launcher.png',
        width: 32,
        height: 32,
        fit: BoxFit.contain,
      ),
      const SizedBox(width: 10),
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
  const _Field({
    required this.label,
    required this.icon,
    this.controller,
    this.maxLength,
    this.keyboardType,
    this.inputFormatters,
  });
  final String label;
  final IconData icon;
  final TextEditingController? controller;
  final int? maxLength;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    maxLength: maxLength,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
  );
}

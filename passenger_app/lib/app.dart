import 'package:flutter/material.dart';

import 'models/app_session.dart';
import 'screens/change_password_screen.dart';
import 'screens/login_screen.dart';
import 'screens/passenger_shell.dart';
import 'screens/session_guard.dart';
import 'services/passenger_firebase_service.dart';

class IkotApp extends StatelessWidget {
  const IkotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ikot La Salle',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF62A77D)),
        scaffoldBackgroundColor: const Color(0xFFF7F8F6),
        useMaterial3: true,
      ),
      home: const _PassengerStartup(),
    );
  }
}

class _PassengerStartup extends StatefulWidget {
  const _PassengerStartup();

  @override
  State<_PassengerStartup> createState() => _PassengerStartupState();
}

class _PassengerStartupState extends State<_PassengerStartup> {
  late Future<AppSession?> restore;

  @override
  void initState() {
    super.initState();
    restore = const PassengerFirebaseService().restoreSession();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppSession?>(
    future: restore,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Could not restore your session. Check your connection and try again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(() {
                      restore = const PassengerFirebaseService()
                          .restoreSession();
                    }),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      final session = snapshot.data;
      if (session == null) return const LoginScreen();
      return SessionGuard(
        session: session,
        child: session.passenger.mustChangePassword
            ? ChangePasswordScreen(session: session)
            : PassengerShell(session: session),
      );
    },
  );
}

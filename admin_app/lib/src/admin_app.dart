import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:flutter/material.dart';
import 'screens/auth_screen.dart';
import 'screens/shell_screen.dart';
import 'services/firebase_service.dart';

class IkotAdminApp extends StatelessWidget {
  const IkotAdminApp({super.key});
  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF08783E);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ikot LaSalle',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
          surface: const Color(0xFFF7F9F7),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F7F5),
        fontFamily: 'Segoe UI',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE5E0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE5E0)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE5EBE7)),
          ),
        ),
      ),
      home: Firebase.apps.isEmpty
          ? const AuthScreen()
          : StreamBuilder(
              stream: FirebaseService.instance.authChanges,
              builder: (context, snapshot) => snapshot.data == null
                  ? const AuthScreen()
                  : const AdminShell(),
            ),
    );
  }
}

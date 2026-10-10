import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'profile_change_password_screen.dart';
import '../models/app_session.dart';
import '../services/passenger_firebase_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({required this.session, super.key});
  final AppSession session;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) => SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Profile',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 24),
          const CircleAvatar(
            radius: 38,
            backgroundColor: Color(0xFFE1F1E5),
            child: Icon(Icons.person, color: Color(0xFF62A77D), size: 42),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              session.passenger.fullName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const Center(
            child: Text(
              'Passenger account',
              style: TextStyle(color: Colors.black54),
            ),
          ),
          const SizedBox(height: 28),
          _detail(
            'Full name',
            session.passenger.fullName,
            Icons.person_outline,
          ),
          const SizedBox(height: 16),
          _detail(
            'ID number',
            session.passenger.idNumber,
            Icons.badge_outlined,
          ),
          const SizedBox(height: 16),
          _detail(
            'Phone number',
            session.passenger.phone,
            Icons.phone_outlined,
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () async {
              final changed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileChangePasswordScreen(session: session),
                ),
              );
              if (changed == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password changed successfully.'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.lock_reset_outlined),
            label: const Text('Change password'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await const PassengerFirebaseService().signOut(
                uid: session.uid,
                sessionId: session.sessionId,
              );
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ],
      ),
    ),
  );

  Widget _detail(String label, String value, IconData icon) => Card(
    elevation: 0,
    color: Colors.white,
    child: ListTile(
      leading: Icon(icon, color: const Color(0xFF08783E)),
      title: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
      subtitle: Text(
        value.isEmpty ? 'Not available' : value,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

import 'package:flutter/material.dart';

import 'credits_screen.dart';
import 'home_screen.dart';
import 'alerts_screen.dart';
import 'profile_screen.dart';
import '../models/app_session.dart';

class PassengerShell extends StatefulWidget {
  const PassengerShell({required this.session, super.key});
  final AppSession session;

  @override
  State<PassengerShell> createState() => _PassengerShellState();
}

class _PassengerShellState extends State<PassengerShell> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(session: widget.session),
      CreditsScreen(session: widget.session),
      AlertsScreen(session: widget.session),
      ProfileScreen(session: widget.session),
    ];
    return Scaffold(
      body: pages[selected],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (index) => setState(() => selected = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class SimplePassengerScreen extends StatelessWidget {
  final String title;
  final IconData icon;

  const SimplePassengerScreen({
    required this.title,
    required this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF62A77D), size: 52),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

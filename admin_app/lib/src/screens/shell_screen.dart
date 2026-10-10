import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import 'auth_screen.dart';
import 'admin_notifications.dart';
import 'dashboard_page.dart';
import 'drivers_page.dart';
import 'fare_page.dart';
import 'password_resets_page.dart';
import 'routes_page.dart';
import 'reports_page.dart';
import 'settings_page.dart';
import 'top_up_page.dart';
import 'users_page.dart';
import 'vehicles_page.dart';

const _tabs = <({IconData icon, String title, Widget page})>[
  (icon: Icons.grid_view_rounded, title: 'Dashboard', page: DashboardPage()),
  (
    icon: Icons.directions_bus_outlined,
    title: 'Vehicles',
    page: VehiclesPage(),
  ),
  (icon: Icons.badge_outlined, title: 'Drivers', page: DriversPage()),
  (icon: Icons.people_outline, title: 'Users', page: UsersPage()),
  (
    icon: Icons.lock_reset_outlined,
    title: 'Password resets',
    page: PasswordResetsPage(),
  ),
  (
    icon: Icons.account_balance_wallet_outlined,
    title: 'Top-ups',
    page: TopUpPage(),
  ),
  (icon: Icons.alt_route_rounded, title: 'Routes', page: RoutesPage()),
  (icon: Icons.payments_outlined, title: 'Fare settings', page: FarePage()),
  (
    icon: Icons.file_download_outlined,
    title: 'Reports & exports',
    page: ReportsPage(),
  ),
  (icon: Icons.settings_outlined, title: 'Settings', page: SettingsPage()),
];

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final activeIndex = selected.clamp(0, _tabs.length - 1);
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 236,
            color: const Color(0xFF073F28),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(22, 28, 16, 30),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.white,
                        child: Icon(
                          Icons.directions_bus_rounded,
                          color: Color(0xFF08783E),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'IKOT LA SALLE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _tabs.length - 1,
                    itemBuilder: (context, index) => _Nav(
                      icon: _tabs[index].icon,
                      label: _tabs[index].title,
                      active: activeIndex == index,
                      onTap: () => setState(() => selected = index),
                    ),
                  ),
                ),
                const Divider(color: Colors.white12, indent: 16, endIndent: 16),
                _Nav(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  active: selected == _tabs.length - 1,
                  onTap: () => setState(() => selected = _tabs.length - 1),
                ),
                _Nav(
                  icon: Icons.logout_rounded,
                  label: 'Log out',
                  active: false,
                  onTap: () async {
                    await FirebaseService.instance.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const AuthScreen()),
                      );
                    }
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 76,
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Text(
                        _tabs[activeIndex].title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      AdminNotificationButton(
                        onNavigate: (index) => setState(() => selected = index),
                      ),
                      const SizedBox(width: 12),
                      const _CurrentUserBadge(),
                    ],
                  ),
                ),
                Expanded(child: _tabs[activeIndex].page),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentUserBadge extends StatelessWidget {
  const _CurrentUserBadge();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseService.instance.auth.currentUser;
    if (user == null) {
      return const _UserIdentity(name: 'Signed out', role: 'No active session');
    }
    return StreamBuilder(
      stream: FirebaseService.instance.db
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final first = (data?['firstName'] as String? ?? '').trim();
        final last = (data?['lastName'] as String? ?? '').trim();
        final profileName = '$first $last'.trim();
        final name = profileName.isNotEmpty
            ? profileName
            : (user.displayName?.trim().isNotEmpty == true
                  ? user.displayName!.trim()
                  : user.email ?? 'User');
        final role =
            (data?['userType'] as String? ?? data?['role'] as String? ?? 'User')
                .trim();
        return _UserIdentity(name: name, role: role.isEmpty ? 'User' : role);
      },
    );
  }
}

class _UserIdentity extends StatelessWidget {
  const _UserIdentity({required this.name, required this.role});
  final String name;
  final String role;

  String get initials {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        backgroundColor: const Color(0xFFE5F4EA),
        child: Text(
          initials,
          style: const TextStyle(
            color: Color(0xFF08783E),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      const SizedBox(width: 10),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              role,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Nav extends StatelessWidget {
  const _Nav({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    child: Material(
      color: active ? const Color(0xFF1A6D48) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(
                icon,
                color: active ? Colors.white : Colors.white60,
                size: 21,
              ),
              const SizedBox(width: 13),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white60,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

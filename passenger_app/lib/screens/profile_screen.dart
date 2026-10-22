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
          Center(
            child: Chip(
              avatar: const Icon(Icons.badge_outlined, size: 18),
              label: Text('User Type: ${session.passenger.userType}'),
            ),
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
          Card(
            elevation: 0,
            color: Colors.white,
            child: ListTile(
              leading: const Icon(
                Icons.email_outlined,
                color: Color(0xFF08783E),
              ),
              title: const Text(
                'Recovery email',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.passenger.email.isEmpty
                        ? 'Not added'
                        : session.passenger.email,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (session.passenger.emailVerified)
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Icon(
                        Icons.verified,
                        size: 18,
                        color: Color(0xFF168447),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0D5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          child: Text(
                            'Unverified',
                            style: TextStyle(
                              color: Color(0xFF946200),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'Change recovery email',
                onPressed: () => _editEmail(context, session),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
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
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Log out?'),
                  content: const Text(
                    'Are you sure you want to log out of your passenger account?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Log out'),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !context.mounted) return;
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

  Future<void> _editEmail(BuildContext context, AppSession session) async {
    final controller = TextEditingController(text: session.passenger.email);
    var sending = false;
    var checking = false;
    var linkSent = false;
    String? errorMessage;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Set password recovery email'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'We will send a verification link to this address for password recovery. Your passenger ID sign-in email will not change.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'New email address',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                if (linkSent) ...[
                  const SizedBox(height: 12),
                  const Text('Open the link in your inbox, then return here.'),
                ],
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending || checking
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            if (linkSent)
              OutlinedButton(
                onPressed: checking || sending
                    ? null
                    : () async {
                        setDialogState(() {
                          checking = true;
                          errorMessage = null;
                        });
                        try {
                          final result = await const PassengerFirebaseService()
                              .refreshRecoveryEmailStatus(uid: session.uid);
                          if (!dialogContext.mounted) return;
                          if (!result.verified ||
                              result.email.toLowerCase() !=
                                  controller.text.trim().toLowerCase()) {
                            setDialogState(() {
                              errorMessage =
                                  'Email is not verified yet. Open the newest verification link and try again.';
                            });
                            return;
                          }
                          session.updatePassenger(
                            session.passenger.copyWith(
                              email: result.email,
                              emailVerified: true,
                            ),
                          );
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                result.profileSynced
                                    ? 'Recovery email verified and saved.'
                                    : 'Recovery email is not verified yet.',
                              ),
                            ),
                          );
                        } catch (error) {
                          if (dialogContext.mounted) {
                            setDialogState(() => errorMessage = '$error');
                          }
                        } finally {
                          if (dialogContext.mounted) {
                            setDialogState(() => checking = false);
                          }
                        }
                      },
                child: Text(checking ? 'Checking...' : 'I verified it'),
              ),
            FilledButton(
              onPressed: sending || checking
                  ? null
                  : () async {
                      setDialogState(() {
                        sending = true;
                        errorMessage = null;
                      });
                      try {
                        final alreadyVerified =
                            await const PassengerFirebaseService()
                                .sendRecoveryEmailVerification(
                                  uid: session.uid,
                                  email: controller.text,
                                );
                        if (!dialogContext.mounted) return;
                        if (alreadyVerified) {
                          session.updatePassenger(
                            session.passenger.copyWith(
                              email: controller.text.trim().toLowerCase(),
                              emailVerified: true,
                            ),
                          );
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Recovery email is already verified and saved.',
                              ),
                            ),
                          );
                          return;
                        }
                        setDialogState(() {
                          linkSent = true;
                          errorMessage = null;
                        });
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() => errorMessage = '$error');
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() => sending = false);
                        }
                      }
                    },
              child: Text(sending ? 'Sending...' : 'Send verification link'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

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

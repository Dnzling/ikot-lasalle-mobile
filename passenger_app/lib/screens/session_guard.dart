import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_session.dart';
import '../services/passenger_firebase_service.dart';
import 'login_screen.dart';

class SessionGuard extends StatefulWidget {
  const SessionGuard({required this.session, required this.child, super.key});

  final AppSession session;
  final Widget child;

  @override
  State<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends State<SessionGuard> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  bool _handlingLogout = false;

  @override
  void initState() {
    super.initState();
    _subscription = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.session.uid)
        .collection('sessions')
        .doc(widget.session.sessionId)
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data();
          final reason = data?['endReason'];
          if (data?['active'] == false &&
              (reason == 'newDevice' || reason == 'passwordReset') &&
              !_handlingLogout) {
            _handleForcedLogout(reason == 'passwordReset');
          }
        });
  }

  Future<void> _handleForcedLogout(bool passwordReset) async {
    _handlingLogout = true;
    await const PassengerFirebaseService().clearLocalSession(
      widget.session.uid,
    );
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          passwordReset
              ? 'Password Reset, Logging Out'
              : 'New Device Detected, Logging Out',
        ),
        content: Text(
          passwordReset
              ? 'Your password was reset. Sign in using the temporary password from the admin office.'
              : 'Another login was detected. Both sessions were signed out. Please log in again.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

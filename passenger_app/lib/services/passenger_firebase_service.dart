import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_session.dart';
import '../models/active_trip.dart';
import '../models/bus_location.dart';
import '../models/passenger.dart';
import '../models/top_up_request.dart';
import 'password_policy.dart';

bool vehicleGpsIsFresh(Map<String, dynamic> vehicle) {
  final lastGpsAt = vehicle['lastGpsAt'];
  if (lastGpsAt is! Timestamp) return false;
  final age = DateTime.now().difference(lastGpsAt.toDate());
  return age >= const Duration(seconds: -5) &&
      age <= const Duration(seconds: 30);
}

class PassengerFirebaseService {
  const PassengerFirebaseService();

  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;
  static final _preferences = SharedPreferencesAsync();

  static String _sessionKey(String uid) => 'passenger.session.$uid';

  Future<void> clearLocalSession(String uid) =>
      _preferences.remove(_sessionKey(uid));

  /// Restore the existing device session without creating a new login.
  /// A mismatched or revoked session must never be treated as this device.
  Future<AppSession?> restoreSession() async {
    final user = await _auth.authStateChanges().first;
    if (user == null) return null;

    final localSessionId = await _preferences.getString(_sessionKey(user.uid));
    if (localSessionId == null || localSessionId.isEmpty) {
      await _auth.signOut();
      return null;
    }

    final userRef = _db.collection('users').doc(user.uid);
    final profile = await userRef.get();
    final data = profile.data();
    final currentSession = data?['session'];
    if (data == null ||
        currentSession is! Map ||
        currentSession['active'] != true ||
        currentSession['id'] != localSessionId) {
      await clearLocalSession(user.uid);
      await _auth.signOut();
      return null;
    }

    final session = await userRef
        .collection('sessions')
        .doc(localSessionId)
        .get();
    if (!session.exists || session.data()?['active'] != true) {
      await clearLocalSession(user.uid);
      await _auth.signOut();
      return null;
    }

    return AppSession(
      uid: user.uid,
      sessionId: localSessionId,
      passenger: _passenger(user.uid, data),
    );
  }

  Future<bool> isAvailable(String uid) async {
    try {
      await _db.collection('users').doc(uid).get();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<AppSession> register({
    required String firstName,
    required String lastName,
    required String idNumber,
    required String phone,
    required String password,
  }) async {
    final cleanId = idNumber.trim();
    final credential = await _auth.createUserWithEmailAndPassword(
      email: _authEmailForId(cleanId),
      password: password,
    );
    final user = credential.user!;
    final profile = <String, dynamic>{
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'idNumber': cleanId,
      'phone': phone.trim(),
      'contactNumber': phone.trim(),
      'email': '',
      'userType': 'Student',
      'balance': 0.0,
      'active': true,
      'mustChangePassword': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    final userRef = _db.collection('users').doc(user.uid);
    final sessionRef = userRef.collection('sessions').doc();
    profile['session'] = {
      'id': sessionRef.id,
      'active': true,
      'startedAt': FieldValue.serverTimestamp(),
    };
    try {
      final batch = _db.batch();
      batch.set(userRef, profile);
      batch.set(sessionRef, {
        'active': true,
        'startedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } catch (_) {
      await user.delete();
      rethrow;
    }
    await _preferences.setString(_sessionKey(user.uid), sessionRef.id);
    return AppSession(
      uid: user.uid,
      sessionId: sessionRef.id,
      passenger: _passenger(user.uid, profile),
    );
  }

  Future<AppSession> login(String idNumber, String password) async {
    final cleanId = idNumber.trim();
    UserCredential credential;
    try {
      credential = await _auth.signInWithEmailAndPassword(
        email: _authEmailForId(cleanId),
        password: password,
      );
    } on FirebaseAuthException catch (aliasError, stackTrace) {
      // Admin-created accounts authenticate with the email stored on their
      // Firestore profile. Look it up by the ID number entered on this screen.
      if (aliasError.code != 'user-not-found' &&
          aliasError.code != 'invalid-credential') {
        rethrow;
      }
      final matches = await _db
          .collection('users')
          .where('idNumber', isEqualTo: cleanId)
          .limit(1)
          .get();
      if (matches.docs.isEmpty) {
        Error.throwWithStackTrace(aliasError, stackTrace);
      }
      final profileData = matches.docs.first.data();
      final emailCandidates = <String>[
        '${profileData['pendingEmail'] ?? ''}'.trim(),
        '${profileData['email'] ?? ''}'.trim(),
      ].where((email) => email.isNotEmpty).toSet();
      if (emailCandidates.isEmpty) {
        Error.throwWithStackTrace(aliasError, stackTrace);
      }
      UserCredential? emailCredential;
      FirebaseAuthException? latestEmailError;
      for (final authEmail in emailCandidates) {
        try {
          emailCredential = await _auth.signInWithEmailAndPassword(
            email: authEmail,
            password: password,
          );
          latestEmailError = null;
          break;
        } on FirebaseAuthException catch (error) {
          latestEmailError = error;
          if (error.code != 'user-not-found' &&
              error.code != 'invalid-credential' &&
              error.code != 'wrong-password') {
            rethrow;
          }
        }
      }
      if (emailCredential == null) {
        if (latestEmailError != null) {
          Error.throwWithStackTrace(latestEmailError, stackTrace);
        }
        Error.throwWithStackTrace(aliasError, stackTrace);
      }
      credential = emailCredential;
    }
    final user = credential.user!;
    final profile = await _db.collection('users').doc(user.uid).get();
    var data = profile.data();
    if (data == null || data['idNumber'] != cleanId) {
      await _auth.signOut();
      throw FirebaseAuthException(
        code: 'passenger-profile-not-found',
        message: 'No passenger profile is linked to this ID number.',
      );
    }
    // Email verification changes the Firebase Auth email first. A passenger
    // may sign out before pressing the Home screen's refresh button, leaving
    // the Firestore lookup stale. Once Auth confirms the verified address,
    // repair that mapping as part of the successful sign-in.
    if (user.emailVerified && user.email != null && user.email!.isNotEmpty) {
      try {
        await _db.collection('users').doc(user.uid).set({
          'email': user.email!.trim().toLowerCase(),
          'emailVerified': true,
          'emailVerifiedAt': FieldValue.serverTimestamp(),
          'pendingEmail': FieldValue.delete(),
        }, SetOptions(merge: true));
      } catch (_) {
        // Authentication has succeeded; do not turn a profile-sync issue
        // into a misleading invalid-credential login failure.
      }
      data = {
        ...data,
        'email': user.email!.trim().toLowerCase(),
        'emailVerified': true,
      };
    }
    // A hot restart can show the login screen while this same installation
    // still holds its Firebase Auth session. Resume that session instead of
    // treating it as another device.
    final currentSession = data['session'];
    final localSessionId = await _preferences.getString(_sessionKey(user.uid));
    if (localSessionId != null &&
        currentSession is Map &&
        currentSession['active'] == true &&
        currentSession['id'] == localSessionId) {
      return AppSession(
        uid: user.uid,
        sessionId: localSessionId,
        passenger: _passenger(user.uid, data),
      );
    }
    final userRef = _db.collection('users').doc(user.uid);
    final sessionRef = userRef.collection('sessions').doc();
    final newDeviceDetected = await _db.runTransaction<bool>((
      transaction,
    ) async {
      final current = await transaction.get(userRef);
      final activeSession = current.data()?['session'];
      if (activeSession is Map && activeSession['active'] == true) {
        final oldSessionId = '${activeSession['id'] ?? ''}';
        if (oldSessionId.isNotEmpty) {
          transaction.set(
            userRef.collection('sessions').doc(oldSessionId),
            {
              'active': false,
              'endReason': 'newDevice',
              'endedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
        transaction.update(userRef, {
          'session.active': false,
          'session.endReason': 'newDevice',
          'session.endedAt': FieldValue.serverTimestamp(),
        });
        return true;
      }
      transaction.set(sessionRef, {
        'active': true,
        'startedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(userRef, {
        'session': {
          'id': sessionRef.id,
          'active': true,
          'startedAt': FieldValue.serverTimestamp(),
        },
      });
      return false;
    });
    if (newDeviceDetected) {
      await clearLocalSession(user.uid);
      await _auth.signOut();
      throw const NewDeviceDetectedException();
    }
    await _preferences.setString(_sessionKey(user.uid), sessionRef.id);
    return AppSession(
      uid: user.uid,
      sessionId: sessionRef.id,
      passenger: _passenger(user.uid, data),
    );
  }

  Future<Passenger> getProfile(String uid) async {
    final snapshot = await _db.collection('users').doc(uid).get();
    final data = snapshot.data();
    if (data == null) throw StateError('Passenger profile not found.');
    return _passenger(uid, data);
  }

  Future<bool> sendPassengerEmailVerification({
    required String uid,
    required String email,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(cleanEmail)) {
      throw ArgumentError('Enter a valid email address.');
    }
    final user = _auth.currentUser;
    if (user == null || user.uid != uid) {
      throw StateError('Your login session expired. Please sign in again.');
    }
    if (user.email?.toLowerCase() == cleanEmail.toLowerCase() &&
        user.emailVerified) {
      await _db.collection('users').doc(uid).set({
        'email': cleanEmail,
        'emailVerified': true,
        'emailVerifiedAt': FieldValue.serverTimestamp(),
        'pendingEmail': FieldValue.delete(),
      }, SetOptions(merge: true));
      return true;
    }
    await _db.collection('users').doc(uid).set({
      'pendingEmail': cleanEmail,
      'emailVerified': false,
      'emailVerificationSentAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await user.verifyBeforeUpdateEmail(cleanEmail);
    return false;
  }

  Future<({String email, bool verified})> refreshPassengerEmail({
    required String uid,
  }) async {
    var user = _auth.currentUser;
    if (user == null || user.uid != uid) {
      throw StateError('Your login session expired. Please sign in again.');
    }
    await user.reload();
    user = _auth.currentUser;
    final email = (user?.email ?? '').toLowerCase();
    final verified = user?.emailVerified ?? false;
    final userRef = _db.collection('users').doc(uid);
    if (verified && email.isNotEmpty) {
      await userRef.set({
        'email': email,
        'emailVerified': true,
        'emailVerifiedAt': FieldValue.serverTimestamp(),
        'pendingEmail': FieldValue.delete(),
      }, SetOptions(merge: true));
    }
    return (email: email, verified: verified);
  }

  Future<void> sendPasswordResetLink({
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    final cleanFirst = firstName.trim();
    final cleanLast = lastName.trim();
    final cleanEmail = email.trim().toLowerCase();
    if (cleanFirst.isEmpty || cleanLast.isEmpty || cleanEmail.isEmpty) {
      throw ArgumentError('Enter your first name, last name, and email.');
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(cleanEmail)) {
      throw ArgumentError('Enter a valid email address.');
    }
    final matches = await _db
        .collection('users')
        .where('email', isEqualTo: cleanEmail)
        .limit(5)
        .get()
        .timeout(const Duration(seconds: 15));
    final matchingProfile = matches.docs.any((doc) {
      final data = doc.data();
      // Firestore's emailVerified flag can lag behind Firebase Auth when a
      // passenger follows the verification link outside the app. Matching the
      // profile establishes the requested identity fields; Firebase's reset
      // link itself is the authoritative proof of inbox access.
      return '${data['firstName'] ?? ''}'.trim().toLowerCase() ==
              cleanFirst.toLowerCase() &&
          '${data['lastName'] ?? ''}'.trim().toLowerCase() ==
              cleanLast.toLowerCase();
    });
    if (!matchingProfile) {
      throw StateError('The name and email do not match a passenger account.');
    }
    await _auth
        .sendPasswordResetEmail(email: cleanEmail)
        .timeout(const Duration(seconds: 20));
  }

  Future<void> requestPasswordReset({
    required String firstName,
    required String lastName,
    required String idNumber,
    required String contactNumber,
  }) async {
    final fields = [
      firstName,
      lastName,
      idNumber,
      contactNumber,
    ].map((value) => value.trim()).toList();
    if (fields.any((value) => value.isEmpty)) {
      throw ArgumentError('Complete all four fields.');
    }
    await _db
        .collection('passwordResetRequests')
        .add({
          'firstName': fields[0],
          'lastName': fields[1],
          'idNumber': fields[2],
          'contactNumber': fields[3],
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 20));
  }

  Future<void> changePassword({
    required String uid,
    required String newPassword,
    String? currentPassword,
    bool clearMustChangePassword = true,
  }) async {
    final passwordError = PasswordPolicy.validate(newPassword);
    if (passwordError != null) {
      throw ArgumentError(passwordError);
    }
    final user = _auth.currentUser;
    if (user == null || user.uid != uid) {
      throw StateError('Your session has expired. Please sign in again.');
    }
    if (currentPassword != null) {
      final email = user.email;
      if (email == null || email.isEmpty || currentPassword.isEmpty) {
        throw StateError('Enter your current password to continue.');
      }
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );
    }
    await user.updatePassword(newPassword);
    if (clearMustChangePassword) {
      await _db.collection('users').doc(uid).update({
        'mustChangePassword': false,
        'passwordChangedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<List<Map<String, dynamic>>> getTransactions(String uid) async {
    final snapshot = await _db
        .collection('transactions')
        .where('userId', isEqualTo: uid)
        .get();
    final rows =
        snapshot.docs.map((doc) {
          final data = doc.data();
          final amount = _number(data['amount']);
          final title =
              '${data['title'] ?? data['description'] ?? 'Transaction'}';
          return <String, dynamic>{
            'title': title,
            'date': _dateText(data['createdAt']),
            'amount':
                '${amount >= 0 ? '+' : '-'} PHP ${amount.abs().toStringAsFixed(2)}',
            '_createdAt': _date(data['createdAt']),
          };
        }).toList()..sort(
          (a, b) => (b['_createdAt'] as DateTime).compareTo(
            a['_createdAt'] as DateTime,
          ),
        );
    return rows
        .map((row) => Map<String, dynamic>.from(row)..remove('_createdAt'))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getNotifications(String uid) async {
    final snapshot = await _db
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .get();
    final rows =
        snapshot.docs.map((doc) {
          final data = doc.data();
          return <String, dynamic>{
            'type': '${data['type'] ?? ''}',
            'title': '${data['title'] ?? 'Update'}',
            'message': '${data['message'] ?? ''}',
            'date': _dateText(data['createdAt']),
            '_createdAt': _date(data['createdAt']),
          };
        }).toList()..sort(
          (a, b) => (b['_createdAt'] as DateTime).compareTo(
            a['_createdAt'] as DateTime,
          ),
        );
    return rows
        .map((row) => Map<String, dynamic>.from(row)..remove('_createdAt'))
        .toList();
  }

  Future<List<BusLocation>> getBusLocations() async {
    final snapshot = await _db.collection('vehicles').get();
    return snapshot.docs
        .map((doc) {
          final data = doc.data();
          final location = data['location'];
          final geoPoint = location is GeoPoint ? location : null;
          return BusLocation(
            id: doc.id,
            label: '${data['name'] ?? 'Bus'}',
            latitude: geoPoint?.latitude ?? _number(data['latitude']),
            longitude: geoPoint?.longitude ?? _number(data['longitude']),
            status: '${data['status'] ?? 'idle'}',
            type: '${data['type'] ?? 'Jeep'}',
            speedKmh: _number(data['speedKmh']),
            lastGpsAt: (data['lastGpsAt'] as Timestamp?)?.toDate(),
          );
        })
        .where(
          (bus) =>
              bus.hasFreshGps &&
              (bus.status.toLowerCase() == 'active' ||
                  bus.status.toLowerCase() == 'idle' ||
                  bus.status.toLowerCase() == 'onroute') &&
              (bus.latitude != 0 || bus.longitude != 0),
        )
        .toList();
  }

  Stream<List<BusLocation>> watchBusLocations() => _db
      .collection('vehicles')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .where((doc) => doc.data()['archived'] != true)
            .map((doc) {
              final data = doc.data();
              final location = data['location'];
              final point = location is GeoPoint ? location : null;
              return BusLocation(
                id: doc.id,
                label: '${data['name'] ?? doc.id}',
                latitude: point?.latitude ?? _number(data['latitude']),
                longitude: point?.longitude ?? _number(data['longitude']),
                status: '${data['status'] ?? 'idle'}',
                type: '${data['type'] ?? 'Jeep'}',
                speedKmh: _number(data['speedKmh']),
                lastGpsAt: (data['lastGpsAt'] as Timestamp?)?.toDate(),
              );
            })
            .where(
              (bus) =>
                  bus.hasFreshGps &&
                  bus.latitude.isFinite &&
                  bus.longitude.isFinite &&
                  bus.latitude.abs() <= 90 &&
                  bus.longitude.abs() <= 180 &&
                  bus.latitude != 0 &&
                  bus.longitude != 0,
            )
            .toList(),
      );

  Future<List<Map<String, dynamic>>> getRoutes() async {
    final snapshot = await _db
        .collection('routes')
        .where('active', isEqualTo: true)
        .get();
    final routes =
        snapshot.docs.map((doc) {
          final data = doc.data();
          return <String, dynamic>{
            'id': doc.id,
            'name': '${data['name'] ?? 'Route'}',
            'order': (data['order'] as num?)?.toInt() ?? 0,
            'location': data['location'],
            'proximityRadius': data['proximityRadius'],
          };
        }).toList()..sort((a, b) {
          final order = (a['order'] as int).compareTo(b['order'] as int);
          return order != 0
              ? order
              : (a['name'] as String).compareTo(b['name'] as String);
        });
    return routes;
  }

  Future<({double latitude, double longitude, double radiusMeters})?>
  getRouteStop({String? routeId, required String name}) async {
    Map<String, dynamic>? data;
    if (routeId != null && routeId.isNotEmpty) {
      data = (await _db.collection('routes').doc(routeId).get()).data();
    }
    if (data == null) {
      final match = await _db
          .collection('routes')
          .where('name', isEqualTo: name)
          .limit(1)
          .get();
      data = match.docs.firstOrNull?.data();
    }
    final point = data?['location'];
    if (point is! GeoPoint) return null;
    return (
      latitude: point.latitude,
      longitude: point.longitude,
      radiusMeters: (_number(
        data?['proximityRadius'],
        fallback: 50,
      )).clamp(1, 100).toDouble(),
    );
  }

  Future<({double defaultFare, double roundTripFare})> getFareSettings() async {
    final snapshot = await _db.collection('settings').doc('fares').get();
    final data = snapshot.data();
    return (
      defaultFare: _number(
        data?['defaultFare'] ?? data?['wholeTripFare'],
        fallback: 15,
      ),
      roundTripFare: _number(data?['roundTripFare'], fallback: 25),
    );
  }

  Future<String> getGcashNumber() async {
    final settings = await getGcashPaymentDetails();
    return settings['gcashNumber'] ?? '';
  }

  Future<Map<String, String>> getGcashPaymentDetails() async {
    final snapshot = await _db.collection('settings').doc('payment').get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    return {
      'accountName': '${data['accountName'] ?? ''}'.trim(),
      'gcashNumber': '${data['gcashNumber'] ?? ''}'.trim(),
    };
  }

  Future<List<TopUpRequest>> getTopUpRequests(String uid) async {
    final snapshot = await _db
        .collection('topUpRequests')
        .where('userId', isEqualTo: uid)
        .get();
    final requests = snapshot.docs.map((doc) {
      final data = doc.data();
      return TopUpRequest.fromJson({
        ...data,
        'id': doc.id,
        'submittedAt': _dateText(data['submittedAt']),
      });
    }).toList()..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return requests;
  }

  Future<void> createTopUpRequest({
    required String uid,
    required double amount,
    required String fileName,
    required String mimeType,
    required Uint8List screenshotBytes,
    required String referenceNumber,
    required String ocrText,
    void Function(String stage)? onProgress,
  }) async {
    if (!amount.isFinite || amount <= 0 || amount > 10000) {
      throw ArgumentError('Enter a valid top-up amount.');
    }
    if (screenshotBytes.isEmpty || screenshotBytes.length > 800 * 1024) {
      throw ArgumentError('Use a receipt image smaller than 800 KB.');
    }
    if (!RegExp(r'^\d{13}$').hasMatch(referenceNumber.trim())) {
      throw ArgumentError(
        'The payment reference number must contain exactly 13 digits.',
      );
    }
    if (_auth.currentUser?.uid != uid) {
      throw StateError('Your login session expired. Sign in again.');
    }
    onProgress?.call('Checking passenger account...');
    final profile = await _db
        .collection('users')
        .doc(uid)
        .get()
        .timeout(const Duration(seconds: 15));
    if (!profile.exists) {
      throw StateError('Passenger account was not found.');
    }
    final profileData = profile.data() ?? const <String, dynamic>{};
    final passengerId = '${profileData['idNumber'] ?? uid}'.trim();
    final passengerName =
        '${profileData['firstName'] ?? ''} ${profileData['lastName'] ?? ''}'
            .trim();
    onProgress?.call('Checking for an existing request...');
    final previous = await _db
        .collection('topUpRequests')
        .where('referenceNumber', isEqualTo: referenceNumber.trim())
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    final hasActiveReference = previous.docs.any((doc) {
      final data = doc.data();
      final status = '${data['status'] ?? 'pending'}'.trim().toLowerCase();
      return '${data['referenceNumber'] ?? ''}'.trim() ==
              referenceNumber.trim() &&
          (status == 'pending' || status == 'approved');
    });
    if (hasActiveReference) {
      throw StateError(
        'This GCash reference already has a pending or approved request. Check Transaction Records.',
      );
    }
    // Check across all passengers. Rejected attempts remain in history and
    // may be resubmitted, but pending and approved references cannot.
    final requestRef = _db.collection('topUpRequests').doc();
    onProgress?.call('Saving receipt and request for admin review...');
    await requestRef
        .set({
          'userId': uid,
          'passengerId': passengerId,
          'passengerName': passengerName,
          'amount': amount,
          'referenceNumber': referenceNumber.trim(),
          'ocrText': ocrText.trim(),
          'status': 'pending',
          // A bounded Firestore blob avoids the web Storage upload/CORS path.
          'receiptBytes': Blob(screenshotBytes),
          'receiptMimeType': mimeType,
          'receiptFileName': fileName,
          'submittedAt': FieldValue.serverTimestamp(),
          'reviewedAt': null,
          'adminNote': '',
          'creditedAt': null,
        })
        .timeout(const Duration(seconds: 20));
    // The payment request is authoritative. A notification-rule failure must
    // never make an otherwise valid request disappear from the admin queue.
    try {
      await _db
          .collection('notifications')
          .add({
            'userId': uid,
            'type': 'topUp',
            'title': 'Top-up request submitted',
            'message':
                'PHP ${amount.toStringAsFixed(2)} is awaiting admin approval.',
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Admin sees the saved request through topUpRequests regardless.
    }
  }

  Future<String> createBooking({
    required String uid,
    required String pickup,
    required String destination,
    required int passengerCount,
    required double fare,
    required String fareType,
    required String pickupRouteId,
    required String destinationRouteId,
  }) async {
    if (passengerCount < 1 || passengerCount > 6) {
      throw ArgumentError('Passenger count must be from 1 to 6.');
    }
    final existingTrips = await _db
        .collection('trips')
        .where('userId', isEqualTo: uid)
        .get(const GetOptions(source: Source.server));
    if (existingTrips.docs.any(
      (doc) => const {
        'waiting',
        'onboard',
        'boarded',
      }.contains('${doc.data()['status'] ?? ''}'.toLowerCase()),
    )) {
      throw StateError('You already have a pending trip. View it from Home.');
    }
    final user = await _db.collection('users').doc(uid).get();
    final bookingRef = _db.collection('trips').doc();
    final batch = _db.batch();
    batch.set(bookingRef, {
      'userId': uid,
      'passengerId': uid,
      'passengerName':
          '${user.data()?['firstName'] ?? ''} ${user.data()?['lastName'] ?? ''}'
              .trim(),
      'pickup': pickup,
      'pickupRouteId': pickupRouteId,
      'destination': destination,
      'destinationRouteId': destinationRouteId,
      'routeName': destination,
      'passengerCount': passengerCount,
      'fare': fare,
      'fareType': fareType,
      'status': 'waiting',
      'createdAt': FieldValue.serverTimestamp(),
      'boardedAt': null,
      'completedAt': null,
    });
    final notificationRef = _db.collection('notifications').doc();
    batch.set(notificationRef, {
      'userId': uid,
      'type': 'booking',
      'title': 'Booking created',
      'message':
          '$pickup to $destination for $passengerCount passenger${passengerCount == 1 ? '' : 's'}.',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return bookingRef.id;
  }

  Stream<ActiveTrip?> watchActiveTrip(
    String uid,
  ) => _db.collection('trips').where('userId', isEqualTo: uid).snapshots().map((
    snapshot,
  ) {
    final active =
        snapshot.docs
            .where(
              (doc) => const {
                'waiting',
                'onboard',
                'boarded',
              }.contains('${doc.data()['status'] ?? ''}'.toLowerCase()),
            )
            .toList()
          ..sort((a, b) {
            final aOnboard = const {
              'onboard',
              'boarded',
            }.contains('${a.data()['status'] ?? ''}'.toLowerCase());
            final bOnboard = const {
              'onboard',
              'boarded',
            }.contains('${b.data()['status'] ?? ''}'.toLowerCase());
            if (aOnboard != bOnboard) return bOnboard ? 1 : -1;
            final aTime = a.data()['createdAt'];
            final bTime = b.data()['createdAt'];
            final aDate = aTime is Timestamp ? aTime.toDate() : DateTime(1970);
            final bDate = bTime is Timestamp ? bTime.toDate() : DateTime(1970);
            return bDate.compareTo(aDate);
          });
    if (active.isEmpty) return null;
    final doc = active.first;
    final data = doc.data();
    final createdAt = data['createdAt'];
    return ActiveTrip(
      id: doc.id,
      destination: '${data['destination'] ?? ''}',
      passengerCount: (data['passengerCount'] as num?)?.toInt() ?? 1,
      fare: _number(data['fare']),
      status: '${data['status'] ?? 'waiting'}'.toLowerCase(),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
      pickupRouteId: data['pickupRouteId'] as String?,
      destinationRouteId: data['destinationRouteId'] as String?,
      pickup: data['pickup'] as String?,
      vehicleId: data['vehicleId'] as String?,
      boardedAt: data['boardedAt'] is Timestamp
          ? (data['boardedAt'] as Timestamp).toDate()
          : null,
    );
  });

  Future<Passenger> boardRide(
    String uid,
    String bookingId,
    String vehicleId,
    String vehicleType,
  ) async {
    final userRef = _db.collection('users').doc(uid);
    final tripRef = _db.collection('trips').doc(bookingId);
    final vehicleRef = _db.collection('vehicles').doc(vehicleId);
    await _db.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      final tripSnapshot = await transaction.get(tripRef);
      final vehicleSnapshot = await transaction.get(vehicleRef);
      final user = userSnapshot.data();
      final trip = tripSnapshot.data();
      final vehicle = vehicleSnapshot.data();
      if (user == null || trip == null || trip['userId'] != uid) {
        throw StateError('Booking not found.');
      }
      if (trip['status'] != 'waiting') {
        throw StateError('This booking was already boarded.');
      }
      final createdAt = trip['createdAt'];
      if (createdAt is Timestamp &&
          DateTime.now().difference(createdAt.toDate()) >=
              const Duration(minutes: 10)) {
        throw StateError(
          'This booking expired after 10 minutes. Please book again.',
        );
      }
      if (vehicle == null ||
          vehicle['archived'] == true ||
          vehicle['type'] != vehicleType ||
          !const {
            'active',
            'idle',
            'onroute',
          }.contains('${vehicle['status'] ?? ''}'.toLowerCase()) ||
          !vehicleGpsIsFresh(vehicle)) {
        throw StateError(
          'This vehicle is not active or the QR code is invalid.',
        );
      }
      final count = (trip['passengerCount'] as num?)?.toInt() ?? 1;
      final onboard = (vehicle['onBoardPassengers'] as num?)?.toInt() ?? 0;
      final capacity = (vehicle['passengerCapacity'] as num?)?.toInt() ?? 0;
      if (capacity > 0 && onboard + count > capacity) {
        throw StateError('This vehicle is full.');
      }
      final fare = _number(trip['fare']);
      final balance = _number(user['balance']);
      final destinationRouteId = '${trip['destinationRouteId'] ?? ''}'.trim();
      final expected = Map<String, dynamic>.from(
        vehicle['expectedOutboardByStop'] is Map
            ? vehicle['expectedOutboardByStop'] as Map
            : const <String, dynamic>{},
      );
      if (destinationRouteId.isNotEmpty) {
        expected[destinationRouteId] =
            ((expected[destinationRouteId] as num?)?.toInt() ?? 0) + count;
      }
      if (balance < fare) {
        throw StateError('Insufficient credits. Please top up first.');
      }
      transaction.update(userRef, {'balance': balance - fare});
      transaction.update(tripRef, {
        'status': 'onboard',
        'vehicleId': vehicleId,
        'vehicleName': vehicle['name'],
        'vehicleType': vehicleType,
        'driverId': vehicle['driverId'],
        'driverName': vehicle['driverName'],
        'boardedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(vehicleRef, {
        'onBoardPassengers': onboard + count,
        'expectedOutboardByStop': expected,
        'tripPassengerCount': FieldValue.increment(count),
        'tripIncome': FieldValue.increment(fare),
      });
      final transactionRef = _db.collection('transactions').doc();
      transaction.set(transactionRef, {
        'userId': uid,
        'passengerName': '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'
            .trim(),
        'userType': '${user['userType'] ?? 'Passenger'}',
        'title': 'Ride to ${trip['destination'] ?? 'destination'}',
        'description': 'Ride to ${trip['destination'] ?? 'destination'}',
        'amount': -fare,
        'type': 'fare',
        'createdAt': FieldValue.serverTimestamp(),
        'tripId': bookingId,
        'vehicleId': vehicleId,
        'vehicleName': vehicle['name'],
      });
      final notificationRef = _db.collection('notifications').doc();
      transaction.set(notificationRef, {
        'userId': uid,
        'type': 'boarded',
        'title': 'You are onboard',
        'message': 'PHP ${fare.toStringAsFixed(2)} was charged for your ride.',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    return getProfile(uid);
  }

  Future<void> completeRide(String uid, String bookingId) async {
    final tripRef = _db.collection('trips').doc(bookingId);
    final notificationRef = _db.collection('notifications').doc();
    await _db.runTransaction((transaction) async {
      final tripSnapshot = await transaction.get(tripRef);
      final trip = tripSnapshot.data();
      if (trip == null || trip['userId'] != uid) {
        throw StateError('Booking not found.');
      }
      if (trip['status'] != 'onboard' && trip['status'] != 'boarded') {
        throw StateError('The ride must be boarded first.');
      }
      final vehicleId = trip['vehicleId'] as String?;
      final vehicleRef = vehicleId == null
          ? null
          : _db.collection('vehicles').doc(vehicleId);
      final vehicle = vehicleRef == null
          ? null
          : await transaction.get(vehicleRef);
      final count = (trip['passengerCount'] as num?)?.toInt() ?? 1;
      if (vehicleRef != null && vehicle?.exists == true) {
        final onboard =
            (vehicle?.data()?['onBoardPassengers'] as num?)?.toInt() ?? 0;
        final destinationRouteId = '${trip['destinationRouteId'] ?? ''}'.trim();
        final expected = Map<String, dynamic>.from(
          vehicle?.data()?['expectedOutboardByStop'] is Map
              ? vehicle!.data()!['expectedOutboardByStop'] as Map
              : const <String, dynamic>{},
        );
        if (destinationRouteId.isNotEmpty) {
          final remaining =
              (((expected[destinationRouteId] as num?)?.toInt() ?? 0) - count)
                  .clamp(0, 999999999);
          if (remaining == 0) {
            expected.remove(destinationRouteId);
          } else {
            expected[destinationRouteId] = remaining;
          }
        }
        transaction.update(vehicleRef, {
          'onBoardPassengers': (onboard - count).clamp(0, 999999999),
          'outBoardPassengers': FieldValue.increment(count),
          'expectedOutboardByStop': expected,
        });
      }
      transaction.update(tripRef, {
        'status': 'arrived',
        'completedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(notificationRef, {
        'userId': uid,
        'type': 'completed',
        'title': 'You have arrived',
        'message':
            'You arrived at ${trip['destination'] ?? 'your destination'}.',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> cancelBooking(
    String uid,
    String bookingId, {
    bool expired = false,
  }) async {
    final tripRef = _db.collection('trips').doc(bookingId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(tripRef);
      final trip = snapshot.data();
      if (trip == null || trip['userId'] != uid) {
        throw StateError('Booking not found.');
      }
      if (trip['status'] == 'canceled') return;
      if (trip['status'] != 'waiting') {
        throw StateError('Only waiting bookings can be canceled.');
      }
      transaction.update(tripRef, {
        'status': 'canceled',
        'cancelReason': expired
            ? 'Waiting time exceeded 10 minutes'
            : 'Canceled by passenger',
        'canceledAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> signOut({required String uid, required String sessionId}) async {
    final userRef = _db.collection('users').doc(uid);
    final sessionRef = userRef.collection('sessions').doc(sessionId);
    try {
      final userSnapshot = await userRef.get();
      final activeSession = userSnapshot.data()?['session'];
      final batch = _db.batch();
      batch.update(sessionRef, {
        'active': false,
        'endedAt': FieldValue.serverTimestamp(),
      });
      if (activeSession is Map && activeSession['id'] == sessionId) {
        batch.update(userRef, {
          'session': {
            'id': sessionId,
            'active': false,
            'endedAt': FieldValue.serverTimestamp(),
          },
        });
      }
      await batch.commit();
    } catch (_) {
      // Sign out locally even when session metadata cannot be updated.
    }
    await clearLocalSession(uid);
    await _auth.signOut();
  }

  static String _authEmailForId(String idNumber) {
    final encoded = base64Url
        .encode(utf8.encode(idNumber.trim().toUpperCase()))
        .replaceAll('=', '');
    return 'passenger_$encoded@ikot-lasalle-ccfab.firebaseapp.com';
  }

  static Passenger _passenger(String uid, Map<String, dynamic> data) =>
      Passenger.fromJson({'id': uid, ...data});

  static double _number(Object? value, {double fallback = 0}) =>
      (value as num?)?.toDouble() ?? double.tryParse('$value') ?? fallback;

  static DateTime _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse('$value') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _dateText(Object? value) {
    if (value == null) return '';
    return _date(value).toLocal().toString();
  }
}

class NewDeviceDetectedException implements Exception {
  const NewDeviceDetectedException();

  @override
  String toString() => 'New Device Detected, Logging Out';
}

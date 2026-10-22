import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' as core;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
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
      age <= const Duration(seconds: 120);
}

class PassengerFirebaseService {
  const PassengerFirebaseService();

  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;
  static final _preferences = SharedPreferencesAsync();
  static const _trustedApiBase = String.fromEnvironment(
    'TRUSTED_API_BASE_URL',
    defaultValue: 'https://ikot-lasalle-mobile.onrender.com',
  );

  StateError _trustedApiError(http.Response response) {
    dynamic result;
    try {
      result = jsonDecode(response.body);
    } on FormatException {
      final body = response.body.trim();
      if (body.isEmpty) {
        return StateError(
          'The relay returned an empty response (HTTP ${response.statusCode}). '
          'Check that the latest recovery backend is deployed at $_trustedApiBase.',
        );
      }
      final detail = body.length > 180 ? '${body.substring(0, 180)}…' : body;
      return StateError(
        'The relay returned a non-JSON response (HTTP ${response.statusCode}): $detail',
      );
    }
    if (result is Map && result['error'] != null) {
      return StateError('${result['error']}');
    }
    return StateError('Relay request failed (HTTP ${response.statusCode}).');
  }

  Future<Map<String, dynamic>> _trustedRequest(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final base = Uri.tryParse(_trustedApiBase);
    if (base == null || base.scheme != 'https' || base.host.isEmpty) {
      throw StateError('Trusted API is not configured with an HTTPS address.');
    }
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in again to continue.');
    final token = await user.getIdToken();
    final response = await http
        .post(
          base.resolve(path),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw _trustedApiError(response);
    dynamic result;
    try {
      result = jsonDecode(response.body);
    } on FormatException {
      throw _trustedApiError(response);
    }
    if (result is! Map<String, dynamic>) throw _trustedApiError(response);
    return result;
  }

  Future<Map<String, dynamic>> _publicTrustedRequest(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final base = Uri.tryParse(_trustedApiBase);
    if (base == null || base.scheme != 'https' || base.host.isEmpty) {
      throw StateError('Trusted API is not configured with an HTTPS address.');
    }
    final response = await http
        .post(
          base.resolve(path),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw _trustedApiError(response);
    dynamic result;
    try {
      result = jsonDecode(response.body);
    } on FormatException {
      throw _trustedApiError(response);
    }
    if (result is! Map<String, dynamic>) throw _trustedApiError(response);
    return result;
  }

  Future<bool> isSelectedPhoneReporter({
    required String uid,
    required String bookingId,
    required String vehicleId,
  }) async {
    if (_auth.currentUser?.uid != uid) return false;
    final trip = (await _db.collection('trips').doc(bookingId).get()).data();
    return trip?['userId'] == uid &&
        trip?['vehicleId'] == vehicleId &&
        trip?['status'] == 'onboard';
  }

  Future<void> publishOnboardPhoneLocation({
    required String uid,
    required String bookingId,
    required String vehicleId,
    required geo.Position position,
  }) async {
    if (position.accuracy > 30 ||
        position.accuracy < 0 ||
        DateTime.now().difference(position.timestamp) >
            const Duration(seconds: 10) ||
        !(await isSelectedPhoneReporter(
          uid: uid,
          bookingId: bookingId,
          vehicleId: vehicleId,
        )))
      return;
    await _db.collection('trips').doc(bookingId).update({
      'phoneLocation': GeoPoint(position.latitude, position.longitude),
      'phoneGpsAt': FieldValue.serverTimestamp(),
      'phoneGpsAccuracyMeters': position.accuracy,
    });
  }

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
        data['active'] == false ||
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
      // Admin-created accounts use the Firebase Auth email stored in the
      // passenger ID alias, while the passenger still signs in with ID.
      if (aliasError.code != 'user-not-found' &&
          aliasError.code != 'invalid-credential') {
        rethrow;
      }
      final alias = await _db.collection('loginAliases').doc(cleanId).get();
      if (!alias.exists) Error.throwWithStackTrace(aliasError, stackTrace);
      final authEmail = '${alias.data()?['email'] ?? ''}'.trim();
      if (authEmail.isEmpty) Error.throwWithStackTrace(aliasError, stackTrace);
      try {
        credential = await _auth.signInWithEmailAndPassword(
          email: authEmail,
          password: password,
        );
      } on FirebaseAuthException catch (error) {
        Error.throwWithStackTrace(error, stackTrace);
      }
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
    if (data['active'] == false) {
      await _auth.signOut();
      throw StateError(
        'This account is inactive. Please contact the administrator.',
      );
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
      if (current.data()?['active'] == false) {
        throw StateError(
          'This account is inactive. Please contact the administrator.',
        );
      }
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

  Future<bool> sendRecoveryEmailVerification({
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
    final profile = await _db.collection('users').doc(uid).get();
    final data = profile.data();
    if (data?['recoveryEmailVerified'] == true &&
        '${data?['recoveryEmail'] ?? ''}'.toLowerCase() == cleanEmail) {
      return true;
    }
    await _trustedRequest('/api/recovery/start-verification', {
      'email': cleanEmail,
    });
    return false;
  }

  Future<({String email, bool verified, bool profileSynced})>
  refreshRecoveryEmailStatus({required String uid}) async {
    if (_auth.currentUser?.uid != uid) {
      throw StateError('Your login session expired. Please sign in again.');
    }
    final snapshot = await _db.collection('users').doc(uid).get();
    final data = snapshot.data();
    if (data == null) throw StateError('Passenger profile not found.');
    final verified = data['recoveryEmailVerified'] == true;
    final email = (verified
            ? data['recoveryEmail']
            : (data['pendingRecoveryEmail'] ?? data['recoveryEmail']))
        ?.toString()
        .trim()
        .toLowerCase() ??
        '';
    return (email: email, verified: verified, profileSynced: verified);
  }

  Future<void> sendPasswordResetLink({required String email}) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) throw ArgumentError('Enter your email address.');
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(cleanEmail)) {
      throw ArgumentError('Enter a valid email address.');
    }
    await _publicTrustedRequest('/api/recovery/request-reset', {
      'email': cleanEmail,
    });
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
            routeDirection: data['routeDirection'] as String?,
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

  Stream<List<BusLocation>> watchBusLocations() {
    late StreamSubscription<QuerySnapshot<Map<String, dynamic>>> vehiclesSub;
    late StreamSubscription<QuerySnapshot<Map<String, dynamic>>> tripsSub;
    QuerySnapshot<Map<String, dynamic>>? vehicles;
    QuerySnapshot<Map<String, dynamic>>? trips;
    final controller = StreamController<List<BusLocation>>(
      onCancel: () async {
        await vehiclesSub.cancel();
        await tripsSub.cancel();
      },
    );
    void emit() {
      final current = vehicles;
      if (current == null || controller.isClosed) return;
      final now = DateTime.now();
      final candidates = <String, List<Map<String, dynamic>>>{};
      for (final trip
          in trips?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
        final data = trip.data();
        final vehicleId = '${data['vehicleId'] ?? ''}';
        if (vehicleId.isEmpty ||
            data['status'] != 'onboard' ||
            data['phoneLocation'] is! GeoPoint ||
            data['phoneGpsAt'] is! Timestamp ||
            (_number(data['phoneGpsAccuracyMeters'], fallback: 999) > 30))
          continue;
        final age = now.difference((data['phoneGpsAt'] as Timestamp).toDate());
        if (age.isNegative || age > const Duration(seconds: 10)) continue;
        candidates.putIfAbsent(vehicleId, () => []).add(data);
      }
      final result = <BusLocation>[];
      for (final doc in current.docs) {
        final data = doc.data();
        if (data['archived'] == true) continue;
        final point = data['location'];
        final hardware = point is GeoPoint ? point : null;
        final hardwareAt = data['lastGpsAt'] as Timestamp?;
        GeoPoint? effective = hardware;
        DateTime? effectiveAt = hardwareAt?.toDate();
        var locationSource = 'hardware';
        final available = candidates[doc.id] ?? [];
        available.sort(
          (a, b) =>
              ((a['boardedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
                  .compareTo(
                    (b['boardedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
                  ),
        );
        for (final candidate in available) {
          final phone = candidate['phoneLocation'] as GeoPoint;
          final phoneAt = (candidate['phoneGpsAt'] as Timestamp).toDate();
          if (hardware == null ||
              hardwareAt == null ||
              !phoneAt.isAfter(hardwareAt.toDate()) ||
              now.difference(hardwareAt.toDate()) >
                  const Duration(seconds: 120) ||
              geo.Geolocator.distanceBetween(
                    phone.latitude,
                    phone.longitude,
                    hardware.latitude,
                    hardware.longitude,
                  ) >
                  500)
            continue;
          effective = phone;
          effectiveAt = phoneAt;
          locationSource = 'phone';
          break;
        }
        final bus = BusLocation(
          id: doc.id,
          label: '${data['name'] ?? doc.id}',
          latitude: effective?.latitude ?? _number(data['latitude']),
          longitude: effective?.longitude ?? _number(data['longitude']),
          status: '${data['status'] ?? 'idle'}',
          type: '${data['type'] ?? 'Jeep'}',
          speedKmh: _number(data['speedKmh']),
          routeDirection: data['routeDirection'] as String?,
          lastGpsAt: effectiveAt,
          locationSource: locationSource,
        );
        if (bus.hasFreshGps &&
            bus.latitude.isFinite &&
            bus.longitude.isFinite &&
            bus.latitude.abs() <= 90 &&
            bus.longitude.abs() <= 180 &&
            (bus.latitude != 0 || bus.longitude != 0))
          result.add(bus);
      }
      controller.add(result);
    }

    vehiclesSub = _db.collection('vehicles').snapshots().listen((snapshot) {
      vehicles = snapshot;
      emit();
    }, onError: controller.addError);
    tripsSub = _db
        .collection('trips')
        .where('userId', isEqualTo: _auth.currentUser?.uid ?? '__signed_out__')
        .snapshots()
        .listen((snapshot) {
          trips = snapshot;
          emit();
        }, onError: controller.addError);
    return controller.stream;
  }

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

  Future<double> getMinimumTopUpCredits() async {
    final snapshot = await _db
        .collection('settings')
        .doc('credits')
        .get(const GetOptions(source: Source.server));
    return (snapshot.data()?['minimumTopUpCredits'] as num?)?.toDouble() ?? 1;
  }

  Stream<int> watchOverstayingPenaltyCredits() =>
      _db.collection('settings').doc('credits').snapshots().map((snapshot) {
        final value = snapshot.data()?['overstayingPenaltyCredits'];
        final credits = value is num ? value.toInt() : 10;
        return credits >= 1 && credits <= 10000 ? credits : 10;
      });

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
    final minimum = await getMinimumTopUpCredits();
    if (amount < minimum) {
      throw ArgumentError(
        'Minimum top-up is PHP ${minimum.toStringAsFixed(2)}.',
      );
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
    // The administrator checks reference uniqueness before approval. Reading
    // every passenger's requests here would expose their private receipts.
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
    if (!user.exists || user.data()?['active'] == false) {
      throw StateError(
        'This account is inactive. Please contact the administrator.',
      );
    }
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
    String vehicleType, {
    required double confirmedFare,
    required String confirmedDirection,
  }) async {
    await _trustedRequest('/api/board', {
      'bookingId': bookingId,
      'vehicleId': vehicleId,
      'vehicleType': vehicleType,
      'confirmedFare': confirmedFare,
      'confirmedDirection': confirmedDirection,
    });
    return getProfile(uid);
  }

  Future<
    ({double fare, String direction, String directionLabel, String fareType})
  >
  previewBoardingFare(String bookingId, String vehicleId) async {
    final results = await Future.wait([
      _db.collection('trips').doc(bookingId).get(),
      _db.collection('vehicles').doc(vehicleId).get(),
    ]);
    final trip = results[0].data();
    final vehicle = results[1].data();
    if (trip == null ||
        vehicle == null ||
        trip['status'] != 'waiting' ||
        !vehicleGpsIsFresh(vehicle)) {
      throw StateError('Booking or vehicle is no longer available.');
    }
    final direction = '${vehicle['routeDirection'] ?? ''}';
    if (!const {'towardLastStop', 'towardFirstStop'}.contains(direction)) {
      throw StateError('Vehicle direction is not available yet.');
    }
    final routes = await getRoutes();
    final pickup = routes.indexWhere((r) => r['id'] == trip['pickupRouteId']);
    final dropOff = routes.indexWhere(
      (r) => r['id'] == trip['destinationRouteId'],
    );
    if (pickup < 0 || dropOff < 0 || pickup == dropOff) {
      throw StateError('The booked route is no longer active.');
    }
    final roundTrip = direction == 'towardLastStop'
        ? dropOff < pickup
        : dropOff > pickup;
    final fares = await getFareSettings();
    final count = (trip['passengerCount'] as num?)?.toInt() ?? 1;
    return (
      fare: (roundTrip ? fares.roundTripFare : fares.defaultFare) * count,
      direction: direction,
      directionLabel: direction == 'towardLastStop'
          ? '${routes.first['name']} → ${routes.last['name']}'
          : '${routes.last['name']} → ${routes.first['name']}',
      fareType: roundTrip ? 'Round trip' : 'Regular',
    );
  }

  Future<void> completeRide(String uid, String bookingId) async {
    await _trustedRequest('/api/arrive', {'bookingId': bookingId});
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
    return 'passenger_$encoded@${core.Firebase.app().options.projectId}.firebaseapp.com';
  }

  static Passenger _passenger(String uid, Map<String, dynamic> data) =>
      Passenger.fromJson({
        'id': uid,
        ...data,
        // Never surface Firebase Auth's internal/login email in passenger UI.
        // Only the separately verified recovery address is user-facing.
        'email': data['recoveryEmail'] ?? '',
        'emailVerified': data['recoveryEmailVerified'] == true,
      });

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

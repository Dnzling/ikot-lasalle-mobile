import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' as core;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as image;

Duration vehicleGpsStaleAfter = const Duration(seconds: 120);
const passengerIdNumberLength = 9;
bool validPassengerIdNumber(String value) =>
    RegExp(r'^\d{9}$').hasMatch(value.trim());

bool vehicleGpsIsFresh(Map<String, dynamic> vehicle, {DateTime? now}) {
  final lastGpsAt = vehicle['lastGpsAt'];
  if (lastGpsAt is! Timestamp) return false;
  final age = (now ?? DateTime.now()).difference(lastGpsAt.toDate());
  return age >= const Duration(seconds: -5) && age <= vehicleGpsStaleAfter;
}

String vehicleDisplayStatus(Map<String, dynamic> vehicle) {
  if (!vehicleGpsIsFresh(vehicle)) return 'OFFLINE';
  return '${vehicle['status'] ?? 'idle'}'.toUpperCase();
}

class FirebaseService {
  FirebaseService._();
  static final instance = FirebaseService._();
  final auth = FirebaseAuth.instance;
  final db = FirebaseFirestore.instance;

  Stream<User?> get authChanges => auth.authStateChanges();

  Future<bool> canCreateInitialAdmin() async {
    final bootstrap = await db
        .collection('system')
        .doc('adminBootstrap')
        .get();
    return !bootstrap.exists;
  }

  Future<void> createInitialAdmin({
    required String idNumber,
    required String password,
  }) async {
    final cleanId = idNumber.trim();
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(cleanId)) {
      throw ArgumentError('The admin ID can contain letters and numbers only.');
    }
    if (password.length < 6) {
      throw ArgumentError('The password must contain at least 6 characters.');
    }

    final bootstrapRef = db.collection('system').doc('adminBootstrap');
    final initialState = await bootstrapRef.get();
    if (initialState.exists) {
      throw StateError('The initial admin account has already been created.');
    }

    final email = _adminAuthEmailForId(cleanId);
    final credential = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw StateError('Firebase did not return the new admin account.');
    }

    try {
      await db.runTransaction((transaction) async {
        final bootstrap = await transaction.get(bootstrapRef);
        if (bootstrap.exists) {
          throw StateError('The initial admin account has already been created.');
        }

        final now = FieldValue.serverTimestamp();
        transaction.set(bootstrapRef, {
          'uid': user.uid,
          'idNumber': cleanId,
          'createdAt': now,
        });
        transaction.set(db.collection('users').doc(user.uid), {
          'idNumber': cleanId,
          'firstName': 'Admin',
          'lastName': 'La Salle',
          'userType': 'Admin',
          'active': true,
          'email': email,
          'emailVerified': false,
          'createdAt': now,
          'updatedAt': now,
        });
        transaction.set(db.collection('loginAliases').doc(cleanId), {
          'uid': user.uid,
          'idNumber': cleanId,
          'email': email,
          'userType': 'Admin',
          'createdAt': now,
        });
      });
    } catch (_) {
      try {
        await user.delete();
      } on FirebaseAuthException {
        await auth.signOut();
      }
      rethrow;
    }
  }

  Future<void> signIn(String idNumber, String password) async {
    final cleanId = idNumber.trim();
    final alias = await db.collection('loginAliases').doc(cleanId).get();
    final email = '${alias.data()?['email'] ?? ''}'.trim();
    if (email.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'No admin account is registered with that ID number.',
      );
    }
    await auth.signInWithEmailAndPassword(email: email, password: password);
    final profile = await db.collection('users').doc(auth.currentUser!.uid).get();
    final data = profile.data();
    if (data == null ||
        '${data['userType'] ?? ''}'.toLowerCase() != 'admin' ||
        '${data['idNumber'] ?? ''}'.trim() != cleanId ||
        data['active'] == false) {
      await auth.signOut();
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'This account is not an active administrator.',
      );
    }
  }

  Future<void> signOut() => auth.signOut();

  Future<void> sendPasswordReset(String email) =>
      auth.sendPasswordResetEmail(email: email.trim());

  Future<void> logExportActivity({
    required String report,
    required String format,
    required int rowCount,
  }) => db.collection('exportLogs').add({
    'report': report,
    'format': format,
    'rowCount': rowCount,
    'adminId': auth.currentUser?.uid,
    'createdAt': FieldValue.serverTimestamp(),
  });

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchDocument(
    String collection,
    String documentId,
  ) => db.collection(collection).doc(documentId).snapshots();

  Future<({double registration, double minimumTopUp})> getCreditSettings() async {
    final snapshot = await db.collection('settings').doc('credits').get(
      const GetOptions(source: Source.server),
    );
    final data = snapshot.data();
    return (
      registration: (data?['registrationCredits'] as num?)?.toDouble() ?? 100,
      minimumTopUp: (data?['minimumTopUpCredits'] as num?)?.toDouble() ?? 1,
    );
  }

  Future<void> updateCreditSettings({
    required double registration,
    required double minimumTopUp,
  }) async {
    bool valid(double value, {bool zeroAllowed = false}) =>
        value.isFinite && value >= (zeroAllowed ? 0 : 0.01) &&
        value <= 10000 && (value * 100 - (value * 100).round()).abs() < 0.000001;
    if (!valid(registration, zeroAllowed: true) || !valid(minimumTopUp)) {
      throw ArgumentError('Enter valid credit amounts up to 10,000 with at most two decimals.');
    }
    await db.collection('settings').doc('credits').set({
      'registrationCredits': registration,
      'minimumTopUpCredits': minimumTopUp,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': auth.currentUser?.uid,
    }, SetOptions(merge: true));
    await logAdminActivity(
      action: 'Updated credit settings',
      details: 'Registration: ${registration.toStringAsFixed(2)} credits; minimum top-up: ${minimumTopUp.toStringAsFixed(2)} credits.',
    );
  }

  Future<void> loadVehicleStatusTimeout() async {
    final snapshot = await db.collection('settings').doc('vehicleStatus').get();
    final seconds = (snapshot.data()?['offlineAfterSeconds'] as num?)?.toInt();
    if (seconds != null && seconds >= 10 && seconds <= 3600) {
      vehicleGpsStaleAfter = Duration(seconds: seconds);
    }
  }

  Future<void> updateVehicleStatusTimeout(int seconds) async {
    await db.collection('settings').doc('vehicleStatus').set({
      'offlineAfterSeconds': seconds,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': auth.currentUser?.uid,
    }, SetOptions(merge: true));
    vehicleGpsStaleAfter = Duration(seconds: seconds);
    await logAdminActivity(
      action: 'Updated vehicle status timing',
      details:
          'Vehicles are marked offline after $seconds seconds without GPS.',
    );
  }

  Future<void> updateFuelingLocations({
    required GeoPoint entrance,
    required GeoPoint exit,
    required double entranceRadiusMeters,
    required double exitRadiusMeters,
  }) async {
    await db.collection('settings').doc('fuelingLocations').set({
      'entrance': entrance,
      'exit': exit,
      'entranceRadiusMeters': entranceRadiusMeters,
      'exitRadiusMeters': exitRadiusMeters,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': auth.currentUser?.uid,
    }, SetOptions(merge: true));
    await logAdminActivity(
      action: 'Updated fueling gate locations',
      details:
          'Entrance: ${entrance.latitude}, ${entrance.longitude} (${entranceRadiusMeters.round()} m); exit: ${exit.latitude}, ${exit.longitude} (${exitRadiusMeters.round()} m).',
    );
  }

  Future<Set<String>> getReadAdminAlertIds() async {
    final adminId = auth.currentUser?.uid;
    if (adminId == null) return <String>{};
    final snapshot = await db
        .collection('adminNotificationReads')
        .where('adminId', isEqualTo: adminId)
        .get();
    return snapshot.docs
        .map((doc) => doc.data()['alertId'])
        .whereType<String>()
        .toSet();
  }

  Future<void> markAdminAlertsRead(Iterable<String> alertIds) async {
    final adminId = auth.currentUser?.uid;
    if (adminId == null) return;
    final ids = alertIds.toSet();
    if (ids.isEmpty) return;
    final batches = <WriteBatch>[];
    var batch = db.batch();
    var count = 0;
    for (final alertId in ids) {
      final key = base64Url.encode(utf8.encode(alertId)).replaceAll('=', '');
      batch.set(
        db.collection('adminNotificationReads').doc('${adminId}_$key'),
        {
          'adminId': adminId,
          'alertId': alertId,
          'readAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (++count == 450) {
        batches.add(batch);
        batch = db.batch();
        count = 0;
      }
    }
    if (count > 0) batches.add(batch);
    for (final pendingBatch in batches) {
      await pendingBatch.commit();
    }
  }

  Future<void> logAdminActivity({
    required String action,
    required String details,
  }) => db.collection('adminAuditLogs').add({
    'action': action,
    'details': details,
    'adminId': auth.currentUser?.uid,
    'createdAt': FieldValue.serverTimestamp(),
  });

  Future<int> bulkInactivate({
    required String collection,
    required List<String> ids,
    required String reason,
  }) async {
    if (collection != 'users' && collection != 'drivers') {
      throw ArgumentError('Unsupported account collection.');
    }
    if (!const {'Graduated', 'Resigned', 'Terminated'}.contains(reason)) {
      throw ArgumentError('Choose a valid inactive reason.');
    }
    final uniqueIds = ids.toSet().toList();
    var changed = 0;
    for (var offset = 0; offset < uniqueIds.length; offset += 200) {
      final chunk = uniqueIds.skip(offset).take(200).toList();
      final snapshots = await Future.wait(
        chunk.map((id) => db.collection(collection).doc(id).get()),
      );
      final batch = db.batch();
      var chunkChanged = 0;
      final changedIds = <String>[];
      for (final snapshot in snapshots) {
        final data = snapshot.data();
        if (data == null || data['active'] == false || data['archived'] == true)
          continue;
        if (collection == 'users') {
          final type = '${data['userType'] ?? ''}';
          if (reason == 'Graduated' && type != 'Student') continue;
          if (reason != 'Graduated' && type != 'Staff' && type != 'Teacher')
            continue;
        }
        batch.update(snapshot.reference, {
          'active': false,
          'inactiveReason': reason,
          'inactiveAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          if (collection == 'users') 'session.active': false,
          if (collection == 'drivers') 'vehicleId': null,
          if (collection == 'drivers') 'vehicleName': 'Unassigned',
        });
        if (collection == 'drivers') {
          final vehicleId = data['vehicleId'] as String?;
          if (vehicleId != null && vehicleId.isNotEmpty) {
            final vehicleRef = db.collection('vehicles').doc(vehicleId);
            batch.update(vehicleRef, {
              'driverId': FieldValue.delete(),
              'driverName': FieldValue.delete(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
        chunkChanged++;
        changedIds.add(snapshot.id);
      }
      if (chunkChanged == 0) continue;
      await batch.commit();
      changed += chunkChanged;
      await logAdminActivity(
        action:
            'Bulk inactivated ${collection == 'users' ? 'passengers' : 'drivers'}',
        details:
            '$reason: $chunkChanged account(s); IDs: ${changedIds.join(', ')}.',
      );
    }
    return changed;
  }

  Future<int> archivePassengers(List<String> ids) async {
    var changed = 0;
    final uniqueIds = ids.toSet().toList();
    for (var offset = 0; offset < uniqueIds.length; offset += 200) {
      final snapshots = await Future.wait(uniqueIds.skip(offset).take(200)
          .map((id) => db.collection('users').doc(id).get()));
      final batch = db.batch();
      final changedIds = <String>[];
      for (final snapshot in snapshots) {
        final data = snapshot.data();
        if (data == null || data['archived'] == true) continue;
        batch.update(snapshot.reference, {
          'archived': true,
          'archivedAt': FieldValue.serverTimestamp(),
          'active': false,
          'session.active': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        final session = data['session'];
        if (session is Map && session['id'] is String &&
            (session['id'] as String).isNotEmpty) {
          batch.set(snapshot.reference.collection('sessions').doc(session['id'] as String), {
            'active': false,
            'endReason': 'archived',
          }, SetOptions(merge: true));
        }
        changedIds.add(snapshot.id);
      }
      if (changedIds.isEmpty) continue;
      await batch.commit();
      changed += changedIds.length;
      await logAdminActivity(
        action: 'Archived passenger accounts',
        details: '${changedIds.length} account(s); IDs: ${changedIds.join(', ')}.',
      );
    }
    return changed;
  }

  Future<void> restorePassenger(String userId) async {
    final ref = db.collection('users').doc(userId);
    final snapshot = await ref.get();
    if (!snapshot.exists) throw StateError('Passenger account not found.');
    await ref.update({
      'archived': false,
      'archivedAt': FieldValue.delete(),
      'active': true,
      'inactiveReason': FieldValue.delete(),
      'inactiveAt': FieldValue.delete(),
      'session.active': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await logAdminActivity(
      action: 'Restored passenger account',
      details: 'User ID: $userId; type: ${snapshot.data()?['userType'] ?? ''}.',
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watch(
    String collection, {
    String orderBy = 'createdAt',
  }) =>
      db.collection(collection).orderBy(orderBy, descending: true).snapshots();

  Future<void> addVehicle({
    required String name,
    required int capacity,
    required String plateNumber,
    required String type,
  }) async {
    await _ensureUniqueVehiclePlate(plateNumber);
    await db.collection('vehicles').add({
      'name': name.trim(),
      'passengerCapacity': capacity,
      'plateNumber': plateNumber.trim().toUpperCase(),
      'type': type,
      'onBoardPassengers': 0,
      'outBoardPassengers': 0,
      'expectedOutboardByStop': <String, int>{},
      'tripPassengerCount': 0,
      'tripIncome': 0.0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await logAdminActivity(
      action: 'Created vehicle',
      details:
          '${type.trim()} $name (${plateNumber.trim()}); capacity $capacity.',
    );
  }

  Future<void> updateVehicle(
    String vehicleId, {
    required String name,
    required int capacity,
    required String plateNumber,
    required String type,
  }) async {
    await _ensureUniqueVehiclePlate(plateNumber, excludingVehicleId: vehicleId);
    await db.collection('vehicles').doc(vehicleId).update({
      'name': name.trim(),
      'passengerCapacity': capacity,
      'plateNumber': plateNumber.trim().toUpperCase(),
      'type': type,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await logAdminActivity(
      action: 'Updated vehicle',
      details:
          '${type.trim()} $name (${plateNumber.trim()}); capacity $capacity. Vehicle ID: $vehicleId.',
    );
  }

  Future<void> _ensureUniqueVehiclePlate(
    String plateNumber, {
    String? excludingVehicleId,
  }) async {
    final normalized = plateNumber.trim().toUpperCase();
    if (normalized.isEmpty) return;
    final vehicles = await db.collection('vehicles').get();
    final duplicate = vehicles.docs.any((vehicle) {
      if (vehicle.id == excludingVehicleId) return false;
      final existing = '${vehicle.data()['plateNumber'] ?? ''}'
          .trim()
          .toUpperCase();
      return existing == normalized;
    });
    if (duplicate) {
      throw ArgumentError('Plate number is already registered.');
    }
  }

  /// Move legacy vehicle compensation to its assigned driver once.
  Future<void> migrateDriverCompensationFromVehicles() async {
    final vehicles = await db.collection('vehicles').get();
    for (final vehicleDoc in vehicles.docs) {
      final data = vehicleDoc.data();
      final driverId = '${data['driverId'] ?? ''}'.trim();
      if (driverId.isEmpty ||
          (!data.containsKey('dailyQuota') &&
              !data.containsKey('driverSalary'))) {
        continue;
      }
      final driverRef = db.collection('drivers').doc(driverId);
      await db.runTransaction((transaction) async {
        final vehicle = await transaction.get(vehicleDoc.reference);
        final driver = await transaction.get(driverRef);
        if (!vehicle.exists ||
            !driver.exists ||
            vehicle.data()?['driverId'] != driverId)
          return;
        final old = vehicle.data()!;
        final current = driver.data()!;
        final driverChanges = <String, dynamic>{};
        if (!current.containsKey('dailySalary') && old['driverSalary'] is num) {
          driverChanges['dailySalary'] = old['driverSalary'];
        }
        if (!current.containsKey('dailyQuota') && old['dailyQuota'] is num) {
          driverChanges['dailyQuota'] = old['dailyQuota'];
        }
        if (driverChanges.isNotEmpty)
          transaction.update(driverRef, driverChanges);
        if (old.containsKey('driverSalary') || old.containsKey('dailyQuota')) {
          transaction.update(vehicleDoc.reference, {
            if (old.containsKey('driverSalary'))
              'driverSalary': FieldValue.delete(),
            if (old.containsKey('dailyQuota'))
              'dailyQuota': FieldValue.delete(),
          });
        }
      });
    }
  }

  Future<void> archiveVehicle(String vehicleId) async {
    await db.collection('vehicles').doc(vehicleId).update({
      'archived': true,
      'archivedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await logAdminActivity(
      action: 'Archived vehicle',
      details: 'Vehicle ID: $vehicleId.',
    );
  }

  Future<void> restoreVehicle(String vehicleId) async {
    await db.collection('vehicles').doc(vehicleId).update({
      'archived': false,
      'archivedAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await logAdminActivity(
      action: 'Restored vehicle',
      details: 'Vehicle ID: $vehicleId.',
    );
  }

  Future<void> deleteVehicle(String vehicleId) async {
    final vehicleRef = db.collection('vehicles').doc(vehicleId);
    final vehicle = await vehicleRef.get();
    final driverId = '${vehicle.data()?['driverId'] ?? ''}'.trim();
    final batch = db.batch();
    if (driverId.isNotEmpty) {
      final driverRef = db.collection('drivers').doc(driverId);
      final driver = await driverRef.get();
      if (driver.exists && driver.data()?['vehicleId'] == vehicleId) {
        batch.update(driverRef, {
          'vehicleId': null,
          'vehicleName': 'Unassigned',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    batch.delete(vehicleRef);
    await batch.commit();
    await logAdminActivity(
      action: 'Deleted vehicle',
      details: 'Vehicle ID: $vehicleId.',
    );
  }

  Future<void> addDriver(
    Map<String, dynamic> data, {
    Uint8List? photoBytes,
    String photoContentType = 'image/jpeg',
  }) async {
    final driverRef = db.collection('drivers').doc();
    final vehicleId = data['vehicleId'] as String?;
    String? vehicleName;
    if (vehicleId != null) {
      final vehicle = await db.collection('vehicles').doc(vehicleId).get();
      if (!vehicle.exists ||
          vehicle.data()?['archived'] == true ||
          (vehicle.data()?['driverId'] != null &&
              '${vehicle.data()?['driverId']}'.isNotEmpty)) {
        throw StateError('Vehicle is unavailable or already assigned.');
      }
      vehicleName = vehicle.data()?['name'] as String?;
    }
    String? photoBase64;
    if (photoBytes != null) {
      photoBase64 = _driverPhotoBase64(photoBytes, photoContentType);
    }
    final batch = db.batch();
    batch.set(driverRef, {
      ...data,
      if (photoBase64 != null) 'photoBase64': photoBase64,
      // The Firestore document ID is the canonical driver ID. It is created
      // here so the form never needs to ask an administrator to type one.
      'driverId': driverRef.id,
      'vehicleName': vehicleName ?? 'Unassigned',
      'createdAt': FieldValue.serverTimestamp(),
      'active': true,
    });
    if (vehicleId != null) {
      batch.update(db.collection('vehicles').doc(vehicleId), {
        'driverId': driverRef.id,
        'driverName': '${data['firstName']} ${data['lastName']}'.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    await logAdminActivity(
      action: 'Created driver',
      details:
          '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim() +
          '; driver ID: ${driverRef.id}; assigned vehicle: ${vehicleName ?? 'Unassigned'}.',
    );
  }

  Future<void> updateDriverPhoto({
    required String driverId,
    required Uint8List? photoBytes,
    String photoContentType = 'image/jpeg',
  }) async {
    final driverRef = db.collection('drivers').doc(driverId);
    final current = await driverRef.get();
    if (!current.exists) throw StateError('Driver not found.');
    final oldPath = '${current.data()?['photoPath'] ?? ''}';
    if (photoBytes == null) {
      await driverRef.update({
        'photoBase64': FieldValue.delete(),
        'photoUrl': FieldValue.delete(),
        'photoPath': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (oldPath.isNotEmpty) unawaited(_cleanupDriverPhoto(oldPath));
      await logAdminActivity(
        action: 'Removed driver photo',
        details: 'Driver ID: $driverId.',
      );
      return;
    }
    final photoBase64 = _driverPhotoBase64(photoBytes, photoContentType);
    await driverRef.update({
      'photoBase64': photoBase64,
      'photoUrl': FieldValue.delete(),
      'photoPath': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (oldPath.isNotEmpty) unawaited(_cleanupDriverPhoto(oldPath));
    await logAdminActivity(
      action: 'Updated driver photo',
      details: 'Driver ID: $driverId.',
    );
  }

  Future<void> _deleteDriverPhotoIfPresent(String path) async {
    try {
      await FirebaseStorage.instance.ref(path).delete();
    } on FirebaseException catch (error) {
      if (!error.code.endsWith('object-not-found')) rethrow;
    }
  }

  String _driverPhotoBase64(Uint8List bytes, String contentType) {
    if (bytes.length > 5 * 1024 * 1024 || !contentType.startsWith('image/')) {
      throw ArgumentError('Choose an image smaller than 5 MB.');
    }
    final decoded = image.decodeImage(bytes);
    if (decoded == null)
      throw ArgumentError('Could not read the selected image.');
    var resized = image.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? 480 : null,
      height: decoded.height > decoded.width ? 480 : null,
    );
    var encoded = image.encodeJpg(resized, quality: 70);
    if (encoded.length > 300 * 1024) {
      resized = image.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? 320 : null,
        height: decoded.height > decoded.width ? 320 : null,
      );
      encoded = image.encodeJpg(resized, quality: 55);
    }
    if (encoded.length > 300 * 1024) {
      throw ArgumentError(
        'Could not reduce the photo below 300 KB. Choose another image.',
      );
    }
    return base64Encode(encoded);
  }

  Future<void> _cleanupDriverPhoto(String path) async {
    try {
      await _deleteDriverPhotoIfPresent(
        path,
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Cleanup should not turn a successful profile save into a failure.
    }
  }

  Future<void> updateDriver(String driverId, Map<String, dynamic> data) async {
    final driverRef = db.collection('drivers').doc(driverId);
    final newVehicleId = data['vehicleId'] as String?;
    await db.runTransaction((transaction) async {
      final driver = await transaction.get(driverRef);
      if (!driver.exists) throw StateError('Driver not found.');
      final oldVehicleId = driver.data()?['vehicleId'] as String?;
      final oldVehicleRef = oldVehicleId == null
          ? null
          : db.collection('vehicles').doc(oldVehicleId);
      final newVehicleRef = newVehicleId == null
          ? null
          : db.collection('vehicles').doc(newVehicleId);
      final oldVehicle = oldVehicleRef == null
          ? null
          : await transaction.get(oldVehicleRef);
      final newVehicle = newVehicleRef == null
          ? null
          : oldVehicleId == newVehicleId
          ? oldVehicle
          : await transaction.get(newVehicleRef);
      if (newVehicleRef != null &&
          (newVehicle == null ||
              !newVehicle.exists ||
              newVehicle.data()?['archived'] == true ||
              (newVehicle.data()?['driverId'] != null &&
                  newVehicle.data()?['driverId'] != driverId))) {
        throw StateError('Vehicle is unavailable or already assigned.');
      }
      if (oldVehicleRef != null &&
          oldVehicle?.exists == true &&
          oldVehicle?.data()?['driverId'] == driverId &&
          oldVehicleId != newVehicleId) {
        transaction.update(oldVehicleRef, {
          'driverId': FieldValue.delete(),
          'driverName': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.update(driverRef, {
        ...data,
        if (data['active'] == true) 'inactiveReason': FieldValue.delete(),
        if (data['active'] == true) 'inactiveAt': FieldValue.delete(),
        'licenseNumber': FieldValue.delete(),
        'licenseExpiry': FieldValue.delete(),
        'vehicleName': newVehicle?.data()?['name'] ?? 'Unassigned',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (newVehicleRef != null) {
        transaction.update(newVehicleRef, {
          'driverId': driverId,
          'driverName': '${data['firstName']} ${data['lastName']}'.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    await logAdminActivity(
      action: 'Updated driver',
      details:
          '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim() +
          '; driver ID: $driverId; assigned vehicle: ${newVehicleId ?? 'Unassigned'}.',
    );
  }

  Future<void> archiveDriver(String driverId) async {
    final driverRef = db.collection('drivers').doc(driverId);
    await db.runTransaction((transaction) async {
      final driver = await transaction.get(driverRef);
      if (!driver.exists) throw StateError('Driver not found.');
      final vehicleId = driver.data()?['vehicleId'] as String?;
      final vehicleRef = vehicleId == null
          ? null
          : db.collection('vehicles').doc(vehicleId);
      final vehicle = vehicleRef == null
          ? null
          : await transaction.get(vehicleRef);
      if (vehicleRef != null && vehicle?.data()?['driverId'] == driverId) {
        transaction.update(vehicleRef, {
          'driverId': FieldValue.delete(),
          'driverName': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.update(driverRef, {
        'archived': true,
        'active': false,
        'vehicleId': null,
        'vehicleName': 'Unassigned',
        'archivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    await logAdminActivity(
      action: 'Archived driver',
      details: 'Driver ID: $driverId.',
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchTopUpRequests() => db
      .collection('topUpRequests')
      .orderBy('submittedAt', descending: true)
      .snapshots();

  Future<String> manualTopUp({required String userId, required double amount}) async {
    if (!amount.isFinite || amount < 0.01 || amount > 10000 ||
        (amount * 100 - (amount * 100).round()).abs() > 0.000001) {
      throw ArgumentError('Enter an amount between 0.01 and 10,000 credits.');
    }
    final userRef = db.collection('users').doc(userId);
    final settingsRef = db.collection('settings').doc('credits');
    final requestRef = db.collection('topUpRequests').doc();
    final reference = 'MT-${DateTime.now().toUtc().millisecondsSinceEpoch}-${requestRef.id.substring(0, 6).toUpperCase()}';
    final stamp = FieldValue.serverTimestamp();
    await db.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      final settingsSnapshot = await transaction.get(settingsRef);
      final minimum = (settingsSnapshot.data()?['minimumTopUpCredits'] as num?)?.toDouble() ?? 1;
      if (amount < minimum) {
        throw ArgumentError('Minimum top-up is ${minimum.toStringAsFixed(2)} credits.');
      }
      final user = snapshot.data();
      if (user == null || user['active'] == false || user['archived'] == true ||
          '${user['userType'] ?? ''}'.toLowerCase() == 'admin') {
        throw StateError('Select an active passenger account.');
      }
      final balance = (user['balance'] as num?)?.toDouble() ?? 0;
      final name = '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
      transaction.update(userRef, {'balance': balance + amount});
      transaction.set(requestRef, {
        'userId': userId,
        'passengerName': name,
        'passengerId': '${user['idNumber'] ?? ''}',
        'amount': amount,
        'referenceNumber': reference,
        'source': 'manual',
        'status': 'approved',
        'submittedAt': stamp,
        'reviewedAt': stamp,
        'creditedAt': stamp,
        'reviewedBy': auth.currentUser?.uid,
      });
      transaction.set(db.collection('transactions').doc('manualTopUp_${requestRef.id}'), {
        'userId': userId,
        'passengerName': name,
        'passengerId': '${user['idNumber'] ?? ''}',
        'type': 'topUp',
        'title': 'Manual top-up',
        'description': 'Admin manual top-up',
        'amount': amount,
        'referenceNumber': reference,
        'topUpRequestId': requestRef.id,
        'createdAt': stamp,
      });
      transaction.set(db.collection('notifications').doc(), {
        'userId': userId,
        'type': 'topUp',
        'title': 'Manual top-up credited',
        'message': 'PHP ${amount.toStringAsFixed(2)} was added to your credits. Reference: $reference.',
        'createdAt': stamp,
      });
      transaction.set(db.collection('adminAuditLogs').doc(), {
        'action': 'Manual top-up',
        'details': 'User ID: $userId; amount: PHP ${amount.toStringAsFixed(2)}; reference: $reference.',
        'adminId': auth.currentUser?.uid,
        'createdAt': stamp,
      });
    });
    return reference;
  }

  Future<String> getGcashNumber() async {
    final settings = await getGcashSettings();
    return settings['gcashNumber'] ?? '';
  }

  Future<Map<String, String>> getGcashSettings() async {
    final snapshot = await db.collection('settings').doc('payment').get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    return {
      'accountName': '${data['accountName'] ?? ''}'.trim(),
      'gcashNumber': '${data['gcashNumber'] ?? ''}'.trim(),
    };
  }

  Future<void> updateGcashSettings({
    required String accountName,
    required String gcashNumber,
  }) async {
    await db.collection('settings').doc('payment').set({
      'accountName': accountName.trim(),
      'gcashNumber': gcashNumber.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await logAdminActivity(
      action: 'Updated GCash payment settings',
      details:
          'Account name updated; GCash number ending ${gcashNumber.trim().length >= 4 ? gcashNumber.trim().substring(gcashNumber.trim().length - 4) : gcashNumber.trim()}.',
    );
  }

  Future<void> updateGcashNumber(String gcashNumber) async {
    final settings = await getGcashSettings();
    await updateGcashSettings(
      accountName: settings['accountName'] ?? '',
      gcashNumber: gcashNumber,
    );
  }

  Future<void> reviewTopUpRequest(
    String requestId, {
    required bool approve,
    String adminNote = '',
  }) async {
    final requestRef = db.collection('topUpRequests').doc(requestId);
    if (approve) {
      final current = await requestRef.get(
        const GetOptions(source: Source.server),
      );
      final reference = '${current.data()?['referenceNumber'] ?? ''}'.trim();
      if (reference.isEmpty || !RegExp(r'^\d{13}$').hasMatch(reference)) {
        throw StateError(
          'This request has no valid 13-digit reference number.',
        );
      }
      final matchingRequests = await db
          .collection('topUpRequests')
          .where('referenceNumber', isEqualTo: reference)
          .get(const GetOptions(source: Source.server));
      if (matchingRequests.docs.any(
        (doc) =>
            doc.id != requestId &&
            '${doc.data()['status'] ?? ''}'.trim().toLowerCase() == 'approved',
      )) {
        throw StateError(
          'This GCash reference was already approved for another top-up.',
        );
      }
      final matchingTransactions = await db
          .collection('transactions')
          .where('referenceNumber', isEqualTo: reference)
          .get(const GetOptions(source: Source.server));
      if (matchingTransactions.docs.any(
        (doc) =>
            doc.data()['topUpRequestId'] != requestId &&
            '${doc.data()['type'] ?? ''}'.toLowerCase() == 'topup',
      )) {
        throw StateError('This GCash reference was already credited.');
      }
    }
    var amountForAudit = 0.0;
    var passengerForAudit = '';
    await db.runTransaction((transaction) async {
      final requestSnapshot = await transaction.get(requestRef);
      final request = requestSnapshot.data();
      if (request == null) throw StateError('Top-up request was not found.');
      if ('${request['status'] ?? 'pending'}' != 'pending') {
        throw StateError('This top-up request has already been reviewed.');
      }
      final amount =
          (request['amount'] as num?)?.toDouble() ??
          double.tryParse('${request['amount']}') ??
          0;
      amountForAudit = amount;
      passengerForAudit = '${request['passengerName'] ?? ''}';
      final userId = '${request['userId'] ?? ''}'.trim();
      final reference = '${request['referenceNumber'] ?? ''}'.trim();
      if (amount <= 0 || userId.isEmpty) {
        throw StateError('The top-up request is missing payment details.');
      }

      DocumentSnapshot<Map<String, dynamic>>? userSnapshot;
      final transactionRef = db
          .collection('transactions')
          .doc('topUp_$reference');
      if (approve) {
        userSnapshot = await transaction.get(
          db.collection('users').doc(userId),
        );
        final existingCredit = await transaction.get(transactionRef);
        if (existingCredit.exists) {
          throw StateError('This GCash reference was already credited.');
        }
      }

      final reviewedAt = FieldValue.serverTimestamp();
      final status = approve ? 'approved' : 'rejected';
      transaction.update(requestRef, {
        'status': status,
        'adminNote': adminNote.trim(),
        'reviewedAt': reviewedAt,
        'reviewedBy': auth.currentUser?.uid,
        if (approve) 'creditedAt': reviewedAt,
      });

      final userRef = db.collection('users').doc(userId);
      if (approve) {
        final user = userSnapshot?.data() ?? const <String, dynamic>{};
        final balance =
            (user['balance'] as num?)?.toDouble() ??
            double.tryParse('${user['balance']}') ??
            0;
        transaction.update(userRef, {'balance': balance + amount});
        transaction.set(transactionRef, {
          'userId': userId,
          'passengerName': '${request['passengerName'] ?? ''}',
          'passengerId': '${request['passengerId'] ?? ''}',
          'type': 'topUp',
          'title': 'GCash top-up',
          'description': 'Approved GCash top-up',
          'amount': amount,
          'referenceNumber': reference,
          'topUpRequestId': requestId,
          'createdAt': reviewedAt,
        });
      }

      final notificationRef = db.collection('notifications').doc();
      transaction.set(notificationRef, {
        'userId': userId,
        'type': 'topUp',
        'title': approve ? 'Top-up approved' : 'Top-up rejected',
        'message': approve
            ? 'PHP ${amount.toStringAsFixed(2)} was added to your credits.'
            : 'Your top-up request was rejected.${adminNote.trim().isEmpty ? '' : ' $adminNote'}',
        'createdAt': reviewedAt,
      });
    });
    await logAdminActivity(
      action: approve ? 'Approved top-up' : 'Rejected top-up',
      details:
          'Request ID: $requestId; passenger: $passengerForAudit; amount: PHP ${amountForAudit.toStringAsFixed(2)}${adminNote.trim().isEmpty ? '' : '; note: ${adminNote.trim()}'}.',
    );
  }

  Future<void> createUserAccount(Map<String, dynamic> data) async {
    final idNumber = '${data['idNumber'] ?? ''}'.trim();
    final lastName = '${data['lastName'] ?? ''}'.trim();
    final userType = '${data['userType'] ?? ''}'.trim();
    if (idNumber.isEmpty ||
        lastName.isEmpty ||
        '${data['firstName'] ?? ''}'.trim().isEmpty) {
      throw ArgumentError('First name, last name, and ID number are required.');
    }
    if (!validPassengerIdNumber(idNumber)) {
      throw ArgumentError('Passenger ID number must be exactly 9 digits.');
    }
    if (RegExp(r'\d').hasMatch('${data['firstName']}') ||
        RegExp(r'\d').hasMatch(lastName)) {
      throw ArgumentError('Names cannot contain numbers.');
    }
    if (!const {'Student', 'Teacher', 'Visitor', 'Staff'}.contains(userType)) {
      throw ArgumentError('Choose a valid passenger type.');
    }
    final duplicate = await db
        .collection('users')
        .where('idNumber', isEqualTo: idNumber)
        .limit(1)
        .get();
    if (duplicate.docs.isNotEmpty) {
      throw ArgumentError('Passenger ID number is already registered.');
    }
    final registrationCredits = (await getCreditSettings()).registration;
    final secondary = await core.Firebase.initializeApp(
      name: 'admin-user-creation-${DateTime.now().microsecondsSinceEpoch}',
      options: core.Firebase.app().options,
    );
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondary);
      // Firebase Auth requires at least six characters. Keep the recognizable
      // last-name initial password while padding short names for creation.
      final password = lastName.toUpperCase().padRight(6, '0');
      final authEmail = _authEmailForId(idNumber);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
      final userRef = db.collection('users').doc(credential.user!.uid);
      final batch = db.batch();
      batch.set(userRef, {
        ...data,
        'email': authEmail,
        'balance': registrationCredits,
        'mustChangePassword': true,
        'createdAt': FieldValue.serverTimestamp(),
        'active': true,
      });
      batch.set(db.collection('loginAliases').doc(idNumber), {
        'uid': credential.user!.uid,
        'email': authEmail.toLowerCase(),
      });
      if (registrationCredits > 0) batch.set(db.collection('transactions').doc(), {
        'userId': credential.user!.uid,
        'passengerName': '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim(),
        'passengerId': idNumber,
        'type': 'initialCredit',
        'title': 'Welcome credits',
        'description': 'Initial account credits',
        'amount': registrationCredits,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      await secondaryAuth.signOut();
    } finally {
      await secondary.delete();
    }
    await logAdminActivity(
      action: 'Created passenger account',
      details:
          '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim() +
          '; type: $userType; ID ending in ${idNumber.length > 4 ? idNumber.substring(idNumber.length - 4) : idNumber}.',
    );
  }

  Future<void> updatePassengerAccount({
    required String userId,
    required Map<String, dynamic> data,
    String? newPassword,
  }) async {
    final firstName = '${data['firstName'] ?? ''}'.trim();
    final lastName = '${data['lastName'] ?? ''}'.trim();
    final idNumber = '${data['idNumber'] ?? ''}'.trim();
    final userType = '${data['userType'] ?? ''}'.trim();
    if (firstName.isEmpty || lastName.isEmpty || idNumber.isEmpty) {
      throw ArgumentError('First name, last name, and ID number are required.');
    }
    if (!validPassengerIdNumber(idNumber)) {
      throw ArgumentError('Passenger ID number must be exactly 9 digits.');
    }
    if (RegExp(r'\d').hasMatch(firstName) || RegExp(r'\d').hasMatch(lastName)) {
      throw ArgumentError('Names cannot contain numbers.');
    }
    if (!const {'Student', 'Teacher', 'Visitor', 'Staff'}.contains(userType)) {
      throw ArgumentError('Choose a valid passenger type.');
    }
    final duplicate = await db
        .collection('users')
        .where('idNumber', isEqualTo: idNumber)
        .limit(2)
        .get();
    if (duplicate.docs.any((doc) => doc.id != userId)) {
      throw ArgumentError('Passenger ID number is already registered.');
    }
    final cleanPassword = newPassword?.trim() ?? '';
    if (cleanPassword.isNotEmpty) {
      throw UnsupportedError(
        'Password reset requires a trusted server endpoint. Configure a callable Cloud Function to update passenger credentials.',
      );
    }
    final updated = Map<String, dynamic>.from(data)
      ..remove('_currentPassword')
      ..remove('email');
    final userRef = db.collection('users').doc(userId);
    final original = await userRef.get();
    final oldId = '${original.data()?['idNumber'] ?? ''}'.trim();
    final authEmail = '${original.data()?['email'] ?? ''}'.trim().toLowerCase();
    if (!original.exists || authEmail.isEmpty) {
      throw StateError('Passenger account or login email is unavailable.');
    }
    final batch = db.batch();
    batch.update(userRef, {
      ...updated,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(db.collection('loginAliases').doc(idNumber), {
      'uid': userId,
      'email': authEmail,
    });
    if (oldId.isNotEmpty && oldId != idNumber) {
      final oldAliasRef = db.collection('loginAliases').doc(oldId);
      final oldAlias = await oldAliasRef.get();
      if (oldAlias.data()?['uid'] == userId) batch.delete(oldAliasRef);
    }
    await batch.commit();
    await logAdminActivity(
      action: 'Updated passenger account',
      details:
          '${firstName.trim()} ${lastName.trim()}; type: $userType; user ID: $userId.',
    );
  }

  static String _authEmailForId(String idNumber) {
    final encoded = base64Url
        .encode(utf8.encode(idNumber.trim().toUpperCase()))
        .replaceAll('=', '');
    return 'passenger_$encoded@${core.Firebase.app().options.projectId}.firebaseapp.com';
  }

  static String _adminAuthEmailForId(String idNumber) {
    final encoded = base64Url
        .encode(utf8.encode(idNumber.trim().toUpperCase()))
        .replaceAll('=', '');
    return 'admin_$encoded@${core.Firebase.app().options.projectId}.firebaseapp.com';
  }

  Future<void> addRoute({
    required String name,
    required double radius,
    required GeoPoint location,
  }) async {
    final existing = await db.collection('routes').count().get();
    await db.collection('routes').add({
      'name': name.trim(),
      'proximityRadius': radius,
      'location': location,
      'order': existing.count ?? 0,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await logAdminActivity(
      action: 'Created route point',
      details:
          '${name.trim()}; radius: ${radius.round()} m; coordinates: ${location.latitude}, ${location.longitude}.',
    );
  }

  Future<void> updateRoute(
    String routeId, {
    required String name,
    required double radius,
    required GeoPoint location,
  }) async {
    await db.collection('routes').doc(routeId).update({
      'name': name.trim(),
      'proximityRadius': radius,
      'location': location,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await logAdminActivity(
      action: 'Updated route point',
      details:
          '${name.trim()}; route ID: $routeId; radius: ${radius.round()} m; coordinates: ${location.latitude}, ${location.longitude}.',
    );
  }

  Future<void> setRouteActive(String routeId, bool active) async {
    await db.collection('routes').doc(routeId).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await logAdminActivity(
      action: active ? 'Activated route' : 'Deactivated route',
      details: 'Route ID: $routeId.',
    );
  }

  Future<void> archiveRoute(String routeId) async {
    await db.collection('routes').doc(routeId).update({
      'archived': true,
      'active': false,
      'archivedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await logAdminActivity(
      action: 'Archived route',
      details: 'Route ID: $routeId.',
    );
  }

  Future<void> restoreRoute(String routeId) async {
    await db.collection('routes').doc(routeId).update({
      'archived': false,
      'active': false,
      'archivedAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await logAdminActivity(
      action: 'Restored route',
      details: 'Route ID: $routeId.',
    );
  }

  Future<void> reorderRoutes(List<String> routeIds) async {
    final batch = db.batch();
    for (var index = 0; index < routeIds.length; index++) {
      batch.update(db.collection('routes').doc(routeIds[index]), {
        'order': index,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    await logAdminActivity(
      action: 'Reordered route points',
      details: 'Updated route order for ${routeIds.length} route points.',
    );
  }

  Future<void> updateFares(
    String routeId,
    double defaultFare,
    double roundFare,
  ) async {
    await db.collection('routes').doc(routeId).update({
      'defaultFare': defaultFare,
      'roundFare': roundFare,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await logAdminActivity(
      action: 'Updated fares',
      details:
          'Route ID: $routeId; default fare PHP ${defaultFare.toStringAsFixed(2)}; round trip PHP ${roundFare.toStringAsFixed(2)}.',
    );
  }

  Future<void> updateGlobalFares({
    required double defaultFare,
    required double roundTripFare,
  }) async {
    await db.collection('settings').doc('fares').set({
      'defaultFare': defaultFare,
      'roundTripFare': roundTripFare,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await logAdminActivity(
      action: 'Updated fares',
      details:
          'Default fare PHP ${defaultFare.toStringAsFixed(2)}; round trip fare PHP ${roundTripFare.toStringAsFixed(2)}.',
    );
  }

  Future<void> updateFaresByRouteName(
    String name,
    double defaultFare,
    double roundFare,
  ) async {
    final result = await db
        .collection('routes')
        .where('name', isEqualTo: name)
        .limit(1)
        .get();
    if (result.docs.isEmpty) return;
    await updateFares(result.docs.first.id, defaultFare, roundFare);
  }
}

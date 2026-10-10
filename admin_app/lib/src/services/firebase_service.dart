import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' as core;

class AdminProfileWriteException implements Exception {
  const AdminProfileWriteException(this.code, this.message);
  final String code;
  final String? message;
}

class FirebaseService {
  FirebaseService._();
  static final instance = FirebaseService._();
  final auth = FirebaseAuth.instance;
  final db = FirebaseFirestore.instance;

  Stream<User?> get authChanges => auth.authStateChanges();
  Future<void> signIn(String email, String password) =>
      auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  Future<void> registerAdmin(
    String first,
    String last,
    String email,
    String password,
  ) async {
    final credential = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user?.updateDisplayName('$first $last'.trim());
    try {
      await db.collection('users').doc(credential.user!.uid).set({
        'firstName': first.trim(),
        'lastName': last.trim(),
        'email': email.trim(),
        'userType': 'Admin',
        'createdAt': FieldValue.serverTimestamp(),
        'active': true,
      }, SetOptions(merge: true));
    } on core.FirebaseException catch (error) {
      // Auth account creation already succeeded. Keep the signed-in session so
      // the administrator can continue, while reporting the profile issue.
      throw AdminProfileWriteException(error.code, error.message);
    }
  }

  Future<void> createAdditionalAdmin(
    String first, String last, String email, String password,
  ) async {
    final secondary = await core.Firebase.initializeApp(
      name: 'admin-creation-${DateTime.now().microsecondsSinceEpoch}',
      options: core.Firebase.app().options,
    );
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondary);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email.trim(), password: password,
      );
      await credential.user?.updateDisplayName('$first $last'.trim());
      await db.collection('users').doc(credential.user!.uid).set({
        'firstName': first.trim(), 'lastName': last.trim(),
        'email': email.trim(), 'userType': 'Admin', 'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await secondaryAuth.signOut();
    } finally {
      await secondary.delete();
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

  Stream<QuerySnapshot<Map<String, dynamic>>> watch(
    String collection, {
    String orderBy = 'createdAt',
  }) =>
      db.collection(collection).orderBy(orderBy, descending: true).snapshots();

  Future<void> addVehicle({
    required String name,
    required int capacity,
    required double dailyQuota,
    required double driverSalary,
    required String plateNumber,
    required String type,
  }) => db.collection('vehicles').add({
    'name': name.trim(),
    'passengerCapacity': capacity,
    'dailyQuota': dailyQuota,
    'plateNumber': plateNumber.trim(),
    'type': type,
    'onBoardPassengers': 0,
    'outBoardPassengers': 0,
    'tripPassengerCount': 0,
    'tripIncome': 0.0,
    'driverSalary': driverSalary,
    'createdAt': FieldValue.serverTimestamp(),
  });

  Future<void> updateVehicle(
    String vehicleId, {
    required String name,
    required int capacity,
    required double dailyQuota,
    required double driverSalary,
    required String plateNumber,
    required String type,
  }) => db.collection('vehicles').doc(vehicleId).update({
    'name': name.trim(),
    'passengerCapacity': capacity,
    'dailyQuota': dailyQuota,
    'driverSalary': driverSalary,
    'plateNumber': plateNumber.trim(),
    'type': type,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> archiveVehicle(String vehicleId) =>
      db.collection('vehicles').doc(vehicleId).update({
        'archived': true,
        'archivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> linkVehicleGpsDevice(String vehicleId, String deviceUid) =>
      db.collection('vehicles').doc(vehicleId).update({
        'gpsDeviceUid': deviceUid.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> restoreVehicle(String vehicleId) =>
      db.collection('vehicles').doc(vehicleId).update({
        'archived': false,
        'archivedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

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
  }

  Future<void> addDriver(Map<String, dynamic> data) async {
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
    final batch = db.batch();
    batch.set(driverRef, {
      ...data,
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
  }

  Future<void> archiveDriver(String driverId) async {
    final driverRef = db.collection('drivers').doc(driverId);
    await db.runTransaction((transaction) async {
      final driver = await transaction.get(driverRef);
      if (!driver.exists) throw StateError('Driver not found.');
      final vehicleId = driver.data()?['vehicleId'] as String?;
      final vehicleRef = vehicleId == null ? null : db.collection('vehicles').doc(vehicleId);
      final vehicle = vehicleRef == null ? null : await transaction.get(vehicleRef);
      if (vehicleRef != null && vehicle?.data()?['driverId'] == driverId) {
        transaction.update(vehicleRef, {
          'driverId': FieldValue.delete(), 'driverName': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.update(driverRef, {
        'archived': true, 'active': false, 'vehicleId': null,
        'vehicleName': 'Unassigned', 'archivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchTopUpRequests() => db
      .collection('topUpRequests')
      .orderBy('submittedAt', descending: true)
      .snapshots();

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
  }) => db.collection('settings').doc('payment').set({
    'accountName': accountName.trim(),
    'gcashNumber': gcashNumber.trim(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

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
      final current = await requestRef.get(const GetOptions(source: Source.server));
      final reference = '${current.data()?['referenceNumber'] ?? ''}'.trim();
      if (reference.isEmpty || !RegExp(r'^\d{13}$').hasMatch(reference)) {
        throw StateError('This request has no valid 13-digit reference number.');
      }
      final matchingRequests = await db.collection('topUpRequests')
          .where('referenceNumber', isEqualTo: reference)
          .get(const GetOptions(source: Source.server));
      if (matchingRequests.docs.any((doc) =>
          doc.id != requestId &&
          '${doc.data()['status'] ?? ''}'.trim().toLowerCase() == 'approved')) {
        throw StateError('This GCash reference was already approved for another top-up.');
      }
      final matchingTransactions = await db.collection('transactions')
          .where('referenceNumber', isEqualTo: reference)
          .get(const GetOptions(source: Source.server));
      if (matchingTransactions.docs.any((doc) =>
          doc.data()['topUpRequestId'] != requestId &&
          '${doc.data()['type'] ?? ''}'.toLowerCase() == 'topup')) {
        throw StateError('This GCash reference was already credited.');
      }
    }
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
      final userId = '${request['userId'] ?? ''}'.trim();
      final reference = '${request['referenceNumber'] ?? ''}'.trim();
      if (amount <= 0 || userId.isEmpty) {
        throw StateError('The top-up request is missing payment details.');
      }

      DocumentSnapshot<Map<String, dynamic>>? userSnapshot;
      final transactionRef = db.collection('transactions').doc('topUp_$reference');
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
  }

  Future<void> createUserAccount(Map<String, dynamic> data) async {
    final idNumber = '${data['idNumber'] ?? ''}'.trim();
    final lastName = '${data['lastName'] ?? ''}'.trim();
    final userType = '${data['userType'] ?? ''}'.trim();
    if (idNumber.isEmpty ||
        lastName.isEmpty ||
        '${data['firstName'] ?? ''}'.trim().isEmpty ||
        !RegExp(r'^\d{11}$').hasMatch('${data['contactNumber'] ?? ''}'.trim())) {
      throw ArgumentError(
        'First name, last name, ID and contact number are required.',
      );
    }
    if (!const {'Student', 'Teacher', 'Visitor', 'Staff'}.contains(userType)) {
      throw ArgumentError('Choose a valid passenger type.');
    }
    final secondary = await core.Firebase.initializeApp(
      name: 'admin-user-creation-${DateTime.now().microsecondsSinceEpoch}',
      options: core.Firebase.app().options,
    );
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondary);
      final password = lastName.toUpperCase();
      final authEmail = _authEmailForId(idNumber);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
      await db.collection('users').doc(credential.user!.uid).set({
        ...data,
        'email': authEmail,
        'mustChangePassword': true,
        'createdAt': FieldValue.serverTimestamp(),
        'active': true,
      });
      await secondaryAuth.signOut();
    } finally {
      await secondary.delete();
    }
  }

  static String _authEmailForId(String idNumber) {
    final encoded = base64Url
        .encode(utf8.encode(idNumber.trim().toUpperCase()))
        .replaceAll('=', '');
    return 'passenger_$encoded@ikot-lasalle-ccfab.firebaseapp.com';
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
  }

  Future<void> updateRoute(
    String routeId, {
    required String name,
    required double radius,
    required GeoPoint location,
  }) => db.collection('routes').doc(routeId).update({
    'name': name.trim(),
    'proximityRadius': radius,
    'location': location,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> setRouteActive(String routeId, bool active) => db
      .collection('routes')
      .doc(routeId)
      .update({'active': active, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> archiveRoute(String routeId) =>
      db.collection('routes').doc(routeId).update({
        'archived': true,
        'active': false,
        'archivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> restoreRoute(String routeId) =>
      db.collection('routes').doc(routeId).update({
        'archived': false,
        'active': false,
        'archivedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> reorderRoutes(List<String> routeIds) async {
    final batch = db.batch();
    for (var index = 0; index < routeIds.length; index++) {
      batch.update(db.collection('routes').doc(routeIds[index]), {
        'order': index,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> updateFares(
    String routeId,
    double defaultFare,
    double roundFare,
  ) => db.collection('routes').doc(routeId).update({
    'defaultFare': defaultFare,
    'roundFare': roundFare,
    'updatedAt': FieldValue.serverTimestamp(),
  });

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

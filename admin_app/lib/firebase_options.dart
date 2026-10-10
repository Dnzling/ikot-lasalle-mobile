// Firebase project shared with passenger_app. Re-run `flutterfire configure`
// when a native Windows/macOS app registration is added to the project.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      // The shared web app configuration works with the FlutterFire desktop
      // implementations. A dedicated desktop app can replace this later.
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return web;
      default:
        return web;
    }
  }

  static const web = FirebaseOptions(
    apiKey: 'AIzaSyC0YXQ83GCutpozyK2wi0B3vH8V2zKt5IQ',
    appId: '1:1002016926977:web:088673e7d0ebc19867ff00',
    messagingSenderId: '1002016926977',
    projectId: 'ikot-lasalle-ccfab',
    authDomain: 'ikot-lasalle-ccfab.firebaseapp.com',
    storageBucket: 'ikot-lasalle-ccfab.firebasestorage.app',
    measurementId: 'G-0FDV8V5DWZ',
  );
  static const android = FirebaseOptions(
    apiKey: 'AIzaSyAWl-gllrN2h1i5ePjEtAPBBTU6RUUuOSc',
    appId: '1:1002016926977:android:a9dc37107d13602467ff00',
    messagingSenderId: '1002016926977',
    projectId: 'ikot-lasalle-ccfab',
    storageBucket: 'ikot-lasalle-ccfab.firebasestorage.app',
  );
  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyA7ImiWbgGLavpCnWRS_iYy-VRZd2NVasM',
    appId: '1:1002016926977:ios:79d91eac0f3b7abf67ff00',
    messagingSenderId: '1002016926977',
    projectId: 'ikot-lasalle-ccfab',
    storageBucket: 'ikot-lasalle-ccfab.firebasestorage.app',
    iosBundleId: 'com.example.ikotLasalle',
  );
}

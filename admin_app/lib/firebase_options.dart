// Firebase project configuration for Ikot La Salle Admin.
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
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return web;
      default:
        return web;
    }
  }

  static const web = FirebaseOptions(
    apiKey: 'AIzaSyDxSUzzgqvBXf4wq63cBFQSboyVBHisTEk',
    appId: '1:896555643484:web:e9fdac23ce2307aa946c99',
    messagingSenderId: '896555643484',
    projectId: 'ikot-lasalle-2bed1',
    authDomain: 'ikot-lasalle-2bed1.firebaseapp.com',
    storageBucket: 'ikot-lasalle-2bed1.firebasestorage.app',
  );

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyDb7ENHyRh983Pd2i_jD9mCeGlLmkFWvXI',
    appId: '1:896555643484:android:09f5bc8e8bba6f2c946c99',
    messagingSenderId: '896555643484',
    projectId: 'ikot-lasalle-2bed1',
    storageBucket: 'ikot-lasalle-2bed1.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyDxVtuwAg2v98l_rzQlnzvwA-4KXrQSLio',
    appId: '1:896555643484:ios:aa4c5e003af71d02946c99',
    messagingSenderId: '896555643484',
    projectId: 'ikot-lasalle-2bed1',
    storageBucket: 'ikot-lasalle-2bed1.firebasestorage.app',
    iosBundleId: 'com.example.adminPage',
  );
}

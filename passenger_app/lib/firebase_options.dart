// File generated for the Ikot La Salle Firebase project.
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
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDxSUzzgqvBXf4wq63cBFQSboyVBHisTEk',
    appId: '1:896555643484:web:8003e69410e080ec946c99',
    messagingSenderId: '896555643484',
    projectId: 'ikot-lasalle-2bed1',
    authDomain: 'ikot-lasalle-2bed1.firebaseapp.com',
    storageBucket: 'ikot-lasalle-2bed1.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDb7ENHyRh983Pd2i_jD9mCeGlLmkFWvXI',
    appId: '1:896555643484:android:c6a16a2b8f43b935946c99',
    messagingSenderId: '896555643484',
    projectId: 'ikot-lasalle-2bed1',
    storageBucket: 'ikot-lasalle-2bed1.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDxVtuwAg2v98l_rzQlnzvwA-4KXrQSLio',
    appId: '1:896555643484:ios:456e7dd735340d92946c99',
    messagingSenderId: '896555643484',
    projectId: 'ikot-lasalle-2bed1',
    storageBucket: 'ikot-lasalle-2bed1.firebasestorage.app',
    iosBundleId: 'com.example.ikotLasalle',
  );
}

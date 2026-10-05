// Generado para el proyecto Firebase: autofix-6f844
// Basado en google-services.json proporcionado por el desarrollador.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] para el proyecto autofix-6f844.
///
/// Uso:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions no soportado en esta plataforma.',
        );
    }
  }

  // -------------------------------------------------------------------
  // Las claves de Android vienen directamente del google-services.json.
  // Para iOS / Web / Windows, se reutilizan el mismo projectId y
  // storageBucket; la apiKey puede diferir si creas apps adicionales
  // en la consola de Firebase para esas plataformas.
  // -------------------------------------------------------------------

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBR6F7V8SxY_RkBoC7mW45EoW8psNsUJXs',
    appId: '1:1059742268264:android:82f0e7cb510ba06decf4dd',
    messagingSenderId: '1059742268264',
    projectId: 'autofix-6f844',
    storageBucket: 'autofix-6f844.firebasestorage.app',
  );

  // Para Web: agrega tu app web en la consola de Firebase y reemplaza
  // apiKey y appId con los valores que te genere.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBR6F7V8SxY_RkBoC7mW45EoW8psNsUJXs',
    appId: '1:1059742268264:web:82f0e7cb510ba06decf4dd',
    messagingSenderId: '1059742268264',
    projectId: 'autofix-6f844',
    authDomain: 'autofix-6f844.firebaseapp.com',
    storageBucket: 'autofix-6f844.firebasestorage.app',
  );

  // Para iOS: descarga GoogleService-Info.plist desde la consola y
  // reemplaza apiKey, appId y iosBundleId con los valores correctos.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBR6F7V8SxY_RkBoC7mW45EoW8psNsUJXs',
    appId: '1:1059742268264:ios:82f0e7cb510ba06decf4dd',
    messagingSenderId: '1059742268264',
    projectId: 'autofix-6f844',
    storageBucket: 'autofix-6f844.firebasestorage.app',
    iosBundleId: 'com.example.autofix',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBR6F7V8SxY_RkBoC7mW45EoW8psNsUJXs',
    appId: '1:1059742268264:ios:82f0e7cb510ba06decf4dd',
    messagingSenderId: '1059742268264',
    projectId: 'autofix-6f844',
    storageBucket: 'autofix-6f844.firebasestorage.app',
    iosBundleId: 'com.example.autofix',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBR6F7V8SxY_RkBoC7mW45EoW8psNsUJXs',
    appId: '1:1059742268264:web:82f0e7cb510ba06decf4dd',
    messagingSenderId: '1059742268264',
    projectId: 'autofix-6f844',
    authDomain: 'autofix-6f844.firebaseapp.com',
    storageBucket: 'autofix-6f844.firebasestorage.app',
  );
}

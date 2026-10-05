import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:autofix/app/conectividad_app.dart';
import 'package:autofix/features/auth/screens/login_screen.dart';
import 'package:autofix/features/sync/sync_service.dart';
import 'package:autofix/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa Firebase.
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    try {
      await FirebaseAuth.instance.signInAnonymously();
      await SyncService.instance.start();
    } catch (e) {
      debugPrint('FirebaseAuth anonymous sign-in skipped: $e');
    }
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ConectividadApp(child: AutoFixApp()));
}

class AutoFixApp extends StatelessWidget {
  const AutoFixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AutoFix',
      // Linea 2 de las 2 del punto de integracion de Conectividad:
      // `MaterialApp.builder` corre ADENTRO del Navigator, asi que el banner
      // queda montado por encima de TODA ruta (login, dashboard, citas,
      // configuracion) y de los bottom sheets.
      builder: ConectividadApp.bannerBuilder,
      home: const LoginScreen(),
    );
  }
}

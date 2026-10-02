import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:autofix/app/conectividad_app.dart';
import 'package:autofix/features/auth/screens/login_screen.dart';

void main() {
  // Sin esto, `getDatabasesPath()` y los plugins de plataforma no pueden
  // usarse todavia: el binding de Flutter todavia no inicializo.
  WidgetsFlutterBinding.ensureInitialized();

  // Banner con fondo: el `headerNavy` de la paleta necesita status bar
  // transparente o queda una franja blanca fea arriba.
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

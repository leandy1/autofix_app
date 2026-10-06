import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:autofix/app/conectividad_app.dart';
import 'package:autofix/app/ruta_inicial.dart';
import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/auth/sesion_cliente.dart';
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
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
  }

  // Restaura la sesion guardada (UID, correo, taller_id) ANTES de montar la
  // primera pantalla. Va aca y no dentro de la ruta inicial porque la decision
  // tiene que estar tomada en el PRIMER frame: si se leyera despues, el arranque
  // offline parpadearia el login y recien ahi saltaria al Dashboard.
  //
  // Es una lectura local (SharedPreferences), no de la nube, por lo que funciona
  // exactamente igual sin internet. Sin sesion guardada devuelve false y la app
  // arranca en el login, como siempre.
  //
  // Las DOS sesiones: la del admin (taller) y la del cliente. Solo una puede
  // estar activa por arranque y la ruta inicial decide; si alguien cerro
  // sesion en la app que sea, esa quedo apagada y no interfiere.
  await SesionAdmin.instance.restaurar();
  await SesionCliente.instance.restaurar();

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
      // La ruta inicial decide entre Dashboard y Login con la sesion ya en
      // memoria (la restauro `main`). Ver `lib/app/ruta_inicial.dart`.
      home: const RutaInicial(),
    );
  }
}

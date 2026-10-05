import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:autofix/app/conectividad_app.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/auth/screens/login_screen.dart';
import 'package:autofix/firebase_options.dart';

Future<void> main() async {
  // Sin esto, `getDatabasesPath()` y los plugins de plataforma no pueden
  // usarse todavia: el binding de Flutter todavia no inicializo.
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa Firebase (usa el archivo generado por FlutterFire CLI).
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Autenticacion anonima silenciosa: el usuario entra sin credenciales.
  // El UID generado se usa como `eliminado_por` en el borrado logico y como
  // propietario de los documentos en Firestore.
  await FirebaseAuth.instance.signInAnonymously();

  // Banner con fondo: el `headerNavy` de la paleta necesita status bar
  // transparente o queda una franja blanca fea arriba.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Citas de DEMOSTRACION para poder ver el Dashboard con numeros y no en cero.
  //
  // Va aqui y no en `_crearEsquema` a proposito: esto es data de prueba, y
  // metida en la semilla inicial cada instalacion real abriria el Dashboard del
  // administrador con clientes e ingresos que no existen. Ademas, los tests no
  // pasan por `main`, asi que siguen probando contra una base vacia.
  //
  // `kDebugMode` y no un parametro: es exactamente la distincion entre "probando
  // la UI con datos" y "repartiendo data falsa en produccion". Para auditar el
  // grafico, corra la app en debug; si ya hay citas propias, `sembrarCitasDemo`
  // no inyecta nada y no pisa el historial real.
  if (kDebugMode) {
    await DatabaseHelper.sembrarCitasDemo();
  }

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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/conectividad_app.dart';
import 'features/citas/presentation/citas_page.dart';

/// DEMO AISLADA de las unidades de Conectividad y Almacenamiento local.
///
/// Esta es la app de trabajo: corre contra SQLite real en el dispositivo y trae
/// el banner de red montado. Sirve para dos cosas:
///
///   1. `flutter run`  ->  probar la base y el banner de forma aislada, sin
///      depender de que el resto del equipo haya integrated su navegacion.
///   2. Defensa       ->  el CRUD se ve funcionando de punta a punta.
///
/// ---------------------------------------------------------------------
/// OJO AL HACER EL MERGE OFICIAL (Leandy, esto no es mio, es un recordatorio):
///
/// `lib/main.dart` es TUYO: vos definis el `AutoFixApp` y el `home: LoginScreen`.
/// Este archivo mio tiene que DESAPARECER. Resolucion en un comando:
///
///     git checkout --theirs lib/main.dart
///
/// y despues pegar estas 2 lineas en tu main.dart (estan comentadas en
/// `lib/app/conectividad_app.dart` con el ejemplo completo):
///
///     runApp(const ConectividadApp(child: AutoFixApp()));   // 1
///     builder: ConectividadApp.bannerBuilder,               // 2
///
/// La clase de acá se llama `AutoFixDemoApp` y NO `AutoFixApp` a proposito:
/// si git llegara a mezclar el contenido de los dos archivos en vez de
/// reemplazar uno, dos clases con el mismo nombre en el mismo archivo no
/// compilan ("Class 'AutoFixApp' is already declared"). Con nombres distintos
/// el peor caso es que sobre una clase de mas, que es un aviso del analyzer,
/// no un proyecto roto.
/// ---------------------------------------------------------------------
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

  runApp(const AutoFixDemoApp());
}

class AutoFixDemoApp extends StatelessWidget {
  const AutoFixDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ConectividadApp(
      // `ConectividadApp` es el MISMO punto de integracion que va a usar
      // Leandy. No hay una version "de prueba" del banner: se prueba el
      // codigo real, asi lo que demo hoy es lo que se mergea manana.
      child: MaterialApp(
        title: 'AutoFix (demo Sandy)',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF07A22)),
        ),
        // Linea 2 de las 2 del parche de integracion: cuelga el banner por
        // DEBAJO del Navigator, asi queda arriba de cualquier pantalla.
        builder: ConectividadApp.bannerBuilder,
        home: const CitasPage(),
      ),
    );
  }
}

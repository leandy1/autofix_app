import 'dart:async';
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:autofix/app/conectividad_app.dart';
import 'package:autofix/app/ruta_inicial.dart';
import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/core/data/limpieza_local.dart';
import 'package:autofix/firebase_options.dart';
import 'package:autofix/features/devMode/sync/devmode_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _instalarManejadoresDeError();

  // Firebase y las DOS lecturas de sesion no se necesitan entre si, asi que se
  // lanzan las tres a la vez y se esperan despues. En serie el arranque paga
  // secuencialmente (plugin de Firebase + prefs de admin + prefs de cliente)
  // justo ANTES del primer frame; en paralelo solo se espera el mas lento.
  final firebaseListo = _inicializarFirebase();
  final adminRestaurado = SesionAdmin.instance.restaurar();
  final clienteRestaurado = SesionCliente.instance.restaurar();

  await firebaseListo;
  final hayAdmin = await adminRestaurado;
  final hayCliente = await clienteRestaurado;

  // Restaura la sesion guardada (UID, correo, taller_id) ANTES de montar la
  // primera pantalla. Va aca y no dentro de la ruta inicial porque el perfil
  // local tiene que estar en memoria antes del primer frame: asi el Login ya
  // arranca con el usuario recordado (`san***`) y la clave deshabilitada.
  //
  // Es una lectura local (SharedPreferences), no de la nube, por lo que funciona
  // exactamente igual sin internet. La sesion restaurada ya NO decide la ruta:
  // quien decide es el Login cuando el usuario pulsa "Ingresar".
  if (!hayAdmin && !hayCliente) {
    // Firebase Auth conserva su propio usuario entre ejecuciones. Sin una
    // sesión local marcada por Recuérdame, ese token no debe convertirse en
    // un bypass implícito: el usuario volverá al login y tendrá que validar
    // credenciales con internet.
    //
    // La unica excepcion es el usuario ANONIMO. No tiene identidad, asi que
    // no puede validar nada por nadie en el login; en cambio es el que
    // permite que `sincronizarCatalogos()` lea `talleres` y `admins` con las
    // reglas `request.auth != null`. Firmarlo fuera aca obligaria a crear una
    // cuenta anonima nueva en CADA arranque, para leer lo mismo.
    try {
      final usuarioPrevia = FirebaseAuth.instance.currentUser;
      if (usuarioPrevia != null && !usuarioPrevia.isAnonymous) {
        await FirebaseAuth.instance.signOut();
      }
    } catch (e) {
      debugPrint('Firebase Auth previo no se pudo cerrar ($e)');
    }
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Rotación bloqueada en vertical (capa Dart; Android e iOS ya lo tienen en
  // su manifest: `screenOrientation="portrait"` e `UISupportedInterfaceOrientations`).
  // Se pide antes de `runApp` para que ni el primer frame ni la transición de
  // entrada se vean en horizontal.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  runApp(const ConectividadApp(child: AutoFixApp()));

  // Ciclo de vida de los datos locales (reglas 1 y 2 de `LimpiezaLocal`):
  // si este arranque NO restauro ninguna sesion, nadie pidio conservar la copia
  // local del usuario anterior, asi que se purga. Con sesion restaurada no se
  // toca nada: esa es exactamente la condicion que permite abrir offline.
  //
  // Igual que la sincronizacion de catalogos: despues de `runApp` y sin
  // `await`, porque es limpieza de fondo y el Login no depende de ella.
  unawaited(LimpiezaLocal.alArrancar(haySesion: hayAdmin || hayCliente));

  // Catalogos PERMANENTES: `talleres` y `admins` se bajan de Firebase a
  // SQLite apenas abre la app, sin que nadie tenga que entrar al Modo
  // Desarrollador y apretar "Sincronizar". Son datos que la app necesita
  // locales para funcionar (el mapa, la lista de afiliados, el rechazo de
  // cuentas dadas de baja), asi que su sincronizacion no depende del rol.
  //
  // Va DESPUES de `runApp` y sin `await` a proposito: es un pull de fondo y
  // el primer frame no puede esperar a la red. Si falla (sin internet, sin
  // permisos) el catalogo local sigue vigente y el proximo arranque reintenta.
  unawaited(DevModeSyncService.instance.sincronizarCatalogos());
}

/// Inicializa Firebase sin tumbar el arranque si falla.
///
/// Devuelve `false` cuando no se pudo abrir, para que `main()` no se apoye en
/// nada que dependa de Auth en ese caso.
Future<bool> _inicializarFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    return true;
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
    return false;
  }
}

/// Engancha los DOS canales por los que un error puede llegar sin nadie que lo
/// mire.
///
/// Sin esto, en release no hay pantalla roja ni stack a la vista: el error se
/// imprime en el log del sistema y desaparece. Fue exactamente lo que oculto
/// el crash del registro de cliente durante semanas.
void _instalarManejadoresDeError() {
  // Errores del framework (build, layout, dispose). `presentError` conserva el
  // cuadro rojo en debug y el volcado en release.
  FlutterError.onError = (detalles) {
    debugPrint(
      'AutoFix [FlutterError] ${detalles.exception}\n${detalles.stack}',
    );
    FlutterError.presentError(detalles);
  };

  // Errores de zonas no capturados: futures sin await, callbacks de streams,
  // cualquier `throw` que nadie atrape. Devolver `true` dice "ya lo maneje"
  // y evita que el motor lo reporte dos veces.
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('AutoFix [no capturado] $error\n$stack');
    return true;
  };
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
      // La ruta inicial siempre pinta el Login; la sesion restaurada por
      // `main` se le muestra ahi (usuario recordado) en vez de saltarsela.
      home: const RutaInicial(),
    );
  }
}

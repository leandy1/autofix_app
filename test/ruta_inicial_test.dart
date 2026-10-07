import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:autofix/app/ruta_inicial.dart';
import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/auth/sesion_cache.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/admin/screens/dashboard_admin_screen.dart';
import 'package:autofix/features/auth/screens/login_screen.dart';

/// El Login es la PRIMERA pantalla en todos los arranques, venga o no una
/// sesion restaurada desde `main()`.
///
/// Este archivo protege la cura del Bug 3: [RutaInicial] decide en el primer
/// frame y su decision es "Login, siempre". Antes devolvia el Dashboard cuando
/// `SesionAdmin`/`SesionCliente` estaban activos, y eso hacia invisible la
/// pantalla que muestra al usuario recordado (`san***`) con la clave
/// deshabilitada esperando a que pulse "Ingresar".
///
/// Lo que verifica:
/// - Sin sesion guardada -> Login (el arranque normal de siempre).
/// - Con sesion guardada -> Login igual, NUNCA el Dashboard; pero la sesion si
///   quedo restaurada en memoria, que es lo que permite entrar sin red desde
///   el propio Login.
void main() {
  setUpAll(() {
    // Las prefs en memoria: sin esto `SharedPreferences.getInstance()` tira
    // MissingPluginException y `SesionCache` (que no truena) devolveria null,
    // haciendo que "restaurar" falle por una razon que nada tiene que ver con
    // la logica que se quiere probar.
    SharedPreferences.setMockInitialValues(<String, Object>{});

    sqfliteFfiInit();
    // La MISMA combinacion que dashboard_admin_screen_test: `databaseFactoryFfi`
    // manda el SQL a un isolate de fondo y `testWidgets` corre dentro de
    // `FakeAsync`, que lo congela y el `pumpWidget` se cuelga en vez de fallar.
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_ruta_inicial_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  /// Deja la sesion y la base como un arranque recien abierto.
  Future<void> abrirAppEnBlanco() async {
    await SesionAdmin.instance.cerrar();
    await DatabaseHelper.resetParaPruebas();
    // Abrir la base FUERA del `FakeAsync` del `testWidgets`, por la misma
    // razon que en dashboard_admin_screen_test: adentro el test se queda
    // esperando una promesa que el reloj falso nunca completa.
    await DatabaseHelper.instance.base;
  }

  group('arranque sin sesion guardada', () {
    setUp(abrirAppEnBlanco);

    testWidgets('entra al Login, como siempre', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RutaInicial()));
      await tester.pump();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);
    });
  });

  group('arranque con sesion guardada (offline)', () {
    setUp(() async {
      await abrirAppEnBlanco();
      // La misma secuencia real: el login dejo la sesion en disco, la app se
      // cerro y en el proximo arranque `main()` la restaura ANTES de runApp.
      // Corre en el setUp (fuera del FakeAsync) justamente porque en produccion
      // tambien ocurre antes de montar el primer frame.
      await SesionCache.guardar(
        const SesionPersistida(
          tallerId: 'taller-1',
          adminUid: 'uid-1',
          tallerNombre: 'Global Refriauto',
          adminEmail: 'admin@autofix.do',
        ),
      );
      expect(await SesionAdmin.instance.restaurar(), isTrue);
    });

    testWidgets('el Login se pinta igual: no hay bypass al Dashboard', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: RutaInicial()));
      // Un solo pump: la decision tiene que estar tomada en el primer frame,
      // sin FutureBuilder ni splash intermedio.
      await tester.pump();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        find.byType(DashboardScreen),
        findsNothing,
        reason: 'una sesion guardada ya no salta el formulario de acceso',
      );
    });

    testWidgets('la sesion si quedo restaurada, para entrar sin red', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: RutaInicial()));
      await tester.pump();

      expect(
        SesionAdmin.instance.activa,
        isTrue,
        reason:
            'el bypass desaparece, pero el dato local no: sin el, '
            'el Login no podria dejar entrar a un usuario sin internet',
      );
      expect(SesionAdmin.instance.tallerId, 'taller-1');
    });

    tearDown(() async {
      // La sesion es un singleton: sin esto, un test posterior arrancaria
      // "logueado" y pasaria por pura contaminacion de estado.
      await SesionAdmin.instance.cerrar();
    });
  });
}

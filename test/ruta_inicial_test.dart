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

/// El corazon del "arranque offline": [RutaInicial] tiene que decidir entre
/// Dashboard y Login en el PRIMER frame, con la sesion que `main()` restauro
/// desde SharedPreferences antes del `runApp`.
///
/// Lo que este archivo protege es la DOSIS EXACTA de lo asincrono:
/// - Sin sesion guardada -> Login (el arranque normal de siempre).
/// - Con sesion guardada -> Dashboard YA en el primer `pump`, sin splash y sin
///   `FutureBuilder` intermedio. Si alguien "mejora" la ruta con un future,
///   el requisito de entrar sin internet parpadeando el login se rompe y este
///   test es el que lo delata.
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

    testWidgets('el primer frame ya es el Dashboard', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RutaInicial()));
      // Un solo pump: si la decision fuera asincrona, en este punto veriamos
      // el splash (o el Login) y el Dashboard recien en el pump siguiente.
      await tester.pump();

      expect(SesionAdmin.instance.activa, isTrue);
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    tearDown(() async {
      // La sesion es un singleton: sin esto, un test posterior arrancaria
      // "logueado" y pasaria por pura contaminacion de estado.
      await SesionAdmin.instance.cerrar();
    });
  });
}

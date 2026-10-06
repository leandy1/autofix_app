import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/auth/screens/login_screen.dart';
import 'package:autofix/features/devMode/screens/talleres_afiliados_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // `databaseFactoryFfiNoIsolate` y NO `databaseFactoryFfi`: al aceptar dev/1234
    // la app navega a TalleresAfiliadosScreen, que consulta SQLite en su
    // initState; con la version normal ese SQL corre en un isolate que FakeAsync
    // congela, el spinner gira sin parar y `pumpAndSettle` muere por timeout.
    // Mismo criterio que dashboard_admin_screen_test.dart:25.
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_dev_mode_login_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    await DatabaseHelper.resetParaPruebas();
    // ABRIR la base aqui, fuera del `FakeAsync` de `testWidgets`: la primera
    // apertura adentro del test cuelga en vez de fallar.
    await DatabaseHelper.instance.base;
  });

  testWidgets('dev/1234 abre el administrador de talleres', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.enterText(find.byType(TextField).at(0), 'dev');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();

    expect(find.byType(TalleresAfiliadosScreen), findsOneWidget);
    expect(find.text('Talleres afiliados'), findsOneWidget);
  });

  testWidgets('rechaza una contraseña incorrecta para dev', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.enterText(find.byType(TextField).at(0), 'dev');
    await tester.enterText(find.byType(TextField).at(1), 'incorrecta');
    await tester.tap(find.text('Ingresar'));
    await tester.pump();

    expect(find.byType(TalleresAfiliadosScreen), findsNothing);
    expect(
      find.text('La contraseña de desarrollador no es válida.'),
      findsOneWidget,
    );
  });
}

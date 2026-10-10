import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/talleres/data/taller_repository.dart';
import 'package:autofix/features/talleres/models/taller.dart';
import 'package:autofix/features/devMode/screens/talleres_afiliados_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // `databaseFactoryFfiNoIsolate` y NO `databaseFactoryFfi`: la version normal
    // manda el SQL a un isolate de fondo que `FakeAsync` (dentro de
    // `testWidgets`) congela, y el primer `pumpAndSettle` se queda esperando
    // una respuesta que nunca llega. Mismo criterio que
    // dashboard_admin_screen_test.dart:25.
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_talleres_screen_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    await DatabaseHelper.resetParaPruebas();
    // ABRIR la base aqui, fuera del `FakeAsync` de `testWidgets`. Si la primera
    // apertura ocurre adentro del test, cuelga en vez de fallar.
    await DatabaseHelper.instance.sembrarTalleres();
  });

  testWidgets('permite editar y guardar los datos de un taller', (
    tester,
  ) async {
    final original = (await TallerRepository.instance.obtenerTodas()).first;

    await tester.pumpWidget(const MaterialApp(home: TalleresAfiliadosScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Talleres afiliados'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Editar').first);
    await tester.pumpAndSettle();

    expect(find.text('Editar taller'), findsOneWidget);
    expect(find.text('ID del taller'), findsOneWidget);
    final campoId = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextFormField).at(0),
        matching: find.byType(EditableText),
      ),
    );
    expect(campoId.readOnly, isTrue);
    expect(campoId.controller.text, original.id.toString());
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'Dirección actualizada',
    );
    await tester.enterText(find.byType(TextFormField).at(4), '18,5');
    await tester.enterText(find.byType(TextFormField).at(5), '-69,5');
    // El dialogo es alto y su contenido va en SingleChildScrollView
    // (talleres_afiliados_screen.dart:491): sin esto el boton queda fuera del
    // viewport de 800x600, el tap pega en el fondo y el guardar no corre.
    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    final actualizado = await TallerRepository.instance.obtenerPorId(
      original.id!,
    );
    expect(actualizado!.direccion, 'Dirección actualizada');
    expect(actualizado.latitud, 18.5);
    expect(actualizado.longitud, -69.5);
    expect(find.text('Dirección actualizada'), findsOneWidget);
  });

  testWidgets(
    'actualiza la lista cuando otro dispositivo agrega un taller',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TalleresAfiliadosScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Taller Widget Sync'), findsNothing);

      await TallerRepository.instance.crear(const Taller(
        nombre: 'Taller Widget Sync',
        direccion: 'Calle de prueba',
        telefono: '809-000-0000',
        latitud: 18.4861,
        longitud: -69.9312,
      ));
      TallerRepository.instance.avisarCatalogoActualizado();
      await tester.pumpAndSettle();

      expect(find.text('Taller Widget Sync'), findsOneWidget);
    },
  );
}

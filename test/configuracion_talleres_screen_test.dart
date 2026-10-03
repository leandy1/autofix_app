import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/talleres/data/taller_repository.dart';
import 'package:autofix/features/devMode/screens/talleres_afiliados_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_talleres_screen_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    await DatabaseHelper.resetParaPruebas();
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
}

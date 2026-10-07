import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/database/semilla_inicial.dart';
import 'package:autofix/features/admin/screens/configuracion_admin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.nombreBaseParaPruebas =
        'autofix_config_admin_screen_test.db';
  });

  tearDownAll(() async {
    await SesionAdmin.instance.cerrar();
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    await DatabaseHelper.resetParaPruebas();
    SharedPreferences.setMockInitialValues({});
    await SesionAdmin.instance.cerrar();
  });

  Future<void> mostrarPantalla(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConfiguracionScreen(tallerId: SemillaInicial.talleres.first.id),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('presenta configuración categorizada en tres pestañas', (
    tester,
  ) async {
    await mostrarPantalla(tester);

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Servicios'), findsOneWidget);
    expect(find.text('Técnicos'), findsOneWidget);
    expect(find.text('Catálogos'), findsOneWidget);

    await tester.tap(find.text('Técnicos'));
    await tester.pumpAndSettle();
    expect(find.text('Personal técnico'), findsOneWidget);
    expect(find.text('Técnico 1'), findsOneWidget);
  });

  testWidgets('rechaza precios negativos antes de guardar un servicio', (
    tester,
  ) async {
    await mostrarPantalla(tester);
    await tester.tap(find.text('Agregar servicio'));
    await tester.pumpAndSettle();

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'Servicio con precio inválido');
    await tester.enterText(campos.at(1), '-350');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Ingresa un precio válido, no negativo.'), findsOneWidget);
    expect(find.text('Nuevo servicio'), findsOneWidget);
  });

  testWidgets('confirma el borrado antes de conservar el tombstone', (
    tester,
  ) async {
    await mostrarPantalla(tester);
    await tester.tap(find.text('Técnicos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eliminar Técnico 1').first);
    await tester.pumpAndSettle();

    expect(
      find.text(
        '¿Estás seguro de que deseas eliminar "Técnico 1"? '
        'Las citas históricas no se verán afectadas.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final db = await DatabaseHelper.instance.base;
      final filas = await db.query(
        DatabaseHelper.tablaTecnicos,
        where: 'nombre = ?',
        whereArgs: ['Técnico 1'],
      );
      expect(filas, hasLength(1));
      expect(filas.single[DatabaseHelper.colEliminadoEn], isA<String>());
    });
  });
}

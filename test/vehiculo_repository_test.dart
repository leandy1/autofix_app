import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/cliente/data/vehiculo_repository.dart';
import 'package:autofix/features/cliente/models/vehiculo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_vehiculos_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async => DatabaseHelper.resetParaPruebas());

  const propietario = 'cliente@autofix.do';

  test(
    'la migración desde v14 conserva filas de vehículos existentes',
    () async {
      final ruta = p.join(
        await getDatabasesPath(),
        DatabaseHelper.nombreBaseParaPruebas!,
      );
      final baseV14 = await databaseFactory.openDatabase(
        ruta,
        options: OpenDatabaseOptions(
          version: 14,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE vehiculos (
              id TEXT NOT NULL PRIMARY KEY,
              cliente_id TEXT NOT NULL,
              marca TEXT NOT NULL,
              modelo TEXT NOT NULL,
              anio INTEGER NOT NULL,
              placa TEXT NOT NULL DEFAULT '',
              activo INTEGER NOT NULL DEFAULT 1,
              creado_en TEXT NOT NULL,
              actualizado_en TEXT NOT NULL
            )
          ''');
            await db.insert('vehiculos', <String, Object?>{
              'id': 'vehiculo-v14',
              'cliente_id': propietario,
              'marca': 'Mazda',
              'modelo': '3',
              'anio': 2020,
              'placa': '',
              'activo': 1,
              'creado_en': '2025-01-01T00:00:00.000Z',
              'actualizado_en': '2025-01-02T00:00:00.000Z',
            });
          },
        ),
      );
      await baseV14.close();

      final db = await DatabaseHelper.instance.base;
      final vehiculo = await VehiculoRepository.instance.obtenerPorId(
        'vehiculo-v14',
      );
      expect(vehiculo?.marca, 'Mazda');
      expect(vehiculo?.syncStatus, 'pending');
      expect(vehiculo?.eliminadoEn, isNull);
      expect(
        (await db.rawQuery('PRAGMA user_version')).single['user_version'],
        15,
      );
    },
  );

  test('el esquema v15 crea vehículos listos para sincronización', () async {
    final db = await DatabaseHelper.instance.base;
    final columnas = await db.rawQuery(
      'PRAGMA table_info(${DatabaseHelper.tablaVehiculos})',
    );
    expect(
      columnas.map((columna) => columna['name']),
      containsAll([
        DatabaseHelper.colId,
        DatabaseHelper.colClienteIdVehiculo,
        DatabaseHelper.colMarcaVehiculo,
        DatabaseHelper.colModeloVehiculo,
        DatabaseHelper.colAnioVehiculo,
        DatabaseHelper.colPlacaVehiculo,
        DatabaseHelper.colSyncStatusVehiculo,
        DatabaseHelper.colEliminadoEnVehiculo,
      ]),
    );
  });

  test(
    'los vehículos se guardan por cliente y sobreviven al reinicio de pantalla',
    () async {
      final repo = VehiculoRepository.instance;
      final id = await repo.crear(
        const Vehiculo(
          clienteId: propietario,
          marca: 'Toyota',
          modelo: 'Corolla',
          anio: 2022,
          placa: 'A123456',
        ),
      );

      final lista = await repo.obtenerPorCliente(propietario.toUpperCase());
      expect(lista, hasLength(1));
      expect(lista.single.id, id);
      expect(lista.single.resumen, 'Toyota · Corolla · 2022 · A123456');
      expect(lista.single.syncStatus, 'pending');
      expect(await repo.obtenerPorCliente('otro@autofix.do'), isEmpty);
    },
  );

  test(
    'editar y dar de baja sólo afectan al vehículo de ese cliente',
    () async {
      final repo = VehiculoRepository.instance;
      final id = await repo.crear(
        const Vehiculo(
          clienteId: propietario,
          marca: 'Honda',
          modelo: 'Civic',
          anio: 2020,
        ),
      );
      final original = (await repo.obtenerPorId(id))!;

      expect(await repo.actualizar(original.copyWith(placa: 'B765432')), 1);
      expect((await repo.obtenerPorId(id))!.placa, 'B765432');
      expect(await repo.eliminar(id, clienteId: 'otro@autofix.do'), 0);
      expect(await repo.eliminar(id, clienteId: propietario), 1);
      expect(await repo.obtenerPorCliente(propietario), isEmpty);
      final baja = await repo.obtenerPorId(id);
      expect(baja?.syncStatus, 'pending');
      expect(baja?.eliminadoEn, isNotNull);
    },
  );
}

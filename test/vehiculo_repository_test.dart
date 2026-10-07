import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/cliente/data/vehiculo_repository.dart';
import 'package:autofix/features/cliente/models/vehiculo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    'el esquema v13 y la tabla de vehículos se crean al abrir la base',
    () async {
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
        ]),
      );
    },
  );

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
    },
  );
}

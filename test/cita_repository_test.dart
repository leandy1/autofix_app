import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Prueba de integracion contra una base SQLite real (via FFI).
/// No usa mocks: crea la tabla, inserta, lee, actualiza y elimina de verdad.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // CRITICO: se borra el .db antes de cada prueba. `sqflite_common_ffi` lo
    // guarda en `.dart_tool/`, o sea EN DISCO, no en memoria. Sin este reset,
    // `onCreate` no se vuelve a correr y los tests dan verde probando un
    // esquema viejo. Asi cada test arranca de una base recien creada de verdad.
    await DatabaseHelper.resetParaPruebas();
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
  });

  Cita nueva({String cliente = 'Ana Torres'}) => Cita(
    cliente: cliente,
    vehiculo: 'Toyota Hilux',
    descripcion: 'Cambio de aceite',
    fechaCita: DateTime(2026, 10, 1, 9, 30),
  );

  test('CREATE: el id generado queda disponible y la fila es recuperable', () async {
    final id = await CitaRepository.instance.crear(nueva());
    expect(id, greaterThan(0));

    final creada = await CitaRepository.instance.obtenerPorId(id);
    expect(creada, isNotNull);
    expect(creada!.cliente, 'Ana Torres');
  });

  test('READ: obtenerTodas devuelve lo que se guardo', () async {
    await CitaRepository.instance.crear(nueva());
    await CitaRepository.instance.crear(nueva(cliente: 'Luis Paz'));

    final todas = await CitaRepository.instance.obtenerTodas();
    expect(todas.length, 2);
    expect(todas.map((c) => c.cliente), containsAll(['Ana Torres', 'Luis Paz']));
  });

  test('UPDATE: los cambios quedan persistidos', () async {
    final id = await CitaRepository.instance.crear(nueva());
    final editada = (await CitaRepository.instance.obtenerPorId(id))!
        .copyWith(estado: EstadoCita.completado, cliente: 'Ana T. Updated');

    final filasAfectadas = await CitaRepository.instance.actualizar(editada);
    expect(filasAfectadas, 1);

    final releida = await CitaRepository.instance.obtenerPorId(id);
    expect(releida!.estado, EstadoCita.completado);
    expect(releida.cliente, 'Ana T. Updated');
  });

  test('UPDATE parcial: cambiarEstado no pisa el resto de la fila', () async {
    final id = await CitaRepository.instance.crear(
      nueva().copyWith(tecnico: 'Tecnico 2', placa: 'A123456'),
    );

    await CitaRepository.instance.cambiarEstado(id, EstadoCita.enProceso);

    final releida = await CitaRepository.instance.obtenerPorId(id);
    expect(releida!.estado, EstadoCita.enProceso);
    expect(releida.tecnico, 'Tecnico 2');
    expect(releida.placa, 'A123456');
  });

  test('DELETE: la cita deja de estar en la base', () async {
    final id = await CitaRepository.instance.crear(nueva());

    final filasAfectadas = await CitaRepository.instance.eliminar(id);
    expect(filasAfectadas, 1);
    expect(await CitaRepository.instance.obtenerPorId(id), isNull);
  });

  test('el total queda persistido como importe real', () async {
    final id = await CitaRepository.instance.crear(
      nueva().copyWith(total: 1250.5),
    );
    final releida = await CitaRepository.instance.obtenerPorId(id);
    expect(releida!.total, 1250.5);
  });

  test('el esquema recien creado tiene TODAS las columnas que usa el modelo', () async {
    // Este test es el que atrapo el bug de `vehiculo`: si el CREATE TABLE se
    // desincroniza del modelo, el INSERT revienta con "no such column". Ahora es
    // todavia mas importante: el modelo declara las claves como literales para no
    // depender de `DatabaseHelper`, y esta es la unica red que los une.
    final db = await DatabaseHelper.instance.base;
    final columnas = await db.rawQuery('PRAGMA table_info(${DatabaseHelper.tablaCitas})');
    final nombres = columnas.map((f) => f['name'] as String).toSet();

    for (final c in nueva().toMap().keys) {
      expect(nombres, contains(c), reason: 'falta la columna $c en la tabla citas');
    }
    expect(nombres, isNot(contains('codigo_qr')));
  });

  test('PATRON BASE: el repositorio se puede usar como BaseRepository<Cita>', () async {
    // Compilar esto YA es la prueba: si `CitaRepository` dejara de cumplir el
    // contrato, el analyzer falla antes de correr el test. Lo que se verifica en
    // runtime es que la API generica funciona contra la base real.
    final BaseRepository<Cita> repo = CitaRepository.instance;

    final id = await repo.crear(nueva());
    expect(id, greaterThan(0));
    expect(repo.tabla, DatabaseHelper.tablaCitas);

    final guardada = await repo.obtenerPorId(id);
    expect(guardada!.cliente, 'Ana Torres');
    expect((await repo.obtenerTodas()).length, 1);

    expect(await repo.actualizar(guardada.copyWith(cliente: 'Ana T.')), 1);
    expect((await repo.obtenerPorId(id))!.cliente, 'Ana T.');

    expect(await repo.eliminar(id), 1);
    expect(await repo.obtenerPorId(id), isNull);
  });

  test('actualizar sin id lanza en vez de fallar en silencio', () async {
    expect(
      () => CitaRepository.instance.actualizar(nueva()),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('eliminar un id inexistente devuelve 0 filas', () async {
    expect(await CitaRepository.instance.eliminar(9999), 0);
  });

  group('migraciones a v3', () {
    // El esquema v1 tal cual lo creo la primera version. Esta es la base que
    // puede tener un dispositivo que ya instalo la app antes de la v2.
    const esquemaV1 = '''
      CREATE TABLE citas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo_qr TEXT NOT NULL UNIQUE,
        cliente TEXT NOT NULL,
        vehiculo TEXT NOT NULL,
        descripcion TEXT NOT NULL DEFAULT '',
        fecha_cita TEXT NOT NULL,
        estado TEXT NOT NULL,
        creado_en TEXT NOT NULL
      )
    ''';
    const esquemaV2 = '''
      CREATE TABLE citas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo_qr TEXT NOT NULL UNIQUE,
        cliente TEXT NOT NULL,
        vehiculo TEXT NOT NULL,
        telefono TEXT NOT NULL DEFAULT '',
        marca TEXT NOT NULL DEFAULT '',
        modelo TEXT NOT NULL DEFAULT '',
        anio INTEGER NOT NULL DEFAULT 0,
        placa TEXT NOT NULL DEFAULT '',
        servicios TEXT NOT NULL DEFAULT '[]',
        tecnico TEXT NOT NULL DEFAULT '',
        descripcion TEXT NOT NULL DEFAULT '',
        fecha_cita TEXT NOT NULL,
        estado TEXT NOT NULL,
        creado_en TEXT NOT NULL,
        actualizado_en TEXT NOT NULL DEFAULT ''
      )
    ''';

    test('un dispositivo con v1 conserva sus citas y gana las columnas nuevas', () async {
      await DatabaseHelper.resetParaPruebas();
      final ruta = p.join(await getDatabasesPath(), 'autofix.db');

      // Se siembra una base v1 a mano, como si el dispositivo ya la tuviera.
      final baseV1 = await databaseFactory.openDatabase(
        ruta,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(esquemaV1);
            await db.execute(
              "INSERT INTO citas (codigo_qr, cliente, vehiculo, fecha_cita, estado, creado_en) "
              "VALUES ('VIEJO-1', 'Cliente Anterior', 'Ford Ranger', '2026-01-05T10:00:00.000', 'pendiente', '2026-01-01T09:00:00.000')",
            );
          },
        ),
      );
      await baseV1.close();

      // Se abre con el helper de la app: version 3 migra y elimina el QR.
      final citas = await CitaRepository.instance.obtenerTodas();

      expect(citas.length, 1, reason: 'la migracion NO debe perder datos');
      expect(citas.first.cliente, 'Cliente Anterior');
      expect(citas.first.vehiculo, 'Ford Ranger');
      // Columnas nuevas: llegan con el default, no en null.
      expect(citas.first.telefono, '');
      expect(citas.first.placa, '');
      expect(citas.first.anio, 0);
      expect(citas.first.servicios, isEmpty);
      expect(citas.first.tecnico, '');
      expect(citas.first.total, 0);
      final db = await DatabaseHelper.instance.base;
      final columnas = await db.rawQuery(
        'PRAGMA table_info(${DatabaseHelper.tablaCitas})',
      );
      expect(
        columnas.map((fila) => fila['name']),
        isNot(contains('codigo_qr')),
      );
    });

    test('un dispositivo con v2 conserva sus citas y gana el total', () async {
      await DatabaseHelper.resetParaPruebas();
      final ruta = p.join(await getDatabasesPath(), 'autofix.db');
      final baseV2 = await databaseFactory.openDatabase(
        ruta,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute(esquemaV2);
            await db.execute(
              "INSERT INTO citas "
              "(codigo_qr, cliente, vehiculo, fecha_cita, estado, creado_en) "
              "VALUES ('OLD-QR', 'Cliente v2', 'Honda Civic', "
              "'2026-02-01T11:30:00.000', 'pendiente', '2026-01-30T08:00:00.000')",
            );
          },
        ),
      );
      await baseV2.close();

      final citas = await CitaRepository.instance.obtenerTodas();
      expect(citas, hasLength(1));
      expect(citas.single.cliente, 'Cliente v2');
      expect(citas.single.total, 0);

      final db = await DatabaseHelper.instance.base;
      final columnas = await db.rawQuery(
        'PRAGMA table_info(${DatabaseHelper.tablaCitas})',
      );
      expect(columnas.map((fila) => fila['name']), contains('total'));
      expect(
        columnas.map((fila) => fila['name']),
        isNot(contains('codigo_qr')),
      );
    });

    test('la migracion es idempotente: abrir dos veces no rompe nada', () async {
      await DatabaseHelper.resetParaPruebas();
      final ruta = p.join(await getDatabasesPath(), 'autofix.db');

      final baseV1 = await databaseFactory.openDatabase(
        ruta,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => db.execute(esquemaV1),
        ),
      );
      await baseV1.close();

      // Primera apertura: migra. Segunda: onUpgrade ya no debe correr.
      await CitaRepository.instance.obtenerTodas();
      await DatabaseHelper.instance.cerrar();
      expect(await CitaRepository.instance.obtenerTodas(), isEmpty);

      final id = await CitaRepository.instance.crear(nueva());
      expect(id, greaterThan(0));
    });
  });
}

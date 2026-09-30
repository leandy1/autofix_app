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

  Cita nueva({String qr = 'QR-001', String cliente = 'Ana Torres'}) => Cita(
    codigoQr: qr,
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
    await CitaRepository.instance.crear(nueva(qr: 'QR-A'));
    await CitaRepository.instance.crear(nueva(qr: 'QR-B', cliente: 'Luis Paz'));

    final todas = await CitaRepository.instance.obtenerTodas();
    expect(todas.length, 2);
    expect(todas.map((c) => c.cliente), containsAll(['Ana Torres', 'Luis Paz']));
  });

  test('READ: el companero de QR resuelve por codigo y null si no existe', () async {
    await CitaRepository.instance.crear(nueva(qr: 'TALLER-77'));

    final porQr = await CitaRepository.instance.obtenerPorCodigoQr('TALLER-77');
    expect(porQr?.vehiculo, 'Toyota Hilux');

    final inexistente = await CitaRepository.instance.obtenerPorCodigoQr('NO-EXISTE');
    expect(inexistente, isNull);
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

  test('LEANDY: agruparPorEstadoUi devuelve las 5 llaves de kColorPorEstado', () async {
    final hoy = DateTime.now();
    // +30min y no "ahora": `esAtrasada` compara contra el instante actual, asi
    // que una cita creada con la hora exacta de ya cae en ATRASADAS al toque.
    final masLater = hoy.add(const Duration(minutes: 30));

    await CitaRepository.instance.crear(
      nueva(qr: 'HOY-1').copyWith(fechaCita: masLater, estado: EstadoCita.pendiente),
    );
    await CitaRepository.instance.crear(
      nueva(qr: 'HOY-2').copyWith(fechaCita: masLater, estado: EstadoCita.completado),
    );
    await CitaRepository.instance.crear(
      nueva(qr: 'AYER-1').copyWith(
        fechaCita: hoy.subtract(const Duration(days: 2)),
        estado: EstadoCita.enProceso,
      ),
    );

    final mapa = await CitaRepository.instance.agruparPorEstadoUi(hoy);

    // Las 5 llaves siempre presentes: el acordeon puede pintar '0' sin romperse.
    expect(
      mapa.keys,
      ['ATRASADAS', 'Pendiente', 'Esperando Pieza', 'En proceso', 'Completado'],
    );
    expect(mapa['Pendiente']!.length, 1);
    expect(mapa['Completado']!.length, 1);
    // La de ayer no aparece: el filtro por dia es en SQL, no en Dart.
    expect(mapa['En proceso']!.length, 0);
    expect(mapa['ATRASADAS']!.length, 0);
  });

  test('LEANDY: una cita de hoy que ya paso la hora cae en ATRASADAS', () async {
    final hoy = DateTime.now();
    await CitaRepository.instance.crear(
      nueva(qr: 'VENCIDA-1').copyWith(
        fechaCita: hoy.subtract(const Duration(hours: 2)),
        estado: EstadoCita.pendiente,
      ),
    );

    final mapa = await CitaRepository.instance.agruparPorEstadoUi(hoy);
    expect(mapa['ATRASADAS']!.length, 1);
    expect(mapa['Pendiente']!.length, 0);
  });

  test('DELETE: la cita deja de estar en la base', () async {
    final id = await CitaRepository.instance.crear(nueva());

    final filasAfectadas = await CitaRepository.instance.eliminar(id);
    expect(filasAfectadas, 1);
    expect(await CitaRepository.instance.obtenerPorId(id), isNull);
  });

  test('UNIQUE: un codigo QR repetido se rechaza', () async {
    await CitaRepository.instance.crear(nueva(qr: 'TALLER-77'));
    expect(
      () => CitaRepository.instance.crear(nueva(qr: 'TALLER-77')),
      throwsA(isA<Exception>()),
    );
  });

  test('el esquema recien creado tiene TODAS las columnas que usa el modelo', () async {
    // Este test es el que atrapo el bug de `vehiculo`: si el CREATE TABLE se
    // desincroniza del modelo, el INSERT revienta con "no such column".
    final db = await DatabaseHelper.instance.base;
    final columnas = await db.rawQuery('PRAGMA table_info(${DatabaseHelper.tablaCitas})');
    final nombres = columnas.map((f) => f['name'] as String).toSet();

    for (final c in nueva().toMap().keys) {
      expect(nombres, contains(c), reason: 'falta la columna $c en la tabla citas');
    }
  });

  group('migracion v1 -> v2', () {
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

      // Se abre con el helper de la app: version 2 dispara onUpgrade.
      final citas = await CitaRepository.instance.obtenerTodas();

      expect(citas.length, 1, reason: 'la migracion NO debe perder datos');
      expect(citas.first.codigoQr, 'VIEJO-1');
      expect(citas.first.cliente, 'Cliente Anterior');
      expect(citas.first.vehiculo, 'Ford Ranger');
      // Columnas nuevas: llegan con el default, no en null.
      expect(citas.first.telefono, '');
      expect(citas.first.placa, '');
      expect(citas.first.anio, 0);
      expect(citas.first.servicios, isEmpty);
      expect(citas.first.tecnico, '');
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

      final id = await CitaRepository.instance.crear(nueva(qr: 'POST-MIGRA'));
      expect(id, greaterThan(0));
    });
  });
}

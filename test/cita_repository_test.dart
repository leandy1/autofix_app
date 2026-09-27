import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Prueba de integracion contra una base SQLite real (en memoria, via FFI).
/// No usa mocks: crea la tabla, inserta, lee, actualiza y elimina de verdad.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final db = await CitaRepository.instance.obtenerTodas();
    for (final c in db) {
      await CitaRepository.instance.eliminar(c.id!);
    }
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
        .copyWith(estado: EstadoCita.completada, cliente: 'Ana T. Updated');

    final filasAfectadas = await CitaRepository.instance.actualizar(editada);
    expect(filasAfectadas, 1);

    final releida = await CitaRepository.instance.obtenerPorId(id);
    expect(releida!.estado, EstadoCita.completada);
    expect(releida.cliente, 'Ana T. Updated');
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
}

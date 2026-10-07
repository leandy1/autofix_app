import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/shared/models/cita_admin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regresion del guardado de citas desde el panel de administracion.
///
/// El defecto era que el admin no perdia datos al EDITAR la ficha: los perdia
/// en silencio y sin avisar. `_aCitaPersistida` reconstruia la entidad `Cita`
/// desde `CitaAdmin` sin `tallerId` ni `creadoEn` (esos campos no existian en
/// `CitaAdmin`), y `Cita.toMap()` escribia `taller_id` aunque fuera null y
/// fabricaba `creado_en` con `DateTime.now()`. `db.update` con mapa completo
/// aplicaba las dos cosas: la cita dejaba de pertenecer a su taller y perdia la
/// fecha en que se agendo.
///
/// Lo grave es que no hacia falta abrir el formulario: mover el desplegable de
/// estado reescribia la fila entera y desasociaba la cita del taller.
///
/// Estos tests fijan el comportamiento correcto para que no vuelva.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Base propia: este archivo corre en paralelo con los otros que usan SQLite.
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_citas_admin_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    await DatabaseHelper.resetParaPruebas();
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
  });

  late CitaRepository repo;

  setUp(() {
    repo = CitaRepository.instance;
  });

  // v7: `leerFila` recibe el id como TEXTO. La PK paso de `INTEGER` a `TEXT`
  // con UUID, asi que un `int` no compila. `whereArgs` va en una lista de
  // `Object?` porque `sqflite` no acepta la lista `int` que se usaba antes.
  Future<List<Map<String, Object?>>> leerFila(String id) async {
    final db = await DatabaseHelper.instance.base;
    final filas = await db.query(
      'citas',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    expect(filas, hasLength(1), reason: 'la cita deberia seguir existiendo');
    return filas;
  }

  /// Id del taller con el que se agendan las citas de estos tests.
  ///
  /// Antes era `3`, el autoincremento que le tocaba al tercer taller sembrado. Con
  /// la PK en TEXT, el id de un taller es un UUID, asi que el `3` paso a ser un
  /// id fijo con la forma correcta.
  ///
  /// A proposito NO se lee el id de un taller real de la base: este archivo prueba
  /// que la cita CONSERVA el `taller_id` que se le dio, no que el id exista en
  /// `talleres`. Esa es otra prueba y esta en `talleres_test.dart`. Y con la
  /// FK ausente (ver `_crearTalleres` en `DatabaseHelper`) SQLite no protestaria
  /// ni con un id inventado, asi que el test seguiria verde igual.
  const tallerId = '33333333-3333-4333-8333-333333333333';

  /// Cita tal como la agenda un cliente: con taller y con fecha de alta.
  ///
  /// La fecha va en `DateTime.utc` porque el modelo persiste UTC. Con
  /// `DateTime(2026, 11, 3, 10)` (hora local) el round-trip devuelve otra hora en
  /// cualquier maquina que no este en UTC, y el test fallaria por zona horaria y
  /// no por un defecto del codigo.
  Cita citaDelCliente() => Cita(
    cliente: 'María Pérez',
    telefono: '809-555-0142',
    correoCliente: 'maria@ejemplo.com',
    vehiculo: 'Toyota Hilux',
    marca: 'Toyota',
    modelo: 'Hilux',
    anio: 2021,
    placa: 'A123456',
    servicios: const ['Cambio de aceite'],
    tecnico: 'Luis',
    descripcion: 'Revisión general',
    fechaCita: DateTime.utc(2026, 11, 3, 10),
    tallerId: tallerId,
    codigoVisible: 'CITA-0025',
    total: 4500,
  );

  /// Reproduce el puente `Cita` -> `CitaAdmin` -> `Cita` de la pantalla real.
  ///
  /// La pantalla tiene estos metodos privados, asi que el test reconstruye el
  /// mismo mapeo. Si `CitaAdmin` vuelve a perder un campo, esta copia queda
  /// desalineada del codigo real y el test dejaria de proteger: por eso el
  /// contrato se comprueba tambien abajo, sobre el modelo.
  Cita puenteDelAdmin(Cita base, {required EstadoCitaAdmin estado}) {
    final tarjeta = CitaAdmin(
      // `base.id!` y no `base.id ?? 7`: la cita ya esta guardada cuando este
      // puente se usa, y `CitaAdmin.id` es `String?` justamente para el caso
      // contrario. Con un `??` inventando un id aca el test dejaria de detectar
      // una cita sin id.
      id: base.id!,
      codigoVisible: base.codigoVisible,
      cliente: base.cliente,
      telefono: base.telefono,
      correoCliente: base.correoCliente,
      marca: base.marca,
      modelo: base.modelo,
      anio: base.anio.toString(),
      placa: base.placa,
      servicios: base.servicios,
      fecha: base.fechaCita,
      hora: TimeOfDay.fromDateTime(base.fechaCita),
      estado: estado,
      descripcion: base.descripcion,
      tecnico: base.tecnico,
      total: base.total.toDouble(),
      tallerId: base.tallerId,
      creadoEn: base.creadoEn,
      actualizadoEn: base.actualizadoEn,
    );

    final estadoCita = switch (tarjeta.estado) {
      EstadoCitaAdmin.pendiente => EstadoCita.pendiente,
      EstadoCitaAdmin.aceptada => EstadoCita.aceptada,
      EstadoCitaAdmin.rechazada => EstadoCita.rechazada,
      EstadoCitaAdmin.esperandoPieza => EstadoCita.esperandoPieza,
      EstadoCitaAdmin.enProceso => EstadoCita.enProceso,
      EstadoCitaAdmin.completada => EstadoCita.completado,
      EstadoCitaAdmin.atrasada => EstadoCita.pendiente,
    };

    return Cita(
      id: tarjeta.id,
      codigoVisible: tarjeta.codigoVisible,
      cliente: tarjeta.cliente,
      telefono: tarjeta.telefono,
      correoCliente: tarjeta.correoCliente,
      vehiculo: base.vehiculo,
      marca: tarjeta.marca,
      modelo: tarjeta.modelo,
      anio: int.tryParse(tarjeta.anio) ?? 0,
      placa: tarjeta.placa,
      servicios: tarjeta.servicios,
      tecnico: tarjeta.tecnico ?? '',
      descripcion: tarjeta.descripcion,
      fechaCita: DateTime(
        tarjeta.fecha.year,
        tarjeta.fecha.month,
        tarjeta.fecha.day,
        tarjeta.hora.hour,
        tarjeta.hora.minute,
      ),
      estado: estadoCita,
      total: tarjeta.total.round(),
      tallerId: tarjeta.tallerId,
      // `creadoEn` y `actualizadoEn` se copian desde la tarjeta. Este es el punto
      // del archivo: si el puente los perdiera, el UPDATE re-sellaria `creado_en`
      // con la hora del guardado y la cita perderia la fecha en que se agendo.
      creadoEn: tarjeta.creadoEn,
      actualizadoEn: tarjeta.actualizadoEn,
    );
  }

  group('CitaAdmin transporta los campos de auditoria', () {
    test('no pierde tallerId ni creadoEn al ir y volver a Cita', () {
      // v7: la cita de este test NO esta guardada (por eso `id` es null), asi que
      // `original.id ?? 7` ya no aplica: el `7` era un id numerico inventado. Se
      // usa un UUID fijo.
      final original = citaDelCliente();
      final ida = CitaAdmin(
        id: original.id ?? '44444444-4444-4444-8444-444444444444',
        codigoVisible: original.codigoVisible,
        correoCliente: original.correoCliente,
        cliente: original.cliente,
        telefono: original.telefono,
        marca: original.marca,
        modelo: original.modelo,
        anio: original.anio.toString(),
        placa: original.placa,
        servicios: original.servicios,
        fecha: original.fechaCita,
        hora: TimeOfDay.fromDateTime(original.fechaCita),
        estado: EstadoCitaAdmin.pendiente,
        descripcion: original.descripcion,
        tecnico: original.tecnico,
        total: original.total.toDouble(),
        tallerId: tallerId,
        creadoEn: DateTime.utc(2026, 1, 1, 8),
        actualizadoEn: DateTime.utc(2026, 1, 2, 9),
      );

      expect(ida.tallerId, tallerId);
      expect(ida.codigoVisible, original.codigoVisible);
      expect(ida.correoCliente, original.correoCliente);
      expect(ida.creadoEn, DateTime.utc(2026, 1, 1, 8));
      expect(ida.actualizadoEn, DateTime.utc(2026, 1, 2, 9));
    });
  });

  group('guardar desde el admin preserva el taller', () {
    test('editar la ficha no borra taller_id', () async {
      final id = await repo.crear(citaDelCliente());

      final guardada = (await repo.obtenerPorId(id))!;
      expect(guardada.tallerId, tallerId);

      // El admin edita el telefono y el tecnico, y guarda.
      final editada = puenteDelAdmin(
        guardada,
        estado: EstadoCitaAdmin.enProceso,
      ).copyWith(telefono: '809-555-9999', tecnico: 'Ana', total: 5000);

      final actualizada = await repo.actualizar(editada);
      expect(actualizada, 1, reason: 'actualizar debe afectar 1 fila');

      final fila = await leerFila(id);
      expect(
        fila.first['taller_id'],
        tallerId,
        reason: 'editar desde el admin no debe desasociar la cita del taller',
      );
      expect(fila.first['telefono'], '809-555-9999');
      expect(fila.first['codigo_visible'], 'CITA-0025');
      expect(fila.first['correo_cliente'], 'maria@ejemplo.com');
    });

    test('la cita sigue apareciendo en obtenerPorTaller tras editar', () async {
      final id = await repo.crear(citaDelCliente());

      final guardada = (await repo.obtenerPorId(id))!;
      await repo.actualizar(
        puenteDelAdmin(
          guardada,
          estado: EstadoCitaAdmin.enProceso,
        ).copyWith(anio: 2022),
      );

      final delTaller = await repo.obtenerPorTaller(tallerId);
      expect(
        delTaller.map((c) => c.id),
        contains(id),
        reason: 'la cita debe seguir listandose en el panel del taller',
      );
    });

    test('un alta sin taller sigue dejando la columna en null', () async {
      // Ojo: `copyWith(tallerId: null)` NO sirve para esto, porque usa
      // `tallerId ?? this.tallerId` y null significa "conserva el actual".
      // Por eso el alta sin taller se construye a mano.
      final id = await repo.crear(
        Cita(
          cliente: 'Sin taller',
          telefono: '809-555-0000',
          vehiculo: 'Kia Rio',
          marca: 'Kia',
          modelo: 'Rio',
          anio: 2019,
          placa: 'B654321',
          servicios: const ['Cambio de filtros'],
          descripcion: 'Sin afiliacion',
          fechaCita: DateTime.utc(2026, 11, 4, 9),
          total: 2000,
        ),
      );
      final fila = await leerFila(id);
      expect(fila.first['taller_id'], isNull);
    });
  });

  group('creado_en se escribe una sola vez', () {
    test('actualizar no reescribe la fecha de creacion', () async {
      final id = await repo.crear(citaDelCliente());
      final altaOriginal = (await leerFila(id)).first['creado_en'];

      await repo.actualizar(
        ((await repo.obtenerPorId(id))!)
            .copyWith(descripcion: 'Cambio de texto'),
      );

      final despues = (await leerFila(id)).first['creado_en'];
      expect(
        despues,
        altaOriginal,
        reason: 'actualizar no debe re-sellar cuando se creo la cita',
      );
    });

    test('un UPDATE sin creadoEn no inventa una fecha de alta', () async {
      final id = await repo.crear(citaDelCliente());
      final original = (await leerFila(id)).first;

      // Se reproduce el caso que rompia: un `Cita` armado a mano sin `creadoEn`
      // (no lo sabe, porque `CitaAdmin` no lo traia) que actualiza la fila.
      final sinTrazabilidad = Cita(
        id: id,
        cliente: 'María Pérez',
        telefono: '809-555-0142',
        vehiculo: 'Toyota Hilux',
        marca: 'Toyota',
        modelo: 'Hilux',
        anio: 2021,
        placa: 'A123456',
        servicios: const ['Cambio de aceite'],
        descripcion: 'Revisión general',
        fechaCita: DateTime.utc(2026, 11, 3, 10),
        tallerId: tallerId,
        total: 4500,
      );

      await repo.actualizar(sinTrazabilidad);

      final fila = (await leerFila(id)).first;
      // La asercion central de ESTE test. `Cita.toMap()` omite `creado_en` cuando
      // el modelo no la conoce, y `db.update` deja intacta la columna: por eso la
      // fecha de alta sobrevive a un UPDATE hecho desde un objeto que no la
      // traia. Si alguien cambia el `toMap` para mandar la columna siempre, aca
      // falla con la hora del guardado en vez de la del alta.
      expect(fila['creado_en'], original['creado_en']);
      expect(fila['taller_id'], tallerId);
    });

    test('actualizado_en si se refresca en cada escritura', () async {
      final id = await repo.crear(citaDelCliente());
      final primera = (await leerFila(id)).first['actualizado_en'];

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await repo.actualizar(
        ((await repo.obtenerPorId(id))!).copyWith(total: 9999),
      );

      final segunda = (await leerFila(id)).first['actualizado_en'];
      expect(segunda, isNot(primera));
    });
  });

  group('cambiarEstado es un update parcial', () {
    test('mueve el estado sin tocar taller_id ni creado_en', () async {
      final id = await repo.crear(citaDelCliente());
      final antes = (await leerFila(id)).first;

      final ok = await repo.cambiarEstado(id, EstadoCita.enProceso);
      expect(ok, 1);

      final despues = (await leerFila(id)).first;
      expect(despues['estado'], EstadoCita.enProceso.name);
      expect(despues['taller_id'], antes['taller_id']);
      expect(despues['creado_en'], antes['creado_en']);
      expect(despues['total'], antes['total']);
      expect(despues['placa'], antes['placa']);
    });

    test('el cambio de estado no pierde el total', () async {
      final id = await repo.crear(citaDelCliente());
      await repo.cambiarEstado(id, EstadoCita.completado);
      expect((await leerFila(id)).first['total'], 4500);
    });
  });
}

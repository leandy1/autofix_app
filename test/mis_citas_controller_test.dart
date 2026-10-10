import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/cliente/presentation/mis_citas_controller.dart';
import 'package:autofix/features/talleres/data/taller_repository.dart';
import 'package:autofix/features/talleres/models/taller.dart';

/// "Mis citas" es la pantalla que el cliente abre SIN internet, asi que lo que
/// hay que garantizar es que su controller se arme solo con la base local:
/// sin sesion (el cliente no tiene), sin nube y con el orden que espera el
/// usuario (lo proximo arriba).
void main() {
  const correoCliente = 'ana@autofix.test';
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Base propia: este archivo corre en paralelo con los demas que usan SQLite.
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_mis_citas_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    // Sin este reset `onCreate` no vuelve a correr y el test prueba un esquema
    // viejo (o citas de otro test).
    await DatabaseHelper.resetParaPruebas();
  });

  final repoCitas = CitaRepository.instance;
  final repoTalleres = TallerRepository.instance;

  Cita citaEn(
    DateTime fecha, {
    String? tallerId,
    EstadoCita estado = EstadoCita.pendiente,
  }) => Cita(
    cliente: 'Ana Torres',
    correoCliente: correoCliente,
    vehiculo: 'Toyota Hilux',
    fechaCita: fecha,
    estado: estado,
    tallerId: tallerId,
  );

  MisCitasController nuevoController() => MisCitasController(
    citas: repoCitas,
    talleres: repoTalleres,
    correoCliente: correoCliente,
  );

  group('lectura local', () {
    test('arranca vacia y sin errores', () async {
      final controller = nuevoController();
      await controller.cargar();

      expect(controller.cargando, isFalse);
      expect(controller.error, isNull);
      expect(controller.hayCitas, isFalse);
      expect(controller.pendientesDeSync, 0);
    });

    test('lista la cita con el nombre del taller ya resuelto', () async {
      final idTaller = await repoTalleres.crear(
        const Taller(
          nombre: 'Global Refriauto',
          latitud: 18.5,
          longitud: -69.9,
        ),
      );
      final id = await repoCitas.crear(
        citaEn(DateTime.now().add(const Duration(days: 2)), tallerId: idTaller),
      );

      final controller = nuevoController();
      await controller.cargar();

      expect(controller.hayCitas, isTrue);
      final item = controller.items.single;
      expect(item.tallerNombre, 'Global Refriauto');
      expect(item.etiqueta, 'Pendiente');
      expect(item.cita.id, id);
    });

    test('las borradas no aparecen', () async {
      final id = await repoCitas.crear(
        citaEn(DateTime.now().add(const Duration(days: 1))),
      );
      await repoCitas.eliminar(id);

      final controller = nuevoController();
      await controller.cargar();

      expect(controller.hayCitas, isFalse);
    });

    test(
      'filtra y conserva las citas asociadas al correo del perfil',
      () async {
        await repoCitas.crear(
          citaEn(DateTime.now().add(const Duration(days: 2))),
        );
        await repoCitas.crear(
          citaEn(DateTime.now().add(const Duration(days: 3)))
              .copyWith(correoCliente: 'otra@autofix.test'),
        );

        final controller = nuevoController();
        await controller.cargar();

        expect(controller.items, hasLength(1));
        expect(controller.items.single.cita.correoCliente, correoCliente);
      },
    );
  });

  group('cola de sincronizacion', () {
    test('cuenta las citas que todavia no subieron', () async {
      await repoCitas.crear(
        citaEn(DateTime.now().add(const Duration(days: 3))),
      );
      final segunda = await repoCitas.crear(
        citaEn(DateTime.now().add(const Duration(days: 4))),
      );

      final controller = nuevoController();
      await controller.cargar();

      expect(controller.pendientesDeSync, 2);
      expect(controller.hayPendientes, isTrue);
      expect(controller.items.every((i) => i.enCola), isTrue);

      // Tras el push a Firebase la fila queda 'synced': el badge tiene que
      // desaparecer, o el usuario creeria que su cita nunca se envio.
      await repoCitas.marcarSincronizada(segunda);
      await controller.cargar();

      expect(controller.pendientesDeSync, 1);
      // `segunda` es la mas lejana (+4 dias), asi que es la ULTIMA de las
      // futuras: por eso la que sigue en cola es `items.first` y la que ya
      // subio cierra la lista.
      expect(controller.items.first.enCola, isTrue);
      expect(controller.items.last.enCola, isFalse);
    });

    test('una cita ya sincronizada no lleva badge de cola', () async {
      final id = await repoCitas.crear(
        citaEn(DateTime.now().add(const Duration(days: 6))),
      );
      await repoCitas.marcarSincronizada(id);

      final controller = nuevoController();
      await controller.cargar();

      expect(controller.hayPendientes, isFalse);
      expect(controller.items.single.enCola, isFalse);
    });
  });

  group('orden para el cliente', () {
    test('las proximas van primero y las pasadas al final', () async {
      await repoCitas.crear(
        citaEn(DateTime.now().subtract(const Duration(days: 5))),
      );
      await repoCitas.crear(
        citaEn(DateTime.now().add(const Duration(days: 10))),
      );
      await repoCitas.crear(
        citaEn(DateTime.now().add(const Duration(days: 1))),
      );

      final controller = nuevoController();
      await controller.cargar();

      final fechas = [for (final item in controller.items) item.cita.fechaCita];
      final ahora = DateTime.now();

      // No es la lista ordenada en su totalidad sino los DOS grupos del
      // diseno: las futuras primero (y ahi si ascendente)...
      expect(controller.items.length, 3);
      expect(fechas[0].isAfter(ahora), isTrue);
      expect(fechas[1].isAfter(ahora), isTrue);
      expect(fechas[0].isBefore(fechas[1]), isTrue);
      // ...y la pasada (hace 5 dias) cerrando la lista, con la etiqueta que
      // la distingue de una cita que simplemente vino despues.
      expect(fechas[2].isBefore(ahora), isTrue);
      expect(controller.items.last.etiqueta, 'ATRASADAS');
    });
  });

  group('casos sin taller', () {
    test('distingue "sin asignar" de "no disponible"', () async {
      await repoCitas.crear(
        citaEn(DateTime.now().add(const Duration(days: 2))),
      );
      await repoCitas.crear(
        citaEn(
          DateTime.now().add(const Duration(days: 3)),
          tallerId: 'taller-que-no-existe',
        ),
      );

      final controller = nuevoController();
      await controller.cargar();

      final nombres = [for (final i in controller.items) i.tallerNombre]
        ..sort();
      expect(nombres, ['Taller no disponible', 'Taller sin asignar']);
    });
  });

  group('errores de la base local', () {
    test('una base ilegible deja el aviso y conserva la lista', () async {
      await repoCitas.crear(
        citaEn(DateTime.now().add(const Duration(days: 2))),
      );
      final controller = nuevoController();
      await controller.cargar();
      expect(controller.hayCitas, isTrue);

      // Pone un directorio justamente en la ruta del .db: `openDatabase` no
      // puede abrirla y revienta con un DatabaseException (que ES un Exception,
      // asi que el catch de `cargar()` lo agarra en vez de dejarlo salir).
      final ruta = p.join(
        await getDatabasesPath(),
        DatabaseHelper.nombreBaseParaPruebas!,
      );
      await DatabaseHelper.resetParaPruebas();
      await Directory(ruta).create(recursive: true);

      try {
        await controller.cargar();

        expect(controller.error, isNotNull);
        expect(controller.cargando, isFalse);
        // Lo importante: no se pinta la pantalla en blanco. La lista anterior
        // sigue ahi y la vista ofrece "reintentar" sobre ese error.
        expect(controller.hayCitas, isTrue);
        expect(controller.pendientesDeSync, 1);
      } finally {
        final dir = Directory(ruta);
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });
  });

  group('motivo de rechazo', () {
    test('cita rechazada con motivo lo muestra en el item', () async {
      final id = await repoCitas.crear(
        citaEn(DateTime.now().add(const Duration(days: 1))).copyWith(
          estado: EstadoCita.rechazada,
          motivoRechazo: 'Taller completo para esa fecha',
        ),
      );

      final controller = nuevoController();
      await controller.cargar();

      expect(controller.hayCitas, isTrue);
      final item = controller.items.single;
      expect(item.cita.estado, EstadoCita.rechazada);
      expect(item.cita.motivoRechazo, 'Taller completo para esa fecha');
      expect(item.etiqueta, 'Rechazada');
    });

    test('cita rechazada sin motivo no muestra motivo vacio', () async {
      await repoCitas.crear(
        citaEn(DateTime.now().add(const Duration(days: 1))).copyWith(
          estado: EstadoCita.rechazada,
          motivoRechazo: '',
        ),
      );

      final controller = nuevoController();
      await controller.cargar();

      expect(controller.hayCitas, isTrue);
      final item = controller.items.single;
      expect(item.cita.estado, EstadoCita.rechazada);
      expect(item.cita.motivoRechazo, isNull); // vacio se guarda como NULL
      expect(item.etiqueta, 'Rechazada');
    });
  });
}

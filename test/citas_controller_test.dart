import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/citas/presentation/citas_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Prueba la capa intermedia: el controller es lo unico que la vista conoce,
/// asi que es lo que hay que garantizar. La agrupacion por estado vive aca
/// desde que salio del repositorio, que no debe saber de etiquetas de UI.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Base propia: este archivo corre en paralelo con los otros que usan SQLite
    // y sin esto se pisarian el mismo archivo.
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_controller_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    // El .db queda en `.dart_tool/`, o sea en disco. Sin este reset `onCreate` no
    // se vuelve a correr y el test pasa probando un esquema viejo.
    await DatabaseHelper.resetParaPruebas();
  });

  Cita nueva() => Cita(
        cliente: 'Ana Torres',
        vehiculo: 'Toyota Hilux',
        fechaCita: DateTime(2026, 10, 1, 9, 30),
      );

  CitasController nuevoController() => CitasController(
        repositorio: CitaRepository.instance,
      );

  group('CRUD a traves del controller', () {
    test('cargar arranca listo y expone la lista', () async {
      final controller = nuevoController();
      await controller.cargar();

      expect(controller.cargando, isFalse);
      expect(controller.hayCitas, isFalse);
      expect(controller.citas, isEmpty);
    });

    test('guardar crea y la lista queda actualizada sin volver a pedirla', () async {
      final controller = nuevoController();
      await controller.cargar();

      final ok = await controller.guardar(nueva());

      expect(ok, isTrue);
      expect(controller.citas.length, 1);
      expect(controller.citas.first.cliente, 'Ana Torres');
      expect(controller.citas.first.id, isNotNull);
    });

    test('guardar con id edita en vez de duplicar', () async {
      final controller = nuevoController();
      await controller.cargar();
      await controller.guardar(nueva());
      final guardada = controller.citas.first;

      await controller.guardar(guardada.copyWith(cliente: 'Ana Editada'));

      expect(controller.citas.length, 1);
      expect(controller.citas.first.cliente, 'Ana Editada');
    });

    test('cambiarEstado actualiza la fila y notifica', () async {
      final controller = nuevoController();
      await controller.cargar();
      await controller.guardar(nueva());
      var notificaciones = 0;
      controller.addListener(() => notificaciones++);

      final ok = await controller.cambiarEstado(
        controller.citas.first.id!,
        EstadoCita.enProceso,
      );

      expect(ok, isTrue);
      expect(controller.citas.first.estado, EstadoCita.enProceso);
      expect(notificaciones, greaterThan(0));
    });

    test('eliminar saca la cita de la lista', () async {
      final controller = nuevoController();
      await controller.cargar();
      await controller.guardar(nueva());

      final ok = await controller.eliminar(controller.citas.first.id!);

      expect(ok, isTrue);
      expect(controller.hayCitas, isFalse);
    });

    test('guardar conserva el total en la lista persistida', () async {
      final controller = nuevoController();
      await controller.cargar();
      final ok = await controller.guardar(nueva().copyWith(total: 900));
      expect(ok, isTrue);
      expect(controller.citas.single.total, 900);
    });

    test('las citas mas antiguas y atrasadas aparecen primero en la lista', () async {
      final controller = nuevoController();
      await controller.cargar();
      await controller.guardar(
        nueva().copyWith(fechaCita: DateTime(2026, 10, 10, 9, 30)),
      );
      await controller.guardar(
        nueva().copyWith(fechaCita: DateTime(2026, 10, 1, 9, 30)),
      );

      expect(controller.citas.first.fechaCita, DateTime(2026, 10, 1, 9, 30));
      expect(controller.citas.last.fechaCita, DateTime(2026, 10, 10, 9, 30));
    });
  });

  group('agrupacion por estado (logica que estaba en el repositorio)', () {
    test('devuelve las 5 llaves de la UI aunque esten vacias', () async {
      final controller = nuevoController();
      await controller.cargar();

      final mapa = controller.agruparPorEstado(DateTime(2026, 10, 1));

      expect(mapa.keys, CitasController.etiquetas);
      expect(mapa.values.every((lista) => lista.isEmpty), isTrue);
    });

    test('reparte las citas del dia en su etiqueta', () async {
      final controller = nuevoController();
      final manana = DateTime(2026, 10, 1, 9, 30);

      await controller.guardar(
        nueva().copyWith(fechaCita: manana, estado: EstadoCita.pendiente),
      );
      await controller.guardar(
        nueva().copyWith(fechaCita: manana, estado: EstadoCita.completado),
      );
      await controller.guardar(
        nueva().copyWith(fechaCita: manana, estado: EstadoCita.enProceso),
      );

      final mapa = controller.agruparPorEstado(
        DateTime(2026, 10, 1),
        ahora: DateTime(2026, 10, 1, 8),
      );

      expect(mapa['Pendiente']!.length, 1);
      expect(mapa['Completado']!.length, 1);
      expect(mapa['En proceso']!.length, 1);
      expect(mapa['ATRASADAS']!.length, 0);
    });

    test('las citas del dia consultado quedan normales y las anteriores pasan a ATRASADAS', () async {
      final controller = nuevoController();
      await controller.guardar(
        nueva().copyWith(
          fechaCita: DateTime(2026, 9, 30, 9, 30),
          estado: EstadoCita.pendiente,
        ),
      );
      await controller.guardar(
        nueva().copyWith(
          fechaCita: DateTime(2026, 10, 1, 9, 30),
          estado: EstadoCita.pendiente,
        ),
      );

      final vistaDelDia30 = controller.agruparPorEstado(
        DateTime(2026, 9, 30),
        ahora: DateTime(2026, 10, 1, 8),
      );

      expect(vistaDelDia30['ATRASADAS']!.length, 0);
      expect(vistaDelDia30['Pendiente']!.length, 1);

      final vistaDelDia1 = controller.agruparPorEstado(
        DateTime(2026, 10, 1),
        ahora: DateTime(2026, 10, 1, 8),
      );

      expect(vistaDelDia1['ATRASADAS']!.length, 1);
      expect(vistaDelDia1['Pendiente']!.length, 1);
    });

    test('las citas de otros dias no aparecen en la vista del dia seleccionado', () async {
      final controller = nuevoController();
      await controller.guardar(
        nueva().copyWith(fechaCita: DateTime(2026, 10, 1, 9, 30)),
      );
      await controller.guardar(
        nueva().copyWith(fechaCita: DateTime(2026, 9, 30, 9, 30)),
      );

      final mapa = controller.agruparPorEstado(
        DateTime(2026, 10, 1),
        ahora: DateTime(2026, 10, 1, 8),
      );

      expect(mapa['ATRASADAS']!.length, 1);
      expect(mapa['Pendiente']!.length, 1);
    });

    test('el mismo dia no se marca atrasada aunque ya haya pasado la hora', () {
      final cita = nueva().copyWith(fechaCita: DateTime(2026, 10, 29, 9, 30));

      expect(cita.esAtrasada(DateTime(2026, 10, 29, 10)), isFalse);
      expect(cita.esAtrasada(DateTime(2026, 10, 30, 9)), isTrue);
      expect(cita.etiquetaUI(DateTime(2026, 10, 29, 10)), 'Pendiente');
      expect(cita.etiquetaUI(DateTime(2026, 10, 30, 9)), 'ATRASADAS');
      expect(CitasController.etiquetas.length, 5);
    });
  });

  group('formateo', () {
    test('la fecha se formatea dd/MM/yyyy HH:mm', () {
      expect(
        CitasController.formatearFechaHora(DateTime(2026, 10, 1, 9, 30)),
        '01/10/2026 09:30',
      );
    });
  });

}

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
    TestWidgetsFlutterBinding.ensureInitialized();
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

  CitasController nuevoController() =>
      CitasController(repositorio: CitaRepository.instance);

  group('CRUD a traves del controller', () {
    test('cargar arranca listo y expone la lista', () async {
      final controller = nuevoController();
      await controller.cargar();

      expect(controller.cargando, isFalse);
      expect(controller.hayCitas, isFalse);
      expect(controller.citas, isEmpty);
    });

    test(
      'guardar crea y la lista queda actualizada sin volver a pedirla',
      () async {
        final controller = nuevoController();
        await controller.cargar();

        final ok = await controller.guardar(nueva());

        expect(ok, isTrue);
        expect(controller.citas.length, 1);
        expect(controller.citas.first.cliente, 'Ana Torres');
      },
    );

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

    test('una cita pendiente de dias anteriores cae en ATRASADAS al consultar hoy', () async {
      final controller = nuevoController();
      await controller.guardar(nueva().copyWith(fechaCita: DateTime(2026, 9, 30, 9, 30)));

      final mapa = controller.agruparPorEstado(
        DateTime(2026, 10, 1),
        ahora: DateTime(2026, 10, 1, 10),
      );

      expect(mapa['ATRASADAS']!.length, 1);
      expect(mapa['Pendiente']!.length, 0);
    });

    test('filtra por dia: lo de otro dia no aparece al consultar fecha distinta a hoy', () async {
      final controller = nuevoController();
      await controller.guardar(
        nueva().copyWith(fechaCita: DateTime(2026, 10, 1, 9, 30)),
      );
      await controller.guardar(
        nueva().copyWith(fechaCita: DateTime(2026, 9, 30, 9, 30)),
      );

      final mapa = controller.agruparPorEstado(
        DateTime(2026, 10, 1),
        ahora: DateTime(2026, 10, 2, 8),
      );

      expect(mapa.values.expand((l) => l).length, 1);
    });

    test(
      'una cita de la noche se agrupa en su dia local, no en el dia UTC',
      () async {
        final controller = nuevoController();
        await controller.guardar(
          nueva().copyWith(fechaCita: DateTime(2026, 10, 1, 23, 30)),
        );

        final hoy = controller.agruparPorEstado(
          DateTime(2026, 10, 1),
          ahora: DateTime(2026, 10, 1, 8),
        );
        final manana = controller.agruparPorEstado(
          DateTime(2026, 10, 2),
          ahora: DateTime(2026, 10, 2, 8),
        );

        // La cita es del 01 a las 23:30 LOCAL. Aunque la base la
        // guarde en UTC (que ya es 02/03/04 del otro dia segun el
        // huso), al leerla tiene que caer en el 01, no en el 02.
        expect(hoy['Pendiente']!.length, 1);
        expect(manana['Pendiente']!.length, 0);
        // Vista desde el 02, la pendiente de ayer es atrasada.
        expect(manana['ATRASADAS']!.length, 1);
      },
    );

    test('el mismo instante da el mismo grupo en cualquier dispositivo', () {
      // El determinismo es la razon de que `esAtrasada` reciba `ahora`: dos
      // dispositivos con el mismo reloj tienen que clasificar igual, siempre.
      final cita = nueva().copyWith(fechaCita: DateTime(2026, 10, 1, 9, 30));

      expect(cita.esAtrasada(DateTime(2026, 10, 2, 0)), isTrue);
      expect(cita.esAtrasada(DateTime(2026, 10, 1, 9)), isFalse);
      expect(cita.etiquetaUI(DateTime(2026, 10, 2, 0)), 'ATRASADAS');
      expect(cita.etiquetaUI(DateTime(2026, 10, 1, 9)), 'Pendiente');
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

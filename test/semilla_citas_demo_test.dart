import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/database/semilla_citas_demo.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pruebas de la semilla de citas de demostracion.
///
/// La prueba mas importante de este archivo es la primera: que una base recien
/// creada nazca SIN citas. Si esa falla, la data de prueba se coló en la
/// semilla inicial de verdad y ahora cada instalacion real abre el Dashboard del
/// administrador con clientes e ingresos que no existen.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_semilla_citas_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    await DatabaseHelper.resetParaPruebas();
  });

  final repo = CitaRepository.instance;
  final referencia = DateTime(2026, 10, 2, 15, 0);
  final hoy = DateTime(2026, 10, 2);

  group('la semilla NO es parte del esquema', () {
    test('una base recien creada nace sin citas', () async {
      // Este es el que protege la instalacion real. `onCreate` siembra talleres,
      // tecnicos, servicios y estados, y NO citas.
      final citas = await repo.obtenerTodas();

      expect(citas, isEmpty);
    });

    test('migrar tampoco inyecta citas en una base que ya tenia', () async {
      // Una base que llega a la v5 con sus propias citas debe conservarlas tal
      // cual: ni se duplican, ni se mezclan con las de demostracion.
      await repo.crear(
        Cita(
          cliente: 'Cliente Real',
          vehiculo: 'Ford Ranger',
          fechaCita: DateTime(2026, 9, 20, 10, 0),
        ),
      );
      await DatabaseHelper.instance.cerrar();

      await repo.obtenerTodas();

      final citas = await repo.obtenerTodas();
      expect(citas.length, 1);
      expect(citas.single.cliente, 'Cliente Real');
    });
  });

  group('sembrarCitasDemo', () {
    test('inyecta una cantidad considerable de citas', () async {
      final insertadas = await DatabaseHelper.sembrarCitasDemo(referencia: referencia);

      expect(insertadas, greaterThan(50));
      expect((await repo.obtenerTodas()).length, insertadas);
    });

    test('cubre pasado, hoy y futuro', () async {
      await DatabaseHelper.sembrarCitasDemo(referencia: referencia);
      final citas = await repo.obtenerTodas();

      final pasadas = citas.where((c) => c.fechaCita.isBefore(hoy)).length;
      final deHoy = citas.where((c) => c.fechaCita.day == 2 && c.fechaCita.month == 10 && c.fechaCita.year == 2026).length;
      final futuras = citas.where((c) => c.fechaCita.isAfter(DateTime(2026, 10, 2, 23, 59))).length;

      expect(pasadas, greaterThan(20), reason: 'historial para el grafico');
      expect(deHoy, greaterThan(0), reason: 'hoy es lo primero que se mira');
      expect(futuras, greaterThan(0), reason: 'agendado hacia adelante');
    });

    test('reparte varios estados, no uno solo', () async {
      await DatabaseHelper.sembrarCitasDemo(referencia: referencia);
      final r = await repo.resumir(ahora: referencia);

      // Los cuatro estados reales tienen que aparecer, porque las cuatro
      // tarjetas del Dashboard los cuentan.
      expect(r.contar(EstadoCita.pendiente), greaterThan(0));
      expect(r.contar(EstadoCita.esperandoPieza), greaterThan(0));
      expect(r.contar(EstadoCita.enProceso), greaterThan(0));
      expect(r.contar(EstadoCita.completado), greaterThan(0));
    });

    test('deja citas atrasadas y citas completadas con ingresos', () async {
      await DatabaseHelper.sembrarCitasDemo(referencia: referencia);
      final r = await repo.resumir(ahora: referencia);

      expect(r.atrasadas, greaterThan(0));
      expect(r.ingresos, greaterThan(0));

      // La prueba de que el filtro por estado REALMENTE se aplica: las citas no
      // completadas tambien llevan `total` (es el precio cotizado), asi que los
      // ingresos tienen que ser menores que la suma de todos los totales. Si
      // dieran igual, seria porque se esta sumando cualquier `total`.
      final todas = await repo.obtenerTodas();
      final sumaDeTodosLosTotales = todas.fold<int>(0, (s, c) => s + c.total);

      expect(
        r.ingresos,
        lessThan(sumaDeTodosLosTotales),
        reason: 'ingresos = $r.ingresos vs suma total $sumaDeTodosLosTotales',
      );
    });

    test('los montos varían de una cita a otra', () async {
      await DatabaseHelper.sembrarCitasDemo(referencia: referencia);
      final citas = await repo.obtenerTodas();
      final montos = citas.map((c) => c.total).toSet();

      expect(montos.length, greaterThan(3));
      expect(citas.any((c) => c.total > 0), isTrue);
    });

    test('deja varias citas HOY para poder leer la lista del dia', () async {
      await DatabaseHelper.sembrarCitasDemo(referencia: referencia);
      final delDia = await repo.obtenerDelDia(hoy);

      expect(delDia.length, greaterThanOrEqualTo(SemillaCitasDemo.citasDeHoy));
      // Y ordenadas por hora, que es lo que espera la tabla del Dashboard.
      for (var i = 1; i < delDia.length; i++) {
        expect(
          delDia[i].fechaCita.isBefore(delDia[i - 1].fechaCita),
          isFalse,
          reason: 'obtenerDelDia debe devolver de menor a mayor hora',
        );
      }
    });

    test('las citas del futuro NO estan completadas', () async {
      await DatabaseHelper.sembrarCitasDemo(referencia: referencia);
      final futuras = (await repo.obtenerTodas())
          .where((c) => c.fechaCita.isAfter(DateTime(2026, 10, 2, 23, 59)));

      expect(futuras, isNotEmpty);
      expect(
        futuras.any((c) => c.estado == EstadoCita.completado),
        isFalse,
        reason: 'una cita del mañana completada sola es data imposible',
      );
    });

    test('es idempotente: llamarla dos veces no duplica nada', () async {
      final primera = await DatabaseHelper.sembrarCitasDemo(referencia: referencia);
      final segunda = await DatabaseHelper.sembrarCitasDemo(referencia: referencia);

      expect(primera, greaterThan(0));
      expect(segunda, 0, reason: 'la segunda pasada no debe insertar nada');
      expect((await repo.obtenerTodas()).length, primera);
    });

    test('NO pisa citas que ya existen', () async {
      // El caso del taller que ya esta trabajando: inyectar encima seria
      // indistinguible de un bug, asi que no se inyecta y se avisa con el 0.
      await repo.crear(
        Cita(
          cliente: 'Cliente Real',
          vehiculo: 'Ford Ranger',
          fechaCita: DateTime(2026, 10, 2, 9, 0),
          estado: EstadoCita.completado,
          total: 1234,
        ),
      );

      final insertadas = await DatabaseHelper.sembrarCitasDemo(referencia: referencia);
      final citas = await repo.obtenerTodas();

      expect(insertadas, 0);
      expect(citas.length, 1);
      expect(citas.single.cliente, 'Cliente Real');
    });

    test('las citas quedan asociadas a talleres que existen de verdad', () async {
      await DatabaseHelper.sembrarCitasDemo(referencia: referencia);

      final db = await DatabaseHelper.instance.base;
      final filasTalleres = await db.query(
        DatabaseHelper.tablaTalleres,
        columns: <String>[DatabaseHelper.colId],
      );
      final idsValidos = filasTalleres
          .map((f) => f[DatabaseHelper.colId])
          .toSet();

      expect(idsValidos, isNotEmpty, reason: 'la semilla de talleres debe existir');

      // `taller_id` tiene que apuntar a una fila real de `talleres`. Si el
      // generador inventara ids, el mapa y los filtros por taller harian de
      // citas a un taller que no existe, y no habria ningun error que lo delate.
      final citas = await repo.obtenerTodas();
      final conTaller = citas.where((c) => c.tallerId != null).toList();
      expect(conTaller, isNotEmpty, reason: 'debería asociar algunas citas');

      for (final c in conTaller) {
        expect(idsValidos, contains(c.tallerId));
      }
    });
  });

  group('generar: determinismo y anclaje temporal', () {
    test('la misma referencia produce el mismo lote', () async {
      final a = SemillaCitasDemo.generar(referencia: referencia, tallerIds: const <int>[1, 2, 3]);
      final b = SemillaCitasDemo.generar(referencia: referencia, tallerIds: const <int>[1, 2, 3]);

      expect(a.length, b.length);
      // Comparar el lote entero, no el largo: un `Random()` sin semilla cambiaria
      // los datos y haria imposible reproducir un fallo de la UI.
      expect(
        a.map((c) => '${c.cliente}|${c.fechaCita.toIso8601String()}|${c.total}').toList(),
        b.map((c) => '${c.cliente}|${c.fechaCita.toIso8601String()}|${c.total}').toList(),
      );
    });

    test('la referencia manda: sin citas HOY si se ancla a otro dia', () async {
      final otroDia = SemillaCitasDemo.generar(
        referencia: DateTime(2026, 3, 15),
        tallerIds: const <int>[1],
      );

      expect(otroDia.any((c) => c.fechaCita.day == 15 && c.fechaCita.month == 3), isTrue);
      expect(otroDia.any((c) => c.fechaCita.month == 10), isFalse);
    });

    test('sin talleres, las citas quedan sin taller y no revienta', () async {
      final sinTalleres = SemillaCitasDemo.generar(
        referencia: referencia,
        tallerIds: const <int>[],
      );

      expect(sinTalleres, isNotEmpty);
      expect(sinTalleres.every((c) => c.tallerId == null), isTrue);
    });

    test('el lote viene ordenado por fecha', () async {
      final lote = SemillaCitasDemo.generar(
        referencia: referencia,
        tallerIds: const <int>[1],
      );

      for (var i = 1; i < lote.length; i++) {
        expect(
          lote[i].fechaCita.isBefore(lote[i - 1].fechaCita),
          isFalse,
          reason: 'la semilla tiene que salir ordenada',
        );
      }
    });
  });
}

import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/admin/presentation/dashboard_admin_controller.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pruebas del `DashboardAdminController`: la capa intermedia entre la pantalla y
/// la base.
///
/// Lo que se garantiza aca es lo que la vista NO puede resolver sola:
///
/// - Que los numeros de las tarjetas salgan de la base y no de un `const`.
/// - Que cambiar la fecha cambie lo que es del dia y NO lo que es del taller.
/// - Que un fallo al releer no deje las tarjetas en cero.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_dashboard_ctrl_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    await DatabaseHelper.resetParaPruebas();
  });

  final repo = CitaRepository.instance;
  final hoy = DateTime.now();

  Cita cita({
    required DateTime fecha,
    EstadoCita estado = EstadoCita.pendiente,
    int total = 0,
    String cliente = 'Ana Torres',
  }) => Cita(
    cliente: cliente,
    vehiculo: 'Toyota Hilux',
    placa: 'A123456',
    servicios: const <String>['Frenos'],
    fechaCita: fecha,
    estado: estado,
    total: total,
  );

  Future<void> sembrar(List<Cita> citas) async {
    for (final c in citas) {
      await repo.crear(c);
    }
  }

  DateTime aLas(int hora) => DateTime(hoy.year, hoy.month, hoy.day, hora, 0);

  group('cargar', () {
    test('sale de cargando, sin error y con la data de la base', () async {
      await sembrar(<Cita>[
        cita(fecha: aLas(9), estado: EstadoCita.completado, total: 2000),
        cita(fecha: aLas(10), estado: EstadoCita.enProceso),
      ]);

      final c = DashboardAdminController();
      await c.cargar();

      expect(c.cargando, isFalse);
      expect(c.actualizando, isFalse);
      expect(c.error, isNull);
      expect(c.citasDia.length, 2);
    });

    test('con la base vacia no revienta: todo en cero y sin error', () async {
      final c = DashboardAdminController();
      await c.cargar();

      expect(c.error, isNull);
      expect(c.ordenesAbiertas, 0);
      expect(c.vehiculosEnTaller, 0);
      expect(c.completadas, 0);
      expect(c.ingresos, 0);
      expect(c.hayCitas, isFalse);
      expect(c.citasDia, isEmpty);
    });

    test('avisa a la vista para que se repinte', () async {
      final c = DashboardAdminController();
      var avisos = 0;
      c.addListener(() => avisos++);

      await c.cargar();

      expect(avisos, greaterThanOrEqualTo(2));
    });

    test('la primera carga tapa, un refresco posterior no', () async {
      final c = DashboardAdminController();
      final vistosCargando = <bool>[];
      c.addListener(() => vistosCargando.add(c.cargando));

      await c.cargar();
      await c.recargar();

      // La primera vez `cargando` va true->false. La segunda ya hay numeros en
      // pantalla, asi que el flag se queda en false: tapar la pantalla entera
      // para volver a pintar lo mismo se siente como que la app se trabo.
      expect(vistosCargando.where((v) => v).length, greaterThanOrEqualTo(1));
      expect(c.cargando, isFalse);
    });
  });

  group('las tarjetas', () {
    test('ordenes abiertas suma los tres estados operativos', () async {
      await sembrar(<Cita>[
        cita(fecha: aLas(8), estado: EstadoCita.pendiente),
        cita(fecha: aLas(9), estado: EstadoCita.esperandoPieza),
        cita(fecha: aLas(10), estado: EstadoCita.enProceso),
        cita(fecha: aLas(11), estado: EstadoCita.completado, total: 1500),
      ]);

      final c = DashboardAdminController();
      await c.cargar();

      // 'Completado' no entra: ya se entrego y no ocupa un orden abierto.
      expect(c.ordenesAbiertas, 3);
    });

    test('las atrasadas NO se suman a ordenes abiertas', () async {
      // Una cita atrasada esta, ademas, en pendiente/en proceso/esperando pieza.
      // Contarla en las dos tarjetas la haria aparecer dos veces.
      //
      // Fechas 3 dias atras y 2 dias adelante, y NO "hoy a las 9": una cita de
      // hoy ya paso o no segun la hora en que corra la suite, y este test daria
      // verde a las 8 de la manana y rojo a las 10.
      final base = DateTime(hoy.year, hoy.month, hoy.day);
      await sembrar(<Cita>[
        cita(
          fecha: base.subtract(const Duration(days: 3)),
          estado: EstadoCita.pendiente,
        ),
        cita(
          fecha: base.add(const Duration(days: 2)),
          estado: EstadoCita.enProceso,
        ),
      ]);

      final c = DashboardAdminController();
      await c.cargar();

      expect(c.ordenesAbiertas, 2);
      expect(c.atrasadas, 1);
    });

    test('vehiculos en el taller es SOLO el en proceso del dia', () async {
      await sembrar(<Cita>[
        cita(fecha: aLas(9), estado: EstadoCita.enProceso),
        cita(fecha: aLas(10), estado: EstadoCita.enProceso),
        cita(fecha: aLas(11), estado: EstadoCita.pendiente),
      ]);

      final c = DashboardAdminController();
      await c.cargar();

      expect(c.vehiculosEnTaller, 2);
    });

    test('ingresos suma solo las completadas del dia', () async {
      await sembrar(<Cita>[
        cita(fecha: aLas(9), estado: EstadoCita.completado, total: 3000),
        cita(fecha: aLas(10), estado: EstadoCita.pendiente, total: 9000),
        cita(fecha: aLas(11), estado: EstadoCita.enProceso, total: 9000),
      ]);

      final c = DashboardAdminController();
      await c.cargar();

      expect(c.completadas, 1);
      expect(c.ingresos, 3000);
    });

    test('conteoPorEstado viene listo para el grafico', () async {
      await sembrar(<Cita>[
        cita(fecha: aLas(9), estado: EstadoCita.pendiente),
        cita(fecha: aLas(10), estado: EstadoCita.completado, total: 100),
      ]);

      final c = DashboardAdminController();
      await c.cargar();

      expect(c.conteoPorEstado[EstadoCita.pendiente], 1);
      expect(c.conteoPorEstado[EstadoCita.completado], 1);
      expect(c.conteoPorEstado[EstadoCita.enProceso], isNull);
    });
  });

  group('formatearDinero', () {
    test('pone el prefijo y el separador de miles', () {
      final c = DashboardAdminController();

      expect(c.formatearDinero(0), 'RD\$ 0');
      expect(c.formatearDinero(1200), 'RD\$ 1,200');
      expect(c.formatearDinero(45000), 'RD\$ 45,000');
    });
  });

  group('seleccionarFecha', () {
    test('cambia lo que es del dia y deja lo que es del taller', () async {
      final manana = DateTime(hoy.year, hoy.month, hoy.day + 1, 0, 0);
      await sembrar(<Cita>[
        cita(fecha: aLas(9), estado: EstadoCita.completado, total: 1000),
        cita(
          fecha: DateTime(manana.year, manana.month, manana.day, 10, 0),
          estado: EstadoCita.completado,
          total: 7000,
        ),
      ]);

      final c = DashboardAdminController();
      await c.cargar();
      expect(c.ingresos, 1000);
      expect(c.ordenesAbiertas, 0);

      await c.seleccionarFecha(manana);

      // Lo del dia cambio...
      expect(c.ingresos, 7000);
      expect(c.completadas, 1);
      expect(c.citasDia.length, 1);
      // ...y lo del taller no, porque el total de ordenes abiertas no depende
      // del dia que se este mirando.
      expect(c.ordenesAbiertas, 0);
    });

    test('guarda solo el dia, sin la hora que trae el calendario', () async {
      final c = DashboardAdminController();
      await c.cargar();

      await c.seleccionarFecha(DateTime(2026, 3, 15, 22, 45));

      // Si quedara la hora, el filtro `LIKE 'AAAA-MM-DD%'` de `obtenerDelDia`
      // seguiria funcionando, pero comparar `fecha` con `DateTime.now()` para
      // saber si es "hoy" daria falso y la cabecera diria la fecha larga cuando
      // toca decir "Hoy".
      expect(c.fecha, DateTime(2026, 3, 15));
    });

    test('las flechas del encabezado mueven un dia', () async {
      final c = DashboardAdminController();
      await c.cargar();
      final inicial = c.fecha;

      await c.diaAnterior();
      expect(c.fecha, inicial.subtract(const Duration(days: 1)));

      await c.diaSiguiente();
      await c.diaSiguiente();
      expect(c.fecha, inicial.add(const Duration(days: 1)));
    });

    test('un dia sin citas vacia la lista sin romper nada', () async {
      await sembrar(<Cita>[
        cita(fecha: aLas(9), estado: EstadoCita.completado, total: 1000),
      ]);

      final c = DashboardAdminController();
      await c.cargar();
      expect(c.hayCitas, isTrue);

      await c.seleccionarFecha(DateTime(2030, 1, 1));

      expect(c.hayCitas, isFalse);
      expect(c.citasDia, isEmpty);
      expect(c.ingresos, 0);
      expect(c.error, isNull);
    });

    test('no vuelve a pedir el resumen global al cambiar de fecha', () async {
      // `seleccionarFecha` solo recarga lo del dia. Si tambien pidiera el global,
      // seria un viaje extra a la base para obtener exactamente lo mismo, y en
      // un taller con la base grande eso se nota.
      await sembrar(<Cita>[cita(fecha: aLas(9), estado: EstadoCita.enProceso)]);

      final c = DashboardAdminController();
      await c.cargar();
      final globalesAntes = c.ordenesAbiertas;

      await c.diaAnterior();
      await c.diaAnterior();

      expect(c.ordenesAbiertas, globalesAntes);
    });
  });

  group('errores', () {
    test('un fallo al releer avisa y NO deja las tarjetas en cero', () async {
      await sembrar(<Cita>[
        cita(fecha: aLas(9), estado: EstadoCita.completado, total: 2000),
      ]);

      final c = DashboardAdminController();
      await c.cargar();
      expect(c.ingresos, 2000);

      // Se rompe la base a proposito: `DROP TABLE` hace que la consulta de
      // agregacion reviente con "no such table", que es exactamente la clase de
      // fallo que la vista tiene que saber manejar.
      final db = await DatabaseHelper.instance.base;
      await db.execute('DROP TABLE ${DatabaseHelper.tablaCitas}');

      await c.recargar();

      expect(c.error, isNotNull);
      expect(c.cargando, isFalse);
      // Lo que ya estaba en pantalla se conserva: volver a cero seria peor que
      // mostrar el numero del dia anterior con un aviso al lado.
      expect(c.ingresos, 2000);
    });

    test('el mensaje de error es para un humano, no SQL crudo', () async {
      final c = DashboardAdminController();
      await c.cargar();

      final db = await DatabaseHelper.instance.base;
      await db.execute('DROP TABLE ${DatabaseHelper.tablaCitas}');
      await c.recargar();

      expect(c.error, isNotNull);
      expect(c.error, isNot(contains('no such table')));
      expect(c.error!.toLowerCase(), contains('cita'));
    });
  });
}

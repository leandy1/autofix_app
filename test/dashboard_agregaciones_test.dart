import 'package:path/path.dart' as p;
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pruebas de las agregaciones que alimentan el Dashboard.
///
/// Mismo criterio que `cita_repository_test.dart`: base SQLite real via FFI, sin
/// mocks. Un `SUM` mal escrito compila igual que uno bien y por eso hay que
/// ejecutarlo de verdad contra filas reales.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Base propia: este archivo corre en paralelo con los demas que usan SQLite.
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_dashboard_agreg_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    await DatabaseHelper.resetParaPruebas();
  });

  final repo = CitaRepository.instance;

  /// Instante fijo para todas las pruebas de este archivo.
  ///
  /// Fijarlo es lo que hace posibles las aserciones sobre "atrasada": con
  /// `DateTime.now()` en el medio, una cita de "hoy a las 10:00" cambia de
  /// grupo depending de si el test corre a las 9:55 o a las 10:05, y el fallo
  /// aparece una vez cada mil, que es la peor forma de tener un test rojo.
  final ahora = DateTime(2026, 10, 2, 15, 0);
  final hoy = DateTime(2026, 10, 2);
  final ayer = DateTime(2026, 10, 1);
  final manana = DateTime(2026, 10, 3);

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

  group('resumir: conteo por estado', () {
    test('la tabla vacia da ceros, NO una excepcion', () async {
      // El `GROUP BY` sobre una tabla sin filas no devuelve ni una fila de
      // ceros: devuelve cero filas. Leer el agregado como si siempre hubiera un
      // primer grupo revienta con un RangeError en el Dashboard recien instalado.
      final r = await repo.resumir(ahora: ahora);

      expect(r.totalCitas, 0);
      expect(r.ingresos, 0);
      expect(r.atrasadas, 0);
      expect(r.porEstado, isEmpty);
      expect(r.contar(EstadoCita.pendiente), 0);
      expect(r.contar(EstadoCita.completado), 0);
    });

    test('cuenta cada estado por separado y el total cuadra', () async {
      await sembrar(<Cita>[
        cita(fecha: ayer, estado: EstadoCita.pendiente),
        cita(fecha: ayer, estado: EstadoCita.pendiente),
        cita(fecha: hoy, estado: EstadoCita.enProceso),
        cita(fecha: hoy, estado: EstadoCita.esperandoPieza),
        cita(fecha: hoy, estado: EstadoCita.completado, total: 1000),
      ]);

      final r = await repo.resumir(ahora: ahora);

      expect(r.contar(EstadoCita.pendiente), 2);
      expect(r.contar(EstadoCita.enProceso), 1);
      expect(r.contar(EstadoCita.esperandoPieza), 1);
      expect(r.completadas, 1);
      expect(r.totalCitas, 5);
    });

    test('los estados que no aparecen NO se inventan en el mapa', () async {
      await sembrar(<Cita>[cita(fecha: hoy, estado: EstadoCita.pendiente)]);

      final r = await repo.resumir(ahora: ahora);

      // `contar` es la unica forma segura de leer el mapa: si se indexa
      // directamente, un estado ausente da `null` donde se esperaba `int`.
      expect(r.contar(EstadoCita.completado), 0);
      expect(r.completadas, 0);
    });
  });

  group('resumir: ingresos', () {
    test('solo suman las citas completadas', () async {
      // Los tres primeros casos son los que importan: `total` se escribe al
      // agendar (es el precio cotizado), asi que una cita PENDIENTE con total
      // cargado es el caso normal, no una rareza. Sumar sin filtrar contaria
      // plata que el taller todavia no cobro.
      await sembrar(<Cita>[
        cita(fecha: hoy, estado: EstadoCita.completado, total: 2500),
        cita(fecha: hoy, estado: EstadoCita.completado, total: 1500),
        cita(fecha: hoy, estado: EstadoCita.pendiente, total: 9999),
        cita(fecha: hoy, estado: EstadoCita.enProceso, total: 9999),
        cita(fecha: hoy, estado: EstadoCita.esperandoPieza, total: 9999),
      ]);

      final r = await repo.resumir(ahora: ahora);

      expect(r.ingresos, 4000);
    });

    test('una cita completada con total 0 no rompe la suma', () async {
      await sembrar(<Cita>[
        cita(fecha: hoy, estado: EstadoCita.completado, total: 0),
        cita(fecha: hoy, estado: EstadoCita.completado, total: 3000),
      ]);

      final r = await repo.resumir(ahora: ahora);

      expect(r.ingresos, 3000);
      expect(r.completadas, 2);
    });
  });

  group('resumir: atrasadas', () {
    test('el SQL cuenta EXACTAMENTE lo que cuenta Cita.esAtrasada', () async {
      // Este es el test que ata el SQL al dominio. `atrasadas` se calcula en
      // SQL (comparando strings ISO) y `Cita.esAtrasada` en Dart (comparando
      // DateTime). Son dos implementaciones de la MISMA regla, y si divergen la
      // tarjeta y la lista de Citas muestran numeros distintos. El lote incluye
      // los cuatro casos limite a proposito.
      final lote = <Cita>[
        // Atrasada: yesterday, no completada.
        cita(fecha: ayer, estado: EstadoCita.pendiente),
        cita(fecha: ayer, estado: EstadoCita.esperandoPieza),
        cita(fecha: ayer, estado: EstadoCita.enProceso),
        // NO atrasada: ayer pero completada. La fecha paso, el trabajo no quedo
        // pendiente, asi que no va en la tarjeta de atrasadas.
        cita(fecha: ayer, estado: EstadoCita.completado, total: 500),
        // NO atrasada: hoy mas tarde que `ahora`.
        cita(fecha: manana, estado: EstadoCita.pendiente),
        cita(fecha: DateTime(2026, 10, 2, 18, 0), estado: EstadoCita.pendiente),
        // Caso limite: exactamente la hora de `ahora`. `isBefore` es estricto,
        // asi que esta NO cuenta. Si el SQL usara `<=` esto daria 1 y el
        // test lo atrapa.
        cita(fecha: ahora, estado: EstadoCita.pendiente),
      ];
      await sembrar(lote);

      final r = await repo.resumir(ahora: ahora);
      final esperadoEnDart = lote.where((c) => c.esAtrasada(ahora)).length;

      expect(
        esperadoEnDart,
        3,
        reason: 'el lote debe tener 3 atrasadas de verdad',
      );
      expect(r.atrasadas, esperadoEnDart);
    });

    test('una completada de ayer NO se cuenta como atrasada', () async {
      await sembrar(<Cita>[
        cita(fecha: ayer, estado: EstadoCita.completado, total: 800),
      ]);

      final r = await repo.resumir(ahora: ahora);

      expect(r.atrasadas, 0);
      expect(r.ingresos, 800);
    });
  });

  group('resumir: filtro por fecha', () {
    test('con fecha, el resumen se limita a ese dia', () async {
      await sembrar(<Cita>[
        cita(fecha: ayer, estado: EstadoCita.completado, total: 1000),
        cita(fecha: hoy, estado: EstadoCita.completado, total: 2000),
        cita(fecha: manana, estado: EstadoCita.completado, total: 4000),
      ]);

      final r = await repo.resumir(fecha: hoy, ahora: ahora);

      expect(r.totalCitas, 1);
      expect(r.ingresos, 2000);
    });

    test('sin fecha, el resumen es de todo el historial', () async {
      await sembrar(<Cita>[
        cita(fecha: ayer, estado: EstadoCita.completado, total: 1000),
        cita(fecha: hoy, estado: EstadoCita.completado, total: 2000),
        cita(fecha: manana, estado: EstadoCita.completado, total: 4000),
      ]);

      final r = await repo.resumir(ahora: ahora);

      expect(r.totalCitas, 3);
      expect(r.ingresos, 7000);
    });

    test('un dia sin citas da ceros y no null', () async {
      await sembrar(<Cita>[
        cita(fecha: hoy, estado: EstadoCita.completado, total: 2000),
      ]);

      final r = await repo.resumir(fecha: DateTime(2030, 1, 1), ahora: ahora);

      expect(r.totalCitas, 0);
      expect(r.ingresos, 0);
      expect(r.atrasadas, 0);
    });
  });

  group('sumarIngresosCompletadas', () {
    test('sin rango, es el total historico', () async {
      await sembrar(<Cita>[
        cita(fecha: ayer, estado: EstadoCita.completado, total: 1000),
        cita(fecha: hoy, estado: EstadoCita.completado, total: 2000),
      ]);

      expect(await repo.sumarIngresosCompletadas(), 3000);
    });

    test('con rango, solo cuenta lo que cae dentro', () async {
      await sembrar(<Cita>[
        cita(fecha: ayer, estado: EstadoCita.completado, total: 1000),
        cita(fecha: hoy, estado: EstadoCita.completado, total: 2000),
        cita(fecha: manana, estado: EstadoCita.completado, total: 4000),
      ]);

      final total = await repo.sumarIngresosCompletadas(
        desde: hoy,
        hasta: manana,
      );

      expect(total, 6000);
    });

    test('nada completado en el rango da 0 y no revienta con NULL', () async {
      // `SUM(...)` sobre cero filas devuelve NULL en SQLite, no 0. Sin el `?? 0`
      // esto revienta con un CastError en el `as int?`.
      await sembrar(<Cita>[
        cita(fecha: hoy, estado: EstadoCita.pendiente, total: 5000),
      ]);

      expect(await repo.sumarIngresosCompletadas(), 0);
    });

    test('tabla vacia da 0', () async {
      expect(await repo.sumarIngresosCompletadas(), 0);
    });
  });

  group('indice de fecha_cita (v6)', () {
    Future<String> rutaDeLaBase() async =>
        p.join(await getDatabasesPath(), 'autofix_dashboard_agreg_test.db');

    Future<List<String>> indicesDeCitas(Database db) async {
      final filas = await db.rawQuery(
        'PRAGMA index_list(${DatabaseHelper.tablaCitas})',
      );
      return filas.map((f) => f['name'] as String).toList();
    }

    test('una base nueva nace con el indice de fecha', () async {
      // El camino de instalacion limpia. Sin esta asercion, un `CREATE INDEX`
      // solo en la migracion deja a todos los talleres NUEVOS escaneando la tabla
      // entera, y como los testes de migracion si pasan, nadie se entera.
      final db = await DatabaseHelper.instance.base;

      expect(await indicesDeCitas(db), contains(DatabaseHelper.idxCitasFecha));
    });

    test('el indice cubre la columna por la que se filtra', () async {
      // Que exista un indice NO basta: si se creo sobre la columna equivocada,
      // `index_list` lo encuentra igual y SQLite sigue escaneando. `index_info`
      // es lo que ata el indice con `fecha_cita`.
      final db = await DatabaseHelper.instance.base;

      final columnas = await db.rawQuery(
        'PRAGMA index_info(${DatabaseHelper.idxCitasFecha})',
      );

      expect(columnas.map((c) => c['name']), <String>[
        DatabaseHelper.colFechaCita,
      ]);
    });

    test('el plan de la consulta del dia usa el indice', () async {
      // El test que de verdad importa. `PRAGMA index_list` demuestra que el indice
      // EXISTE; este demuestra que SQLite lo USA.
      //
      // Y este es el test que hace falta justamente porque la version anterior de
      // estas consultas usaba `LIKE '2026-10-02%'`: con el indice puesto y todo,
      // el plan decia `SCAN citas`. La optimizacion de `LIKE` con prefijo de
      // SQLite solo aplica a columnas indexadas con `COLLATE NOCASE`, y
      // `fecha_cita` es TEXT con BINARY. El indice estaba puesto y no servia
      // para nada, y ningun test lo habria detectado salvo este.
      final db = await DatabaseHelper.instance.base;
      await sembrar(<Cita>[cita(fecha: hoy), cita(fecha: manana)]);

      final plan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM ${DatabaseHelper.tablaCitas} '
        'WHERE ${DatabaseHelper.colFechaCita} >= ? '
        'AND ${DatabaseHelper.colFechaCita} < ?',
        ['2026-10-02T00:00:00.000', '2026-10-03T00:00:00.000'],
      );

      final detalle = plan.map((f) => f['detail']).join(' | ');
      expect(
        detalle,
        contains(DatabaseHelper.idxCitasFecha),
        reason: 'la consulta del dia se sigue escaneando: $detalle',
      );
    });

    test('el filtro por dia sigue trayendo las filas correctas', () async {
      // El indice es la optimizacion; el RANGO es lo que devuelve los datos
      // correctos. Si el cambio de `LIKE` a rango metiera la fila de las 23:59 o
      // dejara fuera la del otro dia, este test es el que lo ve.
      await sembrar(<Cita>[
        cita(fecha: DateTime(2026, 10, 2, 0, 0), cliente: 'Medianoche'),
        cita(fecha: DateTime(2026, 10, 2, 23, 59, 59), cliente: 'Fin Del Dia'),
        cita(fecha: DateTime(2026, 10, 3, 0, 0), cliente: 'Manana'),
        cita(fecha: DateTime(2026, 10, 1, 23, 59, 59), cliente: 'Ayer'),
      ]);

      final delDia = await repo.obtenerDelDia(hoy);

      expect(delDia.map((c) => c.cliente).toList(), <String>[
        'Medianoche',
        'Fin Del Dia',
      ]);

      // Y el resumen por dia cuenta las mismas dos, ni una mas ni una menos.
      final resumen = await repo.resumir(fecha: hoy, ahora: ahora);
      expect(resumen.totalCitas, 2);
    });

    test('un dispositivo en v5 migra a v6 y gana el indice', () async {
      // La v5 es la que reconstruye la tabla (DROP + RENAME) para quitar
      // `codigo_qr`. Si el `CREATE INDEX` del paso 6 se ejecutara antes de ese,
      // el indice moriria con la tabla vieja y `IF NOT EXISTS` no lo detectaria.
      // Este test es el que se da cuenta de un orden invertido.
      await DatabaseHelper.resetParaPruebas();

      final base = await databaseFactory.openDatabase(
        await rutaDeLaBase(),
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE citas (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                cliente TEXT NOT NULL,
                telefono TEXT NOT NULL DEFAULT '',
                vehiculo TEXT NOT NULL,
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
                actualizado_en TEXT NOT NULL DEFAULT '',
                taller_id INTEGER,
                total INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await db.execute(
              'INSERT INTO citas (cliente, vehiculo, fecha_cita, estado, '
              "creado_en, total) VALUES ('Cliente V5', 'Toyota RAV4', "
              "'2026-10-02T09:00:00.000', 'pendiente', "
              "'2026-10-01T09:00:00.000', 4500)",
            );
          },
        ),
      );
      await base.close();

      // Abrir con el helper dispara `onUpgrade`.
      final db = await DatabaseHelper.instance.base;
      expect(await db.getVersion(), greaterThanOrEqualTo(6));

      expect(await indicesDeCitas(db), contains(DatabaseHelper.idxCitasFecha));

      // Y la migracion NO puede perder la cita que ya estaba.
      final citas = await repo.obtenerTodas();
      expect(citas.length, 1);
      expect(citas.first.cliente, 'Cliente V5');
    });

    test('abrir dos veces no vuelve a intentar el indice', () async {
      // `onUpgrade` solo corre cuando la version guardada es menor. Si el paso
      // 6 se ejecutara en cada apertura, un taller que abre la app cien veces
      // pagaria cien `CREATE INDEX`.
      //
      // El cierre va por `cerrar()` y no por `db.close()` directo: `cerrar()`
      // ademas suelta la referencia interna del helper, y si se cierra la
      // conexion a mano el singleton sigue apuntando a una base ya cerrada y la
      // segunda apertura revienta con `database_closed` en vez de probar nada.
      await DatabaseHelper.instance.base;
      await DatabaseHelper.instance.cerrar();

      final otra = await DatabaseHelper.instance.base;
      expect(
        await indicesDeCitas(otra),
        contains(DatabaseHelper.idxCitasFecha),
      );
    });
  });
}

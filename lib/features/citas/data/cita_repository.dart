import 'package:sqflite/sqflite.dart';

import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/citas/models/resumen_citas.dart';

/// Acceso a datos de citas. Implementa el contrato base para que el resto de
/// la app no dependa de SQLite: cambiar a Drift o a una API toca solo esto.
///
/// Las etiquetas de UI ('ATRASADAS', 'Pendiente'...) viven en el modelo y en el
/// controller, no aca. Un repositorio que conoce textos de pantalla deja de
/// ser reutilizable en cuanto el diseño cambia una palabra.
class CitaRepository implements BaseRepository<Cita> {
  CitaRepository._();

  static final CitaRepository instance = CitaRepository._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  @override
  String get tabla => DatabaseHelper.tablaCitas;

  // ------------------------------ CREATE ------------------------------
  @override
  Future<int> crear(Cita cita) async {
    final db = await _helper.base;
    return db.insert(
      tabla,
      cita.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // ------------------------------- READ -------------------------------
  @override
  Future<List<Cita>> obtenerTodas() async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      orderBy: '${DatabaseHelper.colFechaCita} DESC',
    );
    return filas.map(Cita.fromMap).toList();
  }

  @override
  Future<Cita?> obtenerPorId(int id) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    return filas.isEmpty ? null : Cita.fromMap(filas.first);
  }

  /// Citas de un dia, ordenadas por hora. El filtro va en SQL y no en Dart
  /// para no traer filas de mas.
  Future<List<Cita>> obtenerDelDia(DateTime fecha) async {
    final db = await _helper.base;
    final rango = _rangoDelDia(fecha);
    final filas = await db.query(
      tabla,
      where:
          '${DatabaseHelper.colFechaCita} >= ? AND ${DatabaseHelper.colFechaCita} < ?',
      whereArgs: [rango.desde, rango.hasta],
      orderBy: '${DatabaseHelper.colFechaCita} ASC',
    );
    return filas.map(Cita.fromMap).toList();
  }

  /// Citas de un taller especifico, de la mas reciente a la mas vieja.
  ///
  /// El filtro va en SQL (`taller_id = ?`) y no en Dart porque es la consulta
  /// del historial: "mis citas en Global Refriauto". Con Dart habia que traer la
  /// tabla entera y descartar, y con la base creciendo eso se nota.
  Future<List<Cita>> obtenerPorTaller(int tallerId) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colTallerId} = ?',
      whereArgs: [tallerId],
      orderBy: '${DatabaseHelper.colFechaCita} DESC',
    );
    return filas.map(Cita.fromMap).toList();
  }

  // ---------------------------- AGREGACIONES ---------------------------
  //
  // Las tres metricas del Dashboard salen de UNA sola consulta, no de tres.
  // Cada una por su cuenta seria correcta y mas lenta: el `GROUP BY estado` ya
  // trae el conteo, y de paso puede arrastrar la suma de `total` de las
  // completadas y el conteo de atrasadas en dos `SUM(CASE ...)`. Con ~100 filas
  // la diferencia es nada; con las miles que acumula un taller en un año,
  // son tres recorridos de la tabla reducidos a uno.

  /// Conteo por estado, ingresos cobrados y atrasadas, en una sola pasada.
  ///
  /// Sin argumentos resume TODO el historial: es lo que necesitan las tarjetas de
  /// "vehiculos en el taller" y "ordenes abiertas", que son del taller, no del
  /// dia. Con [fecha] el resumen se limita a ese dia, que es lo que necesitan
  /// "completadas" e "ingresos del dia".
  ///
  /// [ahora] va por parametro, con la misma razon que en `Cita.esAtrasada`: leer
  /// el reloj adentro hace que dos dispositivos clasifiquen la misma cita
  /// distinto. El que arma la pasada lo fija una sola vez.
  Future<ResumenCitas> resumir({DateTime? fecha, DateTime? ahora}) async {
    final momento = ahora ?? DateTime.now();
    final db = await _helper.base;

    // El orden de los argumentos importa y NO es el de lectura del SQL:
    // 1) `estado = ?`       -> que estado cuenta como ingreso
    // 2) `estado <> ?`      -> la misma referencia, para excluir de atrasadas
    // 3) `fecha_cita < ?`   -> el instante que define "ya paso"
    // 4) `fecha_cita >= ?`  -> el rango del dia, si se pidio uno
    // 5) `fecha_cita < ?`   -> el mismo rango, por el otro extremo
    //
    // 'completado' viaja como argumento y no pegado en el SQL, para que el dia
    // que se anada un estado no haya que cazarlo en un string.
    final argumentos = <Object?>[
      EstadoCita.completado.name,
      EstadoCita.completado.name,
      momento.toIso8601String(),
    ];

    // Rango `[desde, hasta)` y NO `LIKE 'AAAA-MM-DD%'`, que es lo que se usaba
    // antes. Los dos filtran las mismas filas, pero solo el rango usa el indice:
    // la optimizacion de `LIKE` con prefijo de SQLite exige que la columna este
    // indexada con `COLLATE NOCASE`, y `fecha_cita` es TEXT con BINARY. Con
    // BINARY, `LIKE '2026-10-02%'` es un escaneo de la tabla completa aunque el
    // indice exista, y `EXPLAIN QUERY PLAN` lo reporta como `SCAN citas`.
    final filtro = fecha == null
        ? ''
        : 'WHERE ${DatabaseHelper.colFechaCita} >= ? '
            'AND ${DatabaseHelper.colFechaCita} < ?';
    if (fecha != null) argumentos.addAll(_rangoDelDia(fecha).argumentos);

    final filas = await db.rawQuery(
      '''
      SELECT
        ${DatabaseHelper.colEstado} AS estado,
        COUNT(*) AS conteo,
        SUM(CASE WHEN ${DatabaseHelper.colEstado} = ?
                 THEN ${DatabaseHelper.colTotal} ELSE 0 END) AS ingresos,
        SUM(CASE WHEN ${DatabaseHelper.colEstado} <> ?
                  AND ${DatabaseHelper.colFechaCita} < ?
                 THEN 1 ELSE 0 END) AS atrasadas
      FROM $tabla
      $filtro
      GROUP BY ${DatabaseHelper.colEstado}
      ''',
      argumentos,
    );

    // Con la tabla vacia el `GROUP BY` no devuelve NINGUNA fila, ni una de ceros.
    // Por eso esto arranca de cero y no de `filas.first`: ese era el bug
    // clasico de leer un agregado como si siempre hubiera al menos un grupo.
    final porEstado = <EstadoCita, int>{};
    var ingresos = 0;
    var atrasadas = 0;

    for (final fila in filas) {
      final estado = EstadoCita.desdeNombre(fila['estado'] as String);
      porEstado[estado] = (fila['conteo'] as num).toInt();
      ingresos += (fila['ingresos'] as num?)?.toInt() ?? 0;
      atrasadas += (fila['atrasadas'] as num?)?.toInt() ?? 0;
    }

    return ResumenCitas(
      porEstado: porEstado,
      ingresos: ingresos,
      atrasadas: atrasadas,
    );
  }

  /// Ingresos cobrados de las citas completadas dentro de un rango.
  ///
  /// [resumir] ya resuelve esto cuando se pide el resumen de un dia, asi que
  /// este metodo existe para el caso puntual de "cuanto facturamos entre el lunes
  /// y el viernes". Sin rango, es el total historico.
  Future<int> sumarIngresosCompletadas({
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final db = await _helper.base;

    final condiciones = <String>[
      '${DatabaseHelper.colEstado} = ?',
    ];
    final argumentos = <Object?>[EstadoCita.completado.name];

    if (desde != null) {
      condiciones.add('${DatabaseHelper.colFechaCita} >= ?');
      argumentos.add(desde.toIso8601String());
    }
    if (hasta != null) {
      // `>=` y no `>` a proposito: [hasta] se entiende como el instante
      // exacto. Si el que lo llama quiere el dia entero, que mande el final de
      // ese dia. Lo contrario, "hasta las 00:00 del lunes" excluye todas las
      // citas del lunes, y eso siempre sorprende.
      condiciones.add('${DatabaseHelper.colFechaCita} <= ?');
      argumentos.add(hasta.toIso8601String());
    }

    final filas = await db.rawQuery(
      'SELECT SUM(${DatabaseHelper.colTotal}) AS ingresos '
      'FROM $tabla WHERE ${condiciones.join(' AND ')}',
      argumentos,
    );

    // `SUM` sobre cero filas devuelve NULL, y no 0. `as int?` reventaria con
    // un null, y `?? 0` es la respuesta correcta: no se facturo nada.
    return (filas.first['ingresos'] as num?)?.toInt() ?? 0;
  }

  // ------------------------------ UPDATE ------------------------------
  @override
  Future<int> actualizar(Cita cita) async {
    final id = cita.id;
    if (id == null) {
      throw ArgumentError('No se puede actualizar una cita sin id.');
    }
    final db = await _helper.base;
    return db.update(
      tabla,
      cita.toMap(),
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Update parcial: manda solo la columna del estado, para cambiarlo desde la
  /// lista sin abrir el formulario y sin pisar el resto de la fila.
  Future<int> cambiarEstado(int id, EstadoCita estado) async {
    final db = await _helper.base;
    return db.update(
      tabla,
      {
        DatabaseHelper.colEstado: estado.name,
        DatabaseHelper.colActualizadoEn: DateTime.now().toIso8601String(),
      },
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
    );
  }

  // ------------------------------ DELETE ------------------------------
  @override
  Future<int> eliminar(int id) async {
    final db = await _helper.base;
    return db.delete(
      tabla,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
    );
  }



  /// 'AAAA-MM-DD'. Se sigue usando para armar los limites del rango del dia.
  static String _claveDia(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';

  /// Los dos limites ISO del dia, como `[desde, hasta)`: desde la medianoche del
  /// dia hasta la medianoche del dia siguiente, sin incluirla.
  ///
  /// Sin hora propia, no `DateTime(fecha.year, ..., 23, 59, 59)`: los timestamps
  /// ISO ordenan bien por prefijo, asi que comparar strings contra estos dos
  /// limites es equivalente a comparar instantes, y no hay que preguntarse si
  /// el reloj del dispositivo esta en horario de verano o no.
  ///
  /// El limite superior es EXCLUSIVO a proposito. Con un `23:59:59.999` incluido
  /// se pierde la cita que caiga en el ultimo microsegundo del dia, porque
  /// `toIso8601String()` escribe seis decimales cuando hay microsegundos
  /// (`23:59:59.999999`), y esa fila queda fuera del `BETWEEN` sin que se note.
  static ({String desde, String hasta, List<Object?> argumentos}) _rangoDelDia(
    DateTime fecha,
  ) {
    final siguiente = DateTime(fecha.year, fecha.month, fecha.day + 1);
    final desde = '${_claveDia(fecha)}T00:00:00.000';
    final hasta = '${_claveDia(siguiente)}T00:00:00.000';
    return (desde: desde, hasta: hasta, argumentos: <Object?>[desde, hasta]);
  }
}

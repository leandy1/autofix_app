import 'package:sqflite/sqflite.dart';

import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/utils/borrado_logico.dart';
import 'package:autofix/core/utils/reloj.dart';
import 'package:autofix/core/utils/uuid.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/citas/models/resumen_citas.dart';

/// Acceso a datos de citas. Implementa el contrato base para que el resto de
/// la app no dependa de SQLite: cambiar a Drift o a una API toca solo esto.
///
/// Las etiquetas de UI ('ATRASADAS', 'Pendiente'...) viven en el modelo y en el
/// controller, no aca. Un repositorio que conoce textos de pantalla deja de
/// ser reutilizable en cuanto el diseño cambia una palabra.
///
/// -----------------------------------------------------------------
/// TRES REGLAS QUE ESTE REPOSITORIO APLICA Y QUE NO SON OPCIONALES (v7)
/// -----------------------------------------------------------------
///
/// 1. **IDIGEN EL REPOSITORIO.** [crear] recibe una cita sin id, le pone un
///    UUID y devuelve el `String` que quedo. Los call sites de la v6 ninguno
///    usaba el `int` que devolvia `db.insert`, asi que hoy no cambian de
///    signature; lo que cambia es que el id ya no es inventado por SQLite.
///
/// 2. **NINGUNA CONSULTA DE UI TRAE CITAS BORRADAS.** Todas las lecturas de este
///    archivo filtran `eliminado_en IS NULL`. No hay una excepcion, ni siquiera
///    para "el dashboard tiene que contarlas": una cita borrada se borro.
///
///    El filtro va en SQL y no en Dart por la misma razon que en el resto del
///    repositorio: si se filtrara despues de traer las filas, habria una ventana
///    en la que la cita borrada ya esta en memoria, y el `GROUP BY` del resumen
///    habria contado ingresos de una orden que el administrador acaba de anular.
///
/// 3. **`eliminar` ES UN BORRADO LOGICO.** Marca `eliminado_en` y `eliminado_por`.
///    No borra la fila. Ver `lib/core/utils/borrado_logico.dart`.
class CitaRepository implements BaseRepository<Cita> {
  CitaRepository._();

  static final CitaRepository instance = CitaRepository._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  @override
  String get tabla => DatabaseHelper.tablaCitas;

  // ------------------------------ CREATE ------------------------------

  /// Guarda la cita y devuelve el id con el que quedo.
  ///
  /// Si la cita ya trae id (una edicion, o un documento que baja de Firestore)
  /// se respeta el suyo. Si no, se le asigna un UUID aca, en el repositorio y no
  /// en el controller, por la razon del doc de `BaseRepository.crear`: que haya
  /// un solo lugar que sabe que hay que pedir un id.
  @override
  Future<String> crear(Cita cita) async {
    // -----------------------------------------------------------------
    // POR QUE `creadoEn` SE SELLACA, Y NO SE DEJA QUE LO PONGA `toMap()`
    // -----------------------------------------------------------------
    //
    // `Cita.toMap()` omite `creado_en` cuando la cita ya trae id, para que un
    // UPDATE no reescriba la fecha de alta. Ese heuristico funciona SOLO si
    // "tiene id" significa "ya esta en la base".
    //
    // Y aca no: este metodo le pone el id a una cita NUEVA. Con el orden
    // inverso (primero `copyWith(id:)`, despues `toMap()`), el mapa sale con
    // `id` pero sin `creado_en`, y el INSERT revienta con
    // `NOT NULL constraint failed: citas.creado_en`.
    //
    // El error no se ve en el modelo ni en el repositorio por separado: cada uno
    // esta bien segun su propio contrato. Solo aparece al juntarlos. Por eso el
    // sello va ACA, que es la capa que sabe si la operacion es un alta o una
    // edicion, y no en el modelo, que no lo sabe.
    //
    // `creadoEn` solo se rellena si venia en null: una cita que YA trae la fecha
    // (una edicion, o un documento que baja de la nube) la conserva.
    final ahora = Reloj.instancia.ahora();
    final conId = cita.copyWith(
      id: cita.id ?? Uuid.instancia.generar(),
      creadoEn: cita.creadoEn ?? ahora,
    );

    final db = await _helper.base;
    await db.insert(
      tabla,
      conId.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return conId.id!;
  }

  /// Guarda una cita que YA trae id (la que baja de Firestore).
  ///
  /// Es [crear] con el id respetado, expuesto aparte porque la sincronizacion lo
  /// necesita y la diferencia es la que evita una condicion de carrera: si el
  /// snapshot trae una cita que este dispositivo ya tiene, [crear] reventaria con
  /// `UNIQUE constraint failed` y el `onSnapshot` no podria ni registrar el
  /// error. Ver `SyncService`.
  Future<void> insertarConId(Cita cita) async {
    // Mismo caso que [crear]: la cita que baja de la nube trae id y puede no traer
    // `creadoEn` (Firestore lo guarda como `Timestamp`, y si el documento se
    // escribio sin ese campo llega null). Sin el sello de abajo el
    // `INSERT OR REPLACE` falla con `NOT NULL constraint failed: citas.creado_en`.
    final conFecha = cita.creadoEn == null
        ? cita.copyWith(creadoEn: cita.actualizadoEn ?? Reloj.instancia.ahora())
        : cita;

    final db = await _helper.base;
    await db.insert(
      tabla,
      conFecha.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ------------------------------- READ -------------------------------

  /// Citas vigentes, de la mas reciente a la mas vieja.
  ///
  /// El filtro de borrado va SIEMPRE, sin excepcion. Ver la regla 2 del doc.
  @override
  Future<List<Cita>> obtenerTodas() async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      // El filtro de borrado va primero y con `IS NULL` explicito. `IS NULL` y no
      // `= NULL` porque en SQL `= NULL` nunca es verdadero (es el operador de
      // tres valores), asi que una cita borrada SE ESCAPARIA del filtro y
      // reapareceria en la lista. Es el error clasico de este filtro.
      where: '${DatabaseHelper.colEliminadoEn} IS NULL',
      orderBy: '${DatabaseHelper.colFechaCita} DESC',
    );
    return filas.map(Cita.fromMap).toList();
  }

  /// Una cita por id, INCLUYENDO las borradas.
  ///
  /// Excepcion deliberada a la regla 2, y es la UNICA: la pantalla de "Restaurar"
  /// tiene que poder leer una cita borrada por id, y la sincronizacion tiene que
  /// poder comparar su `trazabilidad` con la local. Para todo lo demas (el
  /// Dashboard, las listas, el formulario) existe [obtenerVigentePorId].
  @override
  Future<Cita?> obtenerPorId(String id) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return filas.isEmpty ? null : Cita.fromMap(filas.first);
  }

  /// Una cita por id, solo si esta vigente.
  ///
  /// Es la version que la UI debe usar. Existe como metodo aparte y no como un
  /// filtro dentro de [obtenerPorId] porque devolver `null` por "esta borrada" y
  /// devolver `null` por "no existe" es una distincion que el llamador no puede
  /// hacer, y en un formulario de edicion eso se traduce en "no encuentro la cita
  /// que tengo abierta".
  Future<Cita?> obtenerVigentePorId(String id) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where:
          '${DatabaseHelper.colId} = ? AND '
          '${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return filas.isEmpty ? null : Cita.fromMap(filas.first);
  }

  /// Citas de un dia, ordenadas por hora. El filtro va en SQL y no en Dart
  /// para no traer filas de mas.
  ///
  /// Sin filas de otros dias: los limites son ISO en UTC y el rango es
  /// `[desde, hasta)`. Ver [_rangoDelDia].
  Future<List<Cita>> obtenerDelDia(DateTime fecha, {String? tallerId}) async {
    final db = await _helper.base;
    final rango = _rangoDelDia(fecha);
    final condiciones = <String>[
      '${DatabaseHelper.colFechaCita} >= ?',
      '${DatabaseHelper.colFechaCita} < ?',
      '${DatabaseHelper.colEliminadoEn} IS NULL',
    ];
    final argumentos = <Object?>[rango.desde, rango.hasta];

    if (tallerId != null) {
      condiciones.add('${DatabaseHelper.colTallerId} = ?');
      argumentos.add(tallerId);
    }

    final filas = await db.query(
      tabla,
      where: condiciones.join(' AND '),
      whereArgs: argumentos,
      orderBy: '${DatabaseHelper.colFechaCita} ASC',
    );
    return filas.map(Cita.fromMap).toList();
  }

  /// Citas de un taller especifico, de la mas reciente a la mas vieja.
  ///
  /// El filtro va en SQL (`taller_id = ?`) y no en Dart porque es la consulta
  /// del historial: "mis citas en Global Refriauto". Con Dart habia que traer
  /// la tabla entera y descartar, y con la base creciendo eso se nota.
  Future<List<Cita>> obtenerPorTaller(String tallerId) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where:
          '${DatabaseHelper.colTallerId} = ? '
          'AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[tallerId],
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
  /// "completadas" e "ingresos del dia". Con [tallerId] filtra exclusivamente
  /// por el taller especificado.
  ///
  /// [ahora] va por parametro, con la misma razon que en `Cita.esAtrasada`: leer
  /// el reloj adentro hace que dos dispositivos clasifiquen la misma cita
  /// distinto. El que arma la pasada lo fija una sola vez.
  Future<ResumenCitas> resumir({
    DateTime? fecha,
    DateTime? ahora,
    String? tallerId,
  }) async {
    final momento = (ahora ?? DateTime.now()).toUtc();
    final db = await _helper.base;

    // El orden de los argumentos importa y NO es el de lectura del SQL:
    // 1) `estado = ?`       -> que estado cuenta como ingreso
    // 2) `estado <> ?`      -> la misma referencia, para excluir de atrasadas
    // 3) `fecha_cita < ?`   -> el instante que define "ya paso"
    // 4) `fecha_cita >= ?`  -> el rango del dia, si se pidio uno
    // 5) `fecha_cita < ?`   -> el mismo rango, por el otro extremo
    // 6) `taller_id = ?`    -> el filtro por taller, si se pidio
    //
    // 'completado' viaja como argumento y no pegado en el SQL, para que el dia
    // que se anada un estado no haya que cazarlo en un string.
    final argumentos = <Object?>[
      EstadoCita.completado.name,
      EstadoCita.completado.name,
      aIsoUtc(momento),
    ];

    // Rango `[desde, hasta)` y NO `LIKE 'AAAA-MM-DD%'`, que es lo que se usaba
    // antes. Los dos filtran las mismas filas, pero solo el rango usa el indice:
    // la optimizacion de `LIKE` con prefijo de SQLite exige que la columna este
    // indexada con `COLLATE NOCASE`, y `fecha_cita` es TEXT con BINARY. Con
    // BINARY, `LIKE '2026-10-02%'` es un escaneo de la tabla completa aunque el
    // indice exista, y `EXPLAIN QUERY PLAN` lo reporta como `SCAN citas`.
    //
    // `eliminado_en IS NULL` es el filtro de la regla 2, y va PRIMERO en la
    // lista de condiciones para que se lea antes el indice `idx_citas_vigentes`
    // (eliminado_en, fecha_cita).
    final condiciones = <String>['${DatabaseHelper.colEliminadoEn} IS NULL'];
    if (fecha != null) {
      condiciones.add('${DatabaseHelper.colFechaCita} >= ?');
      condiciones.add('${DatabaseHelper.colFechaCita} < ?');
      argumentos.addAll(_rangoDelDia(fecha).argumentos);
    }
    if (tallerId != null) {
      condiciones.add('${DatabaseHelper.colTallerId} = ?');
      argumentos.add(tallerId);
    }

    final filas = await db.rawQuery('''
      SELECT
        ${DatabaseHelper.colEstado} AS estado,
        COUNT(*) AS conteo,
        SUM(CASE WHEN ${DatabaseHelper.colEstado} = ?
                 THEN ${DatabaseHelper.colTotal} ELSE 0 END) AS ingresos,
        SUM(CASE WHEN ${DatabaseHelper.colEstado} <> ?
                  AND ${DatabaseHelper.colFechaCita} < ?
                 THEN 1 ELSE 0 END) AS atrasadas
      FROM $tabla
      WHERE ${condiciones.join(' AND ')}
      GROUP BY ${DatabaseHelper.colEstado}
      ''', argumentos);

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
    String? tallerId,
  }) async {
    final db = await _helper.base;

    final condiciones = <String>[
      '${DatabaseHelper.colEstado} = ?',
      '${DatabaseHelper.colEliminadoEn} IS NULL',
    ];
    final argumentos = <Object?>[EstadoCita.completado.name];

    if (desde != null) {
      condiciones.add('${DatabaseHelper.colFechaCita} >= ?');
      argumentos.add(aIsoUtc(desde));
    }
    if (hasta != null) {
      // `>=` y no `>` a proposito: [hasta] se entiende como el instante
      // exacto. Si el que lo llama quiere el dia entero, que mande el final de
      // ese dia. Lo contrario, "hasta las 00:00 del lunes" excluye todas las
      // citas del lunes, y eso siempre sorprende.
      condiciones.add('${DatabaseHelper.colFechaCita} <= ?');
      argumentos.add(aIsoUtc(hasta));
    }
    if (tallerId != null) {
      condiciones.add('${DatabaseHelper.colTallerId} = ?');
      argumentos.add(tallerId);
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
    // Forzamos sync_status = 'pending' para que SyncService detecte la edicion
    // y la suba a Firebase. Si se dejara el valor del modelo, una cita ya
    // sincronizada quedaria como 'synced' y el push la ignoraria.
    final mapa = cita.toMap()..[DatabaseHelper.colSyncStatus] = 'pending';
    return db.update(
      tabla,
      mapa,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Update parcial: manda solo la columna del estado, para cambiarlo desde la
  /// lista sin abrir el formulario y sin pisar el resto de la fila.
  ///
  /// `eliminado_en IS NULL` en el WHERE: cambiar el estado de una cita borrada
  /// tiene que devolver 0 y no reanimarla. Sin ese filtro, una cita borrada hace
  /// de contenedor de edits que nadie ve y que reaparece restaurada a medias.
  ///
  /// El mapa NO lleva las columnas de trazabilidad, y eso es deliberado: en un
  /// `UPDATE` de SQLite una columna ausente NO SE TOCA, mientras que mandarla en
  /// `null` la vaciaria. Un update de estado no debe saber nada del borrado de
  /// otro dispositivo.
  Future<int> cambiarEstado(String id, EstadoCita estado) async {
    final db = await _helper.base;
    return db.update(
      tabla,
      <String, Object?>{
        DatabaseHelper.colEstado: estado.name,
        DatabaseHelper.colActualizadoEn: ahoraIso(),
        // Marcamos 'pending' para que SyncService suba el cambio de estado a Firebase.
        DatabaseHelper.colSyncStatus: 'pending',
      },
      where:
          '${DatabaseHelper.colId} = ? '
          'AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[id],
    );
  }

  /// Reemplaza el codigo visible por el definitivo que confirmo la nube.
  ///
  /// Existe como metodo y no como un `actualizar` de la cita entera por una
  /// razon de concurrencia: este es el unico camino por el que la UI cambia de
  /// 'PENDIENTE' a 'CITA-0004', y llega al mismo tiempo que el resto del
  /// documento por el `onSnapshot`. Si bajara la cita completa y la guardara con
  /// `actualizar`, el `toMap` de [Cita] reescribiria `actualizado_en` con el reloj
  /// de ESTE dispositivo, y la fila recien sincronizada pareceria una edicion
  /// local que el servicio tendria que volver a subir. Es un ping-pong: cada
  /// dispositivo hace subir al otro un documento que no cambio.
  ///
  /// Ademas no puede reescribir `eliminado_en`: una cita que se borro en otro
  /// dispositivo y cuyo numero llega despues no debe perder su borrado.
  Future<int> asignarCodigoVisible(String id, String codigo) async {
    final db = await _helper.base;
    return db.update(
      tabla,
      <String, Object?>{
        DatabaseHelper.colCodigoVisible: codigo,
        DatabaseHelper.colActualizadoEn: ahoraIso(),
      },
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
    );
  }

  // --------------------------- BORRADO LOGICO -------------------------

  /// Marca la cita como borrada. NO borra la fila.
  ///
  /// Devuelve las filas tocadas: 0 significa que el id no existe, que es un
  /// resultado legitimo que el llamador tiene que poder distinguir de "ya estaba
  /// borrada" (que tambien devuelve 0).
  ///
  /// `eliminadaPor` va en la columna a proposito. Es lo que permite que dos
  /// dispositivos que borraron la misma cita a la vez no se pisen, y lo que le
  /// dice al administrador de que tablet se borro la orden. Con la autenticacion
  /// anonima de la v7 llega el uid de Firebase Auth; sin sesion vale `null` y el
  /// borrado igual se registra.
  /// El id que el administrador esta mirando cuando aprieta "borrar".
  ///
  /// Sin sesion iniciada, `eliminadaPor` va en `null`: el borrado se registra
  /// igual, y cuando exista la sesion de Firebase Auth este metodo va a pasar el
  /// uid por [borrar]. Por eso [borrar] es el metodo con el parametro y [eliminar]
  /// es el atajo que cumple el contrato de [BaseRepository].
  @override
  Future<int> eliminar(String id) async {
    return borrar(id, eliminadaPor: null);
  }

  /// Borrado logico con la identidad de quien lo hizo.
  Future<int> borrar(String id, {String? eliminadaPor}) async {
    final db = await _helper.base;
    final ahora = Reloj.instancia.ahora();
    return db.update(
      tabla,
      <String, Object?>{
        DatabaseHelper.colEliminadoEn: aIsoUtc(ahora),
        DatabaseHelper.colEliminadoPor: eliminadaPor,
        DatabaseHelper.colActualizadoEn: aIsoUtc(ahora),
        // Marcamos 'pending' para que SyncService suba el borrado a Firebase.
        DatabaseHelper.colSyncStatus: 'pending',
      },
      where:
          '${DatabaseHelper.colId} = ? '
          'AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[id],
    );
  }

  /// Devuelve una cita borrada a la vida.
  ///
  /// Es el otro lado del tombstone, y es lo que va a usar la Papelera cuando
  /// exista. [restaurado_en] queda con la hora de ahora y `eliminado_en` en NULL:
  /// la fila vuelve a las consultas de la UI sin perder la huella de que estuvo
  /// fuera.
  ///
  /// El `WHERE eliminado_en IS NULL` es la red de seguridad: restaurar una cita
  /// que ya esta viva devuelve 0 en vez de inventarle una fecha de restauracion
  /// que no ocurrio.
  Future<int> restaurar(String id) async {
    final db = await _helper.base;
    final ahora = Reloj.instancia.ahora();
    return db.update(
      tabla,
      <String, Object?>{
        DatabaseHelper.colEliminadoEn: null,
        DatabaseHelper.colEliminadoPor: null,
        DatabaseHelper.colRestauradoEn: aIsoUtc(ahora),
        DatabaseHelper.colActualizadoEn: aIsoUtc(ahora),
      },
      where:
          '${DatabaseHelper.colId} = ? '
          'AND ${DatabaseHelper.colEliminadoEn} IS NOT NULL',
      whereArgs: <Object?>[id],
    );
  }

  /// Las citas borradas: la consulta de la futura Papelera.
  ///
  /// No la usa ninguna pantalla todavia, y por eso lleva el nombre [obtenerBorradas]
  /// y no `obtenerPapelera`: lo que hay hoy es la consulta, no la pantalla.
  ///
  /// Viene ANTES que `obtenerTodas` en el archivo a proposito: asi, un
  /// `obtenerTodas` nuevo se escribe miranto de receso la excepcion.
  Future<List<Cita>> obtenerBorradas({int limite = 200}) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colEliminadoEn} IS NOT NULL',
      orderBy: '${DatabaseHelper.colEliminadoEn} DESC',
      limit: limite,
    );
    return filas.map(Cita.fromMap).toList();
  }

  /// Las citas locales que la nube todavia no ha confirmado o no ha visto.
  ///
  /// Son las que [SyncService] sube. `LIMIT` porque la pregunta es "hay algo
  /// pendiente?", y no "traeme todo el historial": un dispositivo que lleva meses
  /// sin sincronizar puede tener cientos de filas y subir las de golpe traba la
  /// base y agota la cuota. El servicio las sube en tandas y vuelve a preguntar.
  Future<List<Cita>> obtenerPendientes({int limite = 50}) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      orderBy: '${DatabaseHelper.colActualizadoEn} ASC',
      limit: limite,
    );
    return filas.map(Cita.fromMap).toList();
  }

  /// Upsert desde la nube: inserta o actualiza lo que llega del `onSnapshot`.
  ///
  /// El nombre es "upsert" y no "actualizar" porque hace las dos cosas, y el
  /// orden de los casos es lo unico importante:
  ///
  /// 1. Si la fila no existe localmente, se inserta. Es una cita que otro
  ///    dispositivo creo.
  /// 2. Si existe, la decision la toma [resolverConflictoDeBorrado], que es una
  ///    funcion pura y por eso se testea sin base de datos.
  ///
  /// La regla de que el borrado gana sobre una edicion esta dentro de esa
  /// funcion y NO antes de la comparacion de relojes, porque si se compararan los
  /// relojes primero, un documento remoto con `eliminado_en` puesto y una fila
  /// local viva darian "la local es mas nueva, no toques nada" y la cita borrada
  /// reapareceria en este dispositivo. Que la reaparezca es el bug exacto que
  /// motivo el tombstone.
  ///
  /// [GanadorDeConflicto.local] NO escribe nada, y es lo correcto: la nube no
  /// tiene nada que esta fila no sepa, asi que no hay nada que bajar. El
  /// `SyncService` es quien sube la version local cuando el ganador es
  /// [GanadorDeConflicto.localAdelantada].
  Future<void> fusionarDesdeNube(Cita remota) async {
    final idRemoto = remota.id;
    if (idRemoto == null) {
      // Un `Cita` sin id no se puede sincronizar: no hay contra que compararlo ni
      // donde escribirlo. Es un documento mal formado (o un bug del `onSnapshot`)
      // y la unica respuesta sensata es ignorarlo sin tirar la exception, porque
      // un solo documento raro no debe detener el resto del snapshot.
      return;
    }

    final db = await _helper.base;
    final local = await obtenerPorId(idRemoto);

    // Caso 1: la cita no existe en ESTE dispositivo. Se inserta tal cual
    // incluyendo su trazabilidad, para que una cita que llega borrada desde otro
    // dispositivo nazca borrada aca y no sea visible por un instante.
    if (local == null) {
      await insertarConId(remota);
      return;
    }

    final ganador = resolverConflictoDeBorrado(
      local: local.trazabilidad,
      remota: remota.trazabilidad,
    );

    switch (ganador) {
      // La nube no trae nada nuevo. No se escribe.
      case GanadorDeConflicto.local:
        return;

      // La version local es la mas nueva: la nube todavia no sabe. Acá no se
      // sube; eso es del `SyncService`, que ademas tiene que decidir si vale la
      // pena pisar lo que ya esta en la nube.
      case GanadorDeConflicto.localAdelantada:
        return;

      // La nube manda: se baja el documento entero, trazabilidad incluida.
      case GanadorDeConflicto.nube:
        await db.update(
          tabla,
          remota.toMap(),
          where: '${DatabaseHelper.colId} = ?',
          whereArgs: <Object?>[idRemoto],
        );
    }
  }

  /// Citas locales pendientes de subir a Firestore (sync_status = 'pending').
  ///
  /// [SyncService] usa esto para saber que subir. El `LIMIT` evita saturar la
  /// base si un dispositivo lleva meses sin sincronizar.
  ///
  /// Incluye las borradas: el borrado logico (`eliminado_en IS NOT NULL`) tambien
  /// tiene que subirse a Firebase para que la nube refleje la eliminacion.
  Future<List<Cita>> obtenerPendientesDeSync({int limite = 50}) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: "${DatabaseHelper.colSyncStatus} = 'pending'",
      orderBy: '${DatabaseHelper.colActualizadoEn} ASC',
      limit: limite,
    );
    return filas.map(Cita.fromMap).toList();
  }

  /// Marca una cita como sincronizada (sync_status = 'synced').
  ///
  /// Lo llama [SyncService] tras un push exitoso. No toca `actualizado_en`
  /// porque no es una edicion del usuario, solo un cambio de estado interno.
  Future<int> marcarSincronizada(String id) async {
    final db = await _helper.base;
    return db.update(
      tabla,
      <String, Object?>{DatabaseHelper.colSyncStatus: 'synced'},
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
    );
  }

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
  ///
  /// Los limites se emiten en UTC con [aIsoUtc], que es lo que hace que el
  /// `>=` y el `<` comparen instantes y no textos.
  static ({String desde, String hasta, List<Object?> argumentos}) _rangoDelDia(
    DateTime fecha,
  ) {
    final siguiente = DateTime(fecha.year, fecha.month, fecha.day + 1);
    final desde = aIsoUtc(DateTime(fecha.year, fecha.month, fecha.day));
    final hasta = aIsoUtc(siguiente);
    return (desde: desde, hasta: hasta, argumentos: <Object?>[desde, hasta]);
  }
}

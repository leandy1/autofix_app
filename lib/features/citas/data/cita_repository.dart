import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_helper.dart';
import '../models/cita.dart';

/// Contrato de acceso a datos de citas.
///
/// Toda la app (y el modulo de escaneo QR) habla con SQLite unicamente a traves
/// de esta clase. Si manana se cambia a Drift o a una API, se cambia SOLO este
/// archivo y ni una pantalla se entera. Ese es todo el punto del repositorio.
class CitaRepository {
  CitaRepository._();

  static final CitaRepository instance = CitaRepository._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  // ---------------------------------------------------------------------
  // PARA LEANDY: como.connectar tu `citas_screen.dart` con la base real.
  //
  // En el `initState` de tu State:
  //
  //     @override
  //     void initState() {
  //       super.initState();
  //       _cargar();
  //     }
  //
  //     Future<void> _cargar() async {
  //       final citas = await CitaRepository.instance.obtenerDelDia(_fechaSeleccionada);
  //       if (!mounted) return;                 // OBLIGATORIO: el context
  //       setState(() => _citas = citas);      // puede morir durante el await
  //     }
  //
  // Despues, en tu `_buildEstadoAccordion`, en vez del `CircleAvatar` con '0'
  // hardcodeado, usame el conteo que ya viene agrupado:
  //
  //     for (final entrada in _citasPorEstado.entries) {
  //       _buildEstadoAccordion(
  //         nombre: entrada.key,
  //         color: kColorPorEstado[entrada.key]!,   // match exacto, sin ifs
  //         total: entrada.value.length,           // el numero REAL
  //         ...
  //       );
  //     }
  //
  // Y para pintar cada fila:
  //
  //     kColorPorEstado[cita.etiquetaUI]!            // devuelve 'ATRASADAS',
  //                                                    // 'Pendiente', etc.
  //     Text('${cita.cliente} - ${cita.placa}')      // placa ya viene del form
  //     cita.servicios                                // List<String> lista
  // ---------------------------------------------------------------------

  // ------------------------------ CREATE ------------------------------
  /// `insert` devuelve el id autogenerado por SQLite (el AUTOINCREMENT).
  /// OJO: la fila NO tiene `id` todavia, por eso devuelvo el int y no el objeto.
  Future<int> crear(Cita cita) async {
    final db = await _helper.base;
    return db.insert(
      DatabaseHelper.tablaCitas,
      cita.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // ------------------------------- READ -------------------------------
  Future<List<Cita>> obtenerTodas() async {
    final db = await _helper.base;
    final filas = await db.query(
      DatabaseHelper.tablaCitas,
      orderBy: '${DatabaseHelper.colFechaCita} DESC',
    );
    return filas.map(Cita.fromMap).toList();
  }

  Future<Cita?> obtenerPorId(int id) async {
    final db = await _helper.base;
    final filas = await db.query(
      DatabaseHelper.tablaCitas,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    return filas.isEmpty ? null : Cita.fromMap(filas.first);
  }

  /// Las citas de un dia, ordenadas por hora: es lo que necesita tu hero card
  /// de "CITAS DE Hoy". Compara por prefijo de fecha ISO (AAAA-MM-DD) en SQL,
  /// no en Dart, asi el filtro ocurre en el motor y no trae filas de mas.
  Future<List<Cita>> obtenerDelDia(DateTime fecha) async {
    final clave = _claveDia(fecha);
    final db = await _helper.base;
    final filas = await db.query(
      DatabaseHelper.tablaCitas,
      where: '${DatabaseHelper.colFechaCita} LIKE ?',
      whereArgs: ['$clave%'],
      orderBy: '${DatabaseHelper.colFechaCita} ASC',
    );
    return filas.map(Cita.fromMap).toList();
  }

  /// Lo que le resuelve a Leandy los 5 acordeones de `kColorPorEstado` de un
  /// tirón: un Map donde la llave es la ETIQUETA de tu mapa de colores
  /// ('ATRASADAS', 'Pendiente', 'En proceso'...) y el valor la lista de citas.
  /// Las llaves siempre estan todas, aunque la lista este vacia, asi el
  /// acordeon puede mostrar '0' sin que se rompa el for.
  Future<Map<String, List<Cita>>> agruparPorEstadoUi(DateTime fecha) async {
    final citas = await obtenerDelDia(fecha);
    final mapa = <String, List<Cita>>{
      for (final etiqueta in _etiquetasUi) etiqueta: <Cita>[],
    };
    for (final cita in citas) {
      mapa[cita.etiquetaUI]!.add(cita);
    }
    return mapa;
  }

  /// Mismas llaves y mismo orden que tu `kColorPorEstado`, para que el Map que
  /// te devuelva `agruparPorEstadoUi` itere en el mismo orden que tu for.
  static const List<String> _etiquetasUi = [
    'ATRASADAS',
    'Pendiente',
    'Esperando Pieza',
    'En proceso',
    'Completado',
  ];

  // ------------------------------ UPDATE ------------------------------
  /// Si `actualizar` devuelve 0 filas, es que el id no existia. Por eso el
  /// metodo exige `id` y tira `ArgumentError` en vez de fallar en silencio:
  /// un UPDATE que no hace nada es un bug que se descubre en produccion.
  Future<int> actualizar(Cita cita) async {
    final id = cita.id;
    if (id == null) {
      throw ArgumentError('No se puede actualizar una cita sin id.');
    }
    final db = await _helper.base;
    return db.update(
      DatabaseHelper.tablaCitas,
      cita.toMap(),
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Update parcial: manda solo la columna del estado, no reescribe la fila
  /// entera. Sirve para el "cambiar estado" desde la lista sin abrir el form.
  Future<int> cambiarEstado(int id, EstadoCita estado) async {
    final db = await _helper.base;
    return db.update(
      DatabaseHelper.tablaCitas,
      {
        DatabaseHelper.colEstado: estado.name,
        DatabaseHelper.colActualizadoEn: DateTime.now().toIso8601String(),
      },
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
    );
  }

  // ------------------------------ DELETE ------------------------------
  /// Devuelve cuantas filas borro: 0 significa que el id no existia.
  Future<int> eliminar(int id) async {
    final db = await _helper.base;
    return db.delete(
      DatabaseHelper.tablaCitas,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
    );
  }

  // --------------------- ESCANEO QR (compania) ---------------------
  /// ESTE es el metodo que va a llamar el compañero que escanea codigos QR.
  ///
  ///     final cita = await CitaRepository.instance
  ///         .obtenerPorCodigoQr(codigoLeidoPorElScanner);
  ///
  /// Devuelve `null` si ese QR no pertenece a ninguna cita: eso NO es un error,
  /// es el caso normal de "escanean un QR que no es de AutoFix", asi que el
  /// caller decide que mostrar. Si encuentra, la cita YA viene con la base,
  /// o sea que no hace falta un segundo query para los datos del cliente.
  Future<Cita?> obtenerPorCodigoQr(String codigoQr) async {
    final db = await _helper.base;
    final filas = await db.query(
      DatabaseHelper.tablaCitas,
      where: '${DatabaseHelper.colCodigoQr} = ?',
      whereArgs: [codigoQr],
      limit: 1,
    );
    return filas.isEmpty ? null : Cita.fromMap(filas.first);
  }

  /// Utilidad interna: 'AAAA-MM-DD', que es como SQLite ordena los timestamps
  /// ISO-8601. Por eso el filtro por dia puede ser un simple `LIKE '2026-10-01%'`
  /// y no un BETWEEN con dos strings.
  static String _claveDia(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';
}

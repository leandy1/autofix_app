import 'package:sqflite/sqflite.dart';

import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/utils/reloj.dart';
import 'package:autofix/core/utils/uuid.dart';
import 'package:autofix/features/configuracion/models/tipo_servicio.dart';

/// Acceso a datos de Tipos de Servicio.
///
/// Mismo contrato que los otros catalogos, mas el precio. Vease
/// `tecnico_repository.dart` para el por que de `ConflictAlgorithm.abort` y para
/// por que no hay `eliminado_en` aca.
///
/// CAMBIO v7: la PK paso a UUID, asi que [crear] devuelve el `String` generado y
/// [obtenerPorId] / [eliminar] reciben `String`.
class TipoServicioRepository implements BaseRepository<TipoServicio> {
  TipoServicioRepository._();

  static final TipoServicioRepository instance = TipoServicioRepository._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  @override
  String get tabla => DatabaseHelper.tablaTiposServicio;

  // ------------------------------ CREATE ------------------------------

  @override
  Future<String> crear(TipoServicio servicio) async {
    // `creadoEn` se sella ACA. Ver `TecnicoRepository.crear` y la nota larga de
    // `Cita.toMap`: el modelo no puede distinguir un alta de una edicion, y el
    // repositorio si.
    final conId = servicio.copyWith(
      id: servicio.id ?? Uuid.instancia.generar(),
      creadoEn: servicio.creadoEn ?? Reloj.instancia.ahora(),
    );
    final db = await _helper.base;
    await db.insert(
      tabla,
      conId.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return conId.id!;
  }

  // ------------------------------- READ -------------------------------

  @override
  Future<List<TipoServicio>> obtenerTodas() async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      orderBy: '${DatabaseHelper.colNombre} COLLATE NOCASE ASC',
    );
    return filas.map(TipoServicio.fromMap).toList();
  }

  @override
  Future<TipoServicio?> obtenerPorId(String id) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return filas.isEmpty ? null : TipoServicio.fromMap(filas.first);
  }

  Future<TipoServicio?> obtenerPorNombre(String nombre) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colNombre} = ? COLLATE NOCASE',
      whereArgs: <Object?>[nombre.trim()],
      limit: 1,
    );
    return filas.isEmpty ? null : TipoServicio.fromMap(filas.first);
  }

  // ------------------------------ UPDATE ------------------------------

  @override
  Future<int> actualizar(TipoServicio servicio) async {
    final id = servicio.id;
    if (id == null) {
      throw ArgumentError('No se puede actualizar un tipo de servicio sin id.');
    }
    final db = await _helper.base;
    return db.update(
      tabla,
      servicio.copyWith(actualizadoEn: Reloj.instancia.ahora()).toMap(),
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // ------------------------------ DELETE ------------------------------

  /// Borrado fisico, por la misma razon que en `TecnicoRepository`: la cita
  /// guarda el texto del servicio, no su id, y `activo` ya cubre la baja logica.
  @override
  Future<int> eliminar(String id) async {
    final db = await _helper.base;
    return db.delete(
      tabla,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
    );
  }
}

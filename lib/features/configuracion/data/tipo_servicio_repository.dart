import 'package:sqflite/sqflite.dart';

import '../../../core/data/base_repository.dart';
import '../../../core/database/database_helper.dart';
import '../models/tipo_servicio.dart';

/// Acceso a datos de Tipos de Servicio.
///
/// Mismo contrato que los otros catalogos, mas el precio. Vease
/// `tecnico_repository.dart` para el por que de `ConflictAlgorithm.abort`.
class TipoServicioRepository implements BaseRepository<TipoServicio> {
  TipoServicioRepository._();

  static final TipoServicioRepository instance = TipoServicioRepository._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  @override
  String get tabla => DatabaseHelper.tablaTiposServicio;

  // ------------------------------ CREATE ------------------------------

  @override
  Future<int> crear(TipoServicio servicio) async {
    final db = await _helper.base;
    return db.insert(
      tabla,
      servicio.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
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
  Future<TipoServicio?> obtenerPorId(int id) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    return filas.isEmpty ? null : TipoServicio.fromMap(filas.first);
  }

  Future<TipoServicio?> obtenerPorNombre(String nombre) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colNombre} = ? COLLATE NOCASE',
      whereArgs: [nombre.trim()],
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
      servicio.copyWith(actualizadoEn: DateTime.now()).toMap(),
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
      conflictAlgorithm: ConflictAlgorithm.abort,
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
}

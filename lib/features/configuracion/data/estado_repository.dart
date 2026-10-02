import 'package:sqflite/sqflite.dart';

import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/configuracion/models/estado.dart';

/// Acceso a datos del catalogo de Estados.
///
/// Este repo NO decide que estados puede tomar una cita: eso es del modulo de
/// Citas. Vease la nota de alcance en [EstadoConfig].
class EstadoRepository implements BaseRepository<EstadoConfig> {
  EstadoRepository._();

  static final EstadoRepository instance = EstadoRepository._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  @override
  String get tabla => DatabaseHelper.tablaEstados;

  // ------------------------------ CREATE ------------------------------

  @override
  Future<int> crear(EstadoConfig estado) async {
    final db = await _helper.base;
    return db.insert(
      tabla,
      estado.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // ------------------------------- READ -------------------------------

  @override
  Future<List<EstadoConfig>> obtenerTodas() async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      orderBy: '${DatabaseHelper.colNombre} COLLATE NOCASE ASC',
    );
    return filas.map(EstadoConfig.fromMap).toList();
  }

  @override
  Future<EstadoConfig?> obtenerPorId(int id) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    return filas.isEmpty ? null : EstadoConfig.fromMap(filas.first);
  }

  Future<EstadoConfig?> obtenerPorNombre(String nombre) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colNombre} = ? COLLATE NOCASE',
      whereArgs: [nombre.trim()],
      limit: 1,
    );
    return filas.isEmpty ? null : EstadoConfig.fromMap(filas.first);
  }

  // ------------------------------ UPDATE ------------------------------

  @override
  Future<int> actualizar(EstadoConfig estado) async {
    final id = estado.id;
    if (id == null) {
      throw ArgumentError('No se puede actualizar un estado sin id.');
    }
    final db = await _helper.base;
    return db.update(
      tabla,
      estado.copyWith(actualizadoEn: DateTime.now()).toMap(),
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

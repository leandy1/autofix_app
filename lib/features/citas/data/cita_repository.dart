import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_helper.dart';
import '../models/cita.dart';

/// Contrato de acceso a datos de citas.
///
/// Toda la app (y el futuro modulo de escaneo QR) habla con SQLite unicamente a
/// traves de esta clase. Si mañana se cambia a Drift o a una API, solo cambia
/// este archivo.
class CitaRepository {
  CitaRepository._();

  static final CitaRepository instance = CitaRepository._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  // CREATE
  Future<int> crear(Cita cita) async {
    final db = await _helper.base;
    return db.insert(
      DatabaseHelper.tablaCitas,
      cita.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // READ
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

  /// Punto de entrada para el escaner QR: resuelve una cita por su codigo.
  /// `null` significa que el QR no pertenece a ninguna cita registrada.
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

  // UPDATE
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

  Future<int> cambiarEstado(int id, EstadoCita estado) async {
    final db = await _helper.base;
    return db.update(
      DatabaseHelper.tablaCitas,
      {DatabaseHelper.colEstado: estado.name},
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
    );
  }

  // DELETE
  Future<int> eliminar(int id) async {
    final db = await _helper.base;
    return db.delete(
      DatabaseHelper.tablaCitas,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
    );
  }
}

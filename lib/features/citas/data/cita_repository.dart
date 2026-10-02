import 'package:sqflite/sqflite.dart';

import '../../../core/data/base_repository.dart';
import '../../../core/database/database_helper.dart';
import '../models/cita.dart';

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
      orderBy: '${DatabaseHelper.colFechaCita} ASC',
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
  /// para no traer filas de mas: se compara por el prefijo de fecha ISO.
  Future<List<Cita>> obtenerDelDia(DateTime fecha) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colFechaCita} LIKE ?',
      whereArgs: ['${_claveDia(fecha)}%'],
      orderBy: '${DatabaseHelper.colFechaCita} ASC',
    );
    return filas.map(Cita.fromMap).toList();
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

  /// 'AAAA-MM-DD'. SQLite ordena los timestamps ISO por prefijo, asi que el
  /// filtro por dia es un `LIKE '2026-10-01%'` y no un BETWEEN de dos strings.
  static String _claveDia(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';
}

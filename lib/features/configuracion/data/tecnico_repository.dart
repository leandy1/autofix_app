import 'package:sqflite/sqflite.dart';

import '../../../core/data/base_repository.dart';
import '../../../core/database/database_helper.dart';
import '../models/tecnico.dart';

/// Acceso a datos de Tecnicos.
///
/// Implementa el contrato base para que ni la vista ni el controller dependan de
/// SQLite: cambiar a Drift o a una API toca solo este archivo.
///
/// Los nombres de UI ("Tecnico 1", "En linea") NO viven aca. Un repositorio que
/// conoce textos de pantalla deja de ser reutilizable en cuanto el diseno cambia
/// una palabra.
class TecnicoRepository implements BaseRepository<Tecnico> {
  TecnicoRepository._();

  static final TecnicoRepository instance = TecnicoRepository._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  @override
  String get tabla => DatabaseHelper.tablaTecnicos;

  // ------------------------------ CREATE ------------------------------

  @override
  Future<int> crear(Tecnico tecnico) async {
    final db = await _helper.base;
    return db.insert(
      tabla,
      tecnico.toMap(),
      // `abort` y no `replace`: si el nombre ya existe, el UNIQUE revienta y el
      // controller le avisa al admin. Con `replace` el alta "exitosa" pisaria la
      // fila del otro tecnico y el usuario nunca se enteraria de que perdio datos.
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // ------------------------------- READ -------------------------------

  @override
  Future<List<Tecnico>> obtenerTodas() async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      // `COLLATE NOCASE` en el ORDER y no solo en el indice: asi "tecnico 2"
      // aparece junto a "Técnico 2" en vez de en otra punta de la lista.
      orderBy: '${DatabaseHelper.colNombre} COLLATE NOCASE ASC',
    );
    return filas.map(Tecnico.fromMap).toList();
  }

  @override
  Future<Tecnico?> obtenerPorId(int id) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    return filas.isEmpty ? null : Tecnico.fromMap(filas.first);
  }

  /// Busca por nombre ignorando mayusculas, que es como lo escribe la persona.
  /// `null` significa que no existe: es un resultado valido, no un error.
  Future<Tecnico?> obtenerPorNombre(String nombre) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colNombre} = ? COLLATE NOCASE',
      whereArgs: [nombre.trim()],
      limit: 1,
    );
    return filas.isEmpty ? null : Tecnico.fromMap(filas.first);
  }

  // ------------------------------ UPDATE ------------------------------

  @override
  Future<int> actualizar(Tecnico tecnico) async {
    final id = tecnico.id;
    if (id == null) {
      throw ArgumentError('No se puede actualizar un tecnico sin id.');
    }
    final db = await _helper.base;
    return db.update(
      tabla,
      tecnico.copyWith(actualizadoEn: DateTime.now()).toMap(),
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

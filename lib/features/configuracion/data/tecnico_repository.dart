import 'package:sqflite/sqflite.dart';

import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/utils/reloj.dart';
import 'package:autofix/core/utils/uuid.dart';
import 'package:autofix/features/configuracion/models/tecnico.dart';

/// Acceso a datos de Tecnicos.
///
/// Implementa el contrato base para que ni la vista ni el controller dependan de
/// SQLite: cambiar a Drift o a una API toca solo este archivo.
///
/// Los nombres de UI ("Tecnico 1", "En linea") NO viven aca. Un
/// repositorio que conoce textos de pantalla deja de ser reutilizable en cuanto
/// el diseño cambia una palabra.
///
/// CAMBIO v7: la PK paso a UUID, asi que [crear] devuelve el `String` generado y
/// [obtenerPorId] / [eliminar] reciben `String`.
class TecnicoRepository implements BaseRepository<Tecnico> {
  TecnicoRepository._();

  static final TecnicoRepository instance = TecnicoRepository._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  @override
  String get tabla => DatabaseHelper.tablaTecnicos;

  // ------------------------------ CREATE ------------------------------

  @override
  Future<String> crear(Tecnico tecnico) async {
    // `creadoEn` se sella ACA y no en `Tecnico.toMap()`: el modelo solo escribe
    // la columna si ya la conoce, y "ya tiene id" no significa "ya esta en la
    // base" porque este metodo se lo acaba de poner. Ver la nota larga de
    // `Cita.toMap`.
    final conId = tecnico.copyWith(
      id: tecnico.id ?? Uuid.instancia.generar(),
      creadoEn: tecnico.creadoEn ?? Reloj.instancia.ahora(),
    );
    final db = await _helper.base;
    await db.insert(
      tabla,
      conId.toMap(),
      // `abort` y no `replace`: si el nombre ya existe, el UNIQUE revienta y el
      // controller le avisa al admin. Con `replace` el alta "exitosa" pisaria la
      // fila del otro tecnico y el usuario nunca se enteraria de que perdio datos.
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return conId.id!;
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
  Future<Tecnico?> obtenerPorId(String id) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
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
      whereArgs: <Object?>[nombre.trim()],
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
      tecnico.copyWith(actualizadoEn: Reloj.instancia.ahora()).toMap(),
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // ------------------------------ DELETE ------------------------------

  /// Borrado fisico.
  ///
  /// Un tecnico NO lleva `eliminado_en` (a diferencia de `citas`), y es
  /// deliberado: el campo `activo` ya es la baja logica del catalogo, y lo que se
  /// ve en las citas viejas es el TEXTO del tecnico (`citas.tecnico`), no su id.
  /// Un tecnico borrado deja las citas viejas legibles con el nombre que
  /// guardaron, que es lo unico que el cliente puede llegar a ver.
  ///
  /// La unica razon por la que haria falta un tombstone aca es que un dia la cita
  /// guarde `tecnico_id` en vez del texto. Ese dia se agrega la columna y se
  /// cambia este metodo; hoy seria una columna que nadie lee.
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

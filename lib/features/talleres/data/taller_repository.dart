import 'package:sqflite/sqflite.dart';

import '../../../core/data/base_repository.dart';
import '../../../core/database/database_helper.dart';
import '../models/taller.dart';

/// Acceso a datos de los talleres AFILIADOS.
///
/// Implementa el contrato base para que ni la vista ni el controller dependan de
/// SQLite: cambiar a Drift o a una API toca solo este archivo.
///
/// Los nombres de UI ("Global Refriauto", "1.2 km") NO viven aca. Un
/// repositorio que conoce textos de pantalla deja de ser reutilizable en cuanto
/// el diseño cambia una palabra.
///
/// DISTANCIA: no hay ningun metodo que la calcule ni la guarde, y es
/// deliberado. La distancia depende de donde esta el cliente, asi que cambia
/// con cada persona. Si estuviera en la tabla quedaria vieja al instante. El
/// calculo vive en [Taller.distanciaKmDesde] y el orden se hace en Dart, sobre
/// la lista que devuelve [obtenerActivos]: SQLite no tiene una funcion de
/// distancia geodésica nativa, y con una red de afiliados de este tamano (tres,
/// hoy) traer las filas y ordenarlas en Dart es mas legible que un HAVERSINE
/// embebido en el SELECT.
class TallerRepository implements BaseRepository<Taller> {
  TallerRepository._();

  static final TallerRepository instance = TallerRepository._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  @override
  String get tabla => DatabaseHelper.tablaTalleres;

  // ------------------------------ CREATE ------------------------------

  @override
  Future<int> crear(Taller taller) async {
    final db = await _helper.base;
    return db.insert(
      tabla,
      taller.toMap(),
      // `abort` y no `replace`: si el nombre ya existe, el UNIQUE revienta y el
      // controller le avisa al admin. Con `replace` el alta "exitosa" pisaria la
      // fila del otro taller y el usuario nunca se enteraria de que perdio datos.
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // ------------------------------- READ -------------------------------

  /// TODOS los talleres, activos y dados de baja.
  ///
  /// Para las pantallas de administracion, que necesitan ver tambien los dados de
  /// baja para poder reactivarlos. Para el mapa del cliente usa
  /// [obtenerActivos].
  @override
  Future<List<Taller>> obtenerTodas() async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      // `COLLATE NOCASE` en el ORDER y no solo en el indice: asi "taller gomez"
      // aparece junto a "Taller Gómez" en vez de en otra punta de la lista.
      orderBy: '${DatabaseHelper.colNombre} COLLATE NOCASE ASC',
    );
    return filas.map(Taller.fromMap).toList();
  }

  /// Solo los talleres activos: la lista que se pinta en el mapa y en el
  /// selector del formulario.
  ///
  /// El filtro va en SQL y no en Dart a proposito: asi un taller dado de baja
  /// nunca llega a la pantalla, ni siquiera un instante antes de que el filtro
  /// de Dart lo saque. Filtrar despues de traer las filas deja una ventana en la
  /// que el dato equivocado ya esta en memoria.
  Future<List<Taller>> obtenerActivos() async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colActivo} = ?',
      whereArgs: <Object?>[1],
      orderBy: '${DatabaseHelper.colNombre} COLLATE NOCASE ASC',
    );
    return filas.map(Taller.fromMap).toList();
  }

  @override
  Future<Taller?> obtenerPorId(int id) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return filas.isEmpty ? null : Taller.fromMap(filas.first);
  }

  /// Busca por nombre ignorando mayusculas y espacios, que es como lo escribe la
  /// persona. `null` significa que no existe: es un resultado valido, no un error.
  Future<Taller?> obtenerPorNombre(String nombre) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colNombre} = ? COLLATE NOCASE',
      whereArgs: <Object?>[nombre.trim()],
      limit: 1,
    );
    return filas.isEmpty ? null : Taller.fromMap(filas.first);
  }

  // ------------------------------ UPDATE ------------------------------

  @override
  Future<int> actualizar(Taller taller) async {
    final id = taller.id;
    if (id == null) {
      throw ArgumentError('No se puede actualizar un taller sin id.');
    }
    final db = await _helper.base;
    return db.update(
      tabla,
      taller.copyWith(actualizadoEn: DateTime.now()).toMap(),
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Da de baja un taller SIN borrarlo.
  ///
  /// Es el metodo que la app deberia usar, y no [eliminar]. Un taller tiene
  /// citas que ya lo nombran, y ese nombre es lo que el cliente ve en su
  /// historial. Borrar la fila deja esas citas apuntando a un id inexistente; con
  /// `activo = 0` el taller desaparece del mapa y del selector, pero su historia
  /// sigue legible.
  Future<int> darDeBaja(int id) async {
    final taller = await obtenerPorId(id);
    if (taller == null) {
      throw ArgumentError('No existe el taller $id.');
    }
    return actualizar(taller.copyWith(activo: false));
  }

  // ------------------------------ DELETE ------------------------------

  @override
  Future<int> eliminar(int id) async {
    final db = await _helper.base;
    return db.delete(
      tabla,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
    );
  }
}

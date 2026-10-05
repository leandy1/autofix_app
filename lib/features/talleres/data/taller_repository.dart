import 'package:sqflite/sqflite.dart';

import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/utils/reloj.dart';
import 'package:autofix/core/utils/uuid.dart';
import 'package:autofix/features/talleres/models/taller.dart';

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
/// calculo vive en [Taller.distanciaKmDesde] y el orden se hace en Dart, sobre la
/// lista que devuelve [obtenerActivos]: SQLite no tiene una funcion de
/// distancia geodésica nativa, y con una red de afiliados de este tamano (tres,
/// hoy) traer las filas y ordenarlas en Dart es mas legible que un HAVERSINE
/// embebido en el SELECT.
///
/// CAMBIO v7: `crear` devuelve el `String` (UUID) en vez del `int` de SQLite, y
/// el id lo genera el repositorio.
class TallerRepository implements BaseRepository<Taller> {
  TallerRepository._();

  static final TallerRepository instance = TallerRepository._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  @override
  String get tabla => DatabaseHelper.tablaTalleres;

  // ------------------------------ CREATE ------------------------------

  /// Guarda el taller y devuelve el UUID con el que quedo.
  ///
  /// El UNIQUE de `nombre` es lo que impide dar de alta dos veces el mismo local,
  /// y `ConflictAlgorithm.abort` es lo que hace que eso sea un error visible en
  /// vez de un alta "exitosa" que piso la fila del otro taller.
  @override
  Future<String> crear(Taller taller) async {
    // `creadoEn` se sella ACA y no en `Taller.toMap()`: el modelo solo escribe la
    // columna si ya la conoce, y "ya tiene id" no significa "ya esta en la base"
    // porque este metodo se lo acaba de poner. Ver la nota larga de `Cita.toMap`.
    final conId = taller.copyWith(
      id: taller.id ?? Uuid.instancia.generar(),
      creadoEn: taller.creadoEn ?? Reloj.instancia.ahora(),
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

  /// TODOS los talleres, activos y dados de baja.
  ///
  /// Para las pantallas de administracion, que necesitan ver tambien los datos de
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
  Future<Taller?> obtenerPorId(String id) async {
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
      taller.copyWith(actualizadoEn: Reloj.instancia.ahora()).toMap(),
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
  Future<int> darDeBaja(String id) async {
    final taller = await obtenerPorId(id);
    if (taller == null) {
      throw ArgumentError('No existe el taller $id.');
    }
    return actualizar(taller.copyWith(activo: false));
  }

  // ------------------------------ DELETE ------------------------------

  /// Borrado FISICO, y sigue siendolo a proposito.
  ///
  /// Es la excepcion consciousa al tombstone de `citas`, y la razon es que el
  /// taller ya tiene su propio mecanismo de baja, que es [darDeBaja]: es
  /// reversible y no pierde el historial de las citas que lo nombran.
  ///
  /// Agregarle `eliminado_en` seria redundancia, y peor que redundancia: la
  /// consulta del mapa tendria que filtrar por `activo = 1 AND eliminado_en IS
  /// NULL`, o sea dos banderas para el mismo significado, y el dia que alguien
  /// olvide una el mapa muestra un taller dado de baja. Un mecanismo, una
  /// bandera.
  ///
  /// Ademas, un taller se crea desde el Modo Desarrollador, y ese flujo es de
  /// pruebas: ahi si conviene que borrar sea borrar de verdad.
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

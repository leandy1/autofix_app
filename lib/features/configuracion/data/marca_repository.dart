import 'package:sqflite/sqflite.dart';

import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/utils/reloj.dart';
import 'package:autofix/core/utils/uuid.dart';
import 'package:autofix/features/configuracion/models/marca.dart';

/// Acceso a datos de Marcas de vehiculo.
///
/// Implementa el contrato base para que ni la vista ni el controller dependan de
/// SQLite: cambiar a Drift o a una API toca solo este archivo.
///
/// Los nombres de UI ("Toyota", "Nueva marca") NO viven aca. Un repositorio que
/// conoce textos de pantalla deja de ser reutilizable en cuanto el diseño cambia
/// una palabra.
///
/// ESTA ES LA API QUE CONECTA LA UI DE LEANDY (punto 6 del encargo). Los cuatro
/// metodos del contrato ([crear], [obtenerTodas], [actualizar], [eliminar]) son
/// lo unico que la vista necesita, y los tres extra ([obtenerPorNombre],
/// [obtenerActivas], [darDeBaja]) estan para las consultas que la pantalla de
/// configuracion y los formularios de cita van a pedir.
///
/// `ConflictAlgorithm.abort` en las escrituras: el UNIQUE de `nombre` (con
/// `COLLATE NOCASE`, o sea "Toyota" y "toyota" chocan) tiene que llegar al
/// controller como error visible, no como un alta "exitosa" que pisa la fila del
/// otro. Ver `tecnico_repository.dart`.
class MarcaRepository implements BaseRepository<Marca> {
  MarcaRepository._();

  static final MarcaRepository instance = MarcaRepository._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  @override
  String get tabla => DatabaseHelper.tablaMarcas;

  // ------------------------------ CREATE ------------------------------

  /// Guarda la marca y devuelve el UUID con el que quedo.
  ///
  /// Si la marca ya trae id (una edicion, o un documento que baja de Firestore) se
  /// respeta el suyo; si no, se le asigna un UUID aca. El generador vive en el
  /// repositorio y no en el controller para que ningun call site pueda olvidarse:
  /// ver el doc de `BaseRepository.crear`.
  @override
  Future<String> crear(Marca marca) async {
    // `creadoEn` se sella ACA. Ver `TecnicoRepository.crear` y la nota larga de
    // `Cita.toMap`: el modelo no puede distinguir un alta de una edicion, y el
    // repositorio si.
    final conId = marca.copyWith(
      id: marca.id ?? Uuid.instancia.generar(),
      creadoEn: marca.creadoEn ?? Reloj.instancia.ahora(),
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

  /// TODAS las marcas, activas y dadas de baja: para la pantalla de
  /// administracion, que tambien necesita ver las de baja para reactivarlas.
  @override
  Future<List<Marca>> obtenerTodas() async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      // `COLLATE NOCASE` en el ORDER y no solo en el indice: asi "toyota"
      // aparece junto a "Toyota" en vez de en otra punta de la lista.
      orderBy: '${DatabaseHelper.colNombre} COLLATE NOCASE ASC',
    );
    return filas.map(Marca.fromMap).toList();
  }

  /// Solo las activas: la lista que se pinta en el desplegable de marca del
  /// formulario de cita.
  ///
  /// El filtro va en SQL y no en Dart a proposito: asi una marca dada de baja
  /// nunca llega a la pantalla, ni siquiera un instante antes de que un filtro de
  /// Dart la saque.
  Future<List<Marca>> obtenerActivas() async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colActivo} = ?',
      whereArgs: <Object?>[1],
      orderBy: '${DatabaseHelper.colNombre} COLLATE NOCASE ASC',
    );
    return filas.map(Marca.fromMap).toList();
  }

  @override
  Future<Marca?> obtenerPorId(String id) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return filas.isEmpty ? null : Marca.fromMap(filas.first);
  }

  /// Busca por nombre ignorando mayusculas, que es como lo escribe la persona.
  /// `null` significa que no existe: es un resultado valido, no un error.
  ///
  /// El `trim` va en el `trim()` del argumento y no en el SQL: SQLite no tiene
  /// `TRIM` con la palabra clave `NOCASE` combined, y comparar 'Toyota ' contra
  /// 'Toyota' con `=` da falso, que es justo el caso que rompe el UNIQUE.
  Future<Marca?> obtenerPorNombre(String nombre) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colNombre} = ? COLLATE NOCASE',
      whereArgs: <Object?>[nombre.trim()],
      limit: 1,
    );
    return filas.isEmpty ? null : Marca.fromMap(filas.first);
  }

  // ------------------------------ UPDATE ------------------------------

  @override
  Future<int> actualizar(Marca marca) async {
    final id = marca.id;
    if (id == null) {
      throw ArgumentError('No se puede actualizar una marca sin id.');
    }
    final db = await _helper.base;
    return db.update(
      tabla,
      marca.copyWith(actualizadoEn: Reloj.instancia.ahora()).toMap(),
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Da de baja una marca sin borrarla: es la operacion que la UI deberia usar
  /// en vez de [eliminar].
  ///
  /// Razon: las citas viejas guardan la marca como TEXTO (`citas.marca`), y ese
  /// texto es lo que el cliente ve en su historial. Borrar la fila no rompe
  /// technically ese texto, pero deja una marca que el admin puede volver a crear
  /// con OTRO id y las dos conviven sin que nada avise. Con `activo = 0` la
  /// marca desaparece de los desplegables y sigue consultable por historial.
  Future<int> darDeBaja(String id) async {
    final marca = await obtenerPorId(id);
    if (marca == null) {
      throw ArgumentError('No existe la marca $id.');
    }
    return actualizar(marca.copyWith(activo: false));
  }

  // ------------------------------ DELETE ------------------------------

  /// Borrado fisico.
  ///
  /// Un `MARCA` NO lleva `eliminado_en` (a diferencia de `citas`) y es
  /// deliberado: [activo] ya es la baja logica del catalogo, y lo que se ve en
  /// las citas viejas es el texto, no el id. Agregarle tombstone seria una segunda
  /// bandera para el mismo significado, y el dia que alguien olvide una de las dos
  /// el desplegable muestra una marca dada de baja.
  ///
  /// Este metodo existe porque el punto 6 pide "eliminar" explicitamente en la API
  /// del catalogo, y hay un flujo donde el borrado fisico es lo correcto: dar de
  /// alta una marca equivocada desde Modo Desarrollador, donde no hay historial que
  /// preservar.
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

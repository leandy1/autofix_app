import 'package:sqflite/sqflite.dart';

import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/database/semilla_inicial.dart';
import 'package:autofix/core/utils/reloj.dart';
import 'package:autofix/core/utils/uuid.dart';
import 'package:autofix/features/configuracion/models/grupo_servicio.dart';

/// Acceso a datos de Grupos de Servicios.
///
/// Implementa el contrato base para que ni la vista ni el controller dependan de
/// SQLite: cambiar a Drift o a una API toca solo este archivo.
///
/// Los nombres de UI ("Carrocería", "Nuevo grupo") NO viven aca.
///
/// Es la misma forma que `MarcaRepository`, y por el mismo motivo: los cuatro
/// metodos del contrato ([crear], [obtenerTodas], [actualizar], [eliminar]) son la
/// API que la UI de Leandy (punto 6 del encargo) conecta, y [obtenerActivos] /
/// [obtenerPorNombre] / [darDeBaja] cubren las consultas de los formularios.
///
/// LO QUE NO HACE todavia: leer los `tipos_servicio` que pertenecen al grupo. Esa
/// relacion necesita una tabla puente (`grupo_servicio_items`) y la decision de
/// si un servicio puede estar en varios grupos todavia no esta tomada. Ver el doc
/// de [GrupoServicio]. Cuando se agregue, este archivo gana un
/// `obtenerServiciosDelGrupo(String grupoId)` y la tabla puente entra en la v8.
class GrupoServicioRepository implements BaseRepository<GrupoServicio> {
  GrupoServicioRepository._();

  static final GrupoServicioRepository instance = GrupoServicioRepository._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  @override
  String get tabla => DatabaseHelper.tablaGruposServicio;

  // ------------------------------ CREATE ------------------------------

  @override
  Future<String> crear(GrupoServicio grupo) async {
    // `creadoEn` se sella ACA. Ver `MarcaRepository.crear`.
    final conId = grupo.copyWith(
      id: grupo.id ?? Uuid.instancia.generar(),
      creadoEn: grupo.creadoEn ?? Reloj.instancia.ahora(),
      tallerId: grupo.tallerId ?? SemillaInicial.talleres.first.id,
      eliminadoEn: null,
      syncStatus: 'pending',
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

  Future<List<GrupoServicio>> obtenerTodasPorTaller(String tallerId) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where:
          '${DatabaseHelper.colTallerId} = ? AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[tallerId],
      orderBy: '${DatabaseHelper.colNombre} COLLATE NOCASE ASC',
    );
    return filas.map(GrupoServicio.fromMap).toList();
  }

  /// Solo los grupos activos de un taller: para formularios y listas de selección.
  Future<List<GrupoServicio>> obtenerActivosPorTaller(String tallerId) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where:
          '${DatabaseHelper.colTallerId} = ? AND ${DatabaseHelper.colActivo} = ? AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[tallerId, 1],
      orderBy: '${DatabaseHelper.colNombre} COLLATE NOCASE ASC',
    );
    return filas.map(GrupoServicio.fromMap).toList();
  }

  Future<GrupoServicio?> obtenerPorNombreYTaller(
    String nombre,
    String tallerId,
  ) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where:
          '${DatabaseHelper.colNombre} = ? COLLATE NOCASE AND ${DatabaseHelper.colTallerId} = ? AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[nombre.trim(), tallerId],
      limit: 1,
    );
    return filas.isEmpty ? null : GrupoServicio.fromMap(filas.first);
  }

  @override
  Future<List<GrupoServicio>> obtenerTodas() async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colEliminadoEn} IS NULL',
      orderBy: '${DatabaseHelper.colNombre} COLLATE NOCASE ASC',
    );
    return filas.map(GrupoServicio.fromMap).toList();
  }

  /// Solo los grupos activos: la lista que alimenta el acordeon de la pantalla de
  /// Configuracion y el desplegable del formulario.
  Future<List<GrupoServicio>> obtenerActivos() async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where:
          '${DatabaseHelper.colActivo} = ? AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[1],
      orderBy: '${DatabaseHelper.colNombre} COLLATE NOCASE ASC',
    );
    return filas.map(GrupoServicio.fromMap).toList();
  }

  @override
  Future<GrupoServicio?> obtenerPorId(String id) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where:
          '${DatabaseHelper.colId} = ? AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return filas.isEmpty ? null : GrupoServicio.fromMap(filas.first);
  }

  Future<GrupoServicio?> obtenerPorNombre(String nombre) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where:
          '${DatabaseHelper.colNombre} = ? COLLATE NOCASE AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[nombre.trim()],
      limit: 1,
    );
    return filas.isEmpty ? null : GrupoServicio.fromMap(filas.first);
  }

  // ------------------------------ UPDATE ------------------------------

  @override
  Future<int> actualizar(GrupoServicio grupo) async {
    final id = grupo.id;
    if (id == null) {
      throw ArgumentError(
        'No se puede actualizar un grupo de servicios sin id.',
      );
    }
    final db = await _helper.base;
    return db.update(
      tabla,
      grupo
          .copyWith(
            actualizadoEn: Reloj.instancia.ahora(),
            syncStatus: 'pending',
          )
          .toMap(),
      where:
          '${DatabaseHelper.colId} = ? AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Da de baja el grupo sin borrarlo. Ver la razon en `MarcaRepository.darDeBaja`.
  Future<int> darDeBaja(String id) async {
    final grupo = await obtenerPorId(id);
    if (grupo == null) {
      throw ArgumentError('No existe el grupo de servicios $id.');
    }
    return actualizar(grupo.copyWith(activo: false));
  }

  // ------------------------------ DELETE ------------------------------

  /// Baja lógica sincronizable. La fila se conserva para el historial.
  @override
  Future<int> eliminar(String id) async {
    final db = await _helper.base;
    final ahora = Reloj.instancia.ahora();
    return db.update(
      tabla,
      <String, Object?>{
        DatabaseHelper.colEliminadoEn: ahora.toIso8601String(),
        DatabaseHelper.colActualizadoEn: ahora.toIso8601String(),
        DatabaseHelper.colSyncStatus: 'pending',
      },
      where:
          '${DatabaseHelper.colId} = ? AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[id],
    );
  }
}

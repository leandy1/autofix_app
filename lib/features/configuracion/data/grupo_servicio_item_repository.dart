import 'package:sqflite/sqflite.dart';

import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/utils/reloj.dart';
import 'package:autofix/core/utils/uuid.dart';
import 'package:autofix/features/configuracion/models/grupo_servicio_item.dart';

/// Acceso a datos de la tabla puente `grupo_servicio_items`.
///
/// Relaciona [GrupoServicio] con [TipoServicio] (many-to-many).
/// Permite que un servicio pertenezca a varios grupos y un grupo tenga varios servicios.
class GrupoServicioItemRepository implements BaseRepository<GrupoServicioItem> {
  GrupoServicioItemRepository._();

  static final GrupoServicioItemRepository instance = GrupoServicioItemRepository._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  @override
  String get tabla => DatabaseHelper.tablaGrupoServicioItems;

  // ------------------------------ CREATE ------------------------------

  /// Crea un vínculo entre un grupo y un servicio.
  ///
  /// [grupoId] y [tipoServicioId] son obligatorios.
  /// [orden] define la posición del servicio dentro del grupo (0 = primero).
  Future<String> crearVinculo({
    required String grupoId,
    required String tipoServicioId,
    required String tallerId,
    int orden = 0,
  }) async {
    final item = GrupoServicioItem(
      id: Uuid.instancia.generar(),
      grupoId: grupoId,
      tipoServicioId: tipoServicioId,
      orden: orden,
      tallerId: tallerId,
      creadoEn: Reloj.instancia.ahora(),
      actualizadoEn: Reloj.instancia.ahora(),
    );

    final db = await _helper.base;
    await db.insert(
      tabla,
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return item.id!;
  }

  @override
  Future<String> crear(GrupoServicioItem item) async {
    final conId = item.copyWith(
      id: item.id ?? Uuid.instancia.generar(),
      creadoEn: item.creadoEn ?? Reloj.instancia.ahora(),
      actualizadoEn: Reloj.instancia.ahora(),
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

  /// Obtiene todos los vínculos activos de un grupo, ordenados por [orden].
  Future<List<GrupoServicioItem>> obtenerPorGrupo(String grupoId) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where:
          '${DatabaseHelper.colGrupoId} = ? AND ${DatabaseHelper.colActivo} = ? AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[grupoId, 1],
      orderBy: '${DatabaseHelper.colOrden} ASC',
    );
    return filas.map(GrupoServicioItem.fromMap).toList();
  }

  /// Obtiene todos los vínculos activos de un servicio (en qué grupos está).
  Future<List<GrupoServicioItem>> obtenerPorServicio(String tipoServicioId) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where:
          '${DatabaseHelper.colTipoServicioId} = ? AND ${DatabaseHelper.colActivo} = ? AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[tipoServicioId, 1],
      orderBy: '${DatabaseHelper.colOrden} ASC',
    );
    return filas.map(GrupoServicioItem.fromMap).toList();
  }

  /// Obtiene todos los vínculos de un taller, incluyendo inactivos y eliminados.
  Future<List<GrupoServicioItem>> obtenerTodasPorTaller(String tallerId) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colTallerId} = ?',
      whereArgs: <Object?>[tallerId],
      orderBy: '${DatabaseHelper.colGrupoId}, ${DatabaseHelper.colOrden} ASC',
    );
    return filas.map(GrupoServicioItem.fromMap).toList();
  }

  /// Obtiene solo los vínculos activos de un taller.
  Future<List<GrupoServicioItem>> obtenerActivosPorTaller(String tallerId) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where:
          '${DatabaseHelper.colTallerId} = ? AND ${DatabaseHelper.colActivo} = ? AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[tallerId, 1],
      orderBy: '${DatabaseHelper.colGrupoId}, ${DatabaseHelper.colOrden} ASC',
    );
    return filas.map(GrupoServicioItem.fromMap).toList();
  }

  @override
  Future<List<GrupoServicioItem>> obtenerTodas() async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where: '${DatabaseHelper.colEliminadoEn} IS NULL',
      orderBy: '${DatabaseHelper.colGrupoId}, ${DatabaseHelper.colOrden} ASC',
    );
    return filas.map(GrupoServicioItem.fromMap).toList();
  }

  @override
  Future<GrupoServicioItem?> obtenerPorId(String id) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where:
          '${DatabaseHelper.colId} = ? AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return filas.isEmpty ? null : GrupoServicioItem.fromMap(filas.first);
  }

  /// Verifica si ya existe un vínculo activo entre el grupo y el servicio.
  Future<bool> existeVinculo({
    required String grupoId,
    required String tipoServicioId,
    required String tallerId,
  }) async {
    final db = await _helper.base;
    final filas = await db.query(
      tabla,
      where:
          '${DatabaseHelper.colGrupoId} = ? AND ${DatabaseHelper.colTipoServicioId} = ? AND ${DatabaseHelper.colTallerId} = ? AND ${DatabaseHelper.colActivo} = ? AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[grupoId, tipoServicioId, tallerId, 1],
      limit: 1,
    );
    return filas.isNotEmpty;
  }

  // ------------------------------ UPDATE ------------------------------

  @override
  Future<int> actualizar(GrupoServicioItem item) async {
    final id = item.id;
    if (id == null) {
      throw ArgumentError('No se puede actualizar un vínculo sin id.');
    }
    final db = await _helper.base;
    return db.update(
      tabla,
      item
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

  /// Actualiza el orden de un vínculo.
  Future<int> actualizarOrden(String id, int orden) async {
    final item = await obtenerPorId(id);
    if (item == null) {
      throw ArgumentError('No existe el vínculo $id.');
    }
    return actualizar(item.copyWith(orden: orden));
  }

  /// Activa/desactiva un vínculo sin borrarlo.
  Future<int> setActivo(String id, bool activo) async {
    final item = await obtenerPorId(id);
    if (item == null) {
      throw ArgumentError('No existe el vínculo $id.');
    }
    return actualizar(item.copyWith(activo: activo));
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

  /// Elimina (baja lógica) todos los vínculos de un grupo.
  Future<int> eliminarPorGrupo(String grupoId) async {
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
          '${DatabaseHelper.colGrupoId} = ? AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[grupoId],
    );
  }

  /// Elimina (baja lógica) un vínculo específico grupo-servicio.
  Future<int> eliminarVinculo({
    required String grupoId,
    required String tipoServicioId,
  }) async {
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
          '${DatabaseHelper.colGrupoId} = ? AND ${DatabaseHelper.colTipoServicioId} = ? AND ${DatabaseHelper.colEliminadoEn} IS NULL',
      whereArgs: <Object?>[grupoId, tipoServicioId],
    );
  }
}
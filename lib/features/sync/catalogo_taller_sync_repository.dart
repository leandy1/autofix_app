import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';

import 'package:autofix/core/database/database_helper.dart';

/// Correspondencia entre un catálogo local y su colección Firestore.
///
/// `tipos_servicio` conserva el nombre local existente, pero su colección remota
/// es `servicios`, como define el contrato de seguridad del proyecto.
class CatalogoTallerSyncDefinition {
  const CatalogoTallerSyncDefinition({
    required this.tabla,
    required this.coleccion,
    this.tienePrecio = false,
  });

  final String tabla;
  final String coleccion;
  final bool tienePrecio;

  List<String> get columnas => <String>[
    DatabaseHelper.colId,
    DatabaseHelper.colNombre,
    DatabaseHelper.colActivo,
    DatabaseHelper.colCreadoEn,
    DatabaseHelper.colActualizadoEn,
    DatabaseHelper.colTallerId,
    if (tienePrecio) DatabaseHelper.colPrecio,
    DatabaseHelper.colSyncStatus,
    DatabaseHelper.colEliminadoEn,
  ];
}

/// Operaciones SQLite compartidas por los catálogos que sincroniza SyncService.
///
/// Los borrados lógicos son filas pendientes normales: [pendientes] no filtra
/// `eliminado_en`, para que el tombstone también se publique en Firestore.
class CatalogoTallerSyncRepository {
  CatalogoTallerSyncRepository({DatabaseHelper? helper})
    : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  Future<List<Map<String, Object?>>> pendientes(
    CatalogoTallerSyncDefinition definition,
    String tallerId,
  ) async {
    final db = await _helper.base;
    return db.query(
      definition.tabla,
      where:
          '${DatabaseHelper.colTallerId} = ? AND ${DatabaseHelper.colSyncStatus} = ?',
      whereArgs: <Object?>[tallerId, 'pending'],
      orderBy: '${DatabaseHelper.colActualizadoEn} ASC',
    );
  }

  /// Incorpora una versión remota, sin convertirla en una edición local.
  ///
  /// Una edición local `pending` siempre se conserva para el push. Entre dos
  /// versiones ya sincronizadas se usa `actualizado_en`; además, un tombstone
  /// local nunca se resucita por una copia remota viva.
  Future<bool> aplicarDesdeNube({
    required CatalogoTallerSyncDefinition definition,
    required String id,
    required String tallerId,
    required Map<String, dynamic> data,
  }) async {
    if (data[DatabaseHelper.colTallerId] != tallerId) return false;

    final db = await _helper.base;
    final filas = await db.query(
      definition.tabla,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    final local = filas.isEmpty ? null : filas.single;

    final actualizadoRemoto = _fechaIso(data[DatabaseHelper.colActualizadoEn]);
    final actualizadoLocal = _fechaIso(local?[DatabaseHelper.colActualizadoEn]);
    final eliminadoLocal = _fechaIso(local?[DatabaseHelper.colEliminadoEn]);
    final eliminadoRemoto = _fechaIso(data[DatabaseHelper.colEliminadoEn]);
    final tombstoneRemotoGana =
        eliminadoRemoto != null && eliminadoLocal == null;

    if (local != null &&
        local[DatabaseHelper.colSyncStatus] == 'pending' &&
        !tombstoneRemotoGana) {
      return false;
    }

    if (eliminadoLocal != null && eliminadoRemoto == null) return false;
    if (eliminadoLocal != null &&
        eliminadoRemoto != null &&
        eliminadoLocal.isAfter(eliminadoRemoto)) {
      return false;
    }
    if (!tombstoneRemotoGana &&
        actualizadoLocal != null &&
        actualizadoRemoto != null &&
        actualizadoLocal.isAfter(actualizadoRemoto)) {
      return false;
    }

    final actualizado = actualizadoRemoto ?? DateTime.now().toUtc();
    final creado =
        _fechaIso(data[DatabaseHelper.colCreadoEn]) ??
        _fechaIso(local?[DatabaseHelper.colCreadoEn]) ??
        actualizado;
    final valores = <String, Object?>{
      DatabaseHelper.colId: id,
      DatabaseHelper.colNombre: data[DatabaseHelper.colNombre] as String? ?? '',
      DatabaseHelper.colActivo: _activoComoEntero(
        data[DatabaseHelper.colActivo],
      ),
      DatabaseHelper.colCreadoEn: creado.toIso8601String(),
      DatabaseHelper.colActualizadoEn: actualizado.toIso8601String(),
      DatabaseHelper.colTallerId: tallerId,
      if (definition.tienePrecio)
        DatabaseHelper.colPrecio:
            (data[DatabaseHelper.colPrecio] as num?)?.toInt() ?? 0,
      DatabaseHelper.colSyncStatus: 'synced',
      DatabaseHelper.colEliminadoEn: eliminadoRemoto?.toIso8601String(),
    };

    await db.insert(
      definition.tabla,
      valores,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return true;
  }

  /// Marca una fila synced solo si no fue editada durante el push.
  Future<bool> marcarSincronizado({
    required CatalogoTallerSyncDefinition definition,
    required String id,
    required String actualizadoEn,
  }) async {
    final db = await _helper.base;
    final filas = await db.update(
      definition.tabla,
      <String, Object?>{DatabaseHelper.colSyncStatus: 'synced'},
      where:
          '${DatabaseHelper.colId} = ? AND ${DatabaseHelper.colSyncStatus} = ? AND ${DatabaseHelper.colActualizadoEn} = ?',
      whereArgs: <Object?>[id, 'pending', actualizadoEn],
    );
    return filas == 1;
  }

  /// Convierte una fila SQLite al formato estable del documento Firestore.
  Map<String, Object?> aFirestore(
    CatalogoTallerSyncDefinition definition,
    Map<String, Object?> fila,
  ) {
    return <String, Object?>{
      for (final columna in definition.columnas)
        if (columna != DatabaseHelper.colSyncStatus &&
            columna != DatabaseHelper.colActivo)
          columna: fila[columna],
      DatabaseHelper.colActivo: _activoComoBool(fila[DatabaseHelper.colActivo]),
      DatabaseHelper.colSyncStatus: 'synced',
    };
  }

  static int _activoComoEntero(Object? valor) => switch (valor) {
    bool booleano => booleano ? 1 : 0,
    num numero => numero == 0 ? 0 : 1,
    _ => 1,
  };

  static bool _activoComoBool(Object? valor) => _activoComoEntero(valor) != 0;

  static DateTime? _fechaIso(Object? valor) {
    if (valor is Timestamp) return valor.toDate().toUtc();
    if (valor is DateTime) return valor.toUtc();
    if (valor is String) return DateTime.tryParse(valor)?.toUtc();
    return null;
  }
}

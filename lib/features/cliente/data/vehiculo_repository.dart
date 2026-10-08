import 'package:sqflite/sqflite.dart';

import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/utils/reloj.dart';
import 'package:autofix/core/utils/uuid.dart';
import 'package:autofix/features/cliente/models/vehiculo.dart';

/// Almacenamiento local de vehículos registrados por el cliente.
class VehiculoRepository {
  VehiculoRepository._();

  static final VehiculoRepository instance = VehiculoRepository._();

  Future<List<Vehiculo>> obtenerPorCliente(String clienteId) async {
    final db = await DatabaseHelper.instance.base;
    final filas = await db.query(
      DatabaseHelper.tablaVehiculos,
      where:
          '${DatabaseHelper.colClienteIdVehiculo} = ? '
          'AND ${DatabaseHelper.colActivoVehiculo} = 1 '
          'AND ${DatabaseHelper.colEliminadoEnVehiculo} IS NULL',
      whereArgs: [clienteId.trim().toLowerCase()],
      orderBy: '${DatabaseHelper.colActualizadoEn} DESC',
    );
    return filas.map(Vehiculo.fromMap).toList(growable: false);
  }

  Future<Vehiculo?> obtenerPorId(String id) async {
    final db = await DatabaseHelper.instance.base;
    final filas = await db.query(
      DatabaseHelper.tablaVehiculos,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    return filas.isEmpty ? null : Vehiculo.fromMap(filas.first);
  }

  Future<String> crear(Vehiculo vehiculo) async {
    _validar(vehiculo);
    final ahora = Reloj.instancia.ahora();
    final guardado = vehiculo.copyWith(
      id: vehiculo.id ?? Uuid.instancia.generar(),
      clienteId: vehiculo.clienteId.trim().toLowerCase(),
      creadoEn: vehiculo.creadoEn ?? ahora,
      actualizadoEn: ahora,
      syncStatus: 'pending',
    );
    final db = await DatabaseHelper.instance.base;
    await db.insert(
      DatabaseHelper.tablaVehiculos,
      guardado.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return guardado.id!;
  }

  Future<int> actualizar(Vehiculo vehiculo) async {
    final id = vehiculo.id;
    if (id == null) throw ArgumentError('El vehículo no tiene id.');
    _validar(vehiculo);
    final db = await DatabaseHelper.instance.base;
    return db.update(
      DatabaseHelper.tablaVehiculos,
      vehiculo
          .copyWith(
            clienteId: vehiculo.clienteId.trim().toLowerCase(),
            actualizadoEn: Reloj.instancia.ahora(),
            syncStatus: 'pending',
          )
          .toMap(),
      where:
          '${DatabaseHelper.colId} = ? AND '
          '${DatabaseHelper.colClienteIdVehiculo} = ?',
      whereArgs: [id, vehiculo.clienteId.trim().toLowerCase()],
    );
  }

  Future<int> eliminar(String id, {required String clienteId}) async {
    final db = await DatabaseHelper.instance.base;
    return db.update(
      DatabaseHelper.tablaVehiculos,
      <String, Object?>{
        DatabaseHelper.colActivoVehiculo: 0,
        DatabaseHelper.colActualizadoEn: ahoraIso(),
        DatabaseHelper.colSyncStatusVehiculo: 'pending',
        DatabaseHelper.colEliminadoEnVehiculo: ahoraIso(),
      },
      where:
          '${DatabaseHelper.colId} = ? AND '
          '${DatabaseHelper.colClienteIdVehiculo} = ?',
      whereArgs: [id, clienteId.trim().toLowerCase()],
    );
  }

  Future<int> borrarLocalTodo() async {
    final db = await DatabaseHelper.instance.base;
    return db.delete(DatabaseHelper.tablaVehiculos);
  }

  Future<List<Vehiculo>> pendientesDeSync(String clienteId) async {
    final db = await DatabaseHelper.instance.base;
    final filas = await db.query(
      DatabaseHelper.tablaVehiculos,
      where:
          '${DatabaseHelper.colClienteIdVehiculo} = ? AND '
          '${DatabaseHelper.colSyncStatusVehiculo} = ?',
      whereArgs: [clienteId.trim().toLowerCase(), 'pending'],
      orderBy: '${DatabaseHelper.colActualizadoEn} ASC',
    );
    return filas.map(Vehiculo.fromMap).toList(growable: false);
  }

  /// Marca el push confirmado solo si la fila no cambió durante la subida.
  Future<bool> marcarSincronizado({
    required String id,
    required String actualizadoEn,
  }) async {
    final db = await DatabaseHelper.instance.base;
    final modificadas = await db.update(
      DatabaseHelper.tablaVehiculos,
      <String, Object?>{DatabaseHelper.colSyncStatusVehiculo: 'synced'},
      where:
          '${DatabaseHelper.colId} = ? AND '
          '${DatabaseHelper.colActualizadoEn} = ?',
      whereArgs: [id, actualizadoEn],
    );
    return modificadas > 0;
  }

  /// Aplica un documento remoto sin volver a encolarlo.
  /// Una edición local pendiente o más reciente conserva prioridad.
  Future<bool> aplicarDesdeNube(
    Vehiculo vehiculo, {
    bool prevaleceBaja = false,
  }) async {
    final id = vehiculo.id;
    if (id == null || id.isEmpty) return false;
    final db = await DatabaseHelper.instance.base;
    final local = await obtenerPorId(id);
    if (local != null) {
      if (!prevaleceBaja && local.syncStatus == 'pending') return false;
      final localMs = local.actualizadoEn?.millisecondsSinceEpoch ?? 0;
      final remotoMs = vehiculo.actualizadoEn?.millisecondsSinceEpoch ?? 0;
      if (!prevaleceBaja && localMs > remotoMs) return false;
    }

    await db.insert(
      DatabaseHelper.tablaVehiculos,
      vehiculo.copyWith(syncStatus: 'synced').toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return true;
  }

  void _validar(Vehiculo vehiculo) {
    if (vehiculo.clienteId.trim().isEmpty ||
        vehiculo.marca.trim().isEmpty ||
        vehiculo.modelo.trim().isEmpty ||
        vehiculo.anio < 1886) {
      throw ArgumentError(
        'Completa cliente, marca, modelo y año del vehículo.',
      );
    }
  }
}

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
          'AND ${DatabaseHelper.colActivoVehiculo} = 1',
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

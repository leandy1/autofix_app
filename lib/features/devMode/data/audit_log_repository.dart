import 'dart:convert';
import 'dart:io';

import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/utils/reloj.dart';
import 'package:autofix/core/utils/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Bitácora append-only compartida por los módulos de la aplicación.
class AuditLogRepository {
  AuditLogRepository._();

  static final AuditLogRepository instance = AuditLogRepository._();

  static const String eliminacion = 'eliminacion';
  static const String restauracion = 'restauracion';

  Future<void> registrar({
    required String modulo,
    required String entidadId,
    required String accion,
    Map<String, Object?> detalles = const <String, Object?>{},
  }) async {
    final auth = _usuarioActual();
    final ahora = Reloj.instancia.ahora().toUtc();
    final id = Uuid.instancia.generar();
    final fila = <String, Object?>{
      'id': id,
      'usuario_uid': auth.uid,
      'usuario_email': auth.email,
      'modulo': modulo,
      'entidad_id': entidadId,
      'accion': accion,
      'fecha_hora': ahora.toIso8601String(),
      // Platform expone el sistema operativo sin añadir plugins. Flutter no
      // ofrece el modelo físico de forma multiplataforma.
      'dispositivo':
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'detalles': jsonEncode(detalles),
      DatabaseHelper.colSyncStatus: 'pending',
    };
    final db = await DatabaseHelper.instance.base;
    await db.insert(DatabaseHelper.tablaAuditLogs, fila);
  }

  Future<List<Map<String, Object?>>> pendientes({int limite = 100}) async {
    final db = await DatabaseHelper.instance.base;
    return db.query(
      DatabaseHelper.tablaAuditLogs,
      where: '${DatabaseHelper.colSyncStatus} = ?',
      whereArgs: const <Object?>['pending'],
      orderBy: 'fecha_hora ASC',
      limit: limite,
    );
  }

  Future<void> marcarSincronizado(String id) async {
    final db = await DatabaseHelper.instance.base;
    await db.update(
      DatabaseHelper.tablaAuditLogs,
      <String, Object?>{DatabaseHelper.colSyncStatus: 'synced'},
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<Map<String, Object?>>> obtenerTodos({int limite = 500}) async {
    final db = await DatabaseHelper.instance.base;
    return db.query(
      DatabaseHelper.tablaAuditLogs,
      orderBy: 'fecha_hora DESC',
      limit: limite,
    );
  }

  Future<bool> ultimaAccionEsRestauracion({
    required String modulo,
    required String entidadId,
  }) async {
    final db = await DatabaseHelper.instance.base;
    final filas = await db.query(
      DatabaseHelper.tablaAuditLogs,
      columns: <String>['accion'],
      where: 'modulo = ? AND entidad_id = ?',
      whereArgs: <Object?>[modulo, entidadId],
      orderBy: 'fecha_hora DESC',
      limit: 1,
    );
    return filas.isNotEmpty && filas.single['accion'] == restauracion;
  }

  ({String uid, String email}) _usuarioActual() {
    User? auth;
    try {
      auth = FirebaseAuth.instance.currentUser;
    } on Object {
      // Firebase Auth aún puede no estar inicializado al guardar localmente.
    }
    return (
      uid:
          (auth != null && !auth.isAnonymous ? auth.uid : null) ??
          SesionAdmin.instance.adminUid ??
          SesionCliente.instance.correo ??
          'local',
      email:
          (auth != null && !auth.isAnonymous ? auth.email : null) ??
          SesionAdmin.instance.adminEmail ??
          SesionCliente.instance.correo ??
          '',
    );
  }
}

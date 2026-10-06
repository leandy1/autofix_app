import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';

import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/talleres/data/taller_repository.dart';
import 'package:autofix/features/talleres/models/taller.dart';

/// Sincronizacion pull para datos de Modo Desarrollador (talleres y admins).
///
/// Escucha cambios en Firestore y refleja en SQLite lo que otros dispositivos
/// crean/editan/dan de baja, sin intervencion del usuario.
class DevModeSyncService {
  DevModeSyncService._();

  static final DevModeSyncService instance = DevModeSyncService._();

  final TallerRepository _talleresRepo = TallerRepository.instance;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _talleresSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _adminsSubscription;

  bool _running = false;

  bool get running => _running;

  Future<void> start() async {
    if (_running) return;
    try {
      await _subirTalleresLocalesAFirebase();

      _talleresSubscription = _db
          .collection('talleres')
          .snapshots()
          .listen(_onTalleresSnapshot);

      _adminsSubscription = _db
          .collection('admins')
          .snapshots()
          .listen(_onAdminsSnapshot);

      _running = true;
    } on FirebaseException {
      // Firebase no inicializado (ej. en tests) — skip real-time sync,
      // los datos siguen disponibles desde SQLite.
    }
  }

   Future<void> stop() async {
    await _talleresSubscription?.cancel();
    await _adminsSubscription?.cancel();
    _talleresSubscription = null;
    _adminsSubscription = null;
    _running = false;
  }

  /// Sube los talleres locales a Firebase para que el onSnapshot los descargue
  /// en los otros dispositivos. Es el paso de sync inicial que faltaba: sin
  /// esto, los talleres de la semilla nunca llegan a Firestore y no se
  /// sincronizan entre dispositivos.
  Future<void> _subirTalleresLocalesAFirebase() async {
    final local = await _talleresRepo.obtenerTodas();
    for (final t in local) {
      if (t.id == null) continue;
      await _db.collection('talleres').doc(t.id).set(
        _tallerAFirebaseMap(t),
        SetOptions(merge: true),
      );
    }
  }

  /// Convierte [Taller] a un mapa compatible con Firestore.
  ///
  /// `Taller.toMap()` esta pensado para SQLite: `activo` se guarda como 0/1.
  /// En Firestore debe ir como `bool`, porque el listener de sync lo lee como
  /// `bool?` y un `int` en ese cast lanza TypeError.
  Map<String, Object?> _tallerAFirebaseMap(Taller t) {
    return <String, Object?>{
      'nombre': t.nombre,
      'direccion': t.direccion,
      'telefono': t.telefono,
      'latitud': t.latitud,
      'longitud': t.longitud,
      'activo': t.activo,
      'creado_en': t.creadoEn?.toUtc().toIso8601String(),
      'actualizado_en':
          t.actualizadoEn?.toUtc().toIso8601String() ??
          DateTime.now().toUtc().toIso8601String(),
    };
  }

  void _onTalleresSnapshot(QuerySnapshot<Map<String, dynamic>> snap) async {
    final db = await DatabaseHelper.instance.base;
    final tabla = _talleresRepo.tabla;
    for (final change in snap.docChanges) {
      try {
        final data = change.doc.data();
        if (data == null) continue;

        final id = change.doc.id;

        if (change.type == DocumentChangeType.removed) {
          await db.delete(
            tabla,
            where: '${DatabaseHelper.colId} = ?',
            whereArgs: <Object?>[id],
          );
          continue;
        }

        final taller = Taller(
          id: id,
          nombre: data['nombre'] as String? ?? '',
          direccion: data['direccion'] as String? ?? '',
          telefono: data['telefono'] as String? ?? '',
          latitud: (data['latitud'] as num?)?.toDouble() ?? 0.0,
          longitud: (data['longitud'] as num?)?.toDouble() ?? 0.0,
          activo: switch (data['activo']) {
            bool b => b,
            int i => i != 0,
            _ => true,
          },
          creadoEn: data['creado_en'] != null
              ? DateTime.tryParse(data['creado_en'].toString())?.toUtc()
              : null,
          actualizadoEn: data['actualizado_en'] != null
              ? DateTime.tryParse(data['actualizado_en'].toString())?.toUtc()
              : null,
        );

        final existente = await _talleresRepo.obtenerPorId(id);
        if (existente == null) {
          await db.insert(
            tabla,
            taller.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          await db.update(
            tabla,
            taller.toMap(),
            where: '${DatabaseHelper.colId} = ?',
            whereArgs: <Object?>[id],
          );
        }
      } catch (e) {
        // Ignorar errores de sync para no interrumpir el listener.
      }
    }
  }

  void _onAdminsSnapshot(QuerySnapshot<Map<String, dynamic>> snap) async {
    final db = await DatabaseHelper.instance.base;
    final tabla = DatabaseHelper.tablaAdmins;
    for (final change in snap.docChanges) {
      try {
        final data = change.doc.data();
        if (data == null) continue;

        final id = change.doc.id;
        final eliminado = data['eliminado'] as bool? ?? false;

        if (change.type == DocumentChangeType.removed) {
          await db.delete(
            tabla,
            where: '${DatabaseHelper.colId} = ?',
            whereArgs: <Object?>[id],
          );
          continue;
        }

        // Soft-delete: la fila se conserva en SQLite con `eliminado = 1` para
        // que la UI muestre el estado "Cuenta eliminada".
        await db.insert(
          tabla,
          <String, Object?>{
            DatabaseHelper.colId: id,
            DatabaseHelper.colAdminEmail: data['email'] as String? ?? '',
            DatabaseHelper.colAdminTallerId: data['tallerId'] as String? ?? '',
            DatabaseHelper.colAdminTallerNombre: data['tallerNombre'] as String?,
            DatabaseHelper.colCreadoEn: data['creado_en'] != null
                ? DateTime.tryParse(
                    data['creado_en'].toString(),
                  )
                  ?.toUtc()
                  .toIso8601String()
                : null,
            DatabaseHelper.colActualizadoEn: data['actualizado_en'] != null
                ? DateTime.tryParse(
                    data['actualizado_en'].toString(),
                  )
                  ?.toUtc()
                  .toIso8601String()
                : null,
            DatabaseHelper.colAdminEliminado: eliminado ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (e) {
        // Ignorar errores de sync para no interrumpir el listener.
      }
    }
  }
}

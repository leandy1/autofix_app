import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/talleres/data/taller_repository.dart';
import 'package:autofix/features/talleres/models/taller.dart';

/// Sincronizacion pull para datos de Modo Desarrollador (talleres y admins).
///
/// Escucha cambios en Firestore y refleja en SQLite lo que otros dispositivos
/// crean/editan/dan de baja, sin intervencion del usuario.
///
/// TIENE DOS MODOS Y NO SE CONFUNDEN:
///
/// - [start]: la sesion del Modo Desarrollador. Ademas de escuchar, SUBE los
///   talleres locales a Firebase (es lo que hace que la semilla de un
///   dispositivo llegue a los demas). Solo la abren las pantallas DEV.
/// - [sincronizarCatalogos]: un pull de UNA pasada, solo nube -> SQLite, sin
///   subir nada. Es el que corre al abrir la app, porque `talleres` y `admins`
///   son datos permanentes que cualquier usuario necesita locales aunque
///   jamas abra el Modo Desarrollador.
class DevModeSyncService {
  DevModeSyncService._();

  static final DevModeSyncService instance = DevModeSyncService._();

  final TallerRepository _talleresRepo = TallerRepository.instance;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _talleresSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _adminsSubscription;

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

  /// Descarga `talleres` y `admins` desde Firestore a SQLite en UNA pasada.
  ///
  /// ---------------------------------------------------------------
  /// POR QUE ESTA SEPARADO DE `start`
  /// ---------------------------------------------------------------
  /// `start` es el listener del Modo Desarrollador y su primer paso es SUBIR
  /// lo local a la nube. Eso no puede correr en el arranque de cualquier
  /// usuario: un dispositivo con la semilla local subiria talleres que todavia
  /// no estan en Firebase, y un usuario normal no deberia tener permisos de
  /// escritura sobre el catalogo.
  ///
  /// Este metodo es solo lectura (nube -> SQLite) y por eso se puede disparar
  /// sin permisos especiales y sin alterar el estado del listener DEV.
  ///
  /// Lo que actualiza, segun lo que diga Firebase:
  /// - `talleres.activo`: un taller que la nube marca inactivo queda
  ///   `activo = 0` localmente (se "desactiva", no se borra: las citas
  ///   referencian su id). Si la nube lo vuelve a activar, se reactiva.
  /// - `admins.eliminado`: baja logica, igual que en el listener. La fila se
  ///   conserva para que la UI muestre "Cuenta eliminada" y el login la
  ///   rechace.
  /// - Un documento que Firebase ELIMINO de la coleccion se borra de SQLite.
  ///
  /// Lo que NO hace: borrar filas locales que la nube no conoce. Este pull
  /// corre al abrir la app, posiblemente antes de que exista sesion de Auth y
  /// antes de que la semilla local se haya subido alguna vez; borrar "lo que
  /// no esta en la nube" en ese momento vaciaria el catalogo del dispositivo
  /// en un arranque sin red a Firebase. La decision de borrar es del listener
  /// en vivo (que solo ve `removed` de documentos que el mismo escucho).
  Future<void> sincronizarCatalogos() async {
    try {
      final talleres = await _db.collection('talleres').get();
      final db = await DatabaseHelper.instance.base;
      for (final doc in talleres.docs) {
        await _persistirTaller(db, doc.id, doc.data());
      }

      final admins = await _db.collection('admins').get();
      for (final doc in admins.docs) {
        await _persistirAdmin(db, doc.id, doc.data());
      }
    } catch (e) {
      // Sin red, sin Firebase inicializado o sin permisos: el catalogo local
      // sigue siendo usable. Es un pull de arranque, no una operacion que el
      // usuario este esperando.
      debugPrint('DevModeSyncService: catalogos no se pudieron bajar ($e)');
    }
  }

  /// Sube los talleres locales a Firebase para que el onSnapshot los descargue
  /// en los otros dispositivos. Es el paso de sync inicial que faltaba: sin
  /// esto, los talleres de la semilla nunca llegan a Firestore y no se
  /// sincronizan entre dispositivos.
  Future<void> _subirTalleresLocalesAFirebase() async {
    final local = await _talleresRepo.obtenerTodas();
    for (final t in local) {
      if (t.id == null) continue;
      await _db
          .collection('talleres')
          .doc(t.id)
          .set(_tallerAFirebaseMap(t), SetOptions(merge: true));
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

        await _persistirTaller(db, id, data);
      } catch (e) {
        // Ignorar errores de sync para no interrumpir el listener.
      }
    }
  }

  void _onAdminsSnapshot(QuerySnapshot<Map<String, dynamic>> snap) async {
    final db = await DatabaseHelper.instance.base;
    for (final change in snap.docChanges) {
      try {
        final data = change.doc.data();
        if (data == null) continue;

        final id = change.doc.id;

        if (change.type == DocumentChangeType.removed) {
          await db.delete(
            DatabaseHelper.tablaAdmins,
            where: '${DatabaseHelper.colId} = ?',
            whereArgs: <Object?>[id],
          );
          continue;
        }

        await _persistirAdmin(db, id, data);
      } catch (e) {
        // Ignorar errores de sync para no interrumpir el listener.
      }
    }
  }

  /// Escribe (o reescribe) la fila de un taller que vino de la nube.
  ///
  /// Compartida por el listener en vivo y por [sincronizarCatalogos]: si los
  /// dos hicieran el cast de `activo` por su cuenta, el dia que aparezca un
  /// cuarto formato (`'true'`, `1.0`) uno de los dos quedaria sin actualizar y
  /// un taller dado de baja seguiria activo en la mitad de las pantallas.
  Future<void> _persistirTaller(
    Database db,
    String id,
    Map<String, dynamic> data,
  ) async {
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
        _talleresRepo.tabla,
        taller.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.update(
        _talleresRepo.tabla,
        taller.toMap(),
        where: '${DatabaseHelper.colId} = ?',
        whereArgs: <Object?>[id],
      );
    }
  }

  /// Escribe (o reescribe) la fila de una cuenta admin que vino de la nube.
  ///
  /// Baja logica, nunca `DELETE`: la fila con `eliminado = 1` es la que
  /// permite que la pantalla de cuentas muestre "Cuenta eliminada" y que
  /// `LoginController` rechace entrar con ella sin perder el historial.
  Future<void> _persistirAdmin(
    Database db,
    String id,
    Map<String, dynamic> data,
  ) async {
    final eliminado = data['eliminado'] as bool? ?? false;

    await db.insert(DatabaseHelper.tablaAdmins, <String, Object?>{
      DatabaseHelper.colId: id,
      DatabaseHelper.colAdminEmail: data['email'] as String? ?? '',
      DatabaseHelper.colAdminTallerId: data['tallerId'] as String? ?? '',
      DatabaseHelper.colAdminTallerNombre: data['tallerNombre'] as String?,
      DatabaseHelper.colCreadoEn: data['creado_en'] != null
          ? DateTime.tryParse(data['creado_en'].toString())
                ?.toUtc()
                .toIso8601String()
          : null,
      DatabaseHelper.colActualizadoEn: data['actualizado_en'] != null
          ? DateTime.tryParse(data['actualizado_en'].toString())
                ?.toUtc()
                .toIso8601String()
          : null,
      DatabaseHelper.colAdminEliminado: eliminado ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

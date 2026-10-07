import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/utils/reloj.dart';
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

  /// Intentos que se dan para abrir sesion y para bajar cada coleccion.
  ///
  /// El arrancar del telefono todavia no resuelve DNS, asi que el primer
  /// intento de cualquiera de las dos cosas puede morir sin que haya un error
  /// real que el usuario deba ver. Ver [_asegurarSesionDeLectura] y [_bajar].
  static const int _intentosDeBajada = 3;

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
  ///
  /// ---------------------------------------------------------------
  /// POR QUE ABRE SESION ANTES DE LEER (el bug del arranque)
  /// ---------------------------------------------------------------
  /// Las reglas de Firestore del proyecto son `allow read, write: if
  /// request.auth != null` para TODO el documento. `main()` arranca firmando
  /// FUERA de Firebase cuando no hay sesion local recordada, asi que el primer
  /// `get()` de este metodo corria como invitado y Firestore respondia
  /// `cloud_firestore/permission-denied`: la coleccion se vaciaba a log y la
  /// descarga nunca ocurría. Por eso el primer paso es garantizar un usuario
  /// de Auth. Si ya hay sesion (la que sea) no se toca nada.
  Future<void> sincronizarCatalogos() async {
    await _asegurarSesionDeLectura();

    // Dos bajadas y no un solo `try`: si `admins` rechaza la lectura,
    // `talleres` ya quedo persistido y no debe perderse por eso. Cada coleccion
    // reporta lo suyo.
    final talleresBajados = await _bajar('talleres', _persistirTaller);
    final adminsBajados = await _bajar('admins', _persistirAdmin);

    debugPrint(
      '[DevModeSync] catalogos bajados: $talleresBajados talleres, '
      '$adminsBajados admins',
    );

    if (talleresBajados > 0) {
      _talleresRepo.avisarCatalogoActualizado();
    }
  }

  /// Trae una coleccion de la nube y la escribe en SQLite.
  ///
  /// La lectura y la escritura estan separadas a proposito: los reintentos
  /// cubren la red, no el disco. Un documento que SQLite rechaza (un campo mal
  /// formado en la nube, por ejemplo) se reintenta siempre igual, y solo
  /// prolongaria el arranque sin arreglarse nunca.
  ///
  /// Devuelve cuantos documentos se escribieron; 0 significa que no se pudo
  /// leer nada.
  Future<int> _bajar(
    String coleccion,
    Future<void> Function(Database db, String id, Map<String, dynamic> data)
    persistir,
  ) async {
    final docs = await _traer(coleccion);
    if (docs == null) return 0;

    final db = await DatabaseHelper.instance.base;
    var guardados = 0;
    for (final doc in docs) {
      try {
        await persistir(db, doc.id, doc.data());
        guardados++;
      } catch (e) {
        // Un documento malo no se traga a los buenos: el fallo queda aislado
        // en su fila y el resto del catalogo igual baja.
        debugPrint(
          '[DevModeSync] $coleccion/${doc.id} no se pudo guardar ($e)',
        );
      }
    }
    return guardados;
  }

  /// La lectura, con reintentos.
  ///
  /// Los reintentos no son desconfianza de Firebase: al arrancar el telefono
  /// todavia no resuelve nombres y el primer `get()` muere con
  /// `UnknownHostException: Unable to resolve host ... No address associated
  /// with hostname` (logcat real del celular). Con un solo intento eso se
  /// traducia en "0 talleres" y el mapa se quedaba con la lista vieja.
  ///
  /// `Source.server` y no el default: con el default, si no hay red el SDK
  /// responde desde su propia cache (vacia) y SIN error, y aqui no habria forma
  /// de distinguir "la nube esta vacia" de "no llegamos a la nube". Con
  /// `Source.server` el fallo es una excepcion, que es lo que se reintenta.
  ///
  /// `null` = no se pudo leer en ningun intento.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>?> _traer(
    String coleccion,
  ) async {
    for (var intento = 1; intento <= _intentosDeBajada; intento++) {
      try {
        final snap = await _db
            .collection(coleccion)
            .get(const GetOptions(source: Source.server));
        return snap.docs;
      } catch (e) {
        debugPrint(
          '[DevModeSync] $coleccion no se pudieron leer '
          '(intento $intento/$_intentosDeBajada): $e',
        );
        if (intento < _intentosDeBajada) {
          await Future<void>.delayed(Duration(seconds: 2 * intento));
        }
      }
    }
    return null;
  }

  /// Garantiza un usuario de Auth para poder leer las colecciones.
  ///
  /// Anonimo basta: las reglas solo piden `request.auth != null`, y un usuario
  /// anonimo no tiene identidad, asi que no puede convertirse en un bypass de
  /// login (el gate de "Agendar cita" sigue mirando la sesion local de perfil,
  /// no este uid). Si el proyecto no tiene el proveedor anonimo habilitado,
  /// esto falla con `operation-not-allowed` y el error se reporta arriba.
  Future<void> _asegurarSesionDeLectura() async {
    if (FirebaseAuth.instance.currentUser != null) return;
    for (var intento = 1; intento <= _intentosDeBajada; intento++) {
      try {
        await FirebaseAuth.instance.signInAnonymously();
        debugPrint('[DevModeSync] sesion anonima abierta para leer catalogos');
        return;
      } catch (e) {
        debugPrint(
          '[DevModeSync] sesion de lectura fallo '
          '(intento $intento/$_intentosDeBajada): $e',
        );
        if (intento < _intentosDeBajada) {
          await Future<void>.delayed(Duration(seconds: 2 * intento));
        }
      }
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
    var cambio = false;
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
          cambio = true;
          continue;
        }

        await _persistirTaller(db, id, data);
        cambio = true;
      } catch (e) {
        // Ignorar errores de sync para no interrumpir el listener.
      }
    }

    if (cambio) _talleresRepo.avisarCatalogoActualizado();
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
      creadoEn: _fechaUtcDe(data['creado_en']),
      actualizadoEn: _fechaUtcDe(data['actualizado_en']),
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

    // `creado_en` y `actualizado_en` son NOT NULL en SQLite, y una cuenta
    // puede venir sin ellos desde la nube. Nunca se escribe NULL: manda lo que
    // diga la nube, si no lo que ya tenga la fila, y solo si no hay nada el
    // reloj. Se lee la fila previa porque `INSERT OR REPLACE` reescribe todo y
    // un NULL aca hundiria la fecha de creacion original.
    final previa = await db.query(
      DatabaseHelper.tablaAdmins,
      columns: [DatabaseHelper.colCreadoEn, DatabaseHelper.colActualizadoEn],
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    String? columna(String col) =>
        previa.isEmpty ? null : previa.first[col] as String?;
    final creadoEn =
        _fechaUtcDe(data['creado_en'])?.toIso8601String() ??
        columna(DatabaseHelper.colCreadoEn) ??
        ahoraIso();
    final actualizadoEn =
        _fechaUtcDe(data['actualizado_en'])?.toIso8601String() ??
        columna(DatabaseHelper.colActualizadoEn) ??
        ahoraIso();

    await db.insert(DatabaseHelper.tablaAdmins, <String, Object?>{
      DatabaseHelper.colId: id,
      DatabaseHelper.colAdminEmail: data['email'] as String? ?? '',
      DatabaseHelper.colAdminTallerId: data['tallerId'] as String? ?? '',
      DatabaseHelper.colAdminTallerNombre: data['tallerNombre'] as String?,
      DatabaseHelper.colCreadoEn: creadoEn,
      DatabaseHelper.colActualizadoEn: actualizadoEn,
      DatabaseHelper.colAdminEliminado: eliminado ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Fecha de un campo de Firestore, sea como venga.
  ///
  /// Firestore devuelve `Timestamp` (no `String`) para lo que se escribio con
  /// `FieldValue.serverTimestamp()`, y `DateTime.tryParse(timestamp.toString())`
  /// da null. Eso es exactamente lo que hacia que una cuenta bajara con
  /// `creado_en = NULL` y SQLite la rechazara con `SQLITE_CONSTRAINT_NOTNULL`
  /// en cada intento.
  ///
  /// `null` = el campo no existe o no se entiende; quien llama decide que
  /// hacer, porque eso no es un error de red ni de formato.
  static DateTime? _fechaUtcDe(Object? valor) {
    if (valor is Timestamp) return valor.toDate().toUtc();
    if (valor is String) return DateTime.tryParse(valor)?.toUtc();
    return null;
  }
}

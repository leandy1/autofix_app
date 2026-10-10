import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/utils/reloj.dart';

/// Perfil del cliente sincronizado en `clientes/{uid}`.
class ClientePerfil {
  const ClientePerfil({
    required this.uid,
    required this.nombre,
    required this.correo,
    required this.telefono,
  });

  final String uid;
  final String nombre;
  final String correo;
  final String telefono;

  factory ClientePerfil.desdeFirestore(
    String uid,
    Map<String, dynamic> datos,
  ) => ClientePerfil(
    uid: uid,
    nombre: datos['nombre'] as String? ?? '',
    correo: datos['correo'] as String? ?? datos['email'] as String? ?? '',
    telefono: datos['telefono'] as String? ?? '',
  );
}

/// Una fila de la tabla local `clientes` (v12).
class ClienteLocal {
  const ClienteLocal({
    required this.id,
    required this.uid,
    required this.nombre,
    required this.correo,
    required this.telefono,
    required this.eliminado,
    required this.creadoEn,
    required this.actualizadoEn,
    required this.syncStatus,
  });

  /// PK local: el uid de Firebase Auth si lo hay, si no el correo normalizado.
  final String id;

  /// uid de Firebase Auth. VACIO mientras la fila se haya creado sin sesion.
  final String uid;
  final String nombre;
  final String correo;
  final String telefono;
  final bool eliminado;
  final String creadoEn;
  final String actualizadoEn;

  /// `'pending'` o `'synced'`, mismo vocabulario que `citas.sync_status`.
  final String syncStatus;

  bool get pendienteDeSync => syncStatus == 'pending';

  factory ClienteLocal.desdeFila(Map<String, Object?> fila) => ClienteLocal(
    id: fila[DatabaseHelper.colId] as String,
    uid: fila[DatabaseHelper.colUid] as String? ?? '',
    nombre: fila[DatabaseHelper.colNombre] as String? ?? '',
    correo: fila[DatabaseHelper.colCorreo] as String? ?? '',
    telefono: fila[DatabaseHelper.colTelefono] as String? ?? '',
    eliminado: (fila[DatabaseHelper.colEliminado] as int? ?? 0) != 0,
    creadoEn: fila[DatabaseHelper.colCreadoEn] as String? ?? '',
    actualizadoEn: fila[DatabaseHelper.colActualizadoEn] as String? ?? '',
    syncStatus: fila[DatabaseHelper.colSyncStatus] as String? ?? 'synced',
  );
}

/// Perfil del cliente, en la nube Y en SQLite.
///
/// ---------------------------------------------------------------
/// POR QUE ESTE ARCHIVO TOCA LAS DOS COSAS
/// ---------------------------------------------------------------
/// Antes de la Fase 3 este repositorio solo hablaba Firestore, y
/// `PerfilClienteController.guardarDatos` escribia el perfil en
/// SharedPreferences. El resultado era un "Guardar cambios" que se confirmaba
/// en pantalla pero que no estaba encolado en ninguna parte: sin red, el dato
/// vivia solo en un almacenamiento de preferencias que `SyncService` ni siquiera
/// sabe leer.
///
/// El modelo ahora es el mismo que el de las citas:
///
///   1. **SQLite primero.** [guardarLocal] escribe la fila con
///      `sync_status = 'pending'` y devuelve. La pantalla se puede cerrar,
///      apagar el telefono o perder la red: la fila esta.
///   2. **La nube despues.** `SyncService` lee las filas `pending`, las sube a
///      `clientes/{uid}` y las marca `synced`.
///
/// SharedPreferences sigue escribiendose, pero desde [PerfilClienteController]
/// y SOLO como la copia de lectura rapida que usan el saludo del AppBar y el
/// prellenado del formulario. SQLite es la fuente que se sincroniza; las
/// preferencias son un cache.
///
/// Sobre la identidad local (la PK): es el uid cuando hay sesion de Firebase
/// Auth, y el correo normalizado cuando no hay (login sin red). Ese segundo
/// camino es el motivo de la v12: un cliente que entra por el keystore y edita
/// su perfil sin internet no tiene uid todavia, pero tiene que poder guardarse,
/// y al entrar con red despues tiene que encontrar SU fila y no crear una
/// segunda. Por eso [guardarLocal] busca por uid, despues por el correo de la
/// sesion, y recien entonces por el correo nuevo.
class ClienteRepository {
  ClienteRepository({FirebaseFirestore? firestore}) {
    _firestore = firestore;
  }

  /// Lazy a proposito: construir el repositorio NO debe tocar Firebase. El
  /// perfil local se puede leer y escribir en un dispositivo donde Firebase
  /// ni siquiera esta inicializado, que es justo el caso del login sin red.
  FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ??= FirebaseFirestore.instance;

  static const String _tabla = DatabaseHelper.tablaClientes;

  CollectionReference<Map<String, dynamic>> get _coleccion =>
      _db.collection('clientes');

  // ------------------------------------------------------------------
  // Firestore (nube)
  // ------------------------------------------------------------------

  Future<void> crear({
    required String uid,
    required String nombre,
    required String correo,
    required String telefono,
  }) async {
    final ahora = FieldValue.serverTimestamp();
    await _coleccion.doc(uid).set(<String, Object?>{
      'uid': uid,
      'nombre': nombre.trim(),
      'correo': correo.trim().toLowerCase(),
      'email': correo.trim().toLowerCase(),
      'telefono': telefono.trim(),
      'creado_en': ahora,
      'actualizado_en': ahora,
      'eliminado': false,
    }, SetOptions(merge: true));
  }

  Future<ClientePerfil?> obtener(String uid) async {
    final snapshot = await _coleccion.doc(uid).get();
    debugPrint('🔐 ClienteRepository.obtener: uid=$uid, exists=${snapshot.exists}');
    if (!snapshot.exists) return null;
    final datos = snapshot.data();
    debugPrint('🔐 ClienteRepository.obtener: datos=$datos');
    if (datos == null || datos['eliminado'] == true) return null;
    return ClientePerfil.desdeFirestore(uid, datos);
  }

  Future<bool> existeDocumento(String uid) async =>
      (await _coleccion.doc(uid).get()).exists;

  // ------------------------------------------------------------------
  // SQLite (local primero)
  // ------------------------------------------------------------------

  /// Guarda el perfil localmente y lo deja `pending` para subir.
  ///
  /// Devuelve `false` si no se pudo guardar; nunca lanza: quien decide que
  /// decirle al usuario es [PerfilClienteController.guardarDatos], y un
  /// `INSERT` que revienta por un indice unico no es un error que la pantalla
  /// deba tragar en silencio ni propagar como excepcion.
  ///
  /// [correoIdentidad] es el correo con el que la sesion GUARDO su fila la vez
  /// anterior. Se pasa aparte del [correo] nuevo porque son cosas distintas:
  /// uno busca la fila, el otro la actualiza. Sin este parametro, cambiar el
  /// correo en Editar Perfil dejaria la fila vieja atras y crearia una segunda
  /// con el correo nuevo.
  Future<bool> guardarLocal({
    String? uid,
    String? correoIdentidad,
    required String nombre,
    required String correo,
    required String telefono,
  }) async {
    final correoNuevo = correo.trim().toLowerCase();
    if (correoNuevo.isEmpty) return false;

    try {
      final db = await DatabaseHelper.instance.base;
      final existente = await _buscar(
        db,
        uid: uid,
        correos: <String>[
          if (correoIdentidad != null) correoIdentidad.trim().toLowerCase(),
          correoNuevo,
        ],
      );

      final ahora = ahoraIso();
      // La PK se fija UNA vez por fila y no cambia con cada edicion: re-id en
      // cada guardado romperia el indice unico y obligaria a reescribir el id
      // en todas las citas que apuntaran a este cliente.
      final id =
          existente?.id ??
          (uid != null && uid.trim().isNotEmpty ? uid.trim() : correoNuevo);

      final fila = <String, Object?>{
        DatabaseHelper.colId: id,
        DatabaseHelper.colUid: uid?.trim() ?? '',
        DatabaseHelper.colCorreo: correoNuevo,
        DatabaseHelper.colNombre: nombre.trim(),
        DatabaseHelper.colTelefono: telefono.trim(),
        DatabaseHelper.colActualizadoEn: ahora,
        // Toda edicion de usuario nace `pending`: es la marca que hace que
        // SyncService la suba en el proximo push.
        DatabaseHelper.colSyncStatus: 'pending',
      };

      if (existente == null) {
        fila[DatabaseHelper.colCreadoEn] = ahora;
        await db.insert(_tabla, fila);
      } else {
        await db.update(
          _tabla,
          fila,
          where: '${DatabaseHelper.colId} = ?',
          whereArgs: <Object?>[existente.id],
        );
      }
      return true;
    } catch (e) {
      debugPrint('ClienteRepository: no se pudo guardar local ($e)');
      return false;
    }
  }

  /// El perfil local de esta persona, buscando por uid y luego por correo.
  Future<ClienteLocal?> local({String? uid, String? correo}) async {
    final db = await DatabaseHelper.instance.base;
    return _buscar(
      db,
      uid: uid,
      correos: <String>[
        if (correo != null && correo.trim().isNotEmpty)
          correo.trim().toLowerCase(),
      ],
    );
  }

  /// Las filas todavia no subidas, de la mas vieja a la mas reciente.
  Future<List<ClienteLocal>> pendientesDeSync({int limite = 20}) async {
    final db = await DatabaseHelper.instance.base;
    final filas = await db.query(
      _tabla,
      where: '${DatabaseHelper.colSyncStatus} = ?',
      whereArgs: const ['pending'],
      orderBy: '${DatabaseHelper.colActualizadoEn} ASC',
      limit: limite,
    );
    return filas.map(ClienteLocal.desdeFila).toList(growable: false);
  }

  /// Borra TODAS las filas locales de perfil.
  ///
  /// La tabla `clientes` es la copia de cache del perfil de la persona que usa
  /// este dispositivo: una sola fila en la practica, pero el indice unico por
  /// correo convive con filas creadas sin uid (login sin red) asi que la
  /// limpieza es un `DELETE` completo y no un "borra esta".
  ///
  /// NO toca `clientes/{uid}` en Firestore. Ver `LimpiezaLocal` para el
  /// contexto: es un purge de almacenamiento local, jamas de la nube.
  Future<int> borrarLocalTodo() async {
    final db = await DatabaseHelper.instance.base;
    return db.delete(_tabla);
  }

  /// Marca la fila como subida y le pega el uid de Auth.
  ///
  /// El `WHERE` trae DOS condiciones ademas del id, y eso no es redundancia:
  ///
  /// - `uid = ?` por si mientras se subia el cliente abrio sesion y cambio la
  ///   identidad de la fila; sin eso quedaria una fila `pending` con un uid
  ///   vacio que volveria a subirse para siempre.
  /// - `actualizado_en = ?` por si edito el perfil mientras el push volvia.
  ///   Si no coincide, la UPDATE no toca nada y la fila sigue `pending`, que
  ///   es exactamente lo que queremos: el cambio mas nuevo vuelve a subirse.
  ///
  /// Devuelve `true` si quedo marcada.
  Future<bool> marcarSincronizada({
    required String id,
    required String uid,
    required String actualizadoEn,
  }) async {
    final db = await DatabaseHelper.instance.base;
    final tocadas = await db.update(
      _tabla,
      <String, Object?>{
        DatabaseHelper.colSyncStatus: 'synced',
        DatabaseHelper.colUid: uid,
      },
      where:
          '${DatabaseHelper.colId} = ? '
          'AND ${DatabaseHelper.colActualizadoEn} = ?',
      whereArgs: <Object?>[id, actualizadoEn],
    );
    return tocadas > 0;
  }

  /// Aplica un documento de la nube a la fila local.
  ///
  /// Devuelve `true` si el dato de la nube gano y se escribio, `false` si se
  /// descarto porque hay un cambio local sin subir.
  ///
  /// La regla de conflicto es deliberadamente distinta a la de las citas
  /// (`actualizado_en` mas reciente gana) y la razon es que el perfil es de UNA
  /// sola persona en UN solo dispositivo a la vez. Comparar timestamps aca
  /// produciria el peor escenario posible: entrar sin red, arreglar el telefono
  /// y que un snapshot en latencia del dato viejo lo pisara. Un perfil `pending`
  /// SIEMPRE gana; el push lo sube y la nube queda al dia.
  Future<bool> aplicarDesdeNube({
    required String uid,
    required String nombre,
    required String correo,
    required String telefono,
    required bool eliminado,
    String? actualizadoEn,
  }) async {
    if (uid.trim().isEmpty) return false;
    try {
      final db = await DatabaseHelper.instance.base;
      final existente = await _buscar(
        db,
        uid: uid,
        correos: <String>[correo.trim().toLowerCase()],
      );

      // Local `pending` gana siempre: la fila todavia no ha subido, asi que
      // cualquier cosa que venga de la nube es mas vieja que ella.
      if (existente?.pendienteDeSync ?? false) return false;

      final ahora = ahoraIso();
      final fila = <String, Object?>{
        DatabaseHelper.colId: existente?.id ?? uid.trim(),
        DatabaseHelper.colUid: uid.trim(),
        DatabaseHelper.colCorreo: correo.trim().toLowerCase(),
        DatabaseHelper.colNombre: nombre.trim(),
        DatabaseHelper.colTelefono: telefono.trim(),
        DatabaseHelper.colEliminado: eliminado ? 1 : 0,
        DatabaseHelper.colActualizadoEn:
            (actualizadoEn != null && actualizadoEn.isNotEmpty)
            ? actualizadoEn
            : ahora,
        DatabaseHelper.colSyncStatus: 'synced',
      };

      if (existente == null) {
        fila[DatabaseHelper.colCreadoEn] = ahora;
        await db.insert(_tabla, fila);
      } else {
        await db.update(
          _tabla,
          fila,
          where: '${DatabaseHelper.colId} = ?',
          whereArgs: <Object?>[existente.id],
        );
      }
      return true;
    } catch (e) {
      debugPrint('ClienteRepository: no se pudo aplicar desde la nube ($e)');
      return false;
    }
  }

  /// Busca por uid y despues por cualquiera de [correos].
  ///
  /// El orden importa: el uid es el identificador definitivo de la nube, el
  /// correo es el identificador provisional que se usa cuando todavia no hay
  /// sesion. Si se buscaran solo por correo, un perfil bajado con su uid
  /// dejaria la fila local "sin uid" y habria dos caminos distintos para la
  /// misma persona.
  Future<ClienteLocal?> _buscar(
    DatabaseExecutor db, {
    String? uid,
    required List<String> correos,
  }) async {
    final condiciones = <String>[];
    final argumentos = <Object?>[];

    final uidLimpio = uid?.trim() ?? '';
    if (uidLimpio.isNotEmpty) {
      condiciones.add('${DatabaseHelper.colUid} = ?');
      argumentos.add(uidLimpio);
    }

    final limpios = correos
        .map((c) => c.trim().toLowerCase())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList(growable: false);
    for (final correo in limpios) {
      condiciones.add('${DatabaseHelper.colCorreo} = ? COLLATE NOCASE');
      argumentos.add(correo);
    }

    if (condiciones.isEmpty) return null;

    final filas = await db.query(
      _tabla,
      where: condiciones.join(' OR '),
      whereArgs: argumentos,
      limit: 1,
    );
    return filas.isEmpty ? null : ClienteLocal.desdeFila(filas.first);
  }
}

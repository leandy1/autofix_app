import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/core/connectivity/connectivity_service.dart';
import 'package:autofix/core/utils/borrado_logico.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/cliente/data/cambios_password_repository.dart';
import 'package:autofix/features/cliente/data/cliente_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'dart:async';

/// Servicio de sincronizacion bidireccional entre SQLite local y Firestore.
///
/// ARQUITECTURA:
/// - PUSH (local -> nube): cuando hay conectividad, recorre las citas con
///   `sync_status = 'pending'` y las sube a Firestore. Si la cita tiene
///   `codigo_visible = 'PENDIENTE'`, ejecuta una transaccion en el contador
///   `counters/citas` para obtener el numero secuencial definitivo.
/// - PULL (nube -> local): `onSnapshot` global en la coleccion `citas`.
///   Hace upsert en SQLite: inserta si no existe, actualiza si cambio,
///   respeta el borrado logico (si viene `eliminado_en` lo aplica).
///
/// Ademas de las citas, drenan DOS colas independientes de perfil, las tres
/// en orden y sin que una pueda cortar a las demas:
///
/// - `clientes`: el perfil que `Editar Perfil` guarda offline (v12).
/// - `cambios_password`: metadata de un cambio de contraseña que no pudo
///   aplicarse; el secreto en si nunca pasa por aca ni por Firestore.
///
/// REGLAS DE CONFLICTO (simples v1):
/// - `actualizado_en` gana: el documento con timestamp mas reciente persiste.
/// - Borrado logico: si la nube trae `eliminado_en` y local no lo tiene, se
///   marca borrado localmente; si local tiene borrado y la nube no, gana local.
/// - `codigo_visible`: una vez asignado por la nube, NUNCA se sobrescribe
///   localmente (es inmutable tras confirmacion).
/// - `clientes` es la EXCEPCION a "actualizado_en gana": ahi gana el local
///   `pending`, y ver [_pushPerfilesPendientes] por que.
///
/// CUANDO CORRE (descarga contextual, no global):
/// - `talleres` y `admins` bajan al ABRIR LA APP, solos, desde
///   `DevModeSyncService.sincronizarCatalogos`. Ese catalogo es permanente y
///   no depende de quien entre.
/// - LAS CITAS no: bajan justo DESPUES del login, filtradas por la sesion
///   (taller del admin / dueno del cliente). Ver [start].
/// - El PERFIL cliente baja con su propio listener, solo si hay sesión de
///   cliente. Ver [_iniciarListenerDePerfil].
class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();

  final CitaRepository _repo = CitaRepository.instance;
  final ClienteRepository _repoClientes = ClienteRepository();
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  ConnectivityService? _connectivity;
  ConnectivityService get _connectivityService =>
      _connectivity ??= ConnectivityService();

  /// `true` cuando HAY evidencia de red.
  ///
  /// Lo usa [LimpiezaLocal] (`lib/core/data/limpieza_local.dart`) para decidir
  /// si vale la pena un ultimo push antes de purgar: intentar subir sin red no
  /// falla rapido, se queda esperando al SDK de Firestore y el logout se cuelga.
  bool get hayConexion => _connectivityService.hayConexion;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _snapshotSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _clientesSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isPushing = false;

  /// Con que filtro de SESION corrio el listener que esta vivo.
  ///
  /// Es la pieza que hace que la descarga sea contextual: sin esta firma,
  /// `start()` no podia distinguir "el listener ya esta corriendo" de "el
  /// listener esta corriendo PERO para otro usuario", y en el segundo caso
  /// devolvia temprano dejando al usuario nuevo mirando las citas del
  /// anterior hasta el proximo arranque de la app.
  String? _firmaDelFiltro;

  /// La consulta de citas que le toca a la sesion actual.
  ///
  /// Admin -> solo las de SU `taller_id`. Cliente (o cualquiera sin sesión de
  /// admin) -> solo las que EL creo (`ownerUid`). Es lo que hace que un
  /// administrador no descargue el historial entero de la plataforma y un
  /// cliente no descargue las ordenes de otros talleres.
  String _firmaDeLaSesion() {
    final tallerId = SesionAdmin.instance.tallerId;
    return tallerId != null
        ? 'taller:$tallerId'
        : 'dueno:${_currentUid() ?? ''}';
  }

  Query<Map<String, dynamic>> _consultaDeLaSesion() {
    final tallerId = SesionAdmin.instance.tallerId;
    if (tallerId != null) {
      return _db.collection('citas').where('taller_id', isEqualTo: tallerId);
    }
    return _db.collection('citas').where('ownerUid', isEqualTo: _currentUid());
  }

  /// Inicia la sincronizacion de la sesion actual.
  ///
  /// NO se llama al abrir la app: las citas se bajan justo despues del login
  /// (el `LoginController` la arranca para el admin y el dashboard del cliente
  /// para el cliente), que es cuando existe una sesion que define QUE citas
  /// corresponden. Bajarlas en el arranque significaria traer la consulta de
  /// la sesion anterior, o de nadie.
  ///
  /// El PRIMER evento del `onSnapshot` trae todas las citas que cumplen el
  /// filtro; [_onSnapshot] las upsertea en SQLite. Esa primera tanda ES la
  /// descarga de soporte offline, no hace falta un `get()` aparte.
  ///
  /// Si ya hay un listener vivo con el MISMO filtro no hace nada (idempotente
  /// para que los N dashboards puedan llamarlo). Si el filtro cambio de
  /// usuario o de taller, cancela el anterior y arma el nuevo: ver
  /// [_firmaDelFiltro].
  Future<void> start() async {
    final firma = _firmaDeLaSesion();
    final yaCorre = _snapshotSubscription != null;
    final cambiaLaSesion = yaCorre && _firmaDelFiltro != firma;
    if (yaCorre && !cambiaLaSesion) return;

    if (cambiaLaSesion) {
      // El listener viejo sigue escuchando la consulta del usuario anterior y
      // su snapshot bajaria sus citas a una base que acaba de purgarse.
      await _snapshotSubscription?.cancel();
      await _clientesSubscription?.cancel();
      _snapshotSubscription = null;
      _clientesSubscription = null;
    }

    _snapshotSubscription = _consultaDeLaSesion()
        .snapshots(includeMetadataChanges: true)
        .listen(
          _onSnapshot,
          onError: (e) {
            debugPrint('[SyncService] Error en onSnapshot: $e');
          },
        );
    _firmaDelFiltro = firma;

    await _iniciarListenerDePerfil();

    // La escucha de conectividad se arma UNA vez por `stop()`/`start()`: si
    // se rearmara en cada cambio de sesion habria un suscriptor por usuario
    // y un solo reconecto dispararia N pushes.
    if (!cambiaLaSesion) {
      // Escuchar cambios de conectividad: al reconectar, disparar pushPending()
      _connectivitySubscription = _connectivityService.onConnectivityChanged
          .listen((resultados) {
            final hayConexion =
                resultados.isNotEmpty &&
                !resultados.contains(ConnectivityResult.none);
            if (hayConexion) {
              debugPrint(
                '[SyncService] Conectividad restaurada -> pushPending()',
              );
              pushPending();
            }
          });
    }

    // Primer push inmediato si hay conectividad.
    await pushPending();
  }

  /// Detiene el listener (ej. al cerrar sesion).
  Future<void> stop() async {
    await _snapshotSubscription?.cancel();
    await _clientesSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    _snapshotSubscription = null;
    _clientesSubscription = null;
    _connectivitySubscription = null;
    _firmaDelFiltro = null;
  }

  /// Sube todas las citas locales con `sync_status = 'pending'`.
  ///
  /// El orden importa: primero las que ya tienen `codigo_visible`
  /// (solo actualizacion), luego las que tienen 'PENDIENTE' (transaccion
  /// para obtener numero secuencial).
  Future<void> pushPending() async {
    if (_isPushing) return;
    _isPushing = true;

    try {
      final pendientes = await _repo.obtenerPendientesDeSync();
      for (final cita in pendientes) {
        if (cita.codigoVisible == 'PENDIENTE') {
          await _pushWithTransaction(cita);
        } else {
          await _pushSimple(cita);
        }
      }
    } catch (e) {
      debugPrint('[SyncService] Error en pushPending: $e');
    } finally {
      // Son colas independientes: si Firestore rechazo una cita, igual hay que
      // intentar el perfil y Auth, y viceversa. El secreto de contraseña nunca
      // pasa por Firestore.
      await _drenarColas();
      _isPushing = false;
    }
  }

  /// Corre las dos colas de perfil sin que el fallo de una corte a la otra.
  Future<void> _drenarColas() async {
    await _sinDejarQueCorte('el perfil de cliente', _pushPerfilesPendientes);
    await _sinDejarQueCorte('cambios de contraseña', _drenarCambiosPassword);
  }

  Future<void> _sinDejarQueCorte(
    String que,
    Future<void> Function() correr,
  ) async {
    try {
      await correr();
    } catch (e) {
      debugPrint('[SyncService] Error drenando $que: $e');
    }
  }

  /// Aplica la cola de cambios de contraseña cuando Auth tiene la cuenta
  /// correspondiente abierta.
  ///
  /// La contraseña nunca se manda a Firestore. Se lee del almacenamiento
  /// seguro y se aplica mediante Firebase Auth; si no hay sesión válida, o
  /// Auth rechaza el cambio (por ejemplo, requiere reautenticación), la fila
  /// permanece `pending` para un próximo intento. El correo de metadata evita
  /// tocar la cuenta de admin si el cliente usa el acceso local.
  Future<void> _drenarCambiosPassword() async {
    final cola = CambiosPasswordRepository.instance;
    final pendientes = await cola.pendientes();
    for (final cambio in pendientes) {
      final secreto = await cola.leerContrasena(cambio);
      if (secreto == null || secreto.isEmpty) {
        await cola.descartar(cambio.id);
        continue;
      }

      final usuario = FirebaseAuth.instance.currentUser;
      final correoPendiente = cambio.correoCliente.trim().toLowerCase();
      final correoAuth = usuario?.email?.trim().toLowerCase();
      if (usuario == null ||
          usuario.isAnonymous ||
          correoPendiente.isEmpty ||
          correoAuth != correoPendiente) {
        // Todavía no hay una sesión del dueño de este cambio. Mantenerlo en la
        // cola es crucial: no se puede aplicar a la cuenta Firebase activa
        // solo porque pertenece a otro usuario.
        return;
      }

      try {
        await usuario.updatePassword(secreto);
        await cola.marcarAplicada(cambio);
      } on FirebaseAuthException catch (e) {
        // Incluye `requires-recent-login`: el cambio sigue guardado de forma
        // segura y se volverá a intentar al próximo push/reconexión.
        debugPrint(
          '[SyncService] Cambio de contraseña sigue pendiente (${e.code})',
        );
        return;
      } catch (e) {
        debugPrint('[SyncService] No se pudo aplicar cambio de contraseña: $e');
        return;
      }
    }
  }

  /// Sube las filas `pending` de `clientes` a `clientes/{uid}`.
  ///
  /// ---------------------------------------------------------------
  /// POR QUE ESTA COLA NO USA LA MISMA REGLA DE CONFLICTO QUE LAS CITAS
  /// ---------------------------------------------------------------
  /// Las citas comparan `actualizado_en` y gana el mas reciente. El perfil no,
  /// y el motivo es un escenario concreto: el cliente edita su telefono sin
  /// internet (fila `pending`) y en el mismo arranque un snapshot en latencia
  /// trae el valor viejo de la nube. Con la regla de las citas, el timestamp
  /// del servidor casi siempre gana y el dato que el usuario acaba de escribir
  /// se pierde, sin aviso. Un perfil es de una sola persona en un solo
  /// dispositivo a la vez, asi que ahi manda el local `pending` y el push lo
  /// sube. Ver `ClienteRepository.aplicarDesdeNube`.
  ///
  /// Tampoco sube si no hay sesion de Firebase Auth. No es una limitacion
  /// tecnica sino de seguridad: sin sesion, las reglas de Firestore rechazan
  /// la escritura, y un `set` que va a fallar no gasta un reintento. La fila
  /// queda `pending` y se sube en el proximo push con sesion.
  Future<void> _pushPerfilesPendientes() async {
    final pendientes = await _repoClientes.pendientesDeSync();
    if (pendientes.isEmpty) return;

    final usuario = FirebaseAuth.instance.currentUser;
    if (usuario == null || usuario.isAnonymous) return;
    final uid = usuario.uid;
    final correoAuth = usuario.email?.trim().toLowerCase();

    for (final perfil in pendientes) {
      final correoPerfil = perfil.correo.trim().toLowerCase();
      if (correoAuth == null ||
          correoAuth.isEmpty ||
          correoPerfil != correoAuth) {
        // La fila pertenece a otra cuenta (o a un acceso local sin correo
        // real). Mismo criterio que en _drenarCambiosPassword: subirla a la
        // cuenta activa seria escribir el perfil de una persona en la cuenta
        // de otra.
        continue;
      }

      await _db.collection('clientes').doc(uid).set(<String, Object?>{
        'uid': uid,
        'nombre': perfil.nombre,
        'correo': correoPerfil,
        // Duplicado a proposito: `crear` escribe las DOS claves y hay
        // escritorios/console que solo leen una.
        'email': correoPerfil,
        'telefono': perfil.telefono,
        'eliminado': perfil.eliminado,
        if (perfil.creadoEn.isNotEmpty) 'creado_en': perfil.creadoEn,
        'actualizado_en': perfil.actualizadoEn,
        'sync_status': 'synced',
      }, SetOptions(merge: true));

      final quedo = await _repoClientes.marcarSincronizada(
        id: perfil.id,
        uid: uid,
        actualizadoEn: perfil.actualizadoEn,
      );
      if (!quedo) {
        // El usuario edito el perfil mientras este push volvia. La fila sigue
        // `pending` a proposito y volvera a subirse en el proximo push, con el
        // dato nuevo.
        debugPrint(
          '[SyncService] Perfil editado durante el push; queda pendiente',
        );
      }
    }
  }

  /// Sube una cita que YA tiene codigo_visible (solo update/merge).
  Future<void> _pushSimple(Cita cita) async {
    final ref = _db.collection('citas').doc(cita.id);
    final data = _citaToMap(cita);
    _preservarDueno(data, (await ref.get()).data());
    await ref.set(data, SetOptions(merge: true));
    await _repo.marcarSincronizada(cita.id!);
  }

  /// S2: no pisar el `ownerUid` que el documento ya tenga en la nube.
  ///
  /// `_citaToMap` sella `ownerUid = _currentUid()` sin mirar nada mas. Eso es
  /// correcto en el ALTA (el creador es el dueno), pero en un push de un
  /// SEGUNDO dispositivo reescribia al dueno original: p. ej. si el admin
  /// edita una cita que agendo el cliente, la cita pasaba a tener el uid del
  /// admin, salia del filtro `where('ownerUid', ...)` con el que el cliente
  /// consulta y desaparecia de su app. El dueno lo pone quien crea la cita y
  /// nadie mas lo cambia; el resto de campos se actualiza con normalidad.
  void _preservarDueno(
    Map<String, Object?> data,
    Map<String, dynamic>? documentoPrevio,
  ) {
    final duenoPrevio = documentoPrevio?['ownerUid'] as String?;
    if (duenoPrevio != null) data['ownerUid'] = duenoPrevio;
  }

  /// Sube una cita con 'PENDIENTE' usando transaccion en contador.
  ///
  /// 1. Lee `counters/citas` (crea si no existe).
  /// 2. Incrementa `nextNumber`.
  /// 3. Genera `CITA-XXXX` con zero-padding 4.
  /// 4. Escribe el documento de la cita con el nuevo codigo.
  /// 5. Actualiza local via `asignarCodigoVisible` y marca sincronizada.
  Future<void> _pushWithTransaction(Cita cita) async {
    final counterRef = _db.collection('counters').doc('citas');

    await _db.runTransaction((tx) async {
      final counterSnap = await tx.get(counterRef);
      int next = 1;
      if (counterSnap.exists) {
        next = (counterSnap.data()?['nextNumber'] as int?) ?? 1;
      }
      final nuevo = next + 1;
      final codigo = 'CITA-${next.toString().padLeft(4, '0')}';

      tx.set(counterRef, {'nextNumber': nuevo}, SetOptions(merge: true));

      final ref = _db.collection('citas').doc(cita.id);
      final data = _citaToMap(cita)..['codigo_visible'] = codigo;
      // Misma proteccion que en _pushSimple: todas las lecturas de la
      // transaccion van ANTES de los writes, asi que aca tambien se lee
      // primero el documento para no pisar su dueno.
      _preservarDueno(data, (await tx.get(ref)).data());
      tx.set(ref, data);
    });

    // La nube ya escribio el codigo; el onSnapshot lo bajara y actualizara
    // local via _onSnapshot. Aqui solo marcamos pendiente de sync resuelto.
    await _repo.marcarSincronizada(cita.id!);
  }

  /// Callback del `onSnapshot` global. Hace upsert en SQLite.
  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) async {
    for (final change in snap.docChanges) {
      try {
        final doc = change.doc;
        final data = doc.data();
        if (data == null) continue;

        // Ignora documentos de otros usuarios (solo en modo anonimo).
        // Cuando hay sesion de admin el query ya filtra por taller_id.
        if (!SesionAdmin.instance.activa) {
          final ownerUid = data['ownerUid'] as String?;
          if (ownerUid != _currentUid()) continue;
        }

        if (change.type == DocumentChangeType.removed) {
          // Firestore no suele borrar (soft delete en app), pero por si acaso:
          await _repo.borrar(doc.id);
          continue;
        }

        final cita = _mapToCita(doc.id, data);

        // Conflicto: gana el `actualizado_en` mas reciente.
        // Las fechas en Firestore viajan como String ISO (porque toMap() usa
        // aIsoUtc). Leemos directamente el string para comparar.
        final local = await _repo.obtenerPorId(doc.id);
        if (local != null) {
          final localMs = local.actualizadoEn?.millisecondsSinceEpoch ?? 0;
          final remoteStr = data['actualizado_en'] as String?;
          final remoteMs = remoteStr != null
              ? DateTime.tryParse(remoteStr)?.millisecondsSinceEpoch ?? 0
              : 0;
          if (localMs > remoteMs) {
            // Local mas reciente: re-subira en el proximo push.
            continue;
          }
        }

        // Usa fusionarDesdeNube en vez de actualizar() para NO marcar
        // sync_status = 'pending': la nube ya tiene este dato, no hay que volver
        // a subirlo y no queremos crear un loop push -> snapshot -> push.
        await _repo.fusionarDesdeNube(cita);
        await _repo.marcarSincronizada(doc.id);
      } catch (e) {
        debugPrint('[SyncService] Error procesando doc ${change.doc.id}: $e');
      }
    }
  }

  /// Escucha `clientes/{uid}` del cliente con sesion activa.
  ///
  /// ---------------------------------------------------------------
  /// POR QUE UN DOCUMENTO Y NO UNA COLECCION COMO LAS CITAS
  /// ---------------------------------------------------------------
  /// El perfil es UNA fila por persona, y el uid ya es el id del documento: un
  /// `where('uid', isEqualTo: ...)` sobre la coleccion seria la misma consulta
  /// con un `listen` mas caro y un codigo mas largo.
  ///
  /// No arranca en dos casos, y ninguno de los dos es un error:
  ///
  /// - **Sin uid de Auth.** El login sin red abre el dashboard con la sesión
  ///   local pero sin sesion en Firebase, y un snapshot de un documento que
  ///   todavia no puede existir no aporta nada. El push de esta misma cola
  ///   tampoco corre en ese caso, asi que no habria nada que bajar.
  /// - **Sin sesión de cliente.** Entra un administrador: no tiene perfil de
  ///   cliente, y abrir un listener solo para que traiga `exists == false`
  ///   seria un roundtrip por arranque.
  Future<void> _iniciarListenerDePerfil() async {
    if (_clientesSubscription != null) return;
    if (!SesionCliente.instance.activa) return;

    final uid = _currentUid();
    if (uid == null || uid.isEmpty) return;

    _clientesSubscription = _db
        .collection('clientes')
        .doc(uid)
        .snapshots()
        .listen(
          _onSnapshotDePerfil,
          onError: (e) {
            debugPrint('[SyncService] Error en el snapshot del perfil: $e');
          },
        );
  }

  /// Baja `clientes/{uid}` a SQLite y, si cambio, a la sesión en memoria.
  Future<void> _onSnapshotDePerfil(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) async {
    try {
      // `exists == false` se ignora a proposito. Puede significar "nadie creo
      // el documento" (el push local todavia no corrio) o "lo borraron desde
      // la consola"; en los DOS casos borrar la copia local significaria tirar
      // el unico perfil que este dispositivo tiene, y no hay pantalla de
      // "eliminar mi cuenta" que justifique eso. Bajar algo vacio no es una
      // operacion con una respuesta segura todavia.
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;

      final aplicado = await _repoClientes.aplicarDesdeNube(
        uid: snap.id,
        nombre: data['nombre'] as String? ?? '',
        correo: data['correo'] as String? ?? data['email'] as String? ?? '',
        telefono: data['telefono'] as String? ?? '',
        eliminado: data['eliminado'] == true,
        actualizadoEn: _isoDe(data['actualizado_en']),
      );

      // Solo si la nube gano. Si gano el local, la sesión ya muestra el dato
      // nuevo y escribirla con el viejo seria regresar la edicion del usuario.
      if (aplicado) await _refrescarSesionLocal(data);
    } catch (e) {
      debugPrint('[SyncService] Error bajando el perfil: $e');
    }
  }

  /// Propaga a `SesionCliente` un perfil bajado de la nube cuando ES el de la
  /// sesión.
  ///
  /// Sin esto, la nube actualizaria SQLite y el saludo del AppBar ("¡Hola,
  /// Maria!") seguiria mostrando el nombre viejo hasta el proximo arranque: la
  /// UI no lee `clientes`, lee la sesión. El filtro por correo es lo que
  /// impide que un snapshot escriba en la sesión de otra persona.
  Future<void> _refrescarSesionLocal(Map<String, dynamic> data) async {
    final correoSesion = SesionCliente.instance.correo?.trim().toLowerCase();
    final correoNube =
        (data['correo'] as String? ?? data['email'] as String? ?? '')
            .trim()
            .toLowerCase();
    if (correoSesion == null ||
        correoSesion.isEmpty ||
        correoSesion != correoNube) {
      return;
    }

    await SesionCliente.instance.guardarPerfil(
      nombre: data['nombre'] as String? ?? '',
      correo: correoNube,
      telefono: data['telefono'] as String? ?? '',
    );
  }

  /// `actualizado_en` de un documento, en el mismo formato ISO que SQLite.
  ///
  /// `ClienteRepository.crear` lo escribe con `FieldValue.serverTimestamp()`,
  /// asi que ahi llega como `Timestamp`; lo que sube [_pushPerfilesPendientes]
  /// lo escribe como String ISO. Las DOS formas se aceptan, igual que en
  /// [_mapToCita], porque un documento puede haber nacido por cualquiera de
  /// los dos caminos y el dia que aparezca el tercero tendra su propio caso.
  String? _isoDe(Object? valor) {
    if (valor == null) return null;
    if (valor is String) return valor;
    if (valor is Timestamp) return valor.toDate().toUtc().toIso8601String();
    return null;
  }

  /// Convierte `Cita` a mapa para Firestore.
  Map<String, Object?> _citaToMap(Cita cita) {
    final map = cita.toMap();
    map['ownerUid'] = _currentUid();
    map['sync_status'] = 'synced';
    return map;
  }

  /// Convierte documento Firestore a `Cita`.
  /// Las fechas llegan como String ISO (aIsoUtc), no como Timestamp.
  Cita _mapToCita(String id, Map<String, dynamic> data) {
    DateTime? _parseDate(Object? val) {
      if (val == null) return null;
      if (val is String) return DateTime.tryParse(val)?.toUtc();
      // Por si algun documento antiguo tiene Timestamp real de Firestore:
      if (val is Timestamp) return val.toDate().toUtc();
      return null;
    }

    return Cita(
      id: id,
      codigoVisible: data['codigo_visible'] as String? ?? 'PENDIENTE',
      cliente: data['cliente'] as String? ?? '',
      correoCliente: data['correo_cliente'] as String? ?? '',
      telefono: data['telefono'] as String? ?? '',
      vehiculo: data['vehiculo'] as String? ?? '',
      marca: data['marca'] as String? ?? '',
      modelo: data['modelo'] as String? ?? '',
      anio: (data['anio'] as num?)?.toInt() ?? 0,
      placa: data['placa'] as String? ?? '',
      servicios: Cita.leerServicios(data['servicios']),
      tecnico: data['tecnico'] as String? ?? '',
      descripcion: data['descripcion'] as String? ?? '',
      fechaCita: _parseDate(data['fecha_cita']) ?? DateTime.now().toUtc(),
      estado: _estadoFromString(data['estado'] as String? ?? 'pendiente'),
      tallerId: data['taller_id'] as String?,
      creadoEn: _parseDate(data['creado_en']),
      actualizadoEn: _parseDate(data['actualizado_en']),
      total: (data['total'] as num?)?.toInt() ?? 0,
      trazabilidad: Trazabilidad(
        eliminadoEn: _parseDate(data['eliminado_en']),
        eliminadoPor: data['eliminado_por'] as String?,
        restauradoEn: _parseDate(data['restaurado_en']),
      ),
      syncStatus: (data['sync_status'] as String?) ?? 'synced',
    );
  }

  String? _currentUid() => FirebaseAuth.instance.currentUser?.uid;

  EstadoCita _estadoFromString(String s) => EstadoCita.values.firstWhere(
    (e) => e.name == s,
    orElse: () => EstadoCita.pendiente,
  );
}

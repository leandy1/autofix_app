import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/core/connectivity/connectivity_service.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/utils/borrado_logico.dart';
import 'package:autofix/core/utils/reloj.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/citas/models/codigo_de_cita.dart';
import 'package:autofix/features/cliente/data/cambios_password_repository.dart';
import 'package:autofix/features/cliente/data/cliente_repository.dart';
import 'package:autofix/features/cliente/data/vehiculo_repository.dart';
import 'package:autofix/features/cliente/models/vehiculo.dart';
import 'package:autofix/features/sync/catalogo_taller_sync_repository.dart';
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
/// - `vehiculos`: cola propia `pending` -> `synced` y listener contextual de la
///   colección Firestore `vehiculos`, limitado al UID/correo del cliente.
///
/// Además de las citas, drena colas independientes de perfil y catálogos sin
/// que el fallo de una pueda impedir que se intenten las otras:
///
/// - `clientes`: el perfil que `Editar Perfil` guarda offline (v12).
/// - `vehiculos`: vehículos registrados por el cliente, incluidos tombstones.
/// - `cambios_password`: metadata de un cambio de contraseña que no pudo
///   aplicarse; el secreto en si nunca pasa por aca ni por Firestore.
/// - `tecnicos`, `servicios`, `marcas` y `grupos_servicio`: datos del taller,
///   filtrados por `taller_id`; sus tombstones se publican como updates.
///
/// REGLAS DE CONFLICTO (simples v1):
/// - `actualizado_en` gana: el documento con timestamp mas reciente persiste.
/// - Borrado lógico de catálogos: el tombstone remoto prevalece ante una copia
///   local viva y también se comprueba antes de subir una edición pendiente.
/// - `codigo_visible`: una vez asignado por la nube, NUNCA se sobrescribe
///   localmente (es inmutable tras confirmacion).
/// - `clientes` es la EXCEPCION a "actualizado_en gana": ahi gana el local
///   `pending`, y ver [_pushPerfilesPendientes] por que.
///
/// CUANDO CORRE (descarga contextual, no global):
/// - `talleres` y `admins` bajan al ABRIR LA APP, solos, desde
///   `DevModeSyncService.sincronizarCatalogos`. Ese catalogo es permanente y
///   no depende de quien entre.
/// - LAS CITAS no: bajan justo DESPUES del login, filtradas por la sesión
///   (taller del admin / owner UID o correo del cliente). Ver [start].
/// - Los catálogos operativos bajan con listener filtrado por `taller_id` al
///   iniciar sesión Admin o al seleccionar taller en el flujo cliente.
/// - El PERFIL cliente baja con su propio listener, solo si hay sesión de
///   cliente. Ver [_iniciarListenerDePerfil].
class SyncService extends ChangeNotifier {
  SyncService._();

  static final SyncService instance = SyncService._();

  final CitaRepository _repo = CitaRepository.instance;
  final ClienteRepository _repoClientes = ClienteRepository();
  final VehiculoRepository _repoVehiculos = VehiculoRepository.instance;
  final CatalogoTallerSyncRepository _repoCatalogos =
      CatalogoTallerSyncRepository();
  static const List<CatalogoTallerSyncDefinition> _catalogosTaller =
      <CatalogoTallerSyncDefinition>[
        CatalogoTallerSyncDefinition(tabla: 'tecnicos', coleccion: 'tecnicos'),
        CatalogoTallerSyncDefinition(
          tabla: 'tipos_servicio',
          coleccion: 'servicios',
          tienePrecio: true,
        ),
        CatalogoTallerSyncDefinition(tabla: 'marcas', coleccion: 'marcas'),
        CatalogoTallerSyncDefinition(
          tabla: 'grupos_servicio',
          coleccion: 'grupos_servicio',
        ),
      ];
  FirebaseFirestore? _firestoreOverride;
  String? _uidOverride;
  FirebaseFirestore get _db => _firestoreOverride ?? FirebaseFirestore.instance;
  ConnectivityService? _connectivity;
  ConnectivityService get _connectivityService =>
      _connectivity ??= ConnectivityService();

  /// `true` cuando HAY evidencia de red.
  ///
  /// Lo usa [LimpiezaLocal] (`lib/core/data/limpieza_local.dart`) para decidir
  /// si vale la pena un ultimo push antes de purgar: intentar subir sin red no
  /// falla rapido, se queda esperando al SDK de Firestore y el logout se cuelga.
  bool get hayConexion => _connectivityService.hayConexion;

  @visibleForTesting
  void usarFirestoreParaPruebas(FirebaseFirestore? firestore) {
    _firestoreOverride = firestore;
  }

  @visibleForTesting
  void usarAuthUidParaPruebas(String? uid) {
    _uidOverride = uid;
  }

  Future<void> Function(Cita cita)? _hookAntesDePushParaPruebas;

  @visibleForTesting
  void usarHookAntesDePushParaPruebas(Future<void> Function(Cita cita)? hook) {
    _hookAntesDePushParaPruebas = hook;
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _snapshotSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _snapshotCorreoSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _clientesSubscription;
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _vehiculosSubscriptions =
      <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _catalogosAdminSubscriptions =
      <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _catalogosClienteSubscriptions =
      <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
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
  String? _tallerCatalogosAdmin;
  String? _tallerCatalogosCliente;

  /// Filtros Firestore de citas que le tocan a la sesión actual.
  ///
  /// Admin -> solo las de SU `taller_id`. Cliente -> las que creó (`ownerUid`)
  /// y las que el taller vinculó a su correo (`correo_cliente`).
  String _firmaDeLaSesion() {
    final tallerId = SesionAdmin.instance.tallerId;
    if (tallerId != null) return 'taller:$tallerId';
    final correo = SesionCliente.instance.correo?.trim().toLowerCase() ?? '';
    return 'dueno:${_currentUid() ?? ''}|correo:$correo';
  }

  List<Query<Map<String, dynamic>>> _consultasDeLaSesion() {
    final tallerId = SesionAdmin.instance.tallerId;
    if (tallerId != null) {
      return <Query<Map<String, dynamic>>>[
        _db.collection('citas').where('taller_id', isEqualTo: tallerId),
      ];
    }
    final uid = _currentUid();
    final correo = SesionCliente.instance.correo?.trim().toLowerCase() ?? '';
    return <Query<Map<String, dynamic>>>[
      if (uid != null && uid.isNotEmpty)
        _db.collection('citas').where('ownerUid', isEqualTo: uid),
      if (correo.isNotEmpty)
        _db.collection('citas').where('correo_cliente', isEqualTo: correo),
    ];
  }

  List<Query<Map<String, dynamic>>> _consultasVehiculosDelCliente() {
    if (!SesionCliente.instance.activa || SesionAdmin.instance.activa) {
      return const <Query<Map<String, dynamic>>>[];
    }
    final uid = _currentUid();
    final correo = SesionCliente.instance.correo?.trim().toLowerCase() ?? '';
    return <Query<Map<String, dynamic>>>[
      if (uid != null && uid.isNotEmpty)
        _db.collection('vehiculos').where('ownerUid', isEqualTo: uid),
      if (correo.isNotEmpty)
        _db.collection('vehiculos').where('correo_cliente', isEqualTo: correo),
    ];
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
    final yaCorre = _firmaDelFiltro != null;
    final cambiaLaSesion = yaCorre && _firmaDelFiltro != firma;
    if (yaCorre && !cambiaLaSesion) return;

    if (cambiaLaSesion) {
      // El listener viejo sigue escuchando la consulta del usuario anterior y
      // su snapshot bajaria sus citas a una base que acaba de purgarse.
      await _snapshotSubscription?.cancel();
      await _snapshotCorreoSubscription?.cancel();
      await _clientesSubscription?.cancel();
      await _cancelarSuscripcionesVehiculos();
      await _cancelarSuscripcionesCatalogos(_catalogosAdminSubscriptions);
      await _cancelarSuscripcionesCatalogos(_catalogosClienteSubscriptions);
      _snapshotSubscription = null;
      _snapshotCorreoSubscription = null;
      _clientesSubscription = null;
    }

    final consultas = _consultasDeLaSesion();
    if (consultas.isNotEmpty) {
      _snapshotSubscription = consultas.first
          .snapshots(includeMetadataChanges: true)
          .listen(
            _onSnapshot,
            onError: (e) {
              debugPrint('[SyncService] Error en onSnapshot: $e');
            },
          );
    }
    if (consultas.length > 1) {
      _snapshotCorreoSubscription = consultas[1]
          .snapshots(includeMetadataChanges: true)
          .listen(
            _onSnapshot,
            onError: (e) {
              debugPrint('[SyncService] Error en onSnapshot por correo: $e');
            },
          );
    }
    for (final consulta in _consultasVehiculosDelCliente()) {
      _vehiculosSubscriptions.add(
        consulta.snapshots().listen(
          _onSnapshotVehiculos,
          onError: (Object error) {
            debugPrint('[SyncService] Error escuchando vehículos: $error');
          },
        ),
      );
    }
    _firmaDelFiltro = firma;

    final tallerAdmin = SesionAdmin.instance.tallerId;
    if (tallerAdmin != null) {
      await sincronizarCatalogosDeTaller(tallerAdmin);
    }

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
    await _snapshotCorreoSubscription?.cancel();
    await _clientesSubscription?.cancel();
    await _cancelarSuscripcionesVehiculos();
    await _connectivitySubscription?.cancel();
    await _cancelarSuscripcionesCatalogos(_catalogosAdminSubscriptions);
    await _cancelarSuscripcionesCatalogos(_catalogosClienteSubscriptions);
    _snapshotSubscription = null;
    _snapshotCorreoSubscription = null;
    _clientesSubscription = null;
    _connectivitySubscription = null;
    _firmaDelFiltro = null;
    _tallerCatalogosAdmin = null;
    _tallerCatalogosCliente = null;
  }

  /// Escucha los catálogos locales del taller elegido por un cliente.
  ///
  /// El administrador llama a esta misma operación desde [start] y queda
  /// limitado a su taller de sesión. Un cliente solo puede abrir el listener
  /// cuando tiene sesión autenticada y se limita al taller seleccionado.
  Future<void> sincronizarCatalogosDeTaller(String tallerId) async {
    final esAdmin = SesionAdmin.instance.tallerId == tallerId;
    final esCliente =
        !SesionAdmin.instance.activa && SesionCliente.instance.activa;
    if (!esAdmin && !esCliente) return;

    await DatabaseHelper.instance.asegurarCatalogosParaTaller(tallerId);

    final suscripciones = esAdmin
        ? _catalogosAdminSubscriptions
        : _catalogosClienteSubscriptions;
    final actual = esAdmin ? _tallerCatalogosAdmin : _tallerCatalogosCliente;
    if (actual == tallerId && suscripciones.length == _catalogosTaller.length) {
      return;
    }

    await _cancelarSuscripcionesCatalogos(suscripciones);
    if (esAdmin) {
      _tallerCatalogosAdmin = tallerId;
    } else {
      _tallerCatalogosCliente = tallerId;
    }

    for (final catalogo in _catalogosTaller) {
      final consulta = _db
          .collection(catalogo.coleccion)
          .where('taller_id', isEqualTo: tallerId);
      suscripciones.add(
        consulta.snapshots().listen(
          (snapshot) => _onSnapshotCatalogo(
            snapshot,
            catalogo: catalogo,
            tallerId: tallerId,
          ),
          onError: (Object error) {
            debugPrint(
              '[SyncService] Error escuchando ${catalogo.coleccion} '
              'del taller $tallerId: $error',
            );
          },
        ),
      );
    }
  }

  Future<void> _cancelarSuscripcionesCatalogos(
    List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> suscripciones,
  ) async {
    for (final suscripcion in suscripciones) {
      await suscripcion.cancel();
    }
    suscripciones.clear();
  }

  Future<void> _cancelarSuscripcionesVehiculos() async {
    for (final suscripcion in _vehiculosSubscriptions) {
      await suscripcion.cancel();
    }
    _vehiculosSubscriptions.clear();
  }

  Future<void> _onSnapshotCatalogo(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required CatalogoTallerSyncDefinition catalogo,
    required String tallerId,
  }) async {
    var huboCambios = false;
    for (final cambio in snapshot.docChanges) {
      // Un removed de una consulta significa que ya no cumple el filtro, o que
      // se borró desde consola. Ninguno de esos casos autoriza un DELETE local:
      // las bajas oficiales llegan como un documento con `eliminado_en`.
      if (cambio.type == DocumentChangeType.removed) continue;
      final datos = cambio.doc.data();
      if (datos == null) continue;
      if (datos['taller_id'] != tallerId) continue;
      try {
        huboCambios =
            await _repoCatalogos.aplicarDesdeNube(
              definition: catalogo,
              id: cambio.doc.id,
              tallerId: tallerId,
              data: datos,
            ) ||
            huboCambios;
      } catch (error) {
        // Una fila mal formada no debe impedir que se apliquen las demás.
        debugPrint(
          '[SyncService] No se pudo aplicar ${catalogo.coleccion}/'
          '${cambio.doc.id}: $error',
        );
      }
    }
    if (huboCambios) notifyListeners();
  }

  /// Sube la cola `pending` y reintenta fallos anteriores sin dejar que la
  /// cola de errores ocupe los cupos de citas nuevas.
  ///
  /// El orden importa: primero las que ya tienen `codigo_visible`
  /// (solo actualizacion), luego las que tienen 'PENDIENTE' (transaccion
  /// para obtener numero secuencial).
  Future<void> pushPending() async {
    if (_isPushing) return;
    _isPushing = true;

    try {
      final pendientes = await _repo.obtenerPendientesDeSync();
      final fallidas = await _repo.obtenerFallidasDeSync();
      // Capturamos fallidas antes de procesar el lote, para no reintentar dos
      // veces en un mismo ciclo una cita que acaba de fallar.
      for (final cita in [...pendientes, ...fallidas]) {
        final id = cita.id;
        try {
          if (id == null) {
            throw StateError('La cita pendiente no tiene id local.');
          }
          if (cita.syncStatus == 'error') {
            await _repo.marcarPendienteSync(id);
          }
          final normalizada = _normalizarCitaLegacy(cita);
          await _hookAntesDePushParaPruebas?.call(normalizada);
          if (normalizada.codigoVisible == 'PENDIENTE') {
            await _pushWithTransaction(normalizada);
          } else {
            await _pushSimple(normalizada);
          }
        } on Object catch (error) {
          if (id != null) {
            try {
              await _repo.marcarErrorSync(id);
            } catch (errorAlMarcar) {
              debugPrint(
                '[SyncService] No se pudo marcar cita $id con error: '
                '$errorAlMarcar',
              );
            }
          }
          // El error de una fila no aborta el lote: el resto de las citas puede
          // sincronizarse. Las fallidas quedan en estado `error` para la
          // siguiente tanda de reintentos.
          debugPrint('[SyncService] Falló el push de cita $id: $error');
          notifyListeners();
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

  /// Completa valores de compatibilidad antes de serializar citas antiguas.
  /// Las columnas nuevas pueden estar vacías en SQLite, pero Firestore recibe
  /// siempre strings/listas con forma válida y `correo_cliente` normalizado.
  Cita _normalizarCitaLegacy(Cita cita) {
    final vehiculoExistente = cita.vehiculo.trim();
    final resumenVehiculo = [
      cita.marca.trim(),
      cita.modelo.trim(),
      if (cita.anio > 0) cita.anio.toString(),
    ].where((parte) => parte.isNotEmpty).join(' ');

    return cita.copyWith(
      cliente: cita.cliente.trim().isEmpty
          ? 'Cliente sin nombre'
          : cita.cliente.trim(),
      telefono: cita.telefono.trim(),
      correoCliente: cita.correoCliente.trim().toLowerCase(),
      vehiculo: vehiculoExistente.isEmpty
          ? (resumenVehiculo.isEmpty
                ? 'Vehículo no especificado'
                : resumenVehiculo)
          : vehiculoExistente,
      marca: cita.marca.trim(),
      modelo: cita.modelo.trim(),
      placa: cita.placa.trim().toUpperCase(),
      servicios: cita.servicios,
      tecnico: cita.tecnico.trim(),
      descripcion: cita.descripcion.trim(),
    );
  }

  /// Corre las dos colas de perfil sin que el fallo de una corte a la otra.
  Future<void> _drenarColas() async {
    await _sinDejarQueCorte('vehículos del cliente', _pushVehiculosPendientes);
    await _sinDejarQueCorte('el perfil de cliente', _pushPerfilesPendientes);
    await _sinDejarQueCorte('cambios de contraseña', _drenarCambiosPassword);
    await _sinDejarQueCorte('catálogos del taller', _pushCatalogosPendientes);
  }

  /// Sube vehículos pendientes del cliente autenticado y publica bajas como
  /// tombstones. La identidad del propietario no se toma de una fila arbitraria:
  /// solo se procesa el correo de la sesión Firebase activa.
  Future<void> _pushVehiculosPendientes() async {
    if (!SesionCliente.instance.activa || SesionAdmin.instance.activa) return;
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) return;

    final correoSesion =
        SesionCliente.instance.correo?.trim().toLowerCase() ?? '';
    if (correoSesion.isEmpty) return;
    if (_uidOverride == null) {
      final usuario = FirebaseAuth.instance.currentUser;
      if (usuario == null ||
          usuario.isAnonymous ||
          usuario.email?.trim().toLowerCase() != correoSesion) {
        return;
      }
    }

    final pendientes = await _repoVehiculos.pendientesDeSync(correoSesion);
    for (final vehiculo in pendientes) {
      final id = vehiculo.id;
      final actualizadoEn = vehiculo.actualizadoEn;
      if (id == null || actualizadoEn == null) continue;
      final referencia = _db.collection('vehiculos').doc(id);
      final fechaActualizacion = aIsoUtc(actualizadoEn);
      final data = <String, Object?>{
        'id': id,
        'cliente_id': correoSesion,
        'correo_cliente': correoSesion,
        'ownerUid': uid,
        'marca': vehiculo.marca,
        'modelo': vehiculo.modelo,
        'anio': vehiculo.anio,
        'placa': vehiculo.placa,
        'activo': vehiculo.activo,
        'creado_en': aIsoUtc(vehiculo.creadoEn ?? actualizadoEn),
        'actualizado_en': fechaActualizacion,
        'eliminado_en': vehiculo.eliminadoEn == null
            ? null
            : aIsoUtc(vehiculo.eliminadoEn!),
        'sync_status': 'synced',
      };

      try {
        final bajaRemota = await _db.runTransaction<Map<String, dynamic>?>((
          transaccion,
        ) async {
          final remoto = await transaccion.get(referencia);
          final datosRemotos = remoto.data();
          if (datosRemotos?['eliminado_en'] != null &&
              vehiculo.eliminadoEn == null) {
            return datosRemotos;
          }
          transaccion.set(referencia, data, SetOptions(merge: true));
          return null;
        });

        if (bajaRemota != null) {
          await _repoVehiculos.aplicarDesdeNube(
            Vehiculo.fromMap(<String, Object?>{
              ...bajaRemota,
              'id': id,
              'correo_cliente': bajaRemota['correo_cliente'] ?? correoSesion,
            }),
            prevaleceBaja: true,
          );
          notifyListeners();
          continue;
        }

        final marcado = await _repoVehiculos.marcarSincronizado(
          id: id,
          actualizadoEn: fechaActualizacion,
        );
        if (marcado) notifyListeners();
      } catch (error) {
        // La fila queda pending y se reintentará en el próximo ciclo.
        debugPrint('[SyncService] Falló el push del vehículo $id: $error');
      }
    }
  }

  Future<void> _onSnapshotVehiculos(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    var huboCambios = false;
    final uid = _currentUid();
    final correo = SesionCliente.instance.correo?.trim().toLowerCase() ?? '';
    for (final cambio in snapshot.docChanges) {
      // El borrado remoto oficial siempre es un tombstone. Un removed no debe
      // convertirse en un DELETE local ni resucitar el vehículo al reconectar.
      if (cambio.type == DocumentChangeType.removed) continue;
      final data = cambio.doc.data();
      if (data == null) continue;
      final propietarioUid = data['ownerUid'] as String?;
      final propietarioCorreo = (data['correo_cliente'] as String? ?? '')
          .trim()
          .toLowerCase();
      if ((uid == null || propietarioUid != uid) &&
          (correo.isEmpty || propietarioCorreo != correo)) {
        continue;
      }

      try {
        final vehiculo = Vehiculo.fromMap(<String, Object?>{
          ...data,
          'id': cambio.doc.id,
          'correo_cliente': propietarioCorreo,
        });
        huboCambios =
            await _repoVehiculos.aplicarDesdeNube(vehiculo) || huboCambios;
      } catch (error) {
        debugPrint(
          '[SyncService] Error aplicando vehículo ${cambio.doc.id}: $error',
        );
      }
    }
    if (huboCambios) notifyListeners();
  }

  /// Publica solo los catálogos pendientes del taller Admin autenticado.
  ///
  /// El tombstone viaja como cualquier otro campo del documento: no se omiten
  /// filas con `eliminado_en` y Firestore no recibe nunca un borrado físico.
  Future<void> _pushCatalogosPendientes() async {
    final tallerId = SesionAdmin.instance.tallerId;
    if (tallerId == null || tallerId.isEmpty) return;

    for (final catalogo in _catalogosTaller) {
      late final List<Map<String, Object?>> pendientes;
      try {
        pendientes = await _repoCatalogos.pendientes(catalogo, tallerId);
      } catch (error) {
        debugPrint(
          '[SyncService] No se pudo leer la cola de ${catalogo.coleccion}: '
          '$error',
        );
        continue;
      }
      for (final fila in pendientes) {
        final id = fila[DatabaseHelper.colId] as String?;
        final actualizadoEn = fila[DatabaseHelper.colActualizadoEn] as String?;
        if (id == null || actualizadoEn == null) continue;

        try {
          final referencia = _db.collection(catalogo.coleccion).doc(id);
          final bajaLocal = fila[DatabaseHelper.colEliminadoEn];
          final bajaRemota = await _db.runTransaction<Map<String, dynamic>?>((
            transaccion,
          ) async {
            final remoto = await transaccion.get(referencia);
            final datosRemotos = remoto.data();
            if (datosRemotos != null &&
                datosRemotos[DatabaseHelper.colEliminadoEn] != null &&
                bajaLocal == null) {
              return datosRemotos;
            }
            transaccion.set(
              referencia,
              _repoCatalogos.aFirestore(catalogo, fila),
            );
            return null;
          });
          if (bajaRemota != null) {
            // Una fila borrada en otro dispositivo no se puede resucitar con
            // una edición local que llevaba tiempo offline. La lectura y el
            // posible push ocurrieron en una transacción para cerrar la carrera.
            final aplicado = await _repoCatalogos.aplicarDesdeNube(
              definition: catalogo,
              id: id,
              tallerId: tallerId,
              data: bajaRemota,
            );
            if (aplicado) notifyListeners();
            continue;
          }

          final marcado = await _repoCatalogos.marcarSincronizado(
            definition: catalogo,
            id: id,
            actualizadoEn: actualizadoEn,
          );
          if (!marcado) {
            // Se editó durante el push: permanece pending y el siguiente ciclo
            // enviará la versión más reciente.
            debugPrint(
              '[SyncService] ${catalogo.coleccion}/$id cambió durante el push; '
              'queda pendiente',
            );
          }
          notifyListeners();
        } catch (error) {
          // Los reintentos son por fila: el resto del catálogo continúa y esta
          // fila permanece pending para la próxima sincronización.
          debugPrint(
            '[SyncService] Falló el push de ${catalogo.coleccion}/$id: $error',
          );
        }
      }
    }
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
    final data = _citaToMap(cita, ownerUid: await _resolverOwnerUid(cita));
    _preservarDueno(data, (await ref.get()).data());
    await ref.set(data, SetOptions(merge: true));
    await _repo.marcarSincronizada(cita.id!);
    notifyListeners();
  }

  /// No pisar el `ownerUid` que el documento ya tenga en la nube.
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
    final citaRef = _db.collection('citas').doc(cita.id);
    final ownerUid = await _resolverOwnerUid(cita);

    final codigoFinal = await _db.runTransaction<String?>((tx) async {
      // Firestore requiere TODAS las lecturas antes de escribir. Leer el
      // documento de cita también hace idempotente un retry cuyo commit previo
      // llegó a la nube pero cuya respuesta se perdió en la red.
      final counterSnap = await tx.get(counterRef);
      final citaPrevia = await tx.get(citaRef);
      final codigoPrevio = citaPrevia.data()?['codigo_visible'] as String?;

      if (!esCodigoAusente(codigoPrevio)) {
        final data = _citaToMap(cita, ownerUid: ownerUid)
          ..['codigo_visible'] = codigoPrevio;
        _preservarDueno(data, citaPrevia.data());
        tx.set(citaRef, data, SetOptions(merge: true));
        return codigoPrevio;
      }

      var next = 1;
      if (counterSnap.exists) {
        final valor = counterSnap.data()?['nextNumber'];
        next = valor is int ? valor : int.tryParse('$valor') ?? 1;
      }
      final nuevo = next + 1;
      final codigo = 'CITA-${next.toString().padLeft(4, '0')}';

      final data = _citaToMap(cita, ownerUid: ownerUid)
        ..['codigo_visible'] = codigo;
      _preservarDueno(data, citaPrevia.data());
      tx.set(counterRef, {
        'nextNumber': nuevo,
        'lastCitaId': cita.id,
      }, SetOptions(merge: true));
      tx.set(citaRef, data);
      return codigo;
    });

    // El mismo código resuelto por la transacción se sella localmente; no se
    // depende de que el listener Firestore alcance a procesar el snapshot.
    if (codigoFinal != null) {
      await _repo.asignarCodigoVisible(cita.id!, codigoFinal);
    }
    await _repo.marcarSincronizada(cita.id!);
    notifyListeners();
  }

  /// ownerUid identifica quién sube el documento. El vínculo con el cliente
  /// cuando crea el Admin queda en `correo_cliente`, evitando leer perfiles
  /// privados de otros usuarios desde la sesión del taller.
  Future<String?> _resolverOwnerUid(Cita cita) async {
    return _currentUid();
  }

  /// Callback del `onSnapshot` global. Hace upsert en SQLite.
  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) async {
    for (final change in snap.docChanges) {
      try {
        final doc = change.doc;
        final data = doc.data();
        if (data == null) continue;

        // El listener por UID y el listener por correo pueden recibir la misma
        // cita. Se aceptan ambos vínculos para que una cita creada desde el
        // panel del taller también llegue a Mis Citas.
        if (!SesionAdmin.instance.activa) {
          final ownerUid = data['ownerUid'] as String?;
          final correoSesion =
              SesionCliente.instance.correo?.trim().toLowerCase() ?? '';
          final correoCita = (data['correo_cliente'] as String? ?? '')
              .trim()
              .toLowerCase();
          final esDelUid = ownerUid != null && ownerUid == _currentUid();
          final esDelCorreo =
              correoSesion.isNotEmpty && correoCita == correoSesion;
          if (!esDelUid && !esDelCorreo) continue;
        }

        if (change.type == DocumentChangeType.removed) {
          // Firestore no suele borrar (soft delete en app), pero por si acaso:
          await _repo.borrar(doc.id);
          notifyListeners();
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
        notifyListeners();
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
  Map<String, Object?> _citaToMap(Cita cita, {required String? ownerUid}) {
    final map = cita.toMap();
    map['correo_cliente'] = cita.correoCliente.trim().toLowerCase();
    map['ownerUid'] = ownerUid;
    map['sync_status'] = 'synced';
    return map;
  }

  /// Convierte documento Firestore a `Cita`.
  /// Las fechas llegan como String ISO (aIsoUtc), no como Timestamp.
  Cita _mapToCita(String id, Map<String, dynamic> data) {
    DateTime? parseDate(Object? val) {
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
      fechaCita: parseDate(data['fecha_cita']) ?? DateTime.now().toUtc(),
      estado: _estadoFromString(data['estado'] as String? ?? 'pendiente'),
      tallerId: data['taller_id'] as String?,
      creadoEn: parseDate(data['creado_en']),
      actualizadoEn: parseDate(data['actualizado_en']),
      total: (data['total'] as num?)?.toInt() ?? 0,
      trazabilidad: Trazabilidad(
        eliminadoEn: parseDate(data['eliminado_en']),
        eliminadoPor: data['eliminado_por'] as String?,
        restauradoEn: parseDate(data['restaurado_en']),
      ),
      syncStatus: (data['sync_status'] as String?) ?? 'synced',
    );
  }

  String? _currentUid() {
    final override = _uidOverride;
    if (override != null) return override;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } on Object catch (error) {
      debugPrint('[SyncService] Firebase Auth no está listo: $error');
      return null;
    }
  }

  EstadoCita _estadoFromString(String s) => EstadoCita.desdeNombre(s);
}

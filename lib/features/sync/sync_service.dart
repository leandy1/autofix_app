import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/connectivity/connectivity_service.dart';
import 'package:autofix/core/utils/borrado_logico.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
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
/// REGLAS DE CONFLICTO (simples v1):
/// - `actualizado_en` gana: el documento con timestamp mas reciente persiste.
/// - Borrado logico: si la nube trae `eliminado_en` y local no lo tiene, se
///   marca borrado localmente; si local tiene borrado y la nube no, gana local.
/// - `codigo_visible`: una vez asignado por la nube, NUNCA se sobrescribe
///   localmente (es inmutable tras confirmacion).
class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();

  final CitaRepository _repo = CitaRepository.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  ConnectivityService? _connectivity;
  ConnectivityService get _connectivityService =>
      _connectivity ??= ConnectivityService();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _snapshotSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isPushing = false;

  /// Inicia el listener `onSnapshot` global y la escucha de conectividad.
  /// Debe llamarse una sola vez tras arrancar la app (ej. en `main.dart`
  /// despues del login anonimo).
  Future<void> start() async {
    if (_snapshotSubscription != null) return;

    // Si hay sesión de admin, filtrar por taller_id; si no, por ownerUid.
    Query<Map<String, dynamic>> query;
    final tallerId = SesionAdmin.instance.tallerId;
    if (tallerId != null) {
      query = _db.collection('citas').where('taller_id', isEqualTo: tallerId);
    } else {
      query = _db
          .collection('citas')
          .where('ownerUid', isEqualTo: _currentUid());
    }

    _snapshotSubscription = query
        .snapshots(includeMetadataChanges: true)
        .listen(
          _onSnapshot,
          onError: (e) {
            print('[SyncService] Error en onSnapshot: $e');
          },
        );

    // Escuchar cambios de conectividad: al reconectar, disparar pushPending()
    _connectivitySubscription = _connectivityService.onConnectivityChanged
        .listen((resultados) {
          final hayConexion =
              resultados.isNotEmpty &&
              !resultados.contains(ConnectivityResult.none);
          if (hayConexion) {
            print('[SyncService] Conectividad restaurada -> pushPending()');
            pushPending();
          }
        });

    // Primer push inmediato si hay conectividad.
    await pushPending();
  }

  /// Detiene el listener (ej. al cerrar sesion).
  Future<void> stop() async {
    await _snapshotSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    _snapshotSubscription = null;
    _connectivitySubscription = null;
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
      print('[SyncService] Error en pushPending: $e');
    } finally {
      _isPushing = false;
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
        print('[SyncService] Error procesando doc ${change.doc.id}: $e');
      }
    }
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
      telefono: data['telefono'] as String? ?? '',
      vehiculo: data['vehiculo'] as String? ?? '',
      marca: data['marca'] as String? ?? '',
      modelo: data['modelo'] as String? ?? '',
      anio: (data['anio'] as num?)?.toInt() ?? 0,
      placa: data['placa'] as String? ?? '',
      servicios: List<String>.from(data['servicios'] as List? ?? []),
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

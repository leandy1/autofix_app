import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ConnectivityService _connectivity = ConnectivityService();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _snapshotSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isPushing = false;

  /// Inicia el listener `onSnapshot` global y la escucha de conectividad.
  /// Debe llamarse una sola vez tras arrancar la app (ej. en `main.dart`
  /// despues del login anonimo).
  Future<void> start() async {
    if (_snapshotSubscription != null) return;

    _snapshotSubscription = _db
        .collection('citas')
        .where('ownerUid', isEqualTo: _currentUid())
        .snapshots(includeMetadataChanges: true)
        .listen(
          _onSnapshot,
          onError: (e) {
            print('[SyncService] Error en onSnapshot: $e');
          },
        );

    // Escuchar cambios de conectividad: al reconectar, disparar pushPending()
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      resultados,
    ) {
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
    final data = _citaToMap(cita);
    await _db
        .collection('citas')
        .doc(cita.id)
        .set(data, SetOptions(merge: true));
    await _repo.marcarSincronizada(cita.id!);
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

      final data = _citaToMap(cita)..['codigo_visible'] = codigo;
      tx.set(_db.collection('citas').doc(cita.id), data);
    });

    // La nube ya escribio el codigo; el onSnapshot lo bajara y actualizara
    // local via _onSnapshot. Aqui solo marcamos pendiente de sync resuelto.
    await _repo.marcarSincronizada(cita.id!);
  }

  /// Callback del `onSnapshot` global. Hace upsert en SQLite.
  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) async {
    for (final change in snap.docChanges) {
      final doc = change.doc;
      final data = doc.data();
      if (data == null) continue;

      // Ignora documentos de otros usuarios.
      final ownerUid = data['ownerUid'] as String?;
      if (ownerUid != _currentUid()) continue;

      final cita = _mapToCita(doc.id, data);

      if (change.type == DocumentChangeType.removed) {
        // Firestore no suele borrar (soft delete en app), pero por si acaso:
        _repo.borrar(doc.id);
        continue;
      }

      // Conflicto simple: gana el `actualizado_en` mas reciente.
      final local = await _repo.obtenerPorId(doc.id);
      if (local != null) {
        final localTime = local.actualizadoEn?.millisecondsSinceEpoch ?? 0;
        final remoteTime =
            (data['actualizado_en'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        if (localTime > remoteTime) {
          // Local mas reciente: re-subira en el proximo push.
          continue;
        }
      }

      // Upsert: inserta o actualiza.
      if (local == null) {
        await _repo.insertarConId(cita);
      } else {
        await _repo.actualizar(cita);
      }
      // Marca sincronizada (la version local ya coincide con la nube).
      await _repo.marcarSincronizada(doc.id);
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
  Cita _mapToCita(String id, Map<String, dynamic> data) {
    return Cita(
      id: id,
      codigoVisible: data['codigo_visible'] as String? ?? 'PENDIENTE',
      cliente: data['cliente'] as String,
      telefono: data['telefono'] as String? ?? '',
      vehiculo: data['vehiculo'] as String,
      marca: data['marca'] as String? ?? '',
      modelo: data['modelo'] as String? ?? '',
      anio: (data['anio'] as num?)?.toInt() ?? 0,
      placa: data['placa'] as String? ?? '',
      servicios: List<String>.from(data['servicios'] as List? ?? []),
      tecnico: data['tecnico'] as String? ?? '',
      descripcion: data['descripcion'] as String? ?? '',
      fechaCita:
          (data['fecha_cita'] as Timestamp?)?.toDate().toUtc() ??
          DateTime.now().toUtc(),
      estado: _estadoFromString(data['estado'] as String? ?? 'pendiente'),
      tallerId: data['taller_id'] as String?,
      creadoEn: (data['creado_en'] as Timestamp?)?.toDate().toUtc(),
      actualizadoEn: (data['actualizado_en'] as Timestamp?)?.toDate().toUtc(),
      total: (data['total'] as num?)?.toInt() ?? 0,
      trazabilidad: Trazabilidad(
        eliminadoEn: (data['eliminado_en'] as Timestamp?)?.toDate().toUtc(),
        eliminadoPor: data['eliminado_por'] as String?,
        restauradoEn: (data['restaurado_en'] as Timestamp?)?.toDate().toUtc(),
      ),
      syncStatus: (data['sync_status'] as String?) ?? 'pending',
    );
  }

  String? _currentUid() => FirebaseAuth.instance.currentUser?.uid;

  EstadoCita _estadoFromString(String s) => EstadoCita.values.firstWhere(
    (e) => e.name == s,
    orElse: () => EstadoCita.pendiente,
  );
}

import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/utils/reloj.dart';

const Object _grupoServicioItemSinCambio = Object();

/// Vínculo entre un [GrupoServicio] y un [TipoServicio].
///
/// Tabla puente de la relación many-to-many: un servicio puede estar en varios
/// grupos ('Frenos' sirve tanto en 'Mecánica general' como en 'Carrocería') y un
/// grupo contiene varios servicios. Sin esta tabla la relación no existe: el
/// modelo [GrupoServicio] tiene solo `nombre` y no hay columna de servicios.
///
/// `orden` permite que los servicios aparezcan en un orden definido por el
/// administrador en vez de alfabético, que es como los muestra la pantalla.
/// Un valor de 0 es el primer elemento; uno de 5 es el sexto.
///
/// CAMBIO v16: tabla nueva. Los dos lados del vínculo usan UUID (v7) por la
/// misma razón que los catálogos: la tabla puente se sincroniza y un
/// autoincremento local haría que el mismo par de ids significara otra cosa en
/// cada dispositivo. Ver [GrupoServicio.id] y [TipoServicio.id].
class GrupoServicioItem implements EntidadPersistida {
  const GrupoServicioItem({
    this.id,
    required this.grupoId,
    required this.tipoServicioId,
    this.orden = 0,
    this.activo = true,
    this.creadoEn,
    this.actualizadoEn,
    this.tallerId,
    this.eliminadoEn,
    this.syncStatus = 'pending',
  });

  static const String _kId = 'id';
  static const String _kGrupoId = 'grupo_id';
  static const String _kTipoServicioId = 'tipo_servicio_id';
  static const String _kOrden = 'orden';
  static const String _kActivo = 'activo';
  static const String _kCreadoEn = 'creado_en';
  static const String _kActualizadoEn = 'actualizado_en';
  static const String _kTallerId = 'taller_id';
  static const String _kEliminadoEn = 'eliminado_en';
  static const String _kSyncStatus = 'sync_status';

  /// UUID v4 de la fila, o `null` si todavía no se guardó.
  @override
  final String? id;

  /// UUID del [GrupoServicio] al que pertenece este vínculo.
  final String grupoId;

  /// UUID del [TipoServicio] que forma parte del grupo.
  final String tipoServicioId;

  /// Posición del servicio dentro del grupo. 0 = primero.
  final int orden;

  /// `true` = el servicio sigue en el grupo, `false` = se quitó sin borrar.
  final bool activo;

  final DateTime? creadoEn;

  @override
  final DateTime? actualizadoEn;

  /// ID del taller al que pertenece este catálogo (v9)
  final String? tallerId;

  /// Tombstone del registro. Las consultas operativas excluyen filas con valor.
  final DateTime? eliminadoEn;

  /// `pending` hasta que SyncService confirme el push a Firestore.
  final String syncStatus;

  GrupoServicioItem copyWith({
    String? id,
    String? grupoId,
    String? tipoServicioId,
    int? orden,
    bool? activo,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
    String? tallerId,
    Object? eliminadoEn = _grupoServicioItemSinCambio,
    String? syncStatus,
  }) {
    return GrupoServicioItem(
      id: id ?? this.id,
      grupoId: grupoId ?? this.grupoId,
      tipoServicioId: tipoServicioId ?? this.tipoServicioId,
      orden: orden ?? this.orden,
      activo: activo ?? this.activo,
      creadoEn: creadoEn ?? this.creadoEn,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
      tallerId: tallerId ?? this.tallerId,
      eliminadoEn: identical(eliminadoEn, _grupoServicioItemSinCambio)
          ? this.eliminadoEn
          : eliminadoEn as DateTime?,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, Object?> toMap() {
    return {
      // El id solo va si ya existe: mandarlo en null en un INSERT lo rompe.
      if (id != null) _kId: id,
      _kGrupoId: grupoId,
      _kTipoServicioId: tipoServicioId,
      _kOrden: orden,
      _kActivo: activo ? 1 : 0,
      if (creadoEn != null) _kCreadoEn: aIsoUtc(creadoEn!),
      _kActualizadoEn: aIsoUtc(actualizadoEn ?? Reloj.instancia.ahora()),
      if (tallerId != null) _kTallerId: tallerId,
      _kEliminadoEn: eliminadoEn == null ? null : aIsoUtc(eliminadoEn!),
      _kSyncStatus: syncStatus,
    };
  }

  factory GrupoServicioItem.fromMap(Map<String, Object?> map) {
    return GrupoServicioItem(
      id: map[_kId]?.toString(),
      grupoId: (map[_kGrupoId] as String?) ?? '',
      tipoServicioId: (map[_kTipoServicioId] as String?) ?? '',
      orden: (map[_kOrden] as int?) ?? 0,
      activo: ((map[_kActivo] as int?) ?? 1) != 0,
      creadoEn: desdeIso(map[_kCreadoEn]),
      actualizadoEn: desdeIso(map[_kActualizadoEn]),
      tallerId: map[_kTallerId]?.toString(),
      eliminadoEn: desdeIso(map[_kEliminadoEn]),
      syncStatus: (map[_kSyncStatus] as String?) ?? 'pending',
    );
  }
}
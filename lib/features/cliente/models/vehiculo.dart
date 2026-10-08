import 'package:autofix/core/utils/reloj.dart';
import 'package:autofix/core/data/base_repository.dart';

/// Vehículo registrado localmente por un cliente.
class Vehiculo implements EntidadPersistida {
  const Vehiculo({
    this.id,
    required this.clienteId,
    required this.marca,
    required this.modelo,
    required this.anio,
    this.placa = '',
    this.activo = true,
    this.creadoEn,
    this.actualizadoEn,
    this.syncStatus = 'pending',
    this.eliminadoEn,
  });

  static const String _kId = 'id';
  static const String _kClienteId = 'cliente_id';
  static const String _kMarca = 'marca';
  static const String _kModelo = 'modelo';
  static const String _kAnio = 'anio';
  static const String _kPlaca = 'placa';
  static const String _kActivo = 'activo';
  static const String _kCreadoEn = 'creado_en';
  static const String _kActualizadoEn = 'actualizado_en';
  static const String _kSyncStatus = 'sync_status';
  static const String _kEliminadoEn = 'eliminado_en';

  @override
  final String? id;
  final String clienteId;
  final String marca;
  final String modelo;
  final int anio;
  final String placa;
  final bool activo;
  final DateTime? creadoEn;

  @override
  final DateTime? actualizadoEn;
  final String syncStatus;
  final DateTime? eliminadoEn;

  String get resumen => [
    marca,
    modelo,
    '$anio',
    if (placa.isNotEmpty) placa,
  ].where((parte) => parte.trim().isNotEmpty).join(' · ');

  Vehiculo copyWith({
    String? id,
    String? clienteId,
    String? marca,
    String? modelo,
    int? anio,
    String? placa,
    bool? activo,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
    String? syncStatus,
    DateTime? eliminadoEn,
  }) => Vehiculo(
    id: id ?? this.id,
    clienteId: clienteId ?? this.clienteId,
    marca: marca ?? this.marca,
    modelo: modelo ?? this.modelo,
    anio: anio ?? this.anio,
    placa: placa ?? this.placa,
    activo: activo ?? this.activo,
    creadoEn: creadoEn ?? this.creadoEn,
    actualizadoEn: actualizadoEn ?? this.actualizadoEn,
    syncStatus: syncStatus ?? this.syncStatus,
    eliminadoEn: eliminadoEn ?? this.eliminadoEn,
  );

  Map<String, Object?> toMap() => {
    if (id != null) _kId: id,
    _kClienteId: clienteId,
    _kMarca: marca,
    _kModelo: modelo,
    _kAnio: anio,
    _kPlaca: placa,
    _kActivo: activo ? 1 : 0,
    if (creadoEn != null) _kCreadoEn: aIsoUtc(creadoEn!),
    _kActualizadoEn: aIsoUtc(actualizadoEn ?? Reloj.instancia.ahora()),
    _kSyncStatus: syncStatus,
    _kEliminadoEn: eliminadoEn == null ? null : aIsoUtc(eliminadoEn!),
  };

  factory Vehiculo.fromMap(Map<String, Object?> map) => Vehiculo(
    id: map[_kId]?.toString(),
    clienteId: (map[_kClienteId] ?? map['correo_cliente'] ?? '').toString(),
    marca: map[_kMarca] as String,
    modelo: map[_kModelo] as String,
    anio: (map[_kAnio] as num).toInt(),
    placa: map[_kPlaca] as String? ?? '',
    activo: switch (map[_kActivo]) {
      final bool activo => activo,
      final num activo => activo != 0,
      _ => true,
    },
    creadoEn: desdeIso(map[_kCreadoEn]),
    actualizadoEn: desdeIso(map[_kActualizadoEn]),
    syncStatus: map[_kSyncStatus] as String? ?? 'synced',
    eliminadoEn: desdeIso(map[_kEliminadoEn]),
  );
}

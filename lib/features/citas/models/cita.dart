import '../../../core/database/database_helper.dart';

enum EstadoCita {
  pendiente,
  enProceso,
  completada;

  static EstadoCita desdeTexto(String valor) => EstadoCita.values.firstWhere(
    (e) => e.name == valor,
    orElse: () => EstadoCita.pendiente,
  );
}

/// Entidad de dominio. No conoce sqflite: solo sabe convertirse a y desde un
/// [Map], que es el formato que SQLite entiende como fila.
class Cita {
  const Cita({
    this.id,
    required this.codigoQr,
    required this.cliente,
    required this.vehiculo,
    this.descripcion = '',
    required this.fechaCita,
    this.estado = EstadoCita.pendiente,
    this.creadoEn,
  });

  final int? id;
  final String codigoQr;
  final String cliente;
  final String vehiculo;
  final String descripcion;
  final DateTime fechaCita;
  final EstadoCita estado;
  final DateTime? creadoEn;
  Cita copyWith({
    int? id,
    String? codigoQr,
    String? cliente,
    String? vehiculo,
    String? descripcion,
    DateTime? fechaCita,
    EstadoCita? estado,
    DateTime? creadoEn,
  }) {
    return Cita(
      id: id ?? this.id,
      codigoQr: codigoQr ?? this.codigoQr,
      cliente: cliente ?? this.cliente,
      vehiculo: vehiculo ?? this.vehiculo,
      descripcion: descripcion ?? this.descripcion,
      fechaCita: fechaCita ?? this.fechaCita,
      estado: estado ?? this.estado,
      creadoEn: creadoEn ?? this.creadoEn,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) DatabaseHelper.colId: id,
      DatabaseHelper.colCodigoQr: codigoQr,
      DatabaseHelper.colCliente: cliente,
      DatabaseHelper.colVehiculo: vehiculo,
      DatabaseHelper.colDescripcion: descripcion,
      DatabaseHelper.colFechaCita: fechaCita.toIso8601String(),
      DatabaseHelper.colEstado: estado.name,
      DatabaseHelper.colCreadoEn: (creadoEn ?? DateTime.now()).toIso8601String(),
    };
  }

  factory Cita.fromMap(Map<String, Object?> map) {
    return Cita(
      id: map[DatabaseHelper.colId] as int?,
      codigoQr: map[DatabaseHelper.colCodigoQr] as String,
      cliente: map[DatabaseHelper.colCliente] as String,
      vehiculo: map[DatabaseHelper.colVehiculo] as String,
      descripcion: (map[DatabaseHelper.colDescripcion] as String?) ?? '',
      fechaCita: DateTime.parse(map[DatabaseHelper.colFechaCita]! as String),
      estado: EstadoCita.desdeTexto(map[DatabaseHelper.colEstado]! as String),
      creadoEn: DateTime.tryParse(map[DatabaseHelper.colCreadoEn]! as String),
    );
  }
}

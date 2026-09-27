import 'dart:convert';

import '../../../core/database/database_helper.dart';

/// Los 4 estados REALES que se guardan en la base.
///
/// OJO IMPORTANTE PARA LEANDY: tu `kColorPorEstado` tiene 5 llaves
/// (ATRASADAS, Pendiente, Esperando Pieza, En proceso, Completado), pero
/// 'ATRASADAS' NO es un estado guardado: es una cita que ya paso su fecha y
/// todavia no se completo. Por eso aca solo hay 4 valores y 'ATRASADAS' se
/// calcula al vuelo con el getter [Cita.esAtrasada] + [Cita.etiquetaUI].
/// Si lo metieras como estado en la base, una cita atrasada que luego se
/// completa tendria que "saltar" de estado y perderias la trazabilidad.
enum EstadoCita {
  pendiente('Pendiente'),
  esperandoPieza('Esperando Pieza'),
  enProceso('En proceso'),
  completado('Completado');

  const EstadoCita(this.etiqueta);

  /// Texto EXACTO que usa tu UI. Esta property es la que hace el match:
  /// `kColorPorEstado[cita.estado.etiqueta]` y listo, sin ifs ni mapazos manuales.
  final String etiqueta;

  /// Lee desde la base (guardamos `.name`, no la etiqueta, porque `.name` es
  /// estable y la etiqueta puede cambiar si redenainan el diseno).
  static EstadoCita desdeNombre(String valor) =>
      EstadoCita.values.firstWhere((e) => e.name == valor, orElse: () => EstadoCita.pendiente);

  /// Lee desde la UI de Leandy ('En proceso', 'Completado'...).
  static EstadoCita desdeEtiqueta(String valor) =>
      EstadoCita.values.firstWhere((e) => e.etiqueta == valor, orElse: () => EstadoCita.pendiente);
}

/// Entidad de dominio. No conoce sqflite: solo sabe convertirse a y desde un
/// [Map], que es el formato que SQLite entiende como fila.
class Cita {
  const Cita({
    this.id,
    required this.codigoQr,
    required this.cliente,
    this.telefono = '',
    required this.vehiculo,
    this.marca = '',
    this.modelo = '',
    this.anio = 0,
    this.placa = '',
    this.servicios = const [],
    this.tecnico = '',
    this.descripcion = '',
    required this.fechaCita,
    this.estado = EstadoCita.pendiente,
    this.creadoEn,
    this.actualizadoEn,
  });

  final int? id;

  /// Llave con el QR fisico del vehiculo. Es UNIQUE en la base.
  /// Este campo existe basically para el modulo de escaneo QR.
  final String codigoQr;
  final String cliente;
  final String telefono;
  final String vehiculo;
  final String marca;
  final String modelo;
  final int anio;
  final String placa;
  final List<String> servicios;
  final String tecnico;
  final String descripcion;
  final DateTime fechaCita;
  final EstadoCita estado;
  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  /// Lo que tu UI necesita mostrar para el acordeon "ATRASADAS".
  ///
  /// OJO con la semantica, Leandy: es "la hora Y PASO y todavia no se completo".
  /// No es "la fecha es de un dia anterior". Consecuencia PRACTICA: si creas una
  /// cita con `fechaCita: DateTime.now()`, a los microsegundos ya esta atrasada
  /// (el `now()` del getter es posterior). Para una cita de hoy usen
  /// `DateTime.now().add(Duration(hours: 2))`, no la hora exacta.
  ///
  /// Es logica de negocio pura: no toca la base, asi que no cuesta un query.
  bool get esAtrasada =>
      estado != EstadoCita.completado && fechaCita.isBefore(DateTime.now());

  /// Llave EXACTA de tu `kColorPorEstado`. Devuelve 'ATRASADAS' con mayusculas
  /// porque asi la definiste vos en el mapa de colores.
  String get etiquetaUI => esAtrasada ? 'ATRASADAS' : estado.etiqueta;

  Cita copyWith({
    int? id,
    String? codigoQr,
    String? cliente,
    String? telefono,
    String? vehiculo,
    String? marca,
    String? modelo,
    int? anio,
    String? placa,
    List<String>? servicios,
    String? tecnico,
    String? descripcion,
    DateTime? fechaCita,
    EstadoCita? estado,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
  }) {
    return Cita(
      id: id ?? this.id,
      codigoQr: codigoQr ?? this.codigoQr,
      cliente: cliente ?? this.cliente,
      telefono: telefono ?? this.telefono,
      vehiculo: vehiculo ?? this.vehiculo,
      marca: marca ?? this.marca,
      modelo: modelo ?? this.modelo,
      anio: anio ?? this.anio,
      placa: placa ?? this.placa,
      servicios: servicios ?? this.servicios,
      tecnico: tecnico ?? this.tecnico,
      descripcion: descripcion ?? this.descripcion,
      fechaCita: fechaCita ?? this.fechaCita,
      estado: estado ?? this.estado,
      creadoEn: creadoEn ?? this.creadoEn,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) DatabaseHelper.colId: id,
      DatabaseHelper.colCodigoQr: codigoQr,
      DatabaseHelper.colCliente: cliente,
      DatabaseHelper.colTelefono: telefono,
      DatabaseHelper.colVehiculo: vehiculo,
      DatabaseHelper.colMarca: marca,
      DatabaseHelper.colModelo: modelo,
      DatabaseHelper.colAnio: anio,
      DatabaseHelper.colPlaca: placa,
      // Los servicios son una lista y SQLite no tiene arrays: la guardo como
      // JSON. Es la forma estandar, no un truco, y `fromMap` la reversa.
      DatabaseHelper.colServicios: jsonEncode(servicios),
      DatabaseHelper.colTecnico: tecnico,
      DatabaseHelper.colDescripcion: descripcion,
      DatabaseHelper.colFechaCita: fechaCita.toIso8601String(),
      DatabaseHelper.colEstado: estado.name,
      DatabaseHelper.colCreadoEn: (creadoEn ?? DateTime.now()).toIso8601String(),
      DatabaseHelper.colActualizadoEn:
          (actualizadoEn ?? DateTime.now()).toIso8601String(),
    };
  }

  factory Cita.fromMap(Map<String, Object?> map) {
    return Cita(
      id: map[DatabaseHelper.colId] as int?,
      codigoQr: map[DatabaseHelper.colCodigoQr] as String,
      cliente: map[DatabaseHelper.colCliente] as String,
      telefono: (map[DatabaseHelper.colTelefono] as String?) ?? '',
      vehiculo: map[DatabaseHelper.colVehiculo] as String,
      marca: (map[DatabaseHelper.colMarca] as String?) ?? '',
      modelo: (map[DatabaseHelper.colModelo] as String?) ?? '',
      anio: (map[DatabaseHelper.colAnio] as int?) ?? 0,
      placa: (map[DatabaseHelper.colPlaca] as String?) ?? '',
      servicios: _leerServicios(map[DatabaseHelper.colServicios]),
      tecnico: (map[DatabaseHelper.colTecnico] as String?) ?? '',
      descripcion: (map[DatabaseHelper.colDescripcion] as String?) ?? '',
      fechaCita: DateTime.parse(map[DatabaseHelper.colFechaCita]! as String),
      estado: EstadoCita.desdeNombre(map[DatabaseHelper.colEstado]! as String),
      creadoEn: DateTime.tryParse(map[DatabaseHelper.colCreadoEn]! as String),
      actualizadoEn:
          DateTime.tryParse(map[DatabaseHelper.colActualizadoEn] as String? ?? ''),
    );
  }

  static List<String> _leerServicios(Object? crudo) {
    if (crudo is! String || crudo.isEmpty) return const [];
    final decodificado = jsonDecode(crudo);
    if (decodificado is! List) return const [];
    return decodificado.map((e) => e.toString()).toList();
  }
}

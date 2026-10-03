import 'dart:convert';

import 'package:autofix/core/data/base_repository.dart';

/// Estados que realmente se guardan.
///
/// 'ATRASADAS' no es uno: se deriva de [Cita.esAtrasada]. Persistirlo obligaria
/// a una cita vencida a "saltar" de estado al completarse y se pierde la
/// trazabilidad de cuando se atraso.
enum EstadoCita {
  pendiente('Pendiente'),
  esperandoPieza('Esperando Pieza'),
  enProceso('En proceso'),
  completado('Completado');

  const EstadoCita(this.etiqueta);

  /// Texto exacto que consume la UI, para que el mapa de colores matchee sin
  /// transformaciones intermedias.
  final String etiqueta;

  /// Se persiste `.name` y no la etiqueta: `.name` es estable aunque el diseño
  /// renombre el texto visible.
  static EstadoCita desdeNombre(String valor) => EstadoCita.values.firstWhere(
        (e) => e.name == valor,
        orElse: () => EstadoCita.pendiente,
      );

  static EstadoCita desdeEtiqueta(String valor) => EstadoCita.values.firstWhere(
        (e) => e.etiqueta == valor,
        orElse: () => EstadoCita.pendiente,
      );
}

/// Entidad de dominio. No importa sqflite ni el helper de base: las claves de
/// fila son literales aca adentro para que el mismo modelo se pueda mapear
/// contra SQLite, contra Postgres o contra un Map de test. El test de esquema
/// (PRAGMA table_info) avisa si el CREATE TABLE se desincroniza.
class Cita implements EntidadPersistida {
  const Cita({
    this.id,
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
    this.tallerId,
    this.creadoEn,
    this.actualizadoEn,
    this.total = 0,
  });

  static const String etiquetaAtrasadas = 'ATRASADAS';

  static const String _kId = 'id';
  static const String _kCliente = 'cliente';
  static const String _kTelefono = 'telefono';
  static const String _kVehiculo = 'vehiculo';
  static const String _kMarca = 'marca';
  static const String _kModelo = 'modelo';
  static const String _kAnio = 'anio';
  static const String _kPlaca = 'placa';
  static const String _kServicios = 'servicios';
  static const String _kTecnico = 'tecnico';
  static const String _kDescripcion = 'descripcion';
  static const String _kFechaCita = 'fecha_cita';
  static const String _kEstado = 'estado';
  static const String _kTallerId = 'taller_id';
  static const String _kCreadoEn = 'creado_en';
  static const String _kActualizadoEn = 'actualizado_en';
  static const String _kTotal = 'total';

  @override
  final int? id;


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

  /// Id del taller AFILIADO donde se agenda la cita.
  ///
  /// `int?` y no `int` a proposito: las citas que ya existian antes de la v4 no
  /// tienen taller, y las que crea el escaner QR todavia no lo_eligen. Nullable
  /// significa "no sabemos todavia", que es distinto de "taller 0".
  ///
  /// Y es un id, NO el nombre del taller. Con el nombre no se puede responder
  /// "dame las citas de Global Refriauto" de forma confiable, y dos filas con el
  /// mismo nombre serian la misma cita a los ojos del sistema.
  final int? tallerId;

  final DateTime? creadoEn;

  @override
  final DateTime? actualizadoEn;
  final int total;

  /// "La hora ya paso y todavia no se completo". No es "la fecha es de ayer".
  ///
  /// `ahora` va por parametro a proposito: leer el reloj adentro hace que dos
  /// dispositivos clasifiquen la misma cita distinto, y en cuanto haya
  /// sincronizacion eso ya no es una discrepancia visual sino conflicto de datos.
  /// Quien arma la lista lo pasa una sola vez para toda la pasada.
  bool esAtrasada(DateTime ahora) =>
      estado != EstadoCita.completado && fechaCita.isBefore(ahora);

  /// Llave exacta del mapa de colores de la UI. Va en mayusculas porque asi
  /// esta definida alla.
  String etiquetaUI(DateTime ahora) =>
      esAtrasada(ahora) ? etiquetaAtrasadas : estado.etiqueta;

  Cita copyWith({
    int? id,
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
    int? tallerId,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
    int? total,
  }) {
    return Cita(
      id: id ?? this.id,
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
      tallerId: tallerId ?? this.tallerId,
      creadoEn: creadoEn ?? this.creadoEn,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
      total: total ?? this.total,
    );
  }

  Map<String, Object?> toMap() {
    return {
      // El id solo va si ya existe: mandarlo en null en un INSERT lo rompe.
      if (id != null) _kId: id,
      _kCliente: cliente,
      _kTelefono: telefono,
      _kVehiculo: vehiculo,
      _kMarca: marca,
      _kModelo: modelo,
      _kAnio: anio,
      _kPlaca: placa,
      // SQLite no tiene arrays: la lista viaja como JSON. `fromMap` la revierte.
      _kServicios: jsonEncode(servicios),
      _kTecnico: tecnico,
      _kDescripcion: descripcion,
      _kFechaCita: fechaCita.toIso8601String(),
      _kEstado: estado.name,
      // `tallerId` va siempre en el mapa, incluso cuando es null: es lo que
      // limpia la columna si se desasigna el taller. Omitirla en un UPDATE
      // dejaria el id viejo pegado a la cita.
      _kTallerId: tallerId,
      // `creado_en` se ESCRIBE UNA SOLA VEZ, al crear. Si el UPDATE lo mandara
      // siempre, cada guardado reescribiria la fecha de creacion y se perderia
      // la trazabilidad de cuando se agendo la cita.
      //
      // Por eso la columna solo entra en el mapa si la cita no tiene id (alta)
      // o si el modelo conoce el valor original. En cualquier otro caso se
      // omite del mapa, y `db.update` deja intacta la columna que ya esta en la
      // base. Antes esto decia `(creadoEn ?? DateTime.now())`, que en un UPDATE
      // sin `creadoEn` plantaba la hora del guardado como si fuera la de alta.
      if (id == null || creadoEn != null)
        _kCreadoEn: (creadoEn ?? DateTime.now()).toIso8601String(),
      // `actualizado_en` es lo contrario por definicion: se refresca en cada
      // escritura, porque de eso sirve. Se sella con el reloj en vez de copiar
      // el valor que venga, asi un UPDATE cuenta como modificacion real.
      _kActualizadoEn: DateTime.now().toIso8601String(),
      _kTotal: total,
    };
  }

  factory Cita.fromMap(Map<String, Object?> map) {
    return Cita(
      id: map[_kId] as int?,
      cliente: map[_kCliente] as String,
      telefono: (map[_kTelefono] as String?) ?? '',
      vehiculo: map[_kVehiculo] as String,
      marca: (map[_kMarca] as String?) ?? '',
      modelo: (map[_kModelo] as String?) ?? '',
      anio: (map[_kAnio] as int?) ?? 0,
      placa: (map[_kPlaca] as String?) ?? '',
      servicios: _leerServicios(map[_kServicios]),
      tecnico: (map[_kTecnico] as String?) ?? '',
      descripcion: (map[_kDescripcion] as String?) ?? '',
      fechaCita: DateTime.parse(map[_kFechaCita] as String),
      estado: EstadoCita.desdeNombre(map[_kEstado] as String),
      tallerId: (map[_kTallerId] as num?)?.toInt(),
      creadoEn: () {
        final v = map[_kCreadoEn];
        if (v == null || (v is String && v.isEmpty)) return null;
        return DateTime.tryParse(v as String);
      }(),
      actualizadoEn: () {
        final v = map[_kActualizadoEn];
        if (v == null || (v is String && v.isEmpty)) return null;
        return DateTime.tryParse(v as String);
      }(),
      total: (map[_kTotal] as int?) ?? 0,
    );
  }

  static List<String> _leerServicios(Object? crudo) {
    if (crudo is! String || crudo.isEmpty) return const [];
    final decodificado = jsonDecode(crudo);
    if (decodificado is! List) return const [];
    return decodificado.map((e) => e.toString()).toList();
  }
}

import '../../../core/data/base_repository.dart';

/// Trabajo que el taller ofrece: "Frenos", "Cambio de aceite", etc.
///
/// Es el MISMO molde que [Tecnico] mas una columna de precio. El precio va
/// entero, en pesos dominicanos.
///
/// Entero y no double, a proposito: un precio de 1250.50 guardado como REAL
/// vuelve como 1250.5 o incluso 1250.4999999, y la suma de una lista de servicios
/// deja de cuadrar con lo que dice el total de la cita. Con enteros la aritmetica
/// es exacta. Los centavos, si alguna vez hacen falta, se ajustan con
/// [precioEnCentavos].
class TipoServicio implements EntidadPersistida {
  const TipoServicio({
    this.id,
    required this.nombre,
    this.precio = 0,
    this.activo = true,
    this.creadoEn,
    this.actualizadoEn,
  });

  static const String _kId = 'id';
  static const String _kNombre = 'nombre';
  static const String _kPrecio = 'precio';
  static const String _kActivo = 'activo';
  static const String _kCreadoEn = 'creado_en';
  static const String _kActualizadoEn = 'actualizado_en';

  @override
  final int? id;

  final String nombre;

  /// Precio en pesos dominicanos, sin centavos.
  final int precio;

  final bool activo;

  final DateTime? creadoEn;

  @override
  final DateTime? actualizadoEn;

  int get precioEnCentavos => precio * 100;

  TipoServicio copyWith({
    int? id,
    String? nombre,
    int? precio,
    bool? activo,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
  }) {
    return TipoServicio(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      precio: precio ?? this.precio,
      activo: activo ?? this.activo,
      creadoEn: creadoEn ?? this.creadoEn,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) _kId: id,
      _kNombre: nombre,
      _kPrecio: precio,
      _kActivo: activo ? 1 : 0,
      _kCreadoEn: (creadoEn ?? DateTime.now()).toIso8601String(),
      _kActualizadoEn: (actualizadoEn ?? DateTime.now()).toIso8601String(),
    };
  }

  factory TipoServicio.fromMap(Map<String, Object?> map) {
    return TipoServicio(
      id: map[_kId] as int?,
      nombre: (map[_kNombre] as String?) ?? '',
      precio: (map[_kPrecio] as int?) ?? 0,
      activo: ((map[_kActivo] as int?) ?? 1) != 0,
      creadoEn: DateTime.tryParse(map[_kCreadoEn] as String? ?? ''),
      actualizadoEn: DateTime.tryParse(map[_kActualizadoEn] as String? ?? ''),
    );
  }
}

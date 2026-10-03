import 'package:autofix/core/data/base_repository.dart';

/// Estado que el administrador puede ASIGNARLE a una cita.
///
/// -----------------------------------------------------------------
/// ALCANCE DEL MODELO (leido antes de tocar nada de esto):
///
/// Esta tabla es un CATALOGO INDEPENDIENTE. NO es la fuente de verdad de
/// `citas.estado`: eso sigue siendo el enum `EstadoCita`, que pertenece al modulo
/// de Leandy y no se toca desde aqui.
///
/// Hay dos razones concretas, y las dos estan en el diseno:
///
///   1. El catalogo del diseno trae 'En diagnostico', que NO existe en
///      `EstadoCita`. Si esta tabla mandara sobre las citas, habria estados que
///      se pueden crear y ninguna cita los puede tomar.
///   2. El catalogo escribe 'Esperando pieza' con minuscula y el enum tiene
///      'Esperando Pieza' con mayuscula. El mapa de colores de la pantalla de
///      Citas hace match por texto EXACTO, asi que un cambio de capitalizacion
///      apaga el color de ese estado sin avisar.
///
/// Que falta para que esta tabla sea la fuente de verdad, cuando el equipo lo
/// decida:
///   - `Cita.estado` deja de ser `EstadoCita` y pasa a ser el id de esta tabla.
///   - El enum `EstadoCita` y su `kColorPorEstado` se reemplazan por un look-up.
///   - La migracion de `citas.estado` (texto -> id) tiene que ir dentro de la
///     misma transaccion que crea la tabla, o se pierden las citas.
/// -----------------------------------------------------------------
class EstadoConfig implements EntidadPersistida {
  const EstadoConfig({
    this.id,
    required this.nombre,
    this.activo = true,
    this.creadoEn,
    this.actualizadoEn,
  });

  static const String _kId = 'id';
  static const String _kNombre = 'nombre';
  static const String _kActivo = 'activo';
  static const String _kCreadoEn = 'creado_en';
  static const String _kActualizadoEn = 'actualizado_en';

  @override
  final int? id;

  final String nombre;

  final bool activo;

  final DateTime? creadoEn;

  @override
  final DateTime? actualizadoEn;

  EstadoConfig copyWith({
    int? id,
    String? nombre,
    bool? activo,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
  }) {
    return EstadoConfig(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      activo: activo ?? this.activo,
      creadoEn: creadoEn ?? this.creadoEn,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) _kId: id,
      _kNombre: nombre,
      _kActivo: activo ? 1 : 0,
      _kCreadoEn: (creadoEn ?? DateTime.now()).toIso8601String(),
      _kActualizadoEn: (actualizadoEn ?? DateTime.now()).toIso8601String(),
    };
  }

  factory EstadoConfig.fromMap(Map<String, Object?> map) {
    return EstadoConfig(
      id: map[_kId] as int?,
      nombre: (map[_kNombre] as String?) ?? '',
      activo: ((map[_kActivo] as int?) ?? 1) != 0,
      creadoEn: DateTime.tryParse(map[_kCreadoEn] as String? ?? ''),
      actualizadoEn: DateTime.tryParse(map[_kActualizadoEn] as String? ?? ''),
    );
  }
}

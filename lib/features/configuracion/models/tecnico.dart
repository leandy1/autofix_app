import '../../../core/data/base_repository.dart';

/// Tecnico del taller: la persona a la que se le asigna una cita.
///
/// Entidad de dominio pura. No importa sqflite ni el helper de base: las claves de
/// fila son literales aca adentro para que el mismo modelo se pueda mapear
/// contra SQLite, contra Postgres o contra un Map de test. El test de esquema
/// (PRAGMA table_info) avisa si el CREATE TABLE se desincroniza.
///
/// `activo` esta en 1 en toda la app: se dejo para el futuro, cuando haya baja
/// logica de tecnicos. Borrarlos de verdad dejaria citas viejas apuntando a
/// un id que ya no existe, y ese nombre es justo lo que se muestra en el
/// historial.
class Tecnico implements EntidadPersistida {
  const Tecnico({
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

  /// `true` = disponible para asignar citas, `false` = dado de baja.
  final bool activo;

  final DateTime? creadoEn;

  @override
  final DateTime? actualizadoEn;

  Tecnico copyWith({
    int? id,
    String? nombre,
    bool? activo,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
  }) {
    return Tecnico(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      activo: activo ?? this.activo,
      creadoEn: creadoEn ?? this.creadoEn,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
    );
  }

  Map<String, Object?> toMap() {
    return {
      // El id solo va si ya existe: mandarlo en null en un INSERT lo rompe.
      if (id != null) _kId: id,
      _kNombre: nombre,
      // SQLite no tiene booleanos: se guarda 1/0.
      _kActivo: activo ? 1 : 0,
      _kCreadoEn: (creadoEn ?? DateTime.now()).toIso8601String(),
      _kActualizadoEn: (actualizadoEn ?? DateTime.now()).toIso8601String(),
    };
  }

  factory Tecnico.fromMap(Map<String, Object?> map) {
    return Tecnico(
      id: map[_kId] as int?,
      nombre: (map[_kNombre] as String?) ?? '',
      activo: ((map[_kActivo] as int?) ?? 1) != 0,
      creadoEn: DateTime.tryParse(map[_kCreadoEn] as String? ?? ''),
      actualizadoEn: DateTime.tryParse(map[_kActualizadoEn] as String? ?? ''),
    );
  }
}

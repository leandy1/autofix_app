import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/utils/reloj.dart';

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
///
/// CAMBIO v7: `id` paso de `int?` (autoincremento) a `String?` (UUID v4). El
/// catalogo de tecnicos se sincroniza entre dispositivos, y un contador local
/// haria que el "tecnico 2" de un celular fuera otro en el resto. Ver
/// `lib/core/utils/uuid.dart`. Los tiempos pasaron a UTC con [aIsoUtc].
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
  final String? id;

  final String nombre;

  /// `true` = disponible para asignar citas, `false` = dado de baja.
  final bool activo;

  final DateTime? creadoEn;

  @override
  final DateTime? actualizadoEn;

  Tecnico copyWith({
    String? id,
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
      // `creado_en` solo si el modelo CONOCE el valor. Ver la nota larga de
      // `Cita.toMap`: la capa de datos le pone el id antes de serializar, asi que
      // "¿tiene id?" no sirve para distinguir un alta de una edicion. Sellar la
      // fecha de alta es trabajo del repositorio, que sabe que operacion es.
      if (creadoEn != null) _kCreadoEn: aIsoUtc(creadoEn!),
      // `actualizadoEn ?? reloj` y NO el reloj a secas: si el tecnico ya traia una
      // marca de la nube, escribirle la hora de ESTE dispositivo haria que cada
      // dispositivo que lo descargue lo registre como una edicion local, y los
      // dos pelearian por la misma fila para siempre.
      _kActualizadoEn: aIsoUtc(actualizadoEn ?? Reloj.instancia.ahora()),
    };
  }

  factory Tecnico.fromMap(Map<String, Object?> map) {
    return Tecnico(
      id: map[_kId]?.toString(),
      nombre: (map[_kNombre] as String?) ?? '',
      activo: ((map[_kActivo] as int?) ?? 1) != 0,
      creadoEn: desdeIso(map[_kCreadoEn]),
      actualizadoEn: desdeIso(map[_kActualizadoEn]),
    );
  }
}

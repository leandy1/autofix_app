import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/utils/reloj.dart';

/// GRUPO de servicios: "Carrocería", "Mecánica general", "Eléctrico".
///
/// Entidad de dominio pura, con la misma forma que [Tecnico], [TipoServicio] y
/// [Marca]. No importa sqflite ni el helper de base, y las claves de fila son
/// literales aca adentro para que el mismo modelo se pueda mapear contra SQLite,
/// contra Postgres o contra un Map de test.
///
/// -----------------------------------------------------------------
/// POR QUE ESTA TABLA NUEVA EN LA v7
/// -----------------------------------------------------------------
///
/// Hasta la v6 los grupos eran `demoGruposServiciosAdmin`, una `const` en
/// `lib/shared/models/demo_admin_data.dart` con un solo grupo ('Carrocería') y
/// servicios escrito a mano. La pantalla de Configuracion los pintaba con un
/// acordeon, pero no eran filas: no se guardaban, no se podian editar y no
/// sobrevivian a un reinstall. Leandy ya definio que la fuente es ESTA base
/// (punto 6 del encargo), asi que la lista de demo se reemplaza por filas.
///
/// -----------------------------------------------------------------
/// LO QUE ESTA TABLA NO TIENE, Y POR QUE
/// -----------------------------------------------------------------
///
/// Un grupo de servicios, en el diseño, es una LISTA de `tipos_servicio`. La
/// relacion entre el grupo y sus servicios (que servicio pertenece a que grupo,
/// en que orden) NO esta implementada, y es una decision pendiente de Leandy:
///
///   - Opcion A, tabla puente `grupo_servicio_items (grupo_id, tipo_servicio_id,
///     orden)`. Es lo correcto si un servicio puede estar en VARIOS grupos, que
///     es el caso real ('Frenos' sirve tanto en 'Mecánica general' como en
///     'Carrocería').
///   - Opcion B, `grupos_servicio.ids_servicios` como texto JSON. Es mas simple
///     de hacer pero no se puede indexar ni consultar con SQL.
///
/// La opcion A es la que va. Como el requisito del punto 6 es 'nombre', y una
/// relacion many-to-many no se resuelve con un campo 'nombre', la tabla queda con
/// la forma de catalogo simple. Cuando Leandy mande los datos validados, la
/// tabla puente se agrega en la v8 como su propia migracion.
///
/// Lo que SI queda listo desde ahora es el CRUD del grupo, que es lo que la UI
/// necesita para pintar la lista y el acordeon. Y queda listo el hecho de que
/// `TipoServicio` ya tiene UUID, asi que cuando se agregue la tabla puente las dos
/// columnas van a ser del mismo tipo y no habra que migrar los servicios.
/// -----------------------------------------------------------------
class GrupoServicio implements EntidadPersistida {
  const GrupoServicio({
    this.id,
    required this.nombre,
    this.activo = true,
    this.creadoEn,
    this.actualizadoEn,
    this.tallerId,
  });

  static const String _kId = 'id';
  static const String _kNombre = 'nombre';
  static const String _kActivo = 'activo';
  static const String _kCreadoEn = 'creado_en';
  static const String _kActualizadoEn = 'actualizado_en';
  static const String _kTallerId = 'taller_id';

  /// UUID v4 de la fila, o `null` si todavia no se guardo.
  ///
  /// CAMBIO v7: `int?` -> `String?`, por la misma razon que en [Marca].
  @override
  final String? id;

  final String nombre;

  /// `true` = disponible para los formularios, `false` = dado de baja.
  final bool activo;

  final DateTime? creadoEn;

  @override
  final DateTime? actualizadoEn;

  /// ID del taller al que pertenece este catalogo (v9)
  final String? tallerId;

  GrupoServicio copyWith({
    String? id,
    String? nombre,
    bool? activo,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
    String? tallerId,
  }) {
    return GrupoServicio(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      activo: activo ?? this.activo,
      creadoEn: creadoEn ?? this.creadoEn,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
      tallerId: tallerId ?? this.tallerId,
    );
  }

  Map<String, Object?> toMap() {
    return {
      // El id solo va si ya existe: mandarlo en null en un INSERT lo rompe.
      if (id != null) _kId: id,
      _kNombre: nombre,
      // SQLite no tiene booleanos: se guarda 1/0.
      _kActivo: activo ? 1 : 0,
      // `creado_en` solo si el modelo conoce el valor. Ver la nota de
      // `Marca.toMap`.
      if (creadoEn != null) _kCreadoEn: aIsoUtc(creadoEn!),
      // El reloj solo se usa si no hay marca previa. Ver la nota de `Marca.toMap`.
      _kActualizadoEn: aIsoUtc(actualizadoEn ?? Reloj.instancia.ahora()),
      if (tallerId != null) _kTallerId: tallerId,
    };
  }

  factory GrupoServicio.fromMap(Map<String, Object?> map) {
    return GrupoServicio(
      id: map[_kId]?.toString(),
      nombre: (map[_kNombre] as String?) ?? '',
      activo: ((map[_kActivo] as int?) ?? 1) != 0,
      creadoEn: desdeIso(map[_kCreadoEn]),
      actualizadoEn: desdeIso(map[_kActualizadoEn]),
      tallerId: map[_kTallerId]?.toString(),
    );
  }
}

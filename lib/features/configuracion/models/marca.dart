import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/utils/reloj.dart';

const Object _marcaSinCambio = Object();

/// MARCA de vehiculo (Toyota, Honda, Ford...).
///
/// Entidad de dominio pura, con la misma forma que [Tecnico] y [TipoServicio]: no
/// importa sqflite ni el helper de base, y las claves de fila son literales aca
/// adentro para que el mismo modelo se pueda mapear contra SQLite, contra
/// Postgres o contra un Map de test. El test de esquema (`PRAGMA table_info`)
/// avisa si el `CREATE TABLE` se desincroniza de estas claves.
///
/// -----------------------------------------------------------------
/// POR QUE ESTA TABLA NUEVA EN LA v7 Y NO ANTES
/// -----------------------------------------------------------------
///
/// Hasta la v6 las marcas eran `demoMarcasVehiculo`, una `const List<String>` en
/// `lib/shared/models/demo_admin_data.dart`: cinco nombres fijos que la pantalla
/// de Configuracion pintaba y que nadie podia editar. No eran filas, no se
/// guardaban, y se perdian en cada rebuild.
///
/// Eso estaba declarado como PAUSADO a proposito, esperando a que el equipo
/// definiera la fuente: la API web de Andy o esta base. Leandy ya definio que la
/// fuente es ESTA base (punto 6 del encargo), asi que la lista de demo se
/// reemplaza por filas reales.
///
/// -----------------------------------------------------------------
/// POR QUE `nombre` Y NO `nombre + pais` O `nombre + logotipo`
/// -----------------------------------------------------------------
///
/// El requisito es 'nombre' y nada mas. Agregar columnas que la UI no muestra es
/// agregar migraciones: cada columna nueva es un `ALTER TABLE` en la v8, y una
/// columna que nadie lee no compra nada. Cuando el diseño pida el logotipo o el
/// pais, se agregan en ese momento.
///
/// `activo` si estaba: sin el, "dar de baja" una marca seria borrarla, y una
/// marca borrada deja las citas viejas del historial sin poder mostrar el texto.
/// Ver la nota de `activo` en [Tecnico].
class Marca implements EntidadPersistida {
  const Marca({
    this.id,
    required this.nombre,
    this.activo = true,
    this.creadoEn,
    this.actualizadoEn,
    this.tallerId,
    this.eliminadoEn,
    this.syncStatus = 'pending',
  });

  static const String _kId = 'id';
  static const String _kNombre = 'nombre';
  static const String _kActivo = 'activo';
  static const String _kCreadoEn = 'creado_en';
  static const String _kActualizadoEn = 'actualizado_en';
  static const String _kTallerId = 'taller_id';
  static const String _kEliminadoEn = 'eliminado_en';
  static const String _kSyncStatus = 'sync_status';

  /// UUID v4 de la fila, o `null` si todavia no se guardo.
  ///
  /// CAMBIO v7: `int?` -> `String?`. El catalogo de marcas se sincroniza entre
  /// dispositivos y un autoincremento daria una marca distinta en cada celular.
  /// Ver `lib/core/utils/uuid.dart`.
  @override
  final String? id;

  final String nombre;

  /// `true` = disponible para los formularios de cita, `false` = dada de baja.
  final bool activo;

  final DateTime? creadoEn;

  @override
  final DateTime? actualizadoEn;

  /// ID del taller al que pertenece este catalogo (v9)
  final String? tallerId;

  /// Tombstone del registro. Las consultas operativas excluyen filas con valor.
  final DateTime? eliminadoEn;

  /// `pending` hasta que SyncService confirme el push a Firestore.
  final String syncStatus;

  Marca copyWith({
    String? id,
    String? nombre,
    bool? activo,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
    String? tallerId,
    Object? eliminadoEn = _marcaSinCambio,
    String? syncStatus,
  }) {
    return Marca(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      activo: activo ?? this.activo,
      creadoEn: creadoEn ?? this.creadoEn,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
      tallerId: tallerId ?? this.tallerId,
      eliminadoEn: identical(eliminadoEn, _marcaSinCambio)
          ? this.eliminadoEn
          : eliminadoEn as DateTime?,
      syncStatus: syncStatus ?? this.syncStatus,
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
      // "¿tiene id?" no sirve para distinguir un alta de una edicion, y mandar
      // `creado_en: ahora()` en un UPDATE planta la hora del guardado como si
      // fuera la de alta. El sello lo pone `MarcaRepository.crear`.
      if (creadoEn != null) _kCreadoEn: aIsoUtc(creadoEn!),
      // `actualizadoEn ?? reloj` y no el reloj a secas: si la marca ya traia una
      // marca de la nube, escribirle la hora local haria que una fila sincronizada
      // pareciera una edicion de ESTE dispositivo, y el servicio de sincronizacion
      // la volveria a subir. El reloj se usa solo cuando no hay marca previa.
      _kActualizadoEn: aIsoUtc(actualizadoEn ?? Reloj.instancia.ahora()),
      if (tallerId != null) _kTallerId: tallerId,
      _kEliminadoEn: eliminadoEn == null ? null : aIsoUtc(eliminadoEn!),
      _kSyncStatus: syncStatus,
    };
  }

  factory Marca.fromMap(Map<String, Object?> map) {
    return Marca(
      // `as String?` y no `as int?`: la PK es TEXT desde la v7.
      id: map[_kId]?.toString(),
      nombre: (map[_kNombre] as String?) ?? '',
      activo: ((map[_kActivo] as int?) ?? 1) != 0,
      creadoEn: desdeIso(map[_kCreadoEn]),
      actualizadoEn: desdeIso(map[_kActualizadoEn]),
      tallerId: map[_kTallerId]?.toString(),
      eliminadoEn: desdeIso(map[_kEliminadoEn]),
      syncStatus: (map[_kSyncStatus] as String?) ?? 'pending',
    );
  }
}

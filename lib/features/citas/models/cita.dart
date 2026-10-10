import 'dart:convert';

import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/utils/borrado_logico.dart';
import 'package:autofix/core/utils/reloj.dart';
import 'package:autofix/features/citas/models/codigo_de_cita.dart';

/// Estados que realmente se guardan.
///
/// 'ATRASADAS' no es uno: se deriva de [Cita.esAtrasada]. Persistirlo obligaria
/// a una cita vencida a "saltar" de estado al completarse y se pierde la
/// trazabilidad de cuando se atraso.
enum EstadoCita {
  pendiente('Pendiente'),
  aceptada('Aceptada'),
  rechazada('Rechazada'),
  esperandoPieza('Esperando Pieza'),
  enProceso('En proceso'),
  completado('Completado');

  const EstadoCita(this.etiqueta);

  /// Texto exacto que consume la UI, para que el mapa de colores matchee sin
  /// transformaciones intermedias.
  final String etiqueta;

  /// Se persiste `.name` y no la etiqueta: `.name` es estable aunque el diseño
  /// renombre el texto visible.
  static EstadoCita desdeNombre(String valor) {
    for (final estado in EstadoCita.values) {
      if (estado.name == valor ||
          estado.etiqueta.toLowerCase() == valor.toLowerCase()) {
        return estado;
      }
    }
    return EstadoCita.pendiente;
  }

  static EstadoCita desdeEtiqueta(String valor) => EstadoCita.values.firstWhere(
    (e) => e.etiqueta == valor,
    orElse: () => EstadoCita.pendiente,
  );
}

/// Entidad de dominio. No importa sqflite ni el helper de base: las claves de
/// fila son literales aca adentro para que el mismo modelo se pueda mapear
/// contra SQLite, contra Postgres o contra un Map de test. El test de esquema
/// (PRAGMA table_info) avisa si el CREATE TABLE se desincroniza.
///
/// -----------------------------------------------------------------
/// CAMBIOS DE LA v7 (leer antes de tocar nada de esto)
/// -----------------------------------------------------------------
///
/// 1. `id` paso de `int?` a `String?`, y es un UUID v4. Antes era el
///    autoincremento de SQLite, que es un contador POR DISPOSITIVO: dos
///    dispositivos de la v6 asignaban el mismo numero a dos citas distintas, y al
///    sincronizar con Firestore una sobrescribia a la otra. Ver
///    `lib/core/utils/uuid.dart`.
///
/// 2. Se agrego `codigoVisible`: el numero que el humano lee. Antes se
///    mostraba el id crudo con un `padLeft(6, '0')` que con un UUID no tiene
///    sentido. Ver `codigo_de_cita.dart`.
///
/// 3. Todos los tiempos se escriben y se leen en UTC. Antes era el reloj local,
///    lo que hacia incomparables dos citas de dispositivos en husos distintos.
///
/// 4. Se agrego `trazabilidad` (eliminado_en / eliminado_por / restaurado_en).
///    No hay mas borrado fisico: `CitaRepository.eliminar` ahora MARCA la fila.
///    Ver `borrado_logico.dart`.
class Cita implements EntidadPersistida {
  const Cita({
    this.id,
    this.codigoVisible = codigoCitaTemporal,
    required this.cliente,
    this.telefono = '',
    this.correoCliente = '',
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
    this.syncStatus = 'pending',
    this.trazabilidad = Trazabilidad.vacia,
    this.motivoRechazo,
  });

  static const String etiquetaAtrasadas = 'ATRASADAS';

  static const String _kId = 'id';
  static const String _kCodigoVisible = 'codigo_visible';
  static const String _kCliente = 'cliente';
  static const String _kTelefono = 'telefono';
  static const String _kCorreoCliente = 'correo_cliente';
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
  static const String _kMotivoRechazo = 'motivo_rechazo';
  static const String _kCreadoEn = 'creado_en';
  static const String _kActualizadoEn = 'actualizado_en';
  static const String _kTotal = 'total';
  static const String _kSyncStatus = 'sync_status';

  /// Id (UUID v4) o `null` si la cita todavia no se ha guardado.
  ///
  /// `String?` y no `String` porque la entidad existe en memoria antes de
  /// guardarse: el formulario arma una cita, la valida y recien ahi se persiste.
  ///
  /// Para GENERARLO hay que llamar a [Uuid.instancia.generar()], no a
  /// `DateTime.now().millisecondsSinceEpoch`. Los ids los pone la CAPA DE DATOS
  /// (`CitaRepository.crear`), no este modelo: el modelo describe lo que es una
  /// cita, y "crear una cita nueva" es una operacion de la base.
  @override
  final String? id;

  /// El numero que se muestra en pantalla: 'CITA-0004'.
  ///
  /// Nace como [codigoCitaTemporal] y lo reemplaza la nube. La secuencia NO se
  /// puede generar en el cliente porque dos dispositivos podrian tomar el mismo
  /// numero: hace falta el documento contador de Firestore. Ver
  /// [codigo_de_cita.dart].
  ///
  /// `final String` y no `String?` a proposito: una cita recien creada SIEMPRE
  /// tiene algo que mostrar. Lo que no tiene es un numero propio, y para eso esta
  /// el valor temporal, que se ve en pantalla como tal en vez de como un hueco.
  final String codigoVisible;

  final String cliente;
  final String telefono;

  /// Correo del contacto. Viene del perfil del cliente que agenda (la app lo
  /// prellena en el formulario) y es la segunda via de contacto del taller
  /// junto con [telefono]. Columna de la v10.
  final String correoCliente;
  final String vehiculo;
  final String marca;
  final String modelo;
  final int anio;
  final String placa;
  final List<String> servicios;
  final String tecnico;
  final String descripcion;

  /// Instante UTC de la cita.
  ///
  /// UTC y no hora local a proposito, aunque sea contraintuitivo: es el instante
  /// de una cita que el usuario eligio escribiendo "el jueves a las 3", y se
  /// guarda como UTC para que dos dispositivos puedan compararla con `<` sin
  ///Zones horarias. Para MOSTRARLA se convierte con [aLocal], en la capa de
  ///pintado y no aca. Ver `reloj.dart`.
  final DateTime fechaCita;

  final EstadoCita estado;

  /// Id del taller AFILIADO donde se agenda la cita.
  ///
  /// `String?` y no `String` a proposito: las citas que ya existian antes de la
  /// v4 no tienen taller, y las que crea el escaner QR todavia no lo_eligen.
  /// Nullable significa "no sabemos todavia", que es distinto de "un taller con id
  /// vacio".
  ///
  /// Y es un UUID, no un numero: antes el id de taller era el autoincremento de
  /// ESTE dispositivo, asi que el "taller 2" del celular A y el "taller 2" del
  /// celular B eran distintos, y al sincronizar las citas de uno aparecian en el
  /// historial del otro. Ver `taller.dart`.
  final String? tallerId;

  final DateTime? creadoEn;

  @override
  final DateTime? actualizadoEn;
  final int total;

  /// Estado de sincronizacion con Firestore (Fase 2).
  ///
  /// 'pending' = recién creada/modificada localmente, falta subir.
  /// 'error' = falló el último intento; sigue en cola para volver a intentarse.
  /// 'synced' = coincide con la nube.
  /// Se escribe SIEMPRE en el mapa (no es opcional) porque la columna tiene
  // NOT NULL DEFAULT 'pending' en la tabla.
  final String syncStatus;

  /// Borrado logico. Antes `eliminar()` hacia un `DELETE` fisico, que con varios
  /// dispositivos resucitaba la cita en cuanto el otro la rebia de la nube.
  final Trazabilidad trazabilidad;

  /// Motivo de rechazo (cuando estado == EstadoCita.rechazada).
  ///
  /// Se muestra al cliente en "Mis citas" para que sepa por que no se acepto.
  final String? motivoRechazo;

  /// Si la fila esta borrada. Es lo que filtra `WHERE eliminado_en IS NULL` en
  /// SQL, y lo que la UI consulta para no pintar una papelera por error.
  bool get estaBorrada => trazabilidad.estaBorrada;

  /// Si el codigo todavia no fue confirmado por la nube.
  bool get tieneCodigoDefinitivo => !esCodigoTemporal(codigoVisible);

  /// Lo que se escribe en pantalla como identificador de la orden.
  ///
  /// Con numero confirmado es el numero. Sin numero es el marcador temporal, que
  /// dice la verdad ("la nube todavia no me confirmo esto") en vez de mostrar un
  /// UUID o un hueco.
  String get identificadorParaPantalla => codigoVisible;

  /// La fecha ya pasó y la cita sigue activa (no fue completada ni rechazada).
  /// La hora no cambia la clasificación: una cita de hoy sigue vigente hasta
  /// el final del día.
  ///
  /// `ahora` va por parametro a proposito: leer el reloj adentro hace que dos
  /// dispositivos clasifiquen la misma cita distinto, y en cuanto hay
  /// sincronizacion eso ya no es una discrepancia visual sino conflicto de datos.
  /// Quien arma la lista lo pasa una sola vez para toda la pasada.
  bool esAtrasada(DateTime ahora) {
    // `fechaCita` viene de la base en UTC, pero "el dia de la cita"
    // es un concepto de horario local, igual que `ahora`. Sin el
    // `toLocal`, una cita de hoy a la noche se lee con fecha UTC de
    // manana y no cuadra con el dia que se esta consultando.
    final local = fechaCita.toLocal();
    final fechaDia = DateTime(local.year, local.month, local.day);
    final ahoraDia = DateTime(ahora.year, ahora.month, ahora.day);
    return estado != EstadoCita.completado &&
        estado != EstadoCita.rechazada &&
        fechaDia.isBefore(ahoraDia);
  }

  /// Llave exacta del mapa de colores de la UI. Va en mayusculas porque asi
  /// esta definida alla.
  String etiquetaUI(DateTime ahora) {
    if (esAtrasada(ahora)) return etiquetaAtrasadas;
    // Mapear estados que ya no existen en la UI admin a 'Pendiente'
    switch (estado) {
      case EstadoCita.aceptada:
        return 'Pendiente';
      case EstadoCita.rechazada:
        return 'Rechazada';
      default:
        return estado.etiqueta;
    }
  }

  Cita copyWith({
    String? id,
    String? codigoVisible,
    String? cliente,
    String? telefono,
    String? correoCliente,
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
    String? tallerId,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
    int? total,
    String? syncStatus,
    Trazabilidad? trazabilidad,
    String? motivoRechazo,
  }) {
    return Cita(
      id: id ?? this.id,
      codigoVisible: codigoVisible ?? this.codigoVisible,
      cliente: cliente ?? this.cliente,
      // Era `?? this.cliente`, un typo que hacia que cualquier `copyWith` sin
      // telefono explicito (marcar borrada, cambiar estado, restaurar)
      // sobrescribiera el telefono con el NOMBRE del cliente. Como esos
      // `copyWith` alimentan un `UPDATE`, el telefono del cliente se perdia en
      // la primera edicion de la cita.
      telefono: telefono ?? this.telefono,
      correoCliente: correoCliente ?? this.correoCliente,
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
      syncStatus: syncStatus ?? this.syncStatus,
      trazabilidad: trazabilidad ?? this.trazabilidad,
      motivoRechazo: motivoRechazo ?? this.motivoRechazo,
    );
  }

  /// Copia con el borrado marcado. Lo usa `CitaRepository.eliminar`.
  ///
  /// Va como metodo y no como un `copyWith` mas porque el nombre obliga a que en
  /// la llamada se vea que es un BORRADO LOGICO. Un `copyWith(trazabilidad: ...)`
  /// a secas se puede escribir sin querer.
  Cita marcarBorrada({required DateTime cuando, String? por}) {
    return copyWith(
      trazabilidad: trazabilidad.marcarBorrada(cuando: cuando, por: por),
      // El sello de modificacion se avanza tambien en un borrado: es una
      // escritura y la nube tiene que saber que hubo una, o el `onSnapshot`
      // confundira un borrado con una fila que nunca cambio.
      actualizadoEn: cuando,
    );
  }

  /// Copia con la restauracion marcada. Lo usa `CitaRepository.restaurar`.
  ///
  /// [actualizadoEn] NO se toca a proposito: el sello de modificacion lo pone el
  /// repositorio, que es quien conoce el reloj del reloj de la base. Dejarlo
  /// quieto aqui hace que una restauracion no parezca una escritura nueva.
  Cita marcarRestaurada({required DateTime cuando}) {
    return copyWith(
      trazabilidad: trazabilidad.marcarRestaurada(cuando: cuando),
    );
  }

  Map<String, Object?> toMap() {
    return {
      // El id solo va si ya existe: mandarlo en null en un INSERT lo rompe.
      if (id != null) _kId: id,
      _kCodigoVisible: codigoVisible,
      _kCliente: cliente,
      _kTelefono: telefono,
      _kCorreoCliente: correoCliente,
      _kVehiculo: vehiculo,
      _kMarca: marca,
      _kModelo: modelo,
      _kAnio: anio,
      _kPlaca: placa,
      // SQLite no tiene arrays: la lista viaja como JSON. `fromMap` la revierte.
      _kServicios: jsonEncode(servicios),
      _kTecnico: tecnico,
      _kDescripcion: descripcion,
      // `aIsoUtc` y no `fechaCita.toIso8601String()`: la columna tiene que quedar
      // SIEMPRE en UTC con la `Z`, porque es la que se ordena y se compara con
      // `<` y `>=`. Un reloj local sin `Z` se ordenaria en otra posicion.
      _kFechaCita: aIsoUtc(fechaCita),
      _kEstado: estado.name,
      // `tallerId` va siempre en el mapa, incluso cuando es null: es lo que
      // limpia la columna si se desasigna el taller. Omitirla en un UPDATE
      // dejaria el id viejo pegado a la cita.
      _kTallerId: tallerId,
      // `creado_en` se ESCRIBE UNA SOLA VEZ, al crear. Si el UPDATE lo mandara
      // siempre, cada guardado reescribiria la fecha de creacion y se perderia
      // la trazabilidad de cuando se agendo la cita.
      //
      // OJO: la columna entra en el mapa SOLO si el modelo CONOCE el valor
      // original. La razon de que no baste con "¿tiene id?" es que la capa de
      // datos le pone el id a la cita nueva ANTES de serializarla (ver
      // `CitaRepository.crear`), asi que una cita de alta llega a `toMap()` con
      // id y sin `creadoEn`, y mandarla asi revienta el `NOT NULL`. Por eso el
      // sello de `creadoEn` lo pone `CitaRepository.crear`, que es la capa que
      // sabe si es un alta o una edicion; el modelo solo lo escribe si ya lo
      // tiene.
      //
      // Un `db.update` que no mention la columna la deja intacta, que es
      // exactamente el comportamiento que se quiere.
      if (creadoEn != null) _kCreadoEn: aIsoUtc(creadoEn!),
      // `actualizado_en` es lo contrario por definicion: se refresca en cada
      // escritura, porque de eso sirve. Se sella con el reloj UTC en vez de copiar
      // el valor que venga, asi un UPDATE cuenta como modificacion real.
      _kActualizadoEn: ahoraIso(),
      _kTotal: total,
      // Estado de sincronizacion (Fase 2). Se escribe SIEMPRE porque la
      // columna tiene NOT NULL DEFAULT 'pending'. El repositorio actualiza
      // a 'synced' tras push exitoso; aqui siempre emitimos el valor actual.
      _kSyncStatus: syncStatus,
      // Motivo de rechazo (solo se escribe cuando estado == rechazada)
      if (motivoRechazo != null && motivoRechazo!.isNotEmpty)
        _kMotivoRechazo: motivoRechazo,
      ...mapaDeTrazabilidad(trazabilidad),
    };
  }

  factory Cita.fromMap(Map<String, Object?> map) {
    return Cita(
      id: map[_kId]?.toString(),
      codigoVisible: map[_kCodigoVisible]?.toString() ?? codigoCitaTemporal,
      cliente: map[_kCliente]?.toString() ?? '',
      telefono: map[_kTelefono]?.toString() ?? '',
      correoCliente: map[_kCorreoCliente]?.toString() ?? '',
      vehiculo: map[_kVehiculo]?.toString() ?? '',
      marca: map[_kMarca]?.toString() ?? '',
      modelo: map[_kModelo]?.toString() ?? '',
      anio: _entero(map[_kAnio]),
      placa: map[_kPlaca]?.toString() ?? '',
      servicios: leerServicios(map[_kServicios]),
      tecnico: map[_kTecnico]?.toString() ?? '',
      descripcion: map[_kDescripcion]?.toString() ?? '',
      fechaCita: desdeIso(map[_kFechaCita]) ?? Reloj.instancia.ahora(),
      estado: EstadoCita.desdeNombre(
        map[_kEstado]?.toString() ?? EstadoCita.pendiente.name,
      ),
      tallerId: map[_kTallerId]?.toString(),
      creadoEn: desdeIso(map[_kCreadoEn]),
      actualizadoEn: desdeIso(map[_kActualizadoEn]),
      total: _entero(map[_kTotal]),
      syncStatus: map[_kSyncStatus]?.toString() ?? 'pending',
      motivoRechazo: (() {
        final value = map[_kMotivoRechazo];
        if (value == null) return null;
        final str = value.toString();
        return str.isEmpty ? null : str;
      })(),
      trazabilidad: Trazabilidad(
        eliminadoEn: desdeIso(map['eliminado_en']),
        eliminadoPor: map['eliminado_por']?.toString(),
        restauradoEn: desdeIso(map['restaurado_en']),
      ),
    );
  }

  static int _entero(Object? valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  /// Lee `servicios` venga como venga.
  ///
  /// `toMap()` lo serializa como JSON porque SQLite no tiene arrays, y ese es
  /// exactamente el formato que Firestore recibe al subir la misma cita
  /// (`SyncService._citaToMap` reutiliza `toMap()`), asi que una cita que
  /// BAJA de la nube trae el JSON como String y no una lista. Aceptar las dos
  /// formas (y una lista nativa, por si algun dia Firestore guarda array de
  /// verdad) es lo que permite que el mismo codigo lea SQLite y la nube.
  ///
  /// Un cast directo `as List?` sobre el String revienta con
  /// `type 'String' is not a subtype of type 'List<dynamic>?'` y deja la cita
  /// entera sin importar, no solo los servicios.
  static List<String> leerServicios(Object? crudo) {
    if (crudo is List) return crudo.map((e) => e.toString()).toList();
    if (crudo is! String || crudo.isEmpty) return const [];
    try {
      final decodificado = jsonDecode(crudo);
      if (decodificado is! List) return const [];
      return decodificado.map((e) => e.toString()).toList();
    } on FormatException {
      return const [];
    }
  }
}

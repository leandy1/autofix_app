import 'dart:math' as math;

import '../../../core/data/base_repository.dart';

/// Taller AFILIADO a AutoFix: uno de los pocos que la empresa tiene en su red.
///
/// Por que existe esta entidad y no se reutiliza el `TallerCliente` del diseño
/// (`lib/models/cliente_dashboard_data.dart`): aquel es un modelo de PANTALLA. No
/// implementa [EntidadPersistida], no tiene id y por lo tanto no puede entrar a
/// un `BaseRepository`. Este si: por eso es el unico que puede vivir en SQLite y
/// ser la fuente de verdad del mapa.
///
/// Alcance (directriz de Leandy): NO buscamos talleres libres en el mundo. Solo
/// mostramos los que estan guardados aca. Por eso la tabla se siembra y se
/// administra, en vez de consultarse a una API de terceros.
class Taller implements EntidadPersistida {
  const Taller({
    this.id,
    required this.nombre,
    this.direccion = '',
    this.telefono = '',
    required this.latitud,
    required this.longitud,
    this.activo = true,
    this.creadoEn,
    this.actualizadoEn,
  });

  static const String _kId = 'id';
  static const String _kNombre = 'nombre';
  static const String _kDireccion = 'direccion';
  static const String _kTelefono = 'telefono';
  static const String _kLatitud = 'latitud';
  static const String _kLongitud = 'longitud';
  static const String _kActivo = 'activo';
  static const String _kCreadoEn = 'creado_en';
  static const String _kActualizadoEn = 'actualizado_en';

  /// Radio medio terrestre en km (IUGN).
  static const double _radioTierraKm = 6371.0;

  @override
  final int? id;

  final String nombre;

  /// Texto libre, no coordenadas. Se muestra en el selector del formulario y en la
  /// ficha del mapa. '' es un valor valido: hay afiliados que todavia no tienen
  /// direccion cargada, y "sin direccion" no es lo mismo que "direccion
  /// desconocida".
  final String direccion;

  /// Telefono de contacto del taller.
  ///
  /// Texto y no `int` a proposito: en Republica Dominicana el numero se escribe
  /// con guiones y con el 809/829/849 adentro ('809-555-0101'). Guardarlo como
  /// entero obliga a quitar los guiones para poder guardarlo, y a ponerselos
  /// despues para poder mostrarlo.
  final String telefono;

  /// Grados decimales, y `double` a proposito: un entero trunca la posicion y el
  /// punto cae en la calle de al lado. SQLite los guarda como REAL.
  ///
  /// Van como `required` y NO admiten null. Un taller sin coordenadas no se puede
  /// pintar en un mapa, y un null aqui terminaria en un `LatLng(null)` que
  /// revienta la pantalla. Si hace falta un borrador sin ubicacion, se deja 0/0 y
  /// se marca `activo = false`.
  final double latitud;
  final double longitud;

  /// Baja logica, no fisica.
  ///
  /// Borrar un taller de verdad dejaria citas viejas apuntando a un id que ya no
  /// existe, y ese nombre es justo lo que se muestra en el historial del cliente.
  /// Con `activo = false` desaparece del mapa y del selector, pero el registro
  /// sigue ahi para las citas que ya lo citaron.
  final bool activo;

  final DateTime? creadoEn;

  /// No es opcional en la practica: es el campo contra el que la sincronizacion
  /// resuelve conflictos. Dejarlo siempre null haria inutil la interfaz.
  @override
  final DateTime? actualizadoEn;

  /// La distancia al cliente NO es un campo guardado, y esa es la decision.
  ///
  /// Depende de donde esta el cliente, o sea que cambia con cada persona y cada
  /// momento. Si la guardamos en la tabla queda vieja al instante y el taller se
  /// queda eternamente "a 1.2 km". Por eso se calcula siempre, con este metodo,
  /// contra la posicion actual. El costo es recalcular unos pocos doubles; el de
  /// guardar un dato que miente es otro.
  double distanciaKmDesde(double latitud, double longitud) {
    return distanciaHaversineKm(latitud, longitud, this.latitud, this.longitud);
  }

  /// Distancia en km entre dos coordenadas, por la formula de Haversine.
  ///
  /// Vive en el modelo y no en la pantalla porque TODA la app necesita la misma
  /// formula: el mapa para ordenar, la lista para mostrar "a X km", y el test
  /// para verificar que el filtro de la base coincide con el calculo de Dart. Si
  /// viviera en la UI, cada pantalla tendria su propia version y dos mostrarian
  /// numeros distintos para el mismo taller.
  ///
  /// Se expone como `static` (y no privado) a proposito: asi el
  /// `TallerRepository` puede ordenar por distancia sin crear un [Taller] falso
  /// solo para preguntar, y asi el test puede verificar la formula.
  static double distanciaHaversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double aGrados = math.pi / 180.0;

    final dLat = (lat2 - lat1) * aGrados;
    final dLng = (lng2 - lng1) * aGrados;

    final senLat = math.sin(dLat / 2);
    final senLng = math.sin(dLng / 2);

    final a =
        senLat * senLat +
        math.cos(lat1 * aGrados) * math.cos(lat2 * aGrados) * senLng * senLng;

    // `sqrt(1)` y no `asin(1)`: por redondeo, `a` puede quedar en 1.0000000001 y
    // `asin` de eso devuelve NaN, que se propaga a todo el orden de la lista.
    final c = math.sqrt(math.min(1.0, a));

    return 2 * _radioTierraKm * math.asin(math.min(1.0, c));
  }

  Taller copyWith({
    int? id,
    String? nombre,
    String? direccion,
    String? telefono,
    double? latitud,
    double? longitud,
    bool? activo,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
  }) {
    return Taller(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      direccion: direccion ?? this.direccion,
      telefono: telefono ?? this.telefono,
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
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
      _kDireccion: direccion,
      _kTelefono: telefono,
      _kLatitud: latitud,
      _kLongitud: longitud,
      // SQLite no tiene booleanos: se guarda 1/0.
      _kActivo: activo ? 1 : 0,
      _kCreadoEn: (creadoEn ?? DateTime.now()).toIso8601String(),
      _kActualizadoEn: (actualizadoEn ?? DateTime.now()).toIso8601String(),
    };
  }

  factory Taller.fromMap(Map<String, Object?> map) {
    return Taller(
      id: map[_kId] as int?,
      // `nombre` es required en el modelo pero se lee como `as String?`: una fila
      // con nombre null tiene que poder LEERSE para que el admin la arregle desde
      // la pantalla, no reventar la consulta entera.
      nombre: (map[_kNombre] as String?) ?? '',
      direccion: (map[_kDireccion] as String?) ?? '',
      telefono: (map[_kTelefono] as String?) ?? '',
      // `as num?` y no `as double?`: SQLite REAL puede devolver un int si el
      // valor se guardo sin decimales (18.0), y un cast directo a double revienta
      // con un TypeError en un taller con latitud entera.
      latitud: (map[_kLatitud] as num?)?.toDouble() ?? 0,
      longitud: (map[_kLongitud] as num?)?.toDouble() ?? 0,
      activo: ((map[_kActivo] as int?) ?? 1) != 0,
      creadoEn: DateTime.tryParse(map[_kCreadoEn] as String? ?? ''),
      actualizadoEn: DateTime.tryParse(map[_kActualizadoEn] as String? ?? ''),
    );
  }
}

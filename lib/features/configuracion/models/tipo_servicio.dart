import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/utils/reloj.dart';

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
///
/// CAMBIO v7: `id` paso de `int?` (autoincremento) a `String?` (UUID v4) por la
/// misma razon que en [Tecnico], y los tiempos pasaron a UTC con [aIsoUtc]. El
/// precio se lee con `as num` porque SQLite puede devolver un REAL si la fila se
/// escribio desde otro cliente con 1200.0.
class TipoServicio implements EntidadPersistida {
  const TipoServicio({
    this.id,
    required this.nombre,
    this.precio = 0,
    this.activo = true,
    this.creadoEn,
    this.actualizadoEn,
    this.tallerId,
  });

  static const String _kId = 'id';
  static const String _kNombre = 'nombre';
  static const String _kPrecio = 'precio';
  static const String _kActivo = 'activo';
  static const String _kCreadoEn = 'creado_en';
  static const String _kActualizadoEn = 'actualizado_en';
  static const String _kTallerId = 'taller_id';

  @override
  final String? id;

  final String nombre;

  /// Precio en pesos dominicanos, sin centavos.
  final int precio;

  final bool activo;

  final DateTime? creadoEn;

  @override
  final DateTime? actualizadoEn;

  /// ID del taller al que pertenece este catalogo (v9)
  final String? tallerId;

  int get precioEnCentavos => precio * 100;

  /// Suma el precio de los servicios marcados para una cita.
  ///
  /// [catalogo] es la lista completa de tipos de servicio y [seleccionados] los
  /// NOMBRES que el cliente marco. Cruza una contra otra por nombre y no por id
  /// porque [Cita.servicios] es una lista de texto: es el JSON de la columna, y
  /// `tipos_servicio.id` no viaja con ella. Si mañana la cita guardara ids, el
  /// cruce pasa a ser por id y esta funcion no cambia de firma.
  ///
  /// Un precio NEGATIVO cuenta como 0. `precio` no tiene CHECK en la base, asi
  /// que un -500 se puede guardar a mano desde Configuracion, y el total de la
  /// cita es lo primero que ve el cliente. Un "-RD$ 500" en pantalla no se lee
  /// como un error de carga de datos: se lee como una deuda que el cliente le
  /// debe al taller. Un total subestimado es un error; un total negativo es un
  /// disparate, y un disparate es peor que un error.
  ///
  /// El resto de lo que no esta en el catalogo tambien cuenta 0 y NO se lanza.
  /// El formulario se arma con los servicios que la base tiene hoy; si el admin
  /// agrega uno entre que el cliente abrio la pantalla y guardo, el nombre no
  /// aparece en el catalogo. Romperle el envio por un dato de precio es peor
  /// que un total subestimado.
  ///
  /// Va en el modelo y no en el widget por el mismo motivo que
  /// [Taller.distanciaHaversineKm]: es la regla de negocio y la tienen que ver
  /// la pantalla, el test y el dia de mañana el panel del taller. Si viviera en
  /// la pantalla habria que reescribirla.
  static int totalDe(
    Iterable<TipoServicio> catalogo,
    Set<String> seleccionados,
  ) {
    if (seleccionados.isEmpty) return 0;

    // `Map` y no un `for` con busqueda lineal: son cuatro servicios hoy y van a
    // ser veinte, y el `where` por nombre dentro del bucle seria O(n*m) por cada
    // cita guardada.
    final precios = <String, int>{
      for (final s in catalogo)
        // `max(0)` y no un `if`: un precio negativo es dato roto, y lo que sale
        // de la suma tiene que ser un precio usable.
        if (s.precio > 0) s.nombre: s.precio,
    };

    var total = 0;
    for (final nombre in seleccionados) {
      total += precios[nombre] ?? 0;
    }
    return total;
  }

  TipoServicio copyWith({
    String? id,
    String? nombre,
    int? precio,
    bool? activo,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
    String? tallerId,
  }) {
    return TipoServicio(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      precio: precio ?? this.precio,
      activo: activo ?? this.activo,
      creadoEn: creadoEn ?? this.creadoEn,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
      tallerId: tallerId ?? this.tallerId,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) _kId: id,
      _kNombre: nombre,
      _kPrecio: precio,
      _kActivo: activo ? 1 : 0,
      // Solo si el modelo conoce el valor. Ver la nota larga de `Cita.toMap`.
      if (creadoEn != null) _kCreadoEn: aIsoUtc(creadoEn!),
      // `actualizadoEn ?? reloj` y no el reloj a secas. Ver `Tecnico.toMap`.
      _kActualizadoEn: aIsoUtc(actualizadoEn ?? Reloj.instancia.ahora()),
      if (tallerId != null) _kTallerId: tallerId,
    };
  }

  factory TipoServicio.fromMap(Map<String, Object?> map) {
    return TipoServicio(
      id: map[_kId]?.toString(),
      nombre: (map[_kNombre] as String?) ?? '',
      precio: (map[_kPrecio] as num?)?.toInt() ?? 0,
      activo: ((map[_kActivo] as int?) ?? 1) != 0,
      creadoEn: desdeIso(map[_kCreadoEn]),
      actualizadoEn: desdeIso(map[_kActualizadoEn]),
      tallerId: map[_kTallerId]?.toString(),
    );
  }
}

import 'cita.dart';

/// Resultado de las agregaciones de `citas`: cuantos hay por estado, cuanto
/// dinero se haredo y cuantas quedaron atrasadas.
///
/// Es un read-model, no una entidad: no tiene `toMap`/`fromMap` porque nunca
/// sale de la base, y no implementa `EntidadPersistida` a proposito. Meterla en
/// el contrato de persistencia haria que alguien la intente guardar.
///
/// Las claves de [porEstado] son [EstadoCita], NO textos. 'ATRASADAS' no es una
/// clave porque no es un estado guardado: se deriva de `Cita.esAtrasada`. Por eso
/// va aparte, en [atrasadas], y no mezclada en el mapa.
///
/// La composicion de las tarjetas del Dashboard ("ordenes abiertas" =
/// pendiente + esperando pieza + en proceso) NO vive aca. Ese es criterio de la
/// pantalla, y por eso lo arma `DashboardAdminController`: si se metiera en el
/// modelo, cambiar el diseno de una tarjeta obligaria a tocar el dominio.
class ResumenCitas {
  const ResumenCitas({
    required this.porEstado,
    required this.ingresos,
    required this.atrasadas,
  });

  /// El resumen de una tabla vacia. Existe para que el controller y la vista
  /// tengan siempre algo que pintar mientras carga, en vez de `null` que hay que
  /// defending en cada acceso.
  static const ResumenCitas vacio = ResumenCitas(
    porEstado: <EstadoCita, int>{},
    ingresos: 0,
    atrasadas: 0,
  );

  /// Conteo por estado REALMENTE guardado. Los estados que no aparecen en el
  /// mapa son cero: se consulta con [contar], que no lanza.
  final Map<EstadoCita, int> porEstado;

  /// Suma de `total` de las citas COMPLETADAS.
  ///
  /// El `total` se escribe al agendar, como precio cotizado, y por eso una cita
  /// pendiente ya lo tiene. Sumar sin filtrar contaria dinero que el taller
  /// todavia no cobró, que es justo el numero que no se puede mostrar en una
  /// tarjeta de ingresos.
  final int ingresos;

  /// Citas no completadas cuya fecha ya paso.
  final int atrasadas;

  int contar(EstadoCita estado) => porEstado[estado] ?? 0;

  int get completadas => contar(EstadoCita.completado);

  int get totalCitas => porEstado.values.fold(0, (suma, n) => suma + n);

  @override
  String toString() =>
      'ResumenCitas(total: $totalCitas, ingresos: $ingresos, atrasadas: $atrasadas)';
}

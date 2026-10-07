import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/citas/models/resumen_citas.dart';

/// Estado y logica de la pantalla de Dashboard del administrador.
///
/// Es la unica capa que la vista conoce: la pantalla no abre la base ni se
/// importa `demo_admin_data.dart`. Sigue el mismo contrato que
/// `ConfiguracionController`: expone entidades y texto ya formateado, nunca
/// `Color` ni `Widget`.
///
/// DOS resúmenes y no uno, porque las tarjetas del diseño no son todas del dia:
///
/// - `_global` (todo el historial) alimenta "ordenes abiertas", "atrasadas" y el
///   grafico de reparto por estado. Son del taller: una orden del martes que sigue
///   en proceso sigue abierta el jueves.
/// - `_dia` (la fecha seleccionada) alimenta "vehiculos en el taller",
///   "completadas" e "ingresos".
///
/// Ojo con "vehiculos en el taller": del dia, no global. Es la unica tarjeta que
/// se apoya en las dos fuentes y la que esta en duda. El nombre suena a un
/// medidor del taller entero ("cuantos carros hay estacionados ahora"), y leido
/// asi deberia ser global; pero el rotulo lleva la barra de fecha y el diseno no
/// dice "del taller". Si el negocio lo confirma como global, el cambio es una
/// linea: `_global.contar(EstadoCita.enProceso)` en vez de `_dia`, mas su prueba.
///
/// Reducirlos a un solo resumen obligaria a elegir: o las ordenes abiertas
/// cambiaran de numero cada vez que el admin mira otra fecha (mentira), o los
/// ingresos contarian todo el historial en vez de lo del dia (tambien mentira).
class DashboardAdminController extends ChangeNotifier {
  DashboardAdminController({CitaRepository? repositorio, String? tallerId})
    : _repo = repositorio ?? CitaRepository.instance,
      _tallerId = tallerId;

  final CitaRepository _repo;
  final String? _tallerId;

  String? get _idTallerEfectivo => _tallerId ?? SesionAdmin.instance.tallerId;

  /// Nombre del taller asignado a la sesión actual (o null si no hay sesión).
  String? get tallerNombre => SesionAdmin.instance.tallerNombre;

  /// Correo del admin logueado (o null si no hay sesión).
  String? get adminEmail => SesionAdmin.instance.adminEmail;

  late final NumberFormat _dinero = NumberFormat('#,##0');

  DateTime _fecha = _soloDia(DateTime.now());
  ResumenCitas _global = ResumenCitas.vacio;
  ResumenCitas _dia = ResumenCitas.vacio;
  List<Cita> _citasDia = const <Cita>[];

  bool _cargando = true;
  bool _actualizando = false;
  bool _tieneDatos = false;
  String? _error;

  // ---------------------------------------------------------------------
  // Estado
  // ---------------------------------------------------------------------

  /// Dia que se esta mirando. Arranca en hoy.
  ///
  /// Sin hora, y no `DateTime.now()` tal cual. El filtro de dia de SQL solo usa
  /// la parte de la fecha, asi que la hora no molesta a la consulta, pero si
  /// molesta a cualquier comparacion: `_fecha` con hora y `seleccionarFecha`
  /// normalizada a medianoche no serian el mismo tipo de valor, y la primera
  /// comparacion `==` entre las dos daria false.
  DateTime get fecha => _fecha;

  /// Se queda solo con la parte de la fecha, sin la hora.
  static DateTime _soloDia(DateTime fecha) =>
      DateTime(fecha.year, fecha.month, fecha.day);

  /// Primera carga, cuando no hay nada que pintar todavia.
  ///
  /// Va aparte de [actualizando] a proposito: si los dos fueran el mismo flag,
  /// cambiar de fecha en el calendario del encabezado taparia la pantalla
  /// entera con un spinner para esconder numeros que ya estan ahi. Con dos
  /// flags, el encabezado cambia de fecha al instante y solo los numeros se
  /// refrescan.
  bool get cargando => _cargando;

  /// Se esta releiendo la base con datos ya en pantalla.
  bool get actualizando => _actualizando;

  /// Ultimo error, en texto que se puede mostrar tal cual. `null` cuando la
  /// ultima operacion salio bien.
  String? get error => _error;

  bool get hayCitas => _citasDia.isNotEmpty;

  /// Citas de la fecha seleccionada, ya ordenadas por hora.
  List<Cita> get citasDia => List.unmodifiable(_citasDia);

  // ---------------------------------------------------------------------
  // Las tarjetas
  // ---------------------------------------------------------------------

  /// Citas de la fecha seleccionada que ya se completaron y se entregaron.
  int get completadas => _dia.completadas;

  /// Ingresos cobrados de la fecha seleccionada: solo citas completadas.
  int get ingresos => _dia.ingresos;

  /// Citas no completadas cuya fecha ya paso, en todo el historial.
  ///
  /// Global y no del dia a proposito. "Atrasada" significa que la fecha ya paso
  /// y el trabajo no se entrego, asi que una cita del martes sigue atrasada
  /// mirando el jueves: contarla solo en el dia que se esta mirando la borraria
  /// de la pantalla en vez de mostrar el problema.
  int get atrasadas => _global.atrasadas;

  /// Conteo global por estado.
  Map<EstadoCita, int> get conteoPorEstado =>
      Map<EstadoCita, int>.unmodifiable(_global.porEstado);

  /// Total de citas de todo el historial, la base sobre la que se calcula el
  /// porcentaje de cadaPORCION del grafico.
  int get totalCitas => _global.totalCitas;

  /// Reparto global por estado, en el orden del enum y SIN los estados en cero.
  ///
  /// Es lo que alimenta el grafico de `fl_chart`. Filtra los ceros aqui y no en
  /// la vista por dos motivos: una seccion con `value: 0` en un `PieChart` no
  /// dibuja nada pero si ensucia la leyenda con una fila en 0%, y el orden lo
  /// fija el enum, no el `GROUP BY` de SQL, que puede devolver las filas en
  /// cualquier orden segua el indice que este usando.
  List<({EstadoCita estado, int cantidad})> get repartoPorEstado => EstadoCita
      .values
      .map((e) => (estado: e, cantidad: _global.contar(e)))
      .where((r) => r.cantidad > 0)
      .toList(growable: false);

  /// Ordenes abiertas del taller: lo que esta en turno y todavia no se entrego.
  ///
  /// Citas aceptadas o en operación que todavía no se han entregado. Las
  /// rechazadas y completadas no son órdenes abiertas.
  int get ordenesAbiertas =>
      _global.contar(EstadoCita.pendiente) +
      _global.contar(EstadoCita.aceptada) +
      _global.contar(EstadoCita.esperandoPieza) +
      _global.contar(EstadoCita.enProceso);

  /// Vehiculos de la fecha seleccionada que siguen en proceso: los que estan
  /// ocupando espacio del taller ahora mismo.
  int get vehiculosEnTaller => _dia.contar(EstadoCita.enProceso);

  // ---------------------------------------------------------------------
  // Formato
  // ---------------------------------------------------------------------

  /// 'RD\$ 12,400'.
  ///
  /// El 0 se muestra como 'RD$ 0' y no como 'RD$ -' (que es lo que hace
  /// `ConfiguracionController` con los precios): alli el cero significa "el
  /// admin todavia no le puso precio" y hay que disimularlo para que no parezca
  /// un trabajo gratis. Aca el cero significa "no se facturo nada", que es un
  /// dato real y asi se dice.
  String formatearDinero(int monto) => 'RD\$ ${_dinero.format(monto)}';

  // ---------------------------------------------------------------------
  // Lectura
  // ---------------------------------------------------------------------

  /// Carga el resumen global y el de la fecha seleccionada.
  ///
  /// Las tres consultas van en `Future.wait` y no encadenadas: son de la misma
  /// base local y no dependen entre si, asi que se resuelven en un solo viaje.
  Future<void> cargar() async {
    final primeraVez = !_tieneDatos;
    if (primeraVez) {
      _cargando = true;
    } else {
      _actualizando = true;
    }
    _error = null;
    notifyListeners();

    try {
      final taller = _idTallerEfectivo;
      final resultados = await Future.wait(<Future<Object?>>[
        _repo.resumir(tallerId: taller),
        _repo.resumir(fecha: _fecha, tallerId: taller),
        _repo.obtenerDelDia(_fecha, tallerId: taller),
      ]);

      _global = resultados[0] as ResumenCitas;
      _dia = resultados[1] as ResumenCitas;
      _citasDia = resultados[2] as List<Cita>;
      _error = null;
      _tieneDatos = true;
    } on Exception catch (_) {
      // No se pisa lo que ya estaba en pantalla: un fallo al cambiar de fecha
      // no puede dejar las tarjetas en cero, que es peor que mostrar el numero
      // del dia anterior.
      _error = 'No se pudo leer la informacion de las citas.';
    }

    _cargando = false;
    _actualizando = false;
    notifyListeners();
  }

  /// Cambia el dia que se mira y recarga lo que depende de el.
  ///
  /// Solo recarga el resumen y la lista DEL dia: el global no cambia con la
  /// fecha, y volverlo a pedir seria un viaje a la base para obtener lo mismo.
  Future<void> seleccionarFecha(DateTime nueva) async {
    _fecha = _soloDia(nueva);
    _actualizando = true;
    _error = null;
    // Se avisa antes de tocar la base para que el encabezado muestre la fecha
    // nueva de inmediato y el usuario vea que el toque registro.
    notifyListeners();

    try {
      final taller = _idTallerEfectivo;
      final resultados = await Future.wait(<Future<Object?>>[
        _repo.resumir(fecha: _fecha, tallerId: taller),
        _repo.obtenerDelDia(_fecha, tallerId: taller),
      ]);

      _dia = resultados[0] as ResumenCitas;
      _citasDia = resultados[1] as List<Cita>;
      _error = null;
      _tieneDatos = true;
    } on Exception catch (_) {
      _error = 'No se pudo leer la informacion de las citas.';
    }

    _actualizando = false;
    notifyListeners();
  }

  /// Vuelve a leer, util cuando el admin cambia el estado de una cita en otra
  /// pantalla y vuelve al Dashboard.
  Future<void> recargar() => cargar();

  /// Dia un dia hacia atras, para las flechas del encabezado.
  Future<void> diaAnterior() =>
      seleccionarFecha(_fecha.subtract(const Duration(days: 1)));

  /// Dia un dia hacia adelante.
  Future<void> diaSiguiente() =>
      seleccionarFecha(_fecha.add(const Duration(days: 1)));
}

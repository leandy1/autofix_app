import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';

/// Estado y logica de la pantalla de citas.
///
/// Es la unica capa que la vista conoce. Leandy engancha su diseño a este
/// `ChangeNotifier` sin tocar la vista actual ni el repositorio.
///
/// No expone `Color` ni `Widget`: devuelve entidades y texto ya formateado.
/// El mapeo etiqueta -> color es del diseño, no del dominio.
class CitasController extends ChangeNotifier {
  CitasController({CitaRepository? repositorio})
      : _repo = repositorio ?? CitaRepository.instance;

  final CitaRepository _repo;

  static final DateFormat _fechaHora = DateFormat('dd/MM/yyyy HH:mm');

  /// Orden de los grupos del dia. Las 5 llaves siempre estan, aunque el grupo
  /// este vacio, para que el acordeon pueda pintar '0' sin romperse el for.
  static const List<String> etiquetas = [
    Cita.etiquetaAtrasadas,
    'Pendiente',
    'Esperando Pieza',
    'En proceso',
    'Completado',
  ];

  List<Cita> _citas = const [];
  bool _cargando = true;
  String? _error;

  List<Cita> get citas => List.unmodifiable(_citas);
  bool get cargando => _cargando;
  String? get error => _error;
  bool get hayCitas => _citas.isNotEmpty;

  static String formatearFechaHora(DateTime fecha) => _fechaHora.format(fecha);

  Future<void> cargar() async {
    _cargando = true;
    _error = null;
    notifyListeners();

    final resultado = await _intentar(() => _repo.obtenerTodas());
    if (resultado != null) _citas = resultado;
    _cargando = false;
    notifyListeners();
  }

  /// CREATE si la cita no tiene id, UPDATE si lo tiene: el mismo metodo para
  /// los dos casos, que es como decide el formulario.
  ///
  /// Vuelve a leer la lista en vez de parchear el array en memoria: el orden
  /// de `obtenerTodas` es por fecha y una insercion al principio lo dejaria
  /// desalineado con lo que ve el usuario.
  Future<bool> guardar(Cita cita) async {
    final ok = await _intentar(() async {
      if (cita.id == null) {
        await _repo.crear(cita);
      } else {
        await _repo.actualizar(cita);
      }
      return _repo.obtenerTodas();
    });

    if (ok == null) return false;
    _citas = ok;
    notifyListeners();
    return true;
  }

  Future<bool> cambiarEstado(int id, EstadoCita estado) async {
    final ok = await _intentar(() async {
      await _repo.cambiarEstado(id, estado);
      return _repo.obtenerTodas();
    });

    if (ok == null) return false;
    _citas = ok;
    notifyListeners();
    return true;
  }

  Future<bool> eliminar(int id) async {
    final ok = await _intentar(() async {
      await _repo.eliminar(id);
      return _repo.obtenerTodas();
    });

    if (ok == null) return false;
    _citas = ok;
    notifyListeners();
    return true;
  }



  /// Citas del dia agrupadas por la etiqueta que consume la UI.
  ///
  /// Al consultar el dia actual, incluye en ATRASADAS las citas pendientes de
  /// cualquier fecha anterior, para que el atraso se gestione desde hoy.
  ///
  /// El `ahora` se fija UNA vez por llamada: si cada fila calculara su propia
  /// hora, dos citas del mismo segundo podrian caer en grupos distintos y el
  /// conteo del acordeon no cerraria con la lista.
  Map<String, List<Cita>> agruparPorEstado(DateTime fecha, {DateTime? ahora}) {
    final momento = ahora ?? DateTime.now();
    final dia = _claveDia(fecha);
    final hoy = _claveDia(momento);
    final mapa = <String, List<Cita>>{
      for (final etiqueta in etiquetas) etiqueta: <Cita>[],
    };

    for (final cita in _citas) {
      if (dia == hoy && cita.esAtrasada(momento)) {
        mapa[Cita.etiquetaAtrasadas]!.add(cita);
        continue;
      }
      if (_claveDia(cita.fechaCita) != dia) continue;
      mapa[cita.etiquetaUI(momento)]!.add(cita);
    }
    return mapa;
  }

  /// Ejecuta una escritura dejando el motivo del fallo en [error] y devuelve
  /// `null` si fallo, para que el caller decida si sigue o no.
  Future<List<Cita>?> _intentar(Future<List<Cita>> Function() accion) async {
    try {
      final resultado = await accion();
      _error = null;
      return resultado;
    } on Exception catch (e) {
      _error = e.toString();
      return null;
    }
  }

  static String _claveDia(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';
}

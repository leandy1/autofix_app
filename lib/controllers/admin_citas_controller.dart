import 'package:flutter/foundation.dart';
import '../models/cita_admin.dart';


class AdminCitasController extends ChangeNotifier {
  final List<CitaAdmin> _citas = [];

  void agregarCita(CitaAdmin cita) {
    _citas.add(cita);
    notifyListeners();
  }

  void actualizarCita(CitaAdmin citaActualizada) {
    final index = _citas.indexWhere((cita) => cita.id == citaActualizada.id);
    if (index == -1) {
      _citas.add(citaActualizada);
    } else {
      _citas[index] = citaActualizada;
    }
    notifyListeners();
  }

  List<CitaAdmin> citasPorEstado(EstadoCitaAdmin estado) {
    return _citas.where((cita) => cita.estado == estado).toList();
  }

  List<CitaAdmin> citasPorCategorias(String categoria) {
     final estado = switch (categoria) {
      'ATRASADAS' => EstadoCitaAdmin.atrasada,
      'Pendiente' => EstadoCitaAdmin.pendiente,
      'Esperando Pieza' => EstadoCitaAdmin.esperandoPieza,
      'En proceso' => EstadoCitaAdmin.enProceso,
      'Completado' => EstadoCitaAdmin.completada,
      _ => null,
    };

    if(estado == null){return [];}
    return citasPorEstado(estado);
  }
}
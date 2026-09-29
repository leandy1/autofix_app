import 'package:flutter/material.dart';

import '../models/solicitud_admin.dart';

class SolicitudesAdminService {
  SolicitudesAdminService()
      : _solicitudes = [
          SolicitudAdmin(
            id: 1,
            cliente: 'María Pérez',
            telefono: '809-555-0142',
            taller: 'AutoFix Central',
            marcaVehiculo: 'Honda',
            modeloVehiculo: 'Civic',
            anioVehiculo: 2021,
            placa: 'A456789',
            servicios: const [
              'Frenos',
              'Revisión general',
            ],
            fecha: DateTime(2026, 10, 8),
            hora: const TimeOfDay(hour: 10, minute: 0),
            descripcion: 'Revisar ruido al frenar.',
            estado: EstadoSolicitudAdmin.nueva,
          ),
        ];

  final List<SolicitudAdmin> _solicitudes;

  List<SolicitudAdmin> get solicitudes =>
      List.unmodifiable(_solicitudes);

  List<SolicitudAdmin> get nuevas =>
      _porEstado(EstadoSolicitudAdmin.nueva);

  List<SolicitudAdmin> get pendientes => _porEstados(
        const [
          EstadoSolicitudAdmin.pendiente,
          EstadoSolicitudAdmin.fechaPropuesta,
        ],
      );

  List<SolicitudAdmin> get esperandoPieza =>
      _porEstado(EstadoSolicitudAdmin.esperandoPieza);

  List<SolicitudAdmin> get enProceso =>
      _porEstado(EstadoSolicitudAdmin.enProceso);

  List<SolicitudAdmin> get atrasadas =>
      _porEstado(EstadoSolicitudAdmin.atrasada);

  List<SolicitudAdmin> get completadas =>
      _porEstado(EstadoSolicitudAdmin.completada);

  SolicitudAdmin? obtenerPorId(int id) {
    for (final solicitud in _solicitudes) {
      if (solicitud.id == id) {
        return solicitud;
      }
    }

    return null;
  }

  SolicitudAdmin agregarSolicitud({
    required String cliente,
    required String telefono,
    required String taller,
    required String marcaVehiculo,
    required String modeloVehiculo,
    required int anioVehiculo,
    required String placa,
    required List<String> servicios,
    required DateTime fecha,
    required TimeOfDay hora,
    required String descripcion,
    required EstadoSolicitudAdmin estado,
  }) {
    final solicitud = SolicitudAdmin(
      id: _siguienteId(),
      cliente: cliente.trim(),
      telefono: telefono.trim(),
      taller: taller.trim(),
      marcaVehiculo: marcaVehiculo.trim(),
      modeloVehiculo: modeloVehiculo.trim(),
      anioVehiculo: anioVehiculo,
      placa: placa.trim(),
      servicios: List.unmodifiable(servicios),
      fecha: fecha,
      hora: hora,
      descripcion: descripcion.trim(),
      estado: estado,
    );

    _solicitudes.add(solicitud);

    return solicitud;
  }

  bool aceptarSolicitud(int id) {
    return cambiarEstado(
      id,
      EstadoSolicitudAdmin.pendiente,
    );
  }

  bool rechazarSolicitud(int id) {
    return cambiarEstado(
      id,
      EstadoSolicitudAdmin.rechazada,
    );
  }

  bool completarSolicitud(int id) {
    return cambiarEstado(
      id,
      EstadoSolicitudAdmin.completada,
    );
  }

  bool cambiarEstado(
    int id,
    EstadoSolicitudAdmin nuevoEstado,
  ) {
    final index = _buscarIndice(id);

    if (index == -1) {
      return false;
    }

    final actual = _solicitudes[index];

    _solicitudes[index] = _copiarSolicitud(
      actual,
      estado: nuevoEstado,
    );

    return true;
  }

  bool proponerFechaHora(
    int id, {
    required DateTime fecha,
    required TimeOfDay hora,
  }) {
    final index = _buscarIndice(id);

    if (index == -1) {
      return false;
    }

    final actual = _solicitudes[index];

    _solicitudes[index] = _copiarSolicitud(
      actual,
      fecha: fecha,
      hora: hora,
      estado: EstadoSolicitudAdmin.fechaPropuesta,
    );

    return true;
  }

  List<SolicitudAdmin> _porEstado(
    EstadoSolicitudAdmin estado,
  ) {
    return _solicitudes
        .where(
          (solicitud) => solicitud.estado == estado,
        )
        .toList();
  }

  List<SolicitudAdmin> _porEstados(
    List<EstadoSolicitudAdmin> estados,
  ) {
    return _solicitudes
        .where(
          (solicitud) => estados.contains(solicitud.estado),
        )
        .toList();
  }

  SolicitudAdmin _copiarSolicitud(
    SolicitudAdmin actual, {
    DateTime? fecha,
    TimeOfDay? hora,
    EstadoSolicitudAdmin? estado,
  }) {
    return SolicitudAdmin(
      id: actual.id,
      cliente: actual.cliente,
      telefono: actual.telefono,
      taller: actual.taller,
      marcaVehiculo: actual.marcaVehiculo,
      modeloVehiculo: actual.modeloVehiculo,
      anioVehiculo: actual.anioVehiculo,
      placa: actual.placa,
      servicios: actual.servicios,
      fecha: fecha ?? actual.fecha,
      hora: hora ?? actual.hora,
      descripcion: actual.descripcion,
      estado: estado ?? actual.estado,
    );
  }

  int _siguienteId() {
    if (_solicitudes.isEmpty) {
      return 1;
    }

    return _solicitudes
            .map((solicitud) => solicitud.id)
            .reduce(
              (a, b) => a > b ? a : b,
            ) +
        1;
  }

  int _buscarIndice(int id) {
    return _solicitudes.indexWhere(
      (solicitud) => solicitud.id == id,
    );
  }
}

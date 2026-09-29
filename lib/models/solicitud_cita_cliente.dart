import 'package:flutter/material.dart';

enum EstadoSolicitudCita {
  pendiente,
  fechaPropuesta,
  aceptada,
  rechazada,
  atrasada,
  esperandoPieza,
  enProceso,
  completada,
}

class SolicitudCitaCliente {
  const SolicitudCitaCliente({
    required this.id,
    required this.cliente,
    required this.telefono,
    required this.taller,
    required this.vehiculo,
    required this.servicios,
    required this.fecha,
    required this.hora,
    required this.descripcion,
    required this.estado,
  });

  final int id;
  final String cliente;
  final String telefono;
  final String taller;
  final String vehiculo;
  final List<String> servicios;
  final DateTime fecha;
  final TimeOfDay hora;
  final String descripcion;
  final EstadoSolicitudCita estado;
}

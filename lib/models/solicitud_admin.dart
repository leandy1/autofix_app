import 'package:flutter/material.dart';

enum EstadoSolicitudAdmin {
  nueva,
  pendiente,
  fechaPropuesta,
  aceptada,
  rechazada,
  atrasada,
  esperandoPieza,
  enProceso,
  completada,
}

class SolicitudAdmin {
  const SolicitudAdmin({
    required this.id,
    required this.cliente,
    required this.telefono,
    required this.taller,
    required this.marcaVehiculo,
    required this.modeloVehiculo,
    required this.anioVehiculo,
    required this.placa,
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

  final String marcaVehiculo;
  final String modeloVehiculo;
  final int anioVehiculo;
  final String placa;

  final List<String> servicios;
  final DateTime fecha;
  final TimeOfDay hora;
  final String descripcion;
  final EstadoSolicitudAdmin estado;

  String get vehiculo =>
      '$marcaVehiculo $modeloVehiculo ($anioVehiculo) · $placa';
}

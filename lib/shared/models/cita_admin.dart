import 'package:flutter/material.dart';

enum EstadoCitaAdmin {
  atrasada,
  pendiente,
  esperandoPieza,
  enProceso,
  completada,
}

class CitaAdmin {
  const CitaAdmin({
    required this.id,
    required this.cliente,
    required this.telefono,
    required this.marca,
    required this.modelo,
    required this.anio,
    required this.placa,
    required this.servicios,
    required this.fecha,
    required this.hora,
    required this.estado,
    required this.descripcion,
    this.tecnico,
    this.total = 0.0,
  });

  final int id;
  final String cliente;
  final String telefono;
  final String marca;
  final String modelo;
  final String anio;
  final String placa;
  final List<String> servicios;
  final DateTime fecha;
  final TimeOfDay hora;
  final EstadoCitaAdmin estado;
  final String descripcion;
  final String? tecnico;
  final double total;
}
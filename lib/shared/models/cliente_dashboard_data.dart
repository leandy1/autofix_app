import 'package:flutter/material.dart';

class TallerCliente {
  const TallerCliente({
    required this.nombre,
    required this.direccion,
    required this.distancia,
    required this.calificacion,
    required this.horario,
  });

  final String nombre;
  final String direccion;
  final String distancia;
  final String calificacion;
  final String horario;
}

class CitaClienteDemo {
  const CitaClienteDemo({
    required this.fecha,
    required this.hora,
    required this.taller,
    required this.servicio,
    required this.vehiculo,
    required this.estado,
    required this.colorEstado,
    required this.codigo,
  });

  final DateTime fecha;
  final String hora;
  final String taller;
  final String servicio;
  final String vehiculo;
  final String estado;
  final Color colorEstado;
  final String codigo;
}

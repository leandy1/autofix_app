import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

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

const talleresCliente = [
  TallerCliente(
    nombre: 'AutoFix Central',
    direccion: 'Av. Winston Churchill, Santo Domingo',
    distancia: '1.2 km',
    calificacion: '4.8',
    horario: 'Abierto · Cierra a las 6:00 p. m.',
  ),
  TallerCliente(
    nombre: 'Taller Los Prados',
    direccion: 'Calle Olof Palme, Los Prados',
    distancia: '2.4 km',
    calificacion: '4.6',
    horario: 'Abierto · Cierra a las 5:30 p. m.',
  ),
  TallerCliente(
    nombre: 'Servicio Motor Express',
    direccion: 'Av. 27 de Febrero, Evaristo Morales',
    distancia: '3.1 km',
    calificacion: '4.5',
    horario: 'Abierto · Cierra a las 7:00 p. m.',
  ),
];

const serviciosCliente = [
  'Cambio de aceite y filtro',
  'Frenos',
  'Suspensión y dirección',
  'Transmisión y caja',
];

final citasClienteDemo = [
  CitaClienteDemo(
    fecha: DateTime(2026, 10, 5),
    hora: '9:00 a. m.',
    taller: 'AutoFix Central',
    servicio: 'Mantenimiento preventivo',
    vehiculo: 'Toyota Corolla · A123456',
    estado: 'Confirmada',
    colorEstado: AppColors.greenAccent,
    codigo: 'AF-2084',
  ),
  CitaClienteDemo(
    fecha: DateTime(2026, 10, 15),
    hora: '2:30 p. m.',
    taller: 'Taller Los Prados',
    servicio: 'Revisión de frenos',
    vehiculo: 'Toyota Corolla · A123456',
    estado: 'Pendiente',
    colorEstado: AppColors.pendientes,
    codigo: 'AF-2117',
  ),
];

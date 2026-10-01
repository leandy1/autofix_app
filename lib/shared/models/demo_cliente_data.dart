import 'package:flutter/material.dart';

import 'package:autofix/shared/theme/app_colors.dart';
import 'cliente_dashboard_data.dart';
import 'solicitud_cita_cliente.dart';

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

final demoSeguimientoCitaCliente = SolicitudCitaCliente(
  id: 2,
  cliente: 'María Pérez',
  telefono: '809-555-0142',
  taller: 'AutoFix Central',
  vehiculo: 'Honda Civic · A456789',
  servicios: ['Frenos'],
  fecha: DateTime(2026, 10, 9),
  hora: TimeOfDay(hour: 11, minute: 30),
  descripcion: 'Revisar ruido al frenar.',
  estado: EstadoSolicitudCita.fechaPropuesta,
);

final citasClienteDemo = List<CitaClienteDemo>.unmodifiable([
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
]);

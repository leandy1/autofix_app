import 'package:flutter/material.dart';

import 'solicitud_cita_cliente.dart';

final demoCitaAdmin = SolicitudCitaCliente(
  id: 0,
  cliente: 'Luis Castillo',
  telefono: '829-555-0505',
  taller: 'AutoFix Central',
  vehiculo: 'TOYOTA RAV4 (2022) · E567890',
  servicios: const ['Motor', 'Correa de distribución'],
  fecha: DateTime(2026, 9, 24),
  hora: TimeOfDay(hour: 8, minute: 30),
  descripcion: 'Revisión profunda de motor.',
  estado: EstadoSolicitudCita.enProceso,
);

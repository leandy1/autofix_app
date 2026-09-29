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

final demoCitaCompletadaAdmin = SolicitudCitaCliente(
  id: 24,
  cliente: 'Carolina Méndez',
  telefono: '809-555-0184',
  taller: 'AutoFix Central',
  vehiculo: 'HONDA CIVIC (2021) · A456789',
  servicios: const ['Cambio de aceite y filtro', 'Revisión de frenos'],
  fecha: DateTime(2026, 9, 24),
  hora: TimeOfDay(hour: 10, minute: 15),
  descripcion: 'Servicio completado. Recibo de demostración.',
  estado: EstadoSolicitudCita.completada,
);

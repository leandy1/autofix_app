import 'package:flutter/material.dart';

import 'solicitud_cita_cliente.dart';

class CitaResumenAdminDemo {
  const CitaResumenAdminDemo({
    required this.cliente,
    required this.vehiculo,
    required this.placa,
    required this.servicio,
  });

  final String cliente;
  final String vehiculo;
  final String placa;
  final String servicio;
}

class DashboardAdminDemo {
  const DashboardAdminDemo({
    required this.vehiculosEnTaller,
    required this.ordenesAbiertas,
    required this.completadasHoy,
    required this.ingresosDelDia,
    required this.citasDelDia,
  });

  final String vehiculosEnTaller;
  final String ordenesAbiertas;
  final String completadasHoy;
  final String ingresosDelDia;
  final List<CitaResumenAdminDemo> citasDelDia;
}

class ServicioAdminDemo {
  const ServicioAdminDemo({required this.nombre, required this.precio});

  final String nombre;
  final String precio;
}

class GrupoServiciosAdminDemo {
  const GrupoServiciosAdminDemo({
    required this.nombre,
    required this.servicios,
  });

  final String nombre;
  final List<ServicioAdminDemo> servicios;
}

const demoDashboardAdmin = DashboardAdminDemo(
  vehiculosEnTaller: '2',
  ordenesAbiertas: '6',
  completadasHoy: '0',
  ingresosDelDia: 'RD\$ 0',
  citasDelDia: [
    CitaResumenAdminDemo(
      cliente: 'Luis Castillo',
      vehiculo: 'Toyota RAV4',
      placa: 'E567890',
      servicio: 'Motor, Correa',
    ),
    CitaResumenAdminDemo(
      cliente: 'Pedro Núñez',
      vehiculo: 'Honda CR-V',
      placa: 'G789012',
      servicio: 'Aire',
    ),
    CitaResumenAdminDemo(
      cliente: 'Isabel Reyes',
      vehiculo: 'Honda Accord',
      placa: 'L234567',
      servicio: 'Correa de tiempo',
    ),
    CitaResumenAdminDemo(
      cliente: 'Natalia Flores',
      vehiculo: 'Ford Edge',
      placa: 'R890123',
      servicio: 'Sistema de frenos',
    ),
    CitaResumenAdminDemo(
      cliente: 'Lucía Medina',
      vehiculo: 'Suzuki Jimny',
      placa: 'T012345',
      servicio: 'Alineación y balanceo',
    ),
  ],
);

final demoSolicitudesAdmin = List<SolicitudCitaCliente>.unmodifiable([
  SolicitudCitaCliente(
    id: 1,
    cliente: 'María Pérez',
    telefono: '809-555-0142',
    taller: 'AutoFix Central',
    vehiculo: 'HONDA CIVIC (2021) · A456789',
    servicios: ['Frenos', 'Revisión general'],
    fecha: DateTime(2026, 10, 8),
    hora: TimeOfDay(hour: 10, minute: 0),
    descripcion: 'Revisar ruido al frenar.',
    estado: EstadoSolicitudCita.pendiente,
  ),
]);

final demoCitaCompletadaAdmin = SolicitudCitaCliente(
  id: 24,
  cliente: 'Carolina Méndez',
  telefono: '809-555-0184',
  taller: 'AutoFix Central',
  vehiculo: 'HONDA CIVIC (2021) · A456789',
  servicios: const ['Cambio de aceite y filtro', 'Revisión de frenos'],
  fecha: DateTime(2026, 9, 24),
  hora: const TimeOfDay(hour: 10, minute: 15),
  descripcion: 'Servicio completado. Recibo de demostración.',
  estado: EstadoSolicitudCita.completada,
);

const demoTecnicosAdmin = ['Técnico 1', 'Técnico 2', 'Técnico 3'];
const demoEstadosAdmin = [
  'Pendiente',
  'Aceptada',
  'Rechazada',
  'Esperando Pieza',
  'En proceso',
  'Completado',
];
const demoMarcasVehiculo = ['Toyota', 'Honda', 'Ford', 'Hyundai', 'Suzuki'];
const demoServiciosAdmin = [
  ServicioAdminDemo(nombre: 'Cambio de aceite y filtro', precio: 'RD\$ —'),
  ServicioAdminDemo(nombre: 'Frenos', precio: 'RD\$ —'),
  ServicioAdminDemo(nombre: 'Suspensión y dirección', precio: 'RD\$ —'),
  ServicioAdminDemo(nombre: 'Transmisión y caja', precio: 'RD\$ —'),
  ServicioAdminDemo(nombre: 'Alineación y balanceo', precio: 'RD\$ —'),
  ServicioAdminDemo(nombre: 'Cambio de gomas', precio: 'RD\$ —'),
];

const demoGruposServiciosAdmin = [
  GrupoServiciosAdminDemo(
    nombre: 'Carrocería',
    servicios: [
      ServicioAdminDemo(nombre: 'Alineación y balanceo', precio: 'RD\$ 1200'),
      ServicioAdminDemo(nombre: 'Cambio de gomas', precio: 'RD\$ 600'),
    ],
  ),
];

const demoTecnicosConfiguracion = demoTecnicosAdmin;

// ---------------------------------------------------------------------------
// v7: SE BORRARON `demoEstadosConfiguracion` y `demoMarcasConfiguracion`.
//
// `demoEstadosConfiguracion` era la lista de 'En diagnóstico' / 'Esperando pieza'
// con tildes y mayusculas que pintaba la tarjeta de estados de Configuracion. Esa
// tarjeta ya no existe (el estado de una cita es el enum cerrado `EstadoCita`,
// no una fila editable) y la lista se fue con ella. Dejarla aca era peor que
// sobrante: alguien la encontraba, la usaba como si fuera el catalogo real, y
// escribia un estado que `EstadoCita.desdeNombre` no reconoce, con lo que la cita
// queda en estado desconocido al leerla de la base.
//
// `demoMarcasConfiguracion` era `demoMarcasVehiculo` reexportada con otro nombre.
// Las marcas pasaron a ser filas de la tabla `marcas` (punto 6 del encargo), y la
// pantalla de Configuracion ya lee de `_cfg.marcas`. La `const` no se "convierte":
// se elimina, porque dos listas de marcas en el codigo es una que alguien va a
// actualizar y la otra no.
//
// `demoEstadosAdmin` NO se toco: esa sigue viva en `citas_admin_screen.dart` como
// las etiquetas del filtro de estado, que es un filtro de TEXTO sobre una columna
// de texto y no un catalogo. Si alguna vez pasa a filtrar por el enum, se
// deriva de `EstadoSolicitudCita.values` y esta lista se borra tambien.
// ---------------------------------------------------------------------------

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
    this.tallerId,
    this.creadoEn,
    this.actualizadoEn,
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

  /// Taller afiliado donde se agendó la cita.
  ///
  /// Este campo NO es para editarlo en pantalla: existe para que el puente
  /// `Cita` <-> `CitaAdmin` sea una ida y vuelta sin perdida. Sin el, el
  /// mapeo hacia `Cita` se construía sin `tallerId`, `Cita.toMap()` escribía la
  /// columna a null y el guardado desde el admin DESASOCIABA la cita del
  /// taller: dejaba de aparecer en `CitaRepository.obtenerPorTaller`.
  final int? tallerId;

  /// Fecha de alta original. Viaja por el mismo motivo que [tallerId]: el
  /// guardado desde admin no debe reescribir cuando se creo la cita.
  final DateTime? creadoEn;

  /// Ultima modificacion. Se refresca en cada escritura.
  final DateTime? actualizadoEn;
}

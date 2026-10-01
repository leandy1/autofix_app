import 'package:flutter/material.dart';

class TallerCliente {
  const TallerCliente({
    required this.nombre,
    required this.direccion,
    required this.distancia,
    required this.latitud,
    required this.longitud,
  });

  final String nombre;
  final String direccion;
  final String distancia;
  final double latitud;
  final double longitud;
}
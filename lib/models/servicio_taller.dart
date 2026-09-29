class ServicioTaller {
  const ServicioTaller({required this.nombre, required this.precioEtiqueta});

  final String nombre;
  final String precioEtiqueta;
}

const serviciosTaller = [
  ServicioTaller(nombre: 'Motor', precioEtiqueta: 'RD\$ 8.000'),
  ServicioTaller(
    nombre: 'Correa de distribución',
    precioEtiqueta: 'RD\$ 3.000',
  ),
  ServicioTaller(
    nombre: 'Diagnóstico eléctrico',
    precioEtiqueta: 'RD\$ 800',
  ),
  ServicioTaller(
    nombre: 'Sistema de arranque y batería',
    precioEtiqueta: 'RD\$ 2.500',
  ),
  ServicioTaller(nombre: 'Luces y señales', precioEtiqueta: 'RD\$ 1.000'),
  ServicioTaller(nombre: 'Sistema de carga', precioEtiqueta: 'RD\$ 1.800'),
  ServicioTaller(
    nombre: 'Aire acondicionado',
    precioEtiqueta: 'RD\$ 3.500',
  ),
  ServicioTaller(
    nombre: 'Cambio de aceite y filtro',
    precioEtiqueta: 'RD\$ —',
  ),
  ServicioTaller(nombre: 'Frenos', precioEtiqueta: 'RD\$ —'),
  ServicioTaller(
    nombre: 'Suspensión y dirección',
    precioEtiqueta: 'RD\$ —',
  ),
  ServicioTaller(nombre: 'Transmisión y caja', precioEtiqueta: 'RD\$ —'),
];

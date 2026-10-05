class ReciboImpresion {
  const ReciboImpresion({
    required this.numero,
    required this.fecha,
    required this.cliente,
    required this.telefono,
    required this.vehiculo,
    required this.placa,
    required this.servicios,
    this.esDemostracion = false,
  });

  final String numero;
  final String fecha;
  final String cliente;
  final String telefono;
  final String vehiculo;
  final String placa;
  final List<String> servicios;
  final bool esDemostracion;
}

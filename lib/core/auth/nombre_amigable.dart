/// Convierte lo que hay guardado (correo, nombre o nada) en algo con lo que se
/// le habla al usuario.
///
/// Existe como funcion suelta porque la usan DOS sesiones distintas: la del
/// admin (que solo tiene el correo) y la del cliente (que tiene nombre pero a
/// veces solo el correo). Meterla dentro de una de las dos obligaria a que la
/// otra importe una clase de mas solo por una linea.
///
/// Reglas, en orden:
/// - `null` o vacio -> [reserva]: la app prefiere decir "cliente" antes que
///   "¡Hola, !".
/// - Correo -> la parte antes de la `@`, capitalizada. `santiago@gmail.com`
///   saludaba "santiago"; con esto saluda "Santiago".
/// - Nombre -> tal cual, pero capitalizado para que "maria perez" no aparezca
///   en el AppBar en minusculas.
///
/// [reserva] es un parametro y no un literal fijo: el admin, si algo falla,
/// prefiere "admin" y no "cliente".
String nombreAmigable(String? origen, {String reserva = 'cliente'}) {
  final limpio = origen?.trim() ?? '';
  if (limpio.isEmpty) return reserva;

  final base = limpio.contains('@') ? limpio.split('@').first : limpio;
  final recortado = base.trim();
  if (recortado.isEmpty) return reserva;

  return recortado[0].toUpperCase() + recortado.substring(1);
}

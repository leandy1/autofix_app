// =============================================================================
// etiqueta_distancia.dart
// LA DISTANCIA AL TALLER, EN TEXTO.
//
// Vive acá y no dentro de la pantalla del mapa porque la necesitan DOS
// pantallas: el mapa (modal de afiliados y ficha del taller) y el formulario de
// cita (selector de taller). Cuando cada una armaba su propio texto, una
// decia "a 2.5 km" y la otra "2.5 km", y el cliente leia dos reglas distintas
// para el mismo dato.
//
// La version que devuelve `null` existe para las pantallas donde la distancia es
// un dato MAS y no el titular: ahi, sin GPS, lo correcto es no escribir nada y
// deixar la direccion sola, no filling el espacio con un "no disponible" que en
// un formulario se lee como un dato faltante del taller.
// Ejecutar:   flutter test test/core/mapa/etiqueta_distancia_test.dart
// =============================================================================

import '../../features/talleres/models/taller.dart';

/// Texto que se muestra cuando no hay GPS con el cual medir. Es una frase y no
/// un '-': el usuario tiene que entender que la app no fallo, que no sabe donde
/// esta el.
const String kDistanciaNoDisponible = 'Distancia no disponible';

/// "a 2.5 km de ti", o `null` si no hay posicion con la cual medir.
///
/// Un decimal y no mas: por debajo de 100 m la distancia deja de servir para
/// decidir a donde ir, y mostrar "0.0 km" al lado de un taller que queda a tres
/// cuadras hace pensar que el calculo esta roto.
///
/// El parametro es `double?` y no `Position?` a proposito: el test puede pasar
/// `null` sin tener que construir una `Position` de geolocator.
String? etiquetaDistanciaSiHayGps(
  Taller taller,
  double? latitudUsuario,
  double? longitudUsuario,
) {
  if (latitudUsuario == null || longitudUsuario == null) {
    return null;
  }

  final km = taller.distanciaKmDesde(latitudUsuario, longitudUsuario);
  return 'a ${km.toStringAsFixed(1)} km de ti';
}

/// Igual que [etiquetaDistanciaSiHayGps], pero nunca devuelve `null`.
///
/// Para el mapa, donde el lugar de la distancia lo ocupa siempre una pieza de UI
/// y un `null` no se puede pintar: sin GPS se dice que no hay distancia, en vez
/// de dejar el hueco puzzling.
String etiquetaDistancia(
  Taller taller,
  double? latitudUsuario,
  double? longitudUsuario,
) =>
    etiquetaDistanciaSiHayGps(taller, latitudUsuario, longitudUsuario) ??
    kDistanciaNoDisponible;
// =============================================================================
// etiqueta_distancia_test.dart
// Tests del texto de distancia que comparten el mapa y el formulario de cita.
//
// Por que el texto necesita test propio y no va escondido en un test de widget:
// las dos pantallas lo usan y cada una necesita una regla DISTINTA para el mismo
// caso sin GPS. El mapa dice "Distancia no disponible" porque ahí el lugar de la
// distancia lo ocupa una pieza de UI que quedaria en el aire. El formulario no
// dice nada, porque en un selector de taller un "no disponible" se lee como que
// al taller le falta un dato.
//
// Si alguien unifica las dos reglas para "no duplicar codigo", el mapa queda con
// un hueco raro o el formulario con una advertencia falsa. Estos tests son los
// que hacen visible esa diferencia antes de que llegue a un cliente.
//
// Son funciones puras y no metodos del State justamente para poder probarlas
// asi: no hay que montar la pantalla, no hace falta un MapLibre real, y el
// resultado es un valor comparable exactamente.
// Ejecutar:   flutter test test/core/mapa/etiqueta_distancia_test.dart
// =============================================================================

import 'package:autofix/core/mapa/etiqueta_distancia.dart';
import 'package:autofix/features/talleres/models/taller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Santo Domingo centro: el punto desde el que se miden las distancias.
const double _latSdq = 18.4861;
const double _lngSdq = -69.9312;

final _gazcue = const Taller(
  nombre: 'Global Refriauto',
  latitud: 18.4184,
  longitud: -69.9167,
);

void main() {
  group('etiquetaDistanciaSiHayGps', () {
    test('con GPS devuelve "a X km de ti"', () {
      expect(
        etiquetaDistanciaSiHayGps(_gazcue, _latSdq, _lngSdq),
        'a 7.7 km de ti',
      );
    });

    test('sin GPS devuelve null, NO un texto', () {
      // Esto es lo que la distingue de `etiquetaDistancia`: el formulario usa
      // esta y escribe la direccion sola cuando no hay nada que medir. Si
      // devolviera `kDistanciaNoDisponible`, el selector de taller mostraría un
      // "Distancia no disponible" que parece un dato que le falta al taller.
      expect(etiquetaDistanciaSiHayGps(_gazcue, null, null), isNull);
    });

    test('con UNA sola coordenada null tambien devuelve null', () {
      // El GPS puede dar la latitud y no la longitud a medio camino. Medir con
      // una coordenada y media produce un numero que no corresponde a ningun punto
      // real del planeta.
      expect(etiquetaDistanciaSiHayGps(_gazcue, _latSdq, null), isNull);
      expect(etiquetaDistanciaSiHayGps(_gazcue, null, _lngSdq), isNull);
    });

    test('el texto es el mismo que el del mapa, no una variante', () {
      // Las dos pantallas tienen que teach la misma frase. Si una decía "2.5 km"
      // y la otra "a 2.5 km de ti", el cliente leeria dos reglas para el mismo
      // dato segun donde mirara.
      expect(
        etiquetaDistanciaSiHayGps(_gazcue, _latSdq, _lngSdq),
        etiquetaDistancia(_gazcue, _latSdq, _lngSdq),
      );
    });

    test('el propio taller da 0.0 km y no NaN', () {
      expect(
        etiquetaDistanciaSiHayGps(_gazcue, 18.4184, -69.9167),
        'a 0.0 km de ti',
      );
    });

    test('coordenadas en 0/0 dan un numero, no una excepcion', () {
      // Un taller guardado sin coordenadas vuelve como 0/0 (lo hace
      // `Taller.fromMap`). El costo del dato malo lo paga quien lo cargo, no una
      // excepcion en la pantalla.
      final sinUbicacion = const Taller(
        nombre: 'Borrador',
        latitud: 0,
        longitud: 0,
      );

      expect(
        etiquetaDistanciaSiHayGps(sinUbicacion, _latSdq, _lngSdq),
        'a 7895.7 km de ti',
      );
    });
  });

  group('etiquetaDistancia', () {
    test('sin GPS dice "Distancia no disponible"', () {
      expect(etiquetaDistancia(_gazcue, null, null), kDistanciaNoDisponible);
    });

    test('delega en la version nullable y solo cambia el fallback', () {
      // Las dos funciones no pueden empezar a divergir: si `etiquetaDistancia`
      // calculara su propio texto, un dia una cambiaria y la otra no.
      expect(
        etiquetaDistancia(_gazcue, _latSdq, _lngSdq),
        etiquetaDistanciaSiHayGps(_gazcue, _latSdq, _lngSdq),
      );
    });
  });
}

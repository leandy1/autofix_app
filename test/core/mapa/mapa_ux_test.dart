// =============================================================================
// mapa_ux_test.dart
// Tests de las funciones puras de la pantalla del mapa de talleres.
//
// Por que funciones puras y no tests de widget: las tres cosas que fallan en
// esta pantalla fallan EN SILENCIO. Un orden mal hecho no revienta, muestra los
// talleres en cualquier lado. Una distancia en NaN muestra "a NaN km de ti". Un
// URI `geo:` mal armado deja el boton de "Abrir en Maps" que no abre nada. En
// los tres casos la app "funciona", el test de widget pasa, y el bug llega a
// produccion.
//
// Son funciones puras y no metodos del State justamente para poder probarlas
// asi: no hay que montar la pantalla, no hace falta un MapLibre real, y el
// resultado es un valor comparable exactamente.
// Ejecutar:   flutter test test/core/mapa/mapa_ux_test.dart
// =============================================================================

import 'package:autofix/core/mapa/etiqueta_distancia.dart';
import 'package:autofix/features/talleres/models/taller.dart';
import 'package:autofix/screens/cliente/talleres_mapa_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Santo Domingo centro: el punto desde el que se miden las distancias.
const double _latSdq = 18.4861;
const double _lngSdq = -69.9312;

/// Santiago de los Caballeros, a mas de 100 km. Sirve para comprobar que el
/// orden por cercania cambia de verdad y no es "el mismo orden de la lista".
const double _latStgo = 19.4517;
const double _lngStgo = -70.6970;

/// Los mismos tres puntos que trae la semilla, mas o menos donde caen.
final _santiago = const Taller(
  nombre: 'AutoFix Central',
  latitud: _latStgo,
  longitud: _lngStgo,
);
final _gazcue = const Taller(
  nombre: 'Global Refriauto',
  latitud: 18.4184,
  longitud: -69.9167,
);
final _gomez = const Taller(
  nombre: 'Taller Gómez',
  latitud: 18.4801,
  longitud: -69.8896,
);

/// El orden por defecto de `obtenerActivos()` es alfabetico, NO por id.
final _ordenPorDefecto = <String>[
  'AutoFix Central',
  'Global Refriauto',
  'Taller Gómez',
];

void main() {
  /// La lista tal como llega de la base.
  final lista = <Taller>[_santiago, _gazcue, _gomez];

  group('ordenarPorCercania', () {
    test('con GPS ordena del mas cercano al mas lejano', () {
      final ordenados = ordenarPorCercania(lista, _latSdq, _lngSdq);

      // Gómez esta a 4.4 km, Gazcue a 7.7 y Santiago a 134.2 desde Santo Domingo.
      // El orden alfabetico de la base es Santiago, Gazcue, Gómez: o sea que
      // este test falla si el sort no hace nada.
      expect(ordenados.map((t) => t.nombre), <String>[
        'Taller Gómez',
        'Global Refriauto',
        'AutoFix Central',
      ]);
    });

    test('sin GPS devuelve la lista en el orden por defecto', () {
      // Este es el caso NORMAL, no la excepcion: pedir permiso de ubicacion y
      // que lo nieguen es de las tres o cuatro cosas que mas pasan. Si este
      // test falla, lo que se rompio es que el usuario sin permiso no ve la
      // lista de talleres.
      expect(
        ordenarPorCercania(lista, null, null).map((t) => t.nombre),
        _ordenPorDefecto,
        reason: 'sin GPS la lista debe quedar como la dio la base',
      );
    });

    test('con UNA sola coordenada null tambien usa el orden por defecto', () {
      // El GPS puede dar la latitud y no la longitud a medio camino. Con `null`
      // en uno de los dos NO se ordena: ordenar por coordenada y media produce
      // un orden que no corresponde a ningun punto real.
      expect(
        ordenarPorCercania(lista, _latSdq, null).map((t) => t.nombre),
        _ordenPorDefecto,
      );
      expect(
        ordenarPorCercania(lista, null, _lngSdq).map((t) => t.nombre),
        _ordenPorDefecto,
      );
    });

    test('ordenar NO muta la lista de entrada', () {
      // `_talleres` es el estado del widget y la misma lista se usa para pintar
      // los circulos. Si `sort` la mutara, el orden del modal y el del mapa se
      // desacoplan segun cual se abrio de ultimo.
      final original = List<Taller>.of(lista);
      final esperada = List<Taller>.of(lista);

      ordenarPorCercania(original, _latSdq, _lngSdq);

      expect(original.map((t) => t.nombre), esperada.map((t) => t.nombre));
    });

    test('lista vacia y lista de uno no dan error', () {
      expect(ordenarPorCercania(const <Taller>[], _latSdq, _lngSdq), isEmpty);
      expect(ordenarPorCercania(const <Taller>[], null, null), isEmpty);
      expect(
        ordenarPorCercania(<Taller>[_santiago], _latSdq, _lngSdq).single.nombre,
        'AutoFix Central',
      );
    });

    test('la distancia real se respeta, no el orden alfabetico', () {
      // Santiago esta alfabeticamente primero y es el mas lejos. Si el orden
      // no cambia, el usuario abre el modal para "ver los mas cercanos" y le
      // aparece primero el taller de otra provincia.
      final ordenados = ordenarPorCercania(lista, _latSdq, _lngSdq);
      expect(ordenados.first.nombre, isNot('AutoFix Central'));
      expect(ordenados.last.nombre, 'AutoFix Central');
    });
  });

  group('etiquetaDistancia', () {
    test('con GPS muestra "a X km de ti"', () {
      final texto = etiquetaDistancia(_gazcue, _latSdq, _lngSdq);

      expect(texto, matches(RegExp(r'^a \d+\.\d km de ti$')));
      expect(texto, 'a 7.7 km de ti');
    });

    test('un solo decimal, nunca mas', () {
      // "a 7.7 km" alcanza para decidir a donde ir. Con mas decimales el numero
      // cambia por centimos mientras el usuario mira la pantalla y parece que la
      // app recalcula en vivo.
      expect(
        etiquetaDistancia(_santiago, _latSdq, _lngSdq),
        'a 134.2 km de ti',
      );
    });

    test('sin GPS dice "Distancia no disponible" y NO un numero', () {
      final texto = etiquetaDistancia(_gazcue, null, null);

      expect(texto, kDistanciaNoDisponible);
      expect(texto, isNot(contains('NaN')));
      expect(texto, isNot(contains('null')));
      expect(texto, isNot(contains('km')));
    });

    test('el propio taller da 0.0 km', () {
      expect(etiquetaDistancia(_gazcue, 18.4184, -69.9167), 'a 0.0 km de ti');
    });

    test('coordenadas en 0/0 no producen NaN ni una excepcion', () {
      // Un taller guardado sin coordenadas vuelve como 0/0 (lo hace
      // `Taller.fromMap`). Contra Santo Domingo eso da casi 8000 km, que es un
      // numero absurdo pero un numero. La app tiene que poder mostrarlo sin
      // romperse: el costo del dato malo lo paga quien lo cargo, no una
      // excepcion en la pantalla del mapa.
      final sinUbicacion = const Taller(
        nombre: 'Borrador',
        latitud: 0,
        longitud: 0,
      );
      final texto = etiquetaDistancia(sinUbicacion, _latSdq, _lngSdq);

      expect(texto, 'a 7895.7 km de ti');
      expect(texto, isNot(contains('NaN')));
    });
  });

  group('uriDeRuta', () {
    test('arma el formato geo: estandar', () {
      expect(uriDeRuta(_gazcue).scheme, 'geo');
      expect(
        uriDeRuta(_gazcue).toString(),
        'geo:18.4184,-69.9167?q=18.4184,-69.9167(Global%20Refriauto)',
      );
    });

    test('codifica acentos y espacios del nombre', () {
      // "Taller Gómez" crudo rompe el parser del otro lado. El espacio tiene que
      // ir como %20 y NO como +, que es lo que producen los formateadores de
      // query string y lo que este intent no interpreta igual.
      final uri = uriDeRuta(_gomez).toString();

      expect(uri, contains('Taller%20G%C3%B3mez'));
      expect(uri, isNot(contains(' ')));
      expect(uri, isNot(contains('+')));
    });

    test('la longitud negativa conserva el signo', () {
      // Sin el signo, el punto cae en el otro hemisferio y el boton abre un
      // mapa con un pin en el oceano.
      expect(uriDeRuta(_gazcue).toString(), contains(',-69.9167'));
    });

    test('un nombre con parentesis y ampersand no rompe el intent', () {
      // El formato de geo: usa parentesis para cerrar la etiqueta del lugar. Un
      // nombre con parentesis propio desbalancea el parser del otro lado.
      final raro = const Taller(
        nombre: 'Taller (Nº 2) & Cia',
        latitud: 18.48,
        longitud: -69.88,
      );
      final uri = uriDeRuta(raro).toString();

      expect(uri, isNot(contains(' ')));
      expect(uri, contains('%28')); // (
      expect(uri, contains('%26')); // &
    });

    test('el URI es parseable para los tres talleres de la semilla', () {
      for (final t in <Taller>[_santiago, _gazcue, _gomez]) {
        expect(uriDeRuta(t).scheme, 'geo');
        expect(uriDeRuta(t).host, isEmpty);
        expect(uriDeRuta(t).toString(), contains('?q='));
      }
    });
  });
}
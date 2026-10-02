// =============================================================================
// estilos_mapa.dart
// ESTILOS DE MAPA 100% GRATUITOS, SIN API KEY.
//
// VERIFICADO: los 3 endpoints responden HTTP 200 y son Mapbox Style
// Specification v8 (que es lo que MapLibre consume). Probados a mano.
//
// ⚠️  NO USES STAMEN. Stamen se mudó a Stadia Maps y ahora exige API Key.
//     Verificado: https://tiles.stadiamaps.com/tiles/stamen_toner/... → HTTP 401
//
// Dónde va este archivo en tu proyecto:
//     lib/core/mapa/estilos_mapa.dart
// =============================================================================

/// Estilos hosted (una URL cada uno). Elige UNO y úsalo en toda la app.
class EstilosMapa {
  const EstilosMapa._();

  // --- OPCIÓN A: CartoDB (recomendada) ------------------------------------
  // Vectorial, limpio, ideal para una app de servicios/talleres.

  /// Claro, minimalista. El mejor para AutoFix.
  static const String cartoPositron =
      'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json';

  /// Más detallado, con relieve y colores de terreno.
  static const String cartoVoyager =
      'https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json';

  /// Modo oscuro. Útil si más adelante agregamos tema oscuro.
  static const String cartoDarkMatter =
      'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json';

  // --- OPCIÓN B: OpenFreeMap ---------------------------------------------
  // Open source completo, sin límites de uso declarados.

  static const String openFreeMapLiberty =
      'https://tiles.openfreemap.org/styles/liberty';

  static const String openFreeMapPositron =
      'https://tiles.openfreemap.org/styles/positron';

  // --- OPCIÓN C: OSM Raster embebido --------------------------------------
  // Tiles directo de OpenStreetMap, sin depender de un servidor de estilos
  // externo. Va como JSON crudo en la MISMA propiedad `styleString`.

  /// ⚠️ La Tile Usage Policy de OSM prohíbe uso pesado/comercial.
  ///    Para un TP de universidad va bien. Si AutoFix creciera, cambia a CartoDB.
  static const String osmRaster = '''
{
  "version": 8,
  "sources": {
    "osm": {
      "type": "raster",
      "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
      "tileSize": 256,
      "attribution": "(c) OpenStreetMap contributors"
    }
  },
  "layers": [
    { "id": "fondo", "type": "background", "paint": { "background-color": "#F3F5F8" } },
    { "id": "osm", "type": "raster", "source": "osm" }
  ]
}
''';

  /// El que usa la app. Cámbialo cuando quieras, no hay más que tocar esto.
  static const String porDefecto = cartoPositron;
}

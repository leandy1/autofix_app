import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/mapa/estilos_mapa.dart';
import '../../core/ubicacion/ubicacion_service.dart';
import '../../features/talleres/data/taller_repository.dart';
import '../../features/talleres/models/taller.dart';
import '../../theme/app_colors.dart';

/// Centro de República Dominicana, usado como punto de partida cuando el
/// usuario no autoriza la ubicación.
const LatLng kCentroRepublicaDominicana = LatLng(18.4861, -69.9312);

/// Con ubicación se usa zoom de ciudad; sin ella, uno que muestra la isla entera.
const double kZoomSinUbicacion = 10.5;
const double kZoomConUbicacion = 13.5;

/// Zoom al centrar un taller puntual.
///
/// Un poco mas cerrado que [kZoomConUbicacion] porque el objetivo ya no es "mi
/// ciudad" sino una esquina concreta: a 13.5 el taller queda en el medio de un
/// mapa de tres kilometros y no se ve ni el local ni la cuadra.
const double kZoomTaller = 15.0;

/// Texto que se muestra cuando no hay GPS con el cual medir. Es una frase y no
/// un '-': el usuario tiene que entender que la app no fallo, que no sabe donde
/// esta el.
const String kDistanciaNoDisponible = 'Distancia no disponible';

// =============================================================================
// Funciones puras de la pantalla.
//
// Viven aca arriba y no como metodos del State para que el test las pueda
// ejercitar sin montar la pantalla. No es purismo: las tres cosas que mas se
// rompen en esta pantalla (ordenar, formatear la distancia y armar el intent
// geo:) fallan EN SILENCIO. Un orden mal hecho no truena, muestra los talleres
// en cualquier lado; una distancia con `NaN` muestra "a NaN km de ti"; un URI
// mal armado deja el boton que no abre nada. Ninguno de los tres lo agarra el
// compilador ni un crash en runtime, asi que se testean aparte.
// =============================================================================

/// Ordena por cercania, del mas cercano al mas lejano.
///
/// Sin coordenadas del usuario devuelve la lista TAL COMO LLEGA, sin copiar y
/// sin reordenar.
///
/// Devolver una lista nueva con los mismos datos, o peor, una excepcion, seria
/// un fallo de UX disfrazado de logica: el caso "el usuario denies el permiso" es
/// un caso NORMAL, no un error. Se espera un tercio de los usuarios sin GPS, o
/// con el permiso denegado para siempre, y en ese escenario la app tiene que
/// mostrar los talleres igual, en el orden por defecto que dio la base.
///
/// Por eso el parametro es `double?` y no `Position?`: el test puede pasar `null`
/// sin tener que construir una `Position` de geolocator.
List<Taller> ordenarPorCercania(
  List<Taller> talleres,
  double? latitudUsuario,
  double? longitudUsuario,
) {
  if (latitudUsuario == null || longitudUsuario == null) {
    return talleres;
  }

  // Copia antes de ordenar: `sort` muta la lista, y la que llega viene de
  // `_talleres`, que es el estado del widget. Ordenarla en el sitio mezclaria
  // el orden de pintado del mapa con el orden de presentacion del modal.
  return [...talleres]
    ..sort(
      (a, b) => a
          .distanciaKmDesde(latitudUsuario, longitudUsuario)
          .compareTo(b.distanciaKmDesde(latitudUsuario, longitudUsuario)),
    );
}

/// "a 2.5 km de ti", o [kDistanciaNoDisponible] si no hay GPS.
///
/// Un decimal y no mas: por debajo de 100 m la distancia deja de servir para
/// decidir a donde ir, y mostrar "0.0 km" al lado de un taller que queda a tres
/// cuadras hace pensar que el calculo esta roto.
String etiquetaDistancia(
  Taller taller,
  double? latitudUsuario,
  double? longitudUsuario,
) {
  if (latitudUsuario == null || longitudUsuario == null) {
    return kDistanciaNoDisponible;
  }

  final km = taller.distanciaKmDesde(latitudUsuario, longitudUsuario);
  return 'a ${km.toStringAsFixed(1)} km de ti';
}

/// Intent `geo:` para abrir la RUTA en la app de mapas del telefono.
///
/// Politica del proyecto: la ruta y el ETA los calcula la app nativa, no
/// MapLibre. Dibujar la linea de ruta adentro de la app exigiria un motor de
/// rutas (OSRM, Valhalla, Mapbox Directions) y todos son de pago o limitadas.
/// Delegando, ademas, se le da al usuario la app que ya conoce, con su modo
/// Division de trabajo: nosotros dibujamos DONDE ESTAN los talleres; el
/// telefono decide COMO LLEGAR.
///
/// El formato es el estandar de Android/iOS para un punto de mapa:
/// `geo:lat,lng?q=lat,lng(nombre)`. La `q` es la que de verdad coloca el pin en
/// los mapas que respetan el parametro; el par inicial es el que respetan los
/// que no.
///
/// El nombre va con [Uri.encodeComponent] y no interpolado crudo: los talleres
/// tienen acentos ("Taller Gómez"), y un espacio sin codificar rompe el parser
/// del otro lado. [Uri.encodeComponent] manda el espacio como `%20` y no como
/// `+`, que es lo unico que los parsers de `geo:` entienden igual.
///
/// [Uri.encodeComponent] NO escapa los parentesis -- estan en el conjunto de
/// caracteres "seguros" de la RFC 3986 -- y en `geo:` justamente son los
/// delimitadores de la etiqueta: `q=lat,lng(Nombre)`. Un taller llamado
/// "Taller (Nº 2) & Cia" deja dos parentesis de mas y el pin deja de interpretar
/// el nombre, o aparece en otro sitio. Por eso se escapan a mano despues.
String _etiquetaGeo(String nombre) =>
    Uri.encodeComponent(nombre).replaceAll('(', '%28').replaceAll(')', '%29');

/// Intent `geo:` para abrir el taller en la app de mapas del telefono.
///
/// Politica del proyecto: la ruta y el ETA los calcula la app nativa, no
/// MapLibre. Dibujar la linea de ruta adentro de la app exigiria un motor de
/// rutas (OSRM, Valhalla, Mapbox Directions) y todos son de pago o de uso
/// limitado. Delegando, ademas, se le da al usuario la app que ya conoce, con su
/// modo sin trafico y su voz.
///
/// Division de trabajo: nosotros dibujamos DONDE ESTAN los talleres; el telefono
/// decide COMO LLEGAR.
///
/// El formato es el estandar de Android/iOS para un punto de mapa:
/// `geo:lat,lng?q=lat,lng(nombre)`. La `q` es la que de verdad coloca el pin en
/// los mapas que respetan el parametro; el par inicial es el que respetan los
/// que no.
Uri uriDeRuta(Taller taller) {
  final lat = taller.latitud;
  final lng = taller.longitud;

  return Uri.parse(
    'geo:$lat,$lng?q=$lat,$lng(${_etiquetaGeo(taller.nombre)})',
  );
}

/// Mapa de los talleres afiliados con su ubicación en vivo.
class TalleresMapaScreen extends StatefulWidget {
  const TalleresMapaScreen({
    super.key,
    this.onTallerSelected,
    this.tallerSeleccionadoId,
    this.embeddido = false,
  });

  /// Se dispara cuando el usuario elige un taller, ya sea tocando su círculo en
  /// el mapa o su tarjeta en la lista. Si es `null`, la pantalla solo muestra.
  final ValueChanged<Taller>? onTallerSelected;

  /// Id del taller que ya venia elegido, para marcarlo en el modal.
  ///
  /// Lo recibe el dashboard en vez de guardarlo por su cuenta, porque la
  /// verdad de "que taller tiene elegido el cliente" esta en el dashboard y
  /// duplicar ese estado aca es como aparecen dos indices distintos: al tocar
  /// una tarjeta, el modal marcaria una y el formulario otra.
  final int? tallerSeleccionadoId;

  /// Cuando es `true` la pantalla no trae `Scaffold` ni `AppBar` propios, para
  /// poder incrustarse dentro del dashboard del cliente, que ya tiene los suyos.
  final bool embeddido;

  @override
  State<TalleresMapaScreen> createState() => _TalleresMapaScreenState();
}

class _TalleresMapaScreenState extends State<TalleresMapaScreen> {
  final UbicacionService _ubicacion = const UbicacionService();

  MapLibreMapController? _mapa;
  Position? _posicion;

  /// Talleres afiliados leídos de la base local.
  List<Taller> _talleres = const <Taller>[];

  /// Círculos actualmente en el mapa. `addCircles` los devuelve y `removeCircles`
  /// los recibe: sin esta lista no hay forma de limpiarlos entre recargas.
  List<Circle> _circulosPintados = const <Circle>[];

  bool _cargando = true;
  String _error = '';
  EstadoUbicacion _estadoError = EstadoUbicacion.errorDesconocido;

  @override
  void initState() {
    super.initState();
    _ubicar();
    _cargarTalleres();
  }

  /// Lee los afiliados. La baja lógica se respeta: `obtenerActivos()` excluye
  /// los dados de baja, que no deben aparecer en el mapa.
  Future<void> _cargarTalleres() async {
    final talleres = await TallerRepository.instance.obtenerActivos();
    if (!mounted) return;

    setState(() => _talleres = talleres);

    // Los talleres pueden terminar de cargarse después de que el estilo del mapa
    // esté listo. Sin esto, el mapa saldría sin puntos.
    if (_mapa != null) unawaited(_pintarSobreElMapa());
  }

  Future<void> _ubicar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });

    final resultado = await _ubicacion.obtenerPosicion();
    if (!mounted) return; // la pantalla pudo desmontarse mientras esperábamos

    if (!resultado.esOk) {
      setState(() {
        _error = resultado.mensaje;
        _estadoError = resultado.estado;
        _cargando = false;
      });
      return;
    }

    final pos = resultado.position;

    // `Position` es nullable en `ResultadoUbicacion` aunque el caso `ok` siempre
    // venga con posición. Si llegara null seguimos sin ubicación y el mapa queda
    // centrado en República Dominicana.
    if (pos == null) {
      setState(() => _cargando = false);
      if (_mapa != null) unawaited(_pintarSobreElMapa());
      return;
    }

    setState(() {
      _posicion = pos;
      _cargando = false;
    });

    // `initialCameraPosition` solo se lee al construir el widget, así que el
    // recentrado va aquí y no en `build`. En 0.27.1 no existe `mapa.move()`: la
    // API real es `easeCamera` con un `CameraUpdate`.
    await _mapa?.easeCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: _zoomActual,
        ),
      ),
    );
  }

  double get _zoomActual =>
      _posicion == null ? kZoomSinUbicacion : kZoomConUbicacion;

  /// Se dispara en cada carga del estilo, incluso cuando Android recrea la
  /// Activity al rotar.
  ///
  /// No lleva un flag de "ya pinté": el callback puede repetirse por motivos que
  /// el flag no distingue, y terminaría bloqueando el redibujado. La idempotencia
  /// la garantiza `_pintarSobreElMapa`, que borra lo anterior antes de pintar.
  void _alCargarEstilo() {
    unawaited(_pintarSobreElMapa());
  }

  /// Dibuja un círculo por cada taller.
  ///
  /// Va en un método aparte porque los talleres se leen de forma asíncrona y
  /// pueden llegar antes o después de que el estilo esté listo. Con los dos
  /// caminos apuntando aquí, da igual el orden.
  ///
  /// El segundo argumento de `addCircles` es la clave del diseño: `data` viaja
  /// adherido a cada círculo y `onCircleTapped` lo devuelve. Así el taller que el
  /// usuario tocó se sabe exactamente, en vez de adivinar por cercanía.
  Future<void> _pintarSobreElMapa() async {
    final mapa = _mapa;
    if (mapa == null || _talleres.isEmpty) return;

    if (_circulosPintados.isNotEmpty) {
      await mapa.removeCircles(_circulosPintados);
      _circulosPintados = const <Circle>[];
    }

    final pintados = await mapa.addCircles(
      [
        for (final t in _talleres)
          CircleOptions(
            geometry: LatLng(t.latitud, t.longitud),
            circleRadius: 9,
            circleColor: AppColors.orangePrimary.aCss,
            circleStrokeWidth: 2,
            circleStrokeColor: AppColors.cardWhite.aCss,
          ),
      ],
      [
        for (final t in _talleres) <String, dynamic>{'tallerId': t.id},
      ],
    );

    _circulosPintados = pintados;
  }

  /// `onCircleTapped` entrega el círculo tocado, que ya trae su `data`. No hace
  /// falta inferir nada ni buscar el más cercano.
  void _registrarTapEnMapa(MapLibreMapController mapa) {
    mapa.onCircleTapped.add((circle) {
      final id = (circle.data as Map?)?['tallerId'] as int?;
      if (id == null) return;

      // `orElse` evita el `StateError` si el taller se dio de baja entre la
      // consulta y el tap.
      final taller = _talleres.firstWhere(
        (t) => t.id == id,
        orElse: () => _talleres.first,
      );
      _mostrarFicha(taller);
    });
  }

  /// Ficha del taller con su distancia y la acción de agendar.
  Future<void> _mostrarFicha(Taller taller) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final pos = _posicion;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  taller.nombre,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.labelDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  taller.direccion,
                  style: const TextStyle(
                    color: AppColors.textGray,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  etiquetaDistancia(
                    taller,
                    pos?.latitude,
                    pos?.longitude,
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.orangePrimary,
                  ),
                ),
                if (taller.telefono.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.phone_outlined,
                        size: 16,
                        color: AppColors.orangePrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        taller.telefono,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),

                // "Abrir en Maps" vive JUNTO a "Agendar cita", no en lugar de el.
                // Uno de los dos botones deja al usuario dentro de AutoFix y el
                // otro lo saca a la app de mapas del sistema, que es la que
                // tiene el trafico y la ruta real. Quitar la busqueda libre no
                // puede significar quitar el camino para llegar al taller.
                Row(
                  children: [
                    Expanded(
                      child: _BotonSecundario(
                        icono: Icons.near_me_outlined,
                        etiqueta: 'Abrir en Maps',
                        onPressed: () => _abrirEnMaps(taller),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _BotonPrimario(
                        etiqueta: 'Agendar cita',
                        onPressed: widget.onTallerSelected == null
                            ? null
                            : () {
                                Navigator.pop(context);
                                widget.onTallerSelected!(taller);
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Abre el taller en la app de mapas del telefono.
  ///
  /// La ruta y el ETA los calcula Waze o Google Maps, no MapLibre: es la forma
  /// de respectar la politica de cero APIs de pago sin dejar al cliente sin
  /// navegacion. Ver [uriDeRuta].
  Future<void> _abrirEnMaps(Taller taller) async {
    // `launchUrl` devuelve `false` en vez de lanzar cuando no hay nada que
    // maneje el intent. Pasa cuando el telefono no tiene ninguna app de mapas y
    // el navegador no acepta `geo:`. Sin este chequeo el boton queda como si
    // no respondiera y el usuario lo repite varias veces.
    final abierto = await launchUrl(
      uriDeRuta(taller),
      mode: LaunchMode.externalApplication,
    );

    if (!abierto) {
      _aviso('No encontramos una app de mapas en este teléfono.');
    }
  }

  void _aviso(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
    );
  }

  /// La lista de afiliados, en el modal del boton flotante.
  ///
  /// El tap NO elige taller ni salta a la seccion de agendar: elige donde mira
  /// la camara. Es un cambio de intencion deliberado. Con la tira horizontal de
  /// antes, tocar una tarjeta abria directamente la ficha con "Agendar cita", de
  /// modo que explorar la red y agendar eran el mismo gesto, y el mapa no
  /// mostraba nunca el taller que el usuario todavia no habia tocado.
  ///
  /// Aqui el modal es una navegacion de Exploracion -- "muestrame donde esta" --
  /// y la cita se agenda aparte, desde la ficha de un circulo o tocando "Abrir
  /// en Maps". Si ademas se emitiera `onTallerSelected`, el dashboard saltaria
  /// a la pantalla de agendar mientras el usuario todavia esta mirando el mapa,
  /// y nunca podria recorrer mas de un taller.
  ///
  /// El check del modal marca el taller que YA venia elegido, para que el
  /// usuario sepa cual tiene en el formulario. Ese estado no se cambia desde
  /// aca.
  ///
  /// El modal se arma con la lista YA ORDENADA y no se ordena con un `setState`
  /// adentro: abrirlo es una lectura del estado actual, no una operacion que
  /// cambie lo que hay en pantalla.
  Future<void> _mostrarListaDeTalleres() async {
    if (_talleres.isEmpty) {
      _aviso('No hay talleres afiliados disponibles.');
      return;
    }

    final pos = _posicion;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        // Se calcula UNA vez y se reutiliza para `itemCount` y para
        // `itemBuilder`. Leer el getter dos veces no es solo una wasted call:
        // cada llamada corre el `sort` de nuevo sobre una lista nueva, y
        // `itemCount` y el indice podrian ver ordenes distintos si la posicion
        // llegara a medio camino.
        final ordenados = _talleresOrdenados;

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _TituloLista(),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: ordenados.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.inputBorder),
                  itemBuilder: (context, index) {
                    final taller = ordenados[index];
                    return _TarjetaTaller(
                      taller: taller,
                      distancia: etiquetaDistancia(
                        taller,
                        pos?.latitude,
                        pos?.longitude,
                      ),
                      esElElegido: taller.id == widget.tallerSeleccionadoId,
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(_centrarEn(taller));
                      },
                      onAbrirEnMaps: () => unawaited(_abrirEnMaps(taller)),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Anima la camara hasta un taller.
  ///
  /// `easeCamera` y no `move`: `move` no existe en maplibre_gl 0.27.1, y el
  /// salto seco de una esquina a otra hace que el usuario pierda de a donde
  /// salio. Con la animacion se ve de donde a donde.
  ///
  /// El zoom se sube a [kZoomTaller] aunque la pantalla haya abierto sin GPS:
  /// cuando el usuario elige un taller a proposito, ya nos dijo que quiere ver
  /// ese taller, no el panorama de la isla.
  Future<void> _centrarEn(Taller taller) async {
    await _mapa?.easeCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(taller.latitud, taller.longitud),
          zoom: kZoomTaller,
        ),
      ),
    );
  }

  /// Dispuesta de más cerca a más lejos.
  ///
  /// Con GPS ordena por [Taller.distanciaKmDesde]. Sin GPS -- permiso denegado,
  /// GPS apagado, o el fused location provider que no respondio -- devuelve la
  /// lista sin tocar: cero errores, cero cambios, la lista tal como la dio la
  /// base.
  ///
  /// El caso sin ubicacion es el NORMAL, no la excepcion: pedir permiso de
  /// ubicacion a un usuario y que lo niegue es de las tres o cuatro cosas que
  /// mas pasan. Que esa persona no vea la lista de talleres seria el fallo mas
  /// caro de la pantalla.
  ///
  /// Ojo con el "orden por defecto": es el que devuelve `obtenerActivos()`, que
  /// ordena por nombre con `COLLATE NOCASE`. No es un sort accidental por id,
  /// y es deliberado: un orden alfabetico es estable entre instalaciones (dos
  /// devices con la misma semilla muestran la misma lista) y no depende de en
  /// que orden se grabaron las filas. Ver `TallerRepository.obtenerActivos`.
  List<Taller> get _talleresOrdenados => ordenarPorCercania(
    _talleres,
    _posicion?.latitude,
    _posicion?.longitude,
  );

  @override
  Widget build(BuildContext context) {
    final mapa = _cuerpo();

    if (widget.embeddido) return mapa;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Talleres Afiliados'),
        backgroundColor: AppColors.headerNavy,
        foregroundColor: AppColors.cardWhite,
      ),
      body: mapa,
    );
  }

  Widget _cuerpo() {
    // El mapa se dibuja siempre. Si no hay ubicación se abre en República
    // Dominicana y el problema de permisos aparece como aviso encima, no
    // reemplazando el mapa: el mapa es la función principal de la pantalla.
    final camaraInicial = _posicion == null
        ? kCentroRepublicaDominicana
        : LatLng(_posicion!.latitude, _posicion!.longitude);

    return Stack(
      children: [
        MapLibreMap(
          styleString: EstilosMapa.porDefecto,

          initialCameraPosition: CameraPosition(
            target: camaraInicial,
            zoom: _zoomActual,
          ),

          onMapCreated: (controlador) {
            _mapa = controlador;
            _registrarTapEnMapa(controlador);

            if (_talleres.isNotEmpty) unawaited(_pintarSobreElMapa());
          },

          // Registrar los círculos acá y no en onMapCreated: desde Android 0.27.0
          // el mapa sobrevive a la recreación de la Activity, pero el contenido
          // del estilo no vuelve. Si se pinta en onMapCreated, al rotar el
          // dispositivo los marcadores desaparecen.
          onStyleLoadedCallback: _alCargarEstilo,

          // No pide permisos ni falla si están denegados: simplemente no se dibuja
          // el punto azul. Los permisos los pide `_ubicar`.
          myLocationEnabled: true,
          myLocationRenderMode: MyLocationRenderMode.normal,
        ),

        if (_error.isNotEmpty)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _AvisoUbicacion(
              mensaje: _error,
              estado: _estadoError,
              onReintentar: _ubicar,
            ),
          ),

        if (_cargando)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66FFFFFF),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),

        // La tira horizontal de talleres que estaba anclada abajo se sustituyo
        // por este boton. El motivo concreto: con la tira, la pantalla ocupaba
        // ~96px de alto con datos que el modal muestra completos y con la
        // distancia. Ademas la tira y el tap sobre el circulo eran dos caminos
        // al mismo dato con comportamientos distintos, y el modal los unifica.
        //
        // Va dentro del `Stack` y no en `Scaffold.floatingActionButton`: esta
        // pantalla se dibuja EMBEBIDA dentro del dashboard del cliente, que ya
        // tiene su Scaffold. Un Scaffold propio anidado pondria el boton fuera
        // del area del mapa, arriba del NavigationBar.
        if (_talleres.isNotEmpty && !_cargando)
          Positioned(
            right: 16,
            bottom: 16,
            child: _FabListaTalleres(
              cantidad: _talleres.length,
              onPressed: _mostrarListaDeTalleres,
            ),
          ),

        if (!_cargando) const Positioned(top: 12, right: 12, child: _Leyenda()),
      ],
    );
  }
}

/// Convierte un `Color` de Flutter al string CSS que MapLibre espera.
///
/// MapLibre no entiende `Color`: espera `'#RRGGBB'`. Sin esto, `circleColor`
/// no acepta `AppColors.orangePrimary`.
extension ColorMapa on Color {
  String get aCss {
    // Los componentes son double 0.0-1.0, hay que escalar a 0-255. Las
    // variables no pueden llamarse r/g/b porque taparían los getters de Color.
    String hex(double componente) => (componente * 255)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
    return '#${hex(r)}${hex(g)}${hex(b)}';
  }
}

/// Boton flotante que abre la lista de afiliados.
///
/// Muestra el numero de talleres en una insignia. No es decorativo: la unica
/// forma de distinguir "no hay afiliados" de "el boton todavia no cargo" es
/// que el boton exista con un 3 adentro, o que no exista con la base vacia.
class _FabListaTalleres extends StatelessWidget {
  const _FabListaTalleres({required this.cantidad, required this.onPressed});

  final int cantidad;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onPressed,
      backgroundColor: AppColors.orangePrimary,
      foregroundColor: Colors.white,
      elevation: 6,
      icon: const Icon(Icons.list_alt_outlined),
      label: Text(
        '$cantidad ${cantidad == 1 ? 'taller' : 'talleres'}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Encabezado del modal de lista.
class _TituloLista extends StatelessWidget {
  const _TituloLista();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Talleres afiliados',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.labelDark,
              ),
            ),
          ),
          Text(
            'Toca para ver en el mapa',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textGray.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una fila del modal: nombre, direccion, distancia y el boton deMaps.
///
/// Las dos acciones van separadas y en lugares distintos del widget a proposito.
/// [onTap] es la fila entera y [onAbrirEnMaps] es el IconButton de la derecha:
/// el boton se queda con el gesto del boton y la fila con el resto. Si el boton
/// fuera parte del `InkWell`, abrir Maps cerraria el modal y moveria la camara
/// al mismo tiempo, que es justo lo contrario de lo que se pidio.
class _TarjetaTaller extends StatelessWidget {
  const _TarjetaTaller({
    required this.taller,
    required this.distancia,
    required this.onTap,
    required this.onAbrirEnMaps,
    this.esElElegido = false,
  });

  final Taller taller;
  final String distancia;
  final VoidCallback onTap;
  final VoidCallback onAbrirEnMaps;
  final bool esElElegido;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardWhite,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  esElElegido
                      ? Icons.location_on
                      : Icons.location_on_outlined,
                  size: 20,
                  color: AppColors.orangePrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      taller.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.labelDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      taller.direccion,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGray,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.straighten,
                          size: 12,
                          color: AppColors.orangePrimary,
                        ),
                        const SizedBox(width: 4),
                        // La distancia se pasa YA formateada desde la pantalla,
                        // y no se calcula aqui. La tarjeta no tiene por que saber
                        // de donde salio la posicion del cliente; solo la pinta.
                        Expanded(
                          child: Text(
                            distancia,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: distancia == kDistanciaNoDisponible
                                  ? AppColors.textGray
                                  : AppColors.orangePrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onAbrirEnMaps,
                tooltip: 'Abrir en Maps',
                icon: const Icon(
                  Icons.near_me_outlined,
                  size: 20,
                  color: AppColors.orangePrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Accion principal de la ficha: la que deja al cliente dentro de AutoFix.
class _BotonPrimario extends StatelessWidget {
  const _BotonPrimario({required this.etiqueta, required this.onPressed});

  final String etiqueta;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.event_available, size: 18),
      label: Text(etiqueta),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.orangePrimary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

/// Accion secundaria: saca al cliente de la app hacia su navegador de mapas.
///
/// Boton delineado y no texto plano porque las dos acciones de la ficha se
/// parecen en importancia y solo una puede ser el relleno naranja: si "Abrir en
/// Maps" tambien fuera un boton lleno, el usuario no sabria cual de los dos es
/// el camino esperado.
class _BotonSecundario extends StatelessWidget {
  const _BotonSecundario({
    required this.icono,
    required this.etiqueta,
    required this.onPressed,
  });

  final IconData icono;
  final String etiqueta;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icono, size: 18),
      label: Text(etiqueta),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.orangePrimary,
        side: const BorderSide(color: AppColors.orangePrimary, width: 1.4),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

/// Aviso de problema de ubicación, en formato de banderita sobre el mapa.
class _AvisoUbicacion extends StatelessWidget {
  const _AvisoUbicacion({
    required this.mensaje,
    required this.estado,
    required this.onReintentar,
  });

  final String mensaje;
  final EstadoUbicacion estado;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    // Con el permiso denegado para siempre Android no vuelve a mostrar el
    // diálogo, así que "Reintentar" no haría nada. Ajustes es la única salida.
    final denegadoParaSiempre =
        estado == EstadoUbicacion.permisoDenegadoPermanente;
    final reintentable =
        estado != EstadoUbicacion.permisoDenegadoPermanente &&
        estado != EstadoUbicacion.servicioDesactivado;

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(10),
      color: AppColors.cardWhite,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(
              Icons.location_off,
              size: 22,
              color: AppColors.atrasadas,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                mensaje,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.labelDark,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (denegadoParaSiempre)
              TextButton(
                onPressed: () =>
                    unawaited(const UbicacionService().abrirAjustesDeLaApp()),
                child: const Text('Ajustes'),
              )
            else if (reintentable)
              TextButton(
                onPressed: onReintentar,
                child: const Text('Reintentar'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda();

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      color: AppColors.cardWhite,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Punto(color: AppColors.blueAccent, etiqueta: 'Vos'),
            SizedBox(width: 14),
            _Punto(color: AppColors.orangePrimary, etiqueta: 'Afiliados'),
          ],
        ),
      ),
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto({required this.color, required this.etiqueta});

  final Color color;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(etiqueta, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

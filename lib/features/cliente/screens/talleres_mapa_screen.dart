import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/core/connectivity/connectivity_scope.dart';
import 'package:autofix/core/mapa/estilos_mapa.dart';
import 'package:autofix/core/mapa/etiqueta_distancia.dart';
import 'package:autofix/core/ubicacion/ubicacion_service.dart';
import 'package:autofix/features/talleres/data/taller_repository.dart';
import 'package:autofix/features/talleres/models/taller.dart';
import 'package:autofix/shared/theme/app_colors.dart';

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
  return [...talleres]..sort(
    (a, b) => a
        .distanciaKmDesde(latitudUsuario, longitudUsuario)
        .compareTo(b.distanciaKmDesde(latitudUsuario, longitudUsuario)),
  );
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

  return Uri.parse('geo:$lat,$lng?q=$lat,$lng(${_etiquetaGeo(taller.nombre)})');
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
  ///
  /// `String?` desde la v7 (UUID).
  final String? tallerSeleccionadoId;

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

  /// Etiquetas de nombre actualmente en el mapa. Mismo contrato que
  /// [_circulosPintados]: `addSymbols` las devuelve y `removeSymbols` las recibe.
  ///
  /// Son una lista aparte y no "un Symbol por circulo" porque son dos anotaciones
  /// distintas que comparten la misma posicion, y borrarlas mezcladas en una sola
  /// lista haria que un tap se atribuyera al elemento equivocado.
  List<Symbol> _simbolosPintados = const <Symbol>[];

  bool _cargando = true;
  String _error = '';
  EstadoUbicacion _estadoError = EstadoUbicacion.errorDesconocido;

  /// El estilo remoto (CartoDB) ya cargo, asi que se puede pintar encima.
  ///
  /// Sin esto no hay forma de saber si los circulos van a ser visibles: el
  /// `addCircles` sobre un estilo que nunca llego no truena, se traga el error
  /// en el lado nativo y el mapa queda limpio y vacio.
  bool _estiloCargado = false;

  /// Se decidio dejar de esperar el estilo (sin red, o el host no respondio).
  bool _estiloAbandonado = false;

  /// Llave de la vista de plataforma del mapa. Cada incremento la reconstruye
  /// desde cero, que es la unica forma de que MapLibre pida el estilo otra vez
  /// despues de un fallo. Ver [_reintentar].
  int _intentoDeEstilo = 0;

  /// Cuanto se espera el estilo remoto antes de mostrar el aviso.
  ///
  /// 12 segundos y no menos: en una red movil lenta el estilo de CartoDB tarda
  /// entre 3 y 8, y cortarlo a 3 le pone "sin conexion" a alguien que solo
  /// tenia dos barras. Con mas de 12 el usuario ya perdio la paciencia.
  static const Duration _esperaEstilo = Duration(seconds: 12);

  Timer? _temporizadorEstilo;

  @override
  void initState() {
    super.initState();
    _armarEsperaDeEstilo();
    _ubicar();
    _cargarTalleres();
    // El pull de catalogos del arranque termina DESPUES de que este mapa ya
    // construyo sus marcadores con la lista local (posiblemente vacia). Sin
    // este oyente la pantalla se quedaria con lo que leyo al abrirse hasta
    // que alguien recargue a mano.
    TallerRepository.instance.addListener(_alCambiarElCatalogo);
  }

  @override
  void dispose() {
    TallerRepository.instance.removeListener(_alCambiarElCatalogo);
    _temporizadorEstilo?.cancel();
    super.dispose();
  }

  /// El catalogo local cambio y esta pantalla ya estaba pintada.
  ///
  /// Relee la tabla y vuelve a armar los marcadores por el mismo camino con
  /// que los arma al abrirse; no hay un segundo código de pintado que pueda
  /// desincronizarse del primero.
  void _alCambiarElCatalogo() {
    if (!mounted) return;
    debugPrint('[Mapa] catalogo local cambio, recargando talleres');
    unawaited(_cargarTalleres());
  }

  /// Arranca (o reinicia) el reloj del estilo.
  ///
  /// El caso que cubre es el de "estoy conectado pero el servidor de mapas no
  /// responde" (DNS caido, portal cautivo, firewall): la red esta, el estilo no
  /// llega, y `onStyleLoadedCallback` nunca se dispara. Sin este timer la
  /// pantalla se queda en mapa en blanco para siempre sin decir nada.
  void _armarEsperaDeEstilo() {
    _temporizadorEstilo?.cancel();
    _temporizadorEstilo = Timer(_esperaEstilo, () {
      if (!mounted || _estiloCargado) return;
      setState(() => _estiloAbandonado = true);
    });
  }

  /// Lee los afiliados. La baja lógica se respeta: `obtenerActivos()` excluye
  /// los dados de baja, que no deben aparecer en el mapa.
  ///
  /// Es una lectura local, pero igual va en try/catch: una base corrupta o un
  /// disco lleno no deberian dejar la pantalla en blanco sin decir por que. El
  /// error queda en [_error], que es el banner que ya existe de la pantalla.
  Future<void> _cargarTalleres() async {
    try {
      final talleres = await TallerRepository.instance.obtenerActivos();
      if (!mounted) return;
      // Sin tocar `_error`: si el `_ubicar()` que corre en paralelo acaba de
      // dejar un aviso de permiso de ubicacion, limpiarlo aqui lo borraria sin
      // que el usuario lo haya visto.
      setState(() => _talleres = talleres);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos leer los talleres guardados en este dispositivo.';
      });
      debugPrint('TalleresMapa: no se pudieron leer los talleres ($e)');
      return;
    }

    // Los talleres pueden terminar de cargarse después de que el estilo del mapa
    // esté listo. Sin esto, el mapa saldría sin puntos.
    if (_mapa != null) unawaited(_pintarSobreElMapa());
  }

  /// Reintenta TODO lo que depende de afuera: ubicacion, talleres y estilo.
  ///
  /// El bump de [_intentoDeEstilo] es la parte que importa. MapLibre no vuelve
  /// a pedir el estilo remoto solo despues de un fallo, y el `onStyleLoaded`
  /// de una carga fallida no se dispara nunca: sin recrear el widget (llave
  /// nueva) el mapa se queda en blanco aunque la red vuelva. Con la llave
  /// distinta se construye otra vista de plataforma, que arranca de cero.
  Future<void> _reintentar() async {
    await _ubicar();
    if (!mounted) return;
    await _cargarTalleres();
    if (!mounted || _estiloCargado) return;
    // La vista de plataforma nueva no tiene NADA de la vieja: si quedaran los
    // ids de los circulos anteriores, el siguiente `_pintarSobreElMapa`
    // empezaria por `removeCircles` con ids que ya no existen y abortaria el
    // pintado completo (el `try` que lo envuelve se traga ese error).
    _mapa = null;
    _circulosPintados = const <Circle>[];
    _simbolosPintados = const <Symbol>[];
    setState(() => _intentoDeEstilo++);
    _armarEsperaDeEstilo();
  }

  /// `true` cuando el mapa no puede pintarse y hay que decirlo en pantalla.
  ///
  /// Tres caminos para llegar a `true`, y el orden importa:
  ///
  /// 1. El estilo ya cargo -> `false`, pase lo que pase despues. Es el unico
  ///    caso en que el mapa SI esta utilizable.
  /// 2. Sin red desde el principio -> `true` YA, sin esperar los 12 segundos
  ///    del timer: la app lo sabe por [ConnectivityScope] y hacer esperar a
  ///    alguien que acaba de apagar el wifi solo para confirmar lo obvio es
  ///    mala educacion.
  /// 3. Hay red pero no llega nada -> `true` recien cuando vence el timer,
  ///    que es el caso donde hace falta la evidencia antes de acusar.
  ///
  /// `dependOnInheritedWidgetOfExactType` y no `ConnectivityScope.of(context)`
  /// a proposito: `.of` tiene un `assert` que revienta cuando no hay scope en
  /// el arbol, que es exactamente lo que pasa en los tests que montan esta
  /// pantalla suelta. Esta llamada devuelve `null` y ya.
  bool _estiloNoDisponible(BuildContext context) {
    if (_estiloCargado) return false;
    if (_estiloAbandonado) return true;
    final scope = context
        .dependOnInheritedWidgetOfExactType<ConnectivityScope>();
    return scope?.notifier?.desconectado ?? false;
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
    _temporizadorEstilo?.cancel();
    _estiloCargado = true;
    // El callback llega desde el lado nativo y puede hacerlo con la pantalla
    // ya desmontada (rotacion a mitad de carga): sin el `mounted`, el
    // `setState` de abajo truena con "setState called after dispose".
    if (!mounted) return;
    // El estilo llego: el aviso de "sin mapa" deja de ser cierto. Sin este
    // setState, el timeout de los 12 segundos seguira mostrando el cartel
    // aunque el estilo se haya cargado tarde.
    if (_estiloAbandonado) setState(() => _estiloAbandonado = false);
    unawaited(_pintarSobreElMapa());
  }

  /// Dibuja un círculo por cada taller, con su nombre encima.
  ///
  /// Va en un método aparte porque los talleres se leen de forma asíncrona y
  /// pueden llegar antes o después de que el estilo esté listo. Con los dos
  /// caminos apuntando aquí, da igual el orden.
  ///
  /// El segundo argumento de `addCircles` y de `addSymbols` es la clave del
  /// diseño: `data` viaja adherido a cada anotación y `onCircleTapped` /
  /// `onSymbolTapped` lo devuelven. Así el taller que el usuario tocó se sabe
  /// exactamente, en vez de adivinar por cercanía.
  ///
  /// Círculo y etiqueta se pintan como DOS anotaciones y no como una sola con
  /// `iconImage`: los nombres de los talleres no son los nombres de los glyphs del
  /// estilo (que son los de CartoDB), así que la etiqueta tiene que ser texto
  /// generado. Y al ser texto, necesita halo: sin el, "Taller Gómez" en naranja
  /// sobre un mapa beige se pierde en el borde de una carretera.
  Future<void> _pintarSobreElMapa() async {
    final mapa = _mapa;
    if (mapa == null || !_estiloCargado || _talleres.isEmpty) return;

    // El `try` cubre el caso de estilo a medias (o estilo que se recarga a
    // mitad de un repaint): `addCircles`/`addSymbols` corren en el lado
    // nativo y su `PlatformException` llegaria como error de runtime no
    // atrapado, tumbando la pantalla en caliente. Pintar es lo primero que se
    // puede perder en una situacion asi, nunca el mapa entero.
    try {
      if (_circulosPintados.isNotEmpty) {
        await mapa.removeCircles(_circulosPintados);
        _circulosPintados = const <Circle>[];
      }
      if (_simbolosPintados.isNotEmpty) {
        await mapa.removeSymbols(_simbolosPintados);
        _simbolosPintados = const <Symbol>[];
      }

      _circulosPintados = await mapa.addCircles(
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

      // El circulo tiene 9 px de radio mas 2 de borde: la etiqueta arranca un
      // poco mas abajo de eso para no quedar encima del pin. `textOffset` se mide
      // en lineas de texto, no en pixeles, asi que el 1.3 de abajo es "un poco mas
      // de una linea hacia abajo" y se lee igual a cualquier tamano de fuente.
      _simbolosPintados = await mapa.addSymbols(
        [
          for (final t in _talleres)
            SymbolOptions(
              geometry: LatLng(t.latitud, t.longitud),
              textField: t.nombre,
              textSize: 11,
              textColor: AppColors.labelDark.aCss,
              textHaloColor: AppColors.cardWhite.aCss,
              textHaloWidth: 1.8,
              textAnchor: 'top',
              textOffset: const Offset(0, 1.3),
              textJustify: 'center',
            ),
        ],
        [
          for (final t in _talleres) <String, dynamic>{'tallerId': t.id},
        ],
      );
    } catch (e) {
      debugPrint('TalleresMapa: no se pudieron pintar los talleres ($e)');
    }
  }

  /// Centro y ficha, en ese orden, para las TRES entradas al taller.
  ///
  /// Circulo, etiqueta y tarjeta del modal terminan acá. No por DRY de manual sino
  /// porque las tres son la misma intencion del usuario -- "quiero ver este
  /// taller" -- y mientras cada una hizo lo que pudo (una animaba la camara, otra
  /// no, otra abria la ficha) el cliente tenia que adivinar cual de las tres iba
  /// a hacer que.
  Future<void> _explorarTaller(Taller taller) async {
    // La camara y la ficha van a la vez, no en serie. Esperar a que termine la
    // animacion para abrir la hoja de abajo hace que el tap se sienta como si no
    // se hubiera registrado.
    unawaited(_centrarEn(taller));
    await _mostrarFicha(taller);
  }

  /// Conecta los callbacks de anotaciones con el mapa.
  ///
  /// `onCircleTapped` y `onSymbolTapped` entregan la anotación tocada, que ya trae
  /// su `data`. No hace falta inferir nada ni buscar el más cercano: los dos
  /// caminos llegan al mismo `_explorarTaller`.
  void _registrarCallbacksEnMapa(MapLibreMapController mapa) {
    mapa.onCircleTapped.add((circle) {
      _abrirSiHayTaller(circle.data);
    });

    // La etiqueta se dibuja PEGADA al circulo, asi que sin esto el nombre seria lo
    // unico que se puede tocar en la mitad de la pantalla.
    mapa.onSymbolTapped.add((symbol) {
      _abrirSiHayTaller(symbol.data);
    });
  }

  /// Traduce el `data` de una anotacion al taller y lo explora.
  ///
  /// El id se lee como `String?` y no `int?`: MapLibre devuelve el `data` como
  /// el mapa que se le dio al crear la anotacion, y como el `id` del taller ahora
  /// es un UUID (TEXT), el cast a `int` revienta con un TypeError en CADA tap.
  ///
  /// Por eso tambien se compara con `==` sobre `String?`: el `null == null` de
  /// una anotacion sin id no deberia abrir nada, y por eso hay un `if` antes.
  void _abrirSiHayTaller(dynamic data) {
    final id = (data as Map?)?['tallerId'] as String?;
    if (id == null) return;

    // `orElse` evita el `StateError` si el taller se dio de baja entre la
    // consulta y el tap.
    final taller = _talleres.firstWhere(
      (t) => t.id == id,
      orElse: () => _talleres.first,
    );
    unawaited(_explorarTaller(taller));
  }

  /// `true` solo cuando la ficha debe ofrecer "Agendar cita".
  ///
  /// El Bug 4: el boton se mostraba siempre que hubiera un `onTallerSelected`,
  /// y el dashboard se lo pasaba tambien a un invitado para poder lanzarle el
  /// dialogo "inicia sesión para agendar" DESPUES del toque. El resultado era
  /// un invitado viendo la opcion de agendar. La regla ahora es que no la vea
  /// nunca, y el chequeo se hace contra la SESION y no contra un flag de UI.
  ///
  /// [SesionCliente.haySesion] mira Firebase Auth y la sesion local: el login
  /// sin red abre el dashboard sin pasar por Auth, y esa persona si puede
  /// agendar (la cita se guarda primero en SQLite y sube sola cuando vuelva
  /// la red).
  ///
  /// Es la segunda barrera: el dashboard ademas deja este callback en `null`
  /// cuando no toca, y ahi `onTallerSelected == null` desactiva el boton por
  /// su cuenta.
  bool get _puedeAgendar =>
      widget.onTallerSelected != null && SesionCliente.haySesion;

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
                  etiquetaDistancia(taller, pos?.latitude, pos?.longitude),
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
                        onPressed: !_puedeAgendar
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
    //
    // El `try` va aparte porque el lanzamiento si tira excepcion en otros dos
    // casos: `PlatformException` cuando el sistema rechaza el intent y
    // `ArgumentError` con un URI mal formado. Ninguno tiene que ver con la red,
    // pero los tres dejarian el `await` sin atrapar.
    try {
      final abierto = await launchUrl(
        uriDeRuta(taller),
        mode: LaunchMode.externalApplication,
      );

      if (!abierto) {
        _aviso('No encontramos una app de mapas en este teléfono.');
      }
    } catch (e) {
      debugPrint('TalleresMapa: no se pudo abrir la ruta ($e)');
      _aviso('No pudimos abrir la ruta en tu app de mapas.');
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
  /// El modal DEVUELVE el taller tocado con `Navigator.pop(context, taller)` en
  /// vez de tener el boton que lo pops y seguir tocando estado desde adentro. Con
  /// el `pop` sin resultado habia que hacer dos cosas en el `onTap` -- cerrar y
  /// animar -- y no se podia garantizar el orden entre la hoja cerrandose y la
  /// ficha del otro taller apareciendo: dos `showModalBottomSheet` seguidos se
  /// pisan. Devolviendo el taller, la hoja se cierra sola y la apertura siguiente
  /// ocurre en el `await` de [_explorarTaller], ya con el modal deshecho.
  ///
  /// Tocar una tarjeta NO elige taller en el formulario ni salta a la seccion de
  /// agendar: elige donde mira la camara y muestra la ficha. Es un cambio de
  /// intencion deliberado. Con la tira horizontal de antes, tocar una tarjeta
  /// abria directamente la ficha con "Agendar cita", de modo que explorar la red
  /// y agendar eran el mismo gesto, y el mapa no mostraba nunca el taller que el
  /// usuario todavia no habia tocado.
  ///
  /// Aqui el modal es una navegacion de Exploracion -- "muestrame donde esta" --
  /// y la cita se agenda aparte, desde "Agendar cita" en la ficha. Si ademas se
  /// emitiera `onTallerSelected`, el dashboard saltaria a la pantalla de agendar
  /// mientras el usuario todavia esta mirando el mapa, y nunca podria recorrer
  /// mas de un taller.
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

    final elegido = await showModalBottomSheet<Taller>(
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
                      onTap: () => Navigator.pop(context, taller),
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

    // `null` es el cierre del usuario: arrastro la hoja para abajo o toco fuera.
    if (elegido == null || !mounted) return;

    await _explorarTaller(elegido);
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
  List<Taller> get _talleresOrdenados =>
      ordenarPorCercania(_talleres, _posicion?.latitude, _posicion?.longitude);

  @override
  Widget build(BuildContext context) {
    final mapa = _cuerpo(context);

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

  Widget _cuerpo(BuildContext context) {
    // El mapa se dibuja siempre. Si no hay ubicación se abre en República
    // Dominicana y el problema de permisos aparece como aviso encima, no
    // reemplazando el mapa: el mapa es la función principal de la pantalla.
    final camaraInicial = _posicion == null
        ? kCentroRepublicaDominicana
        : LatLng(_posicion!.latitude, _posicion!.longitude);

    final sinEstilo = _estiloNoDisponible(context);

    return Stack(
      children: [
        MapLibreMap(
          // Llave que cambia al reintentar: ver `_reintentar`.
          key: ValueKey('mapa-estilo-$_intentoDeEstilo'),

          styleString: EstilosMapa.porDefecto,

          initialCameraPosition: CameraPosition(
            target: camaraInicial,
            zoom: _zoomActual,
          ),

          onMapCreated: (controlador) {
            _mapa = controlador;
            _registrarCallbacksEnMapa(controlador);

            if (_talleres.isNotEmpty) unawaited(_pintarSobreElMapa());
          },

          // Registrar los círculos acá y no en onMapCreated: desde Android 0.27.0
          // el mapa sobrevive a la recreación de la Activity, pero el contenido
          // del estilo no vuelve. Si se pinta en onMapCreated, al rotar el
          // dispositivo los marcadores desaparecen.
          onStyleLoadedCallback: _alCargarEstilo,

          // `myLocationEnabled` atado a `_posicion`, y NO en `true` fijo, es el
          // arreglo del punto azul que no aparecia. Lo que pasaba: el plugin crea
          // su componente de ubicacion cuando carga el estilo, y en ese instante
          // el permiso todavia no estaba concedido (el dialogo del sistema
          // apenas se esta mostrando), asi que el lado nativo lo descarta con
          // "missing location permissions". Despues el permiso se concede, la
          // posicion llega, pero como el parametro sigue siendo `true` -- el
          // MISMO valor -- `didUpdateWidget` no manda ninguna actualizacion al
          // mapa nativo y el componente, que quedo en null, nunca se vuelve a
          // crear. El punto azul no aparecia hasta rotar el telefono.
          //
          // Atarlo a `_posicion` hace que el valor CAMBIE de `false` a `true` en
          // el `setState` de `_ubicar`, y ahi si viaja la orden que el nativo
          // necesita para activar el componente. De paso no le pedimos al mapa
          // que dibuje una ubicacion que todavia no tenemos.
          //
          // `MyLocationRenderMode.normal` se puede dejar fijo con el flag en
          // false: el unico assert del plugin es para los modos que necesitan
          // GPS, y `normal` es justamente el que no.
          myLocationEnabled: _posicion != null,
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
              onReintentar: _reintentar,
            ),
          ),

        // Aviso de "el mapa no se pudo dibujar". El requisito de la unidad es
        // que la desconexion no tire excepciones NI deje pantallas mudas: sin
        // esto, sin internet el usuario ve un cuadro gris y no sabe si la app
        // se colgo o si no hay datos.
        //
        // Va con `Positioned.fill` + `Align` para quedar centrada sobre el
        // area del mapa sin desplazar el FAB (que sigue arriba en el Stack y
        // sigue recibiendo los toques: un `Container` sin color no captura
        // hits).
        if (sinEstilo && !_cargando)
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 84),
                child: _AvisoMapaSinEstilo(
                  onVerLista: _mostrarListaDeTalleres,
                  onReintentar: _reintentar,
                ),
              ),
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

        // Sin estilo no hay capa de ubicacion ni circulos, asi que la leyenda
        // "Tu / Afiliados" describiria cosas que no se estan viendo.
        if (!_cargando && !sinEstilo)
          const Positioned(top: 12, right: 12, child: _Leyenda()),
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
            'Toca para ver sus datos',
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
                  esElElegido ? Icons.location_on : Icons.location_on_outlined,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// Aviso de que el mapa remoto no se pudo dibujar, con salida hacia la lista.
///
/// No es un error de la app: es la consecuencia esperada de estar sin internet
/// en una pantalla cuyo fondo es un tile server remoto. Por eso el texto
/// arranca diciendo lo que SI funciona (la lista, las citas) en vez de solo
/// anunciar el problema.
class _AvisoMapaSinEstilo extends StatelessWidget {
  const _AvisoMapaSinEstilo({
    required this.onVerLista,
    required this.onReintentar,
  });

  final VoidCallback onVerLista;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: AppColors.cardWhite,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 22,
                  color: AppColors.orangePrimary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'El mapa necesita conexión para dibujarse',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.labelDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'La lista de talleres y tus citas siguen funcionando '
                        'sin conexión.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textGray.withValues(alpha: 0.95),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onReintentar,
                  child: const Text(
                    'Reintentar',
                    style: TextStyle(color: AppColors.textGray),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: onVerLista,
                  child: const Text(
                    'Ver lista de talleres',
                    style: TextStyle(
                      color: AppColors.orangePrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
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
            _Punto(color: AppColors.blueAccent, etiqueta: 'Tú'),
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

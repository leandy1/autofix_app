import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

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

/// Mapa de los talleres afiliados con su ubicación en vivo.
class TalleresMapaScreen extends StatefulWidget {
  const TalleresMapaScreen({
    super.key,
    this.onTallerSelected,
    this.embeddido = false,
  });

  /// Se dispara cuando el usuario elige un taller, ya sea tocando su círculo en
  /// el mapa o su tarjeta en la lista. Si es `null`, la pantalla solo muestra.
  final ValueChanged<Taller>? onTallerSelected;

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
        final distancia = _posicion == null
            ? 'Sin tu ubicacion'
            : '${taller.distanciaKmDesde(_posicion!.latitude, _posicion!.longitude).toStringAsFixed(1)} km';

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
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.straighten,
                      size: 16,
                      color: AppColors.orangePrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      distancia,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.labelDark,
                      ),
                    ),
                    if (taller.telefono.isNotEmpty) ...[
                      const SizedBox(width: 18),
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
                  ],
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.onTallerSelected == null
                        ? null
                        : () {
                            Navigator.pop(context);
                            widget.onTallerSelected!(taller);
                          },
                    icon: const Icon(Icons.event_available),
                    label: const Text('Agendar cita en este taller'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orangePrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Dispuesta de más cerca a más lejos. Sin ubicación mantiene el orden de la
  /// base, que es alfabético.
  List<Taller> get _talleresOrdenados {
    final pos = _posicion;
    if (pos == null) return _talleres;

    return [..._talleres]..sort(
      (a, b) => a
          .distanciaKmDesde(pos.latitude, pos.longitude)
          .compareTo(b.distanciaKmDesde(pos.latitude, pos.longitude)),
    );
  }

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

        if (_talleres.isNotEmpty && !_cargando)
          Positioned(
            bottom: 16,
            left: 12,
            right: 12,
            child: _ListaDeTalleres(
              talleres: _talleresOrdenados,
              onTap: _mostrarFicha,
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

class _ListaDeTalleres extends StatelessWidget {
  const _ListaDeTalleres({required this.talleres, required this.onTap});

  final List<Taller> talleres;
  final ValueChanged<Taller> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: talleres.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final t = talleres[index];
          return Material(
            color: AppColors.cardWhite,
            borderRadius: BorderRadius.circular(10),
            elevation: 3,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onTap(t),
              child: Container(
                width: 216,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      t.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.labelDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      t.direccion,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.phone_outlined,
                          size: 12,
                          color: AppColors.orangePrimary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            t.telefono,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.labelDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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

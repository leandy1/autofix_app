import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/cliente_dashboard_data.dart';
import '../../models/demo_cliente_data.dart';
import '../../theme/app_colors.dart';
import 'agendar_cita_cliente_section.dart';

class TalleresClienteSection extends StatefulWidget {
  const TalleresClienteSection({super.key});

  @override
  State<TalleresClienteSection> createState() => _TalleresClienteSectionState();
}

class _TalleresClienteSectionState extends State<TalleresClienteSection> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _isLoading = true;
  String _errorMessage = '';
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _determinarUbicacion();
  }

  /// Manejo de permisos de ubicación y obtención de coordenadas
  Future<void> _determinarUbicacion() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _errorMessage = 'El servicio de ubicación está desactivado.';
        _isLoading = false;
      });
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _errorMessage = 'Los permisos de ubicación fueron denegados.';
          _isLoading = false;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _errorMessage =
            'Los permisos de ubicación están denegados permanentemente.';
        _isLoading = false;
      });
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _currentPosition = position;
      _isLoading = false;
      _cargarMarcadores();
    });
  }

  /// Construcción de marcadores y cálculo de distancia aproximada[cite: 1]
  void _cargarMarcadores() {
    if (_currentPosition == null) return;

    final markers = <Marker>{};

    // Marcador de Ubicación del Cliente
    markers.add(
      Marker(
        markerId: const MarkerId('cliente_location'),
        position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        infoWindow: const InfoWindow(title: 'Mi Ubicación Actual'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
    );

    // Marcadores para Talleres
    for (var i = 0; i < talleresCliente.length; i++) {
      final taller = talleresCliente[i];

      // Cálculo de distancia en km desde la ubicación actual
      final distanciaEnMetros = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        taller.latitud,
        taller.longitud,
      );
      final distanciaKm = (distanciaEnMetros / 1000).toStringAsFixed(1);

      markers.add(
        Marker(
          markerId: MarkerId('taller_$i'),
          position: LatLng(taller.latitud, taller.longitud),
          infoWindow: InfoWindow(
            title: taller.nombre,
            snippet: '${taller.direccion} ($distanciaKm km)',
          ),
          onTap: () => _mostrarDetalleTaller(taller, distanciaKm),
        ),
      );
    }

    setState(() {
      _markers = markers;
    });
  }

  void _mostrarDetalleTaller(TallerCliente taller, String distanciaKm) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
           me: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                taller.nombre,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Dirección: ${taller.direccion}'),
              Text('Distancia aproximada: $distanciaKm km'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.background,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AgendarCitaClienteSection(tallerSeleccionado: taller),
                      ),
                    );
                  },
                  child: const Text('Agendar Cita en este Taller'),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_errorMessage, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _determinarUbicacion,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Talleres Cercanos'),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          zoom: 13.5,
        ),
        markers: _markers,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        onMapCreated: (controller) => _mapController = controller,
      ),
    );
  }
}
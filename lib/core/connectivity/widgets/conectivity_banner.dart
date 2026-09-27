import 'package:flutter/material.dart';

import '../connectivity_scope.dart';

/// Banner global de estado de red.
///
/// Se coloca por encima del [Navigator] desde `MaterialApp.builder`, asi que
/// es visible en cualquier pantalla, ruta o bottom sheet sin repetir codigo.
class ConectivityBanner extends StatelessWidget {
  const ConectivityBanner({super.key});

  static const double _alto = 30;

  @override
  Widget build(BuildContext context) {
    final servicio = ConnectivityScope.of(context);
    final hayConexion = servicio.hayConexion;

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: hayConexion
          ? const SizedBox.shrink()
          : Material(
              color: Colors.red.shade700,
              child: SafeArea(
                bottom: false,
                child: Container(
                  height: _alto,
                  width: double.infinity,
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off, size: 16, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Sin conexion: los datos se guardan en el dispositivo',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// Version compacta para pantallas que ya tienen su propio AppBar.
class ConectivityChip extends StatelessWidget {
  const ConectivityChip({super.key});

  @override
  Widget build(BuildContext context) {
    final servicio = ConnectivityScope.of(context);
    final hayConexion = servicio.hayConexion;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: hayConexion ? Colors.green.shade600 : Colors.red.shade700,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hayConexion ? Icons.wifi : Icons.wifi_off,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            hayConexion ? 'En linea' : 'Sin conexion',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../connectivity_scope.dart';

/// Banner global de estado de red.
///
/// Va inyectado desde `MaterialApp.builder`, o sea POR DEBAJO del Navigator,
/// asi que aparece en cualquier pantalla sin que cada una lo monte.
///
/// PALETA: uso `AppColors.greenAccent` (0xFF22C55E) para en linea y
/// `AppColors.atrasadas` (0xFFE0554F) para sin conexion, que son los colores
/// que YA definiste en `lib/theme/app_colors.dart`. No invento hex sueltos:
/// si manana cambiamos el verde de la marca, el banner cambia solo.
///
/// OJO: `atrasadas` suena a "citas atrasadas" y NO tiene nada que ver con red.
/// Reusarlo es decision de diseno (es el rojo de tu paleta, ni un tono mas)
/// pero si te incomoda el nombre, decime y agrego `redOffline` a AppColors.
class ConectivityBanner extends StatelessWidget {
  const ConectivityBanner({super.key});

  static const double _alto = 30;

  @override
  Widget build(BuildContext context) {
    final hayConexion = ConnectivityScope.of(context).hayConexion;

    // `AnimatedSize` en vez de un `if` con SizedBox: cuando la variable del
    // banner pasa de 0 a 30, el layout se desliza en 250ms en vez de saltar.
    // Ahi se nota que la app esta "viva" y no que se rompió la pantalla.
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: !hayConexion
          ? Material(
              color: AppColors.atrasadas,
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
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Version compacta para pantallas con poco espacio (tipo el AppBar de Citas).
/// Mismo patron: un chip verde/rojo con el estado, sin ocupar ancho.
class ConectivityChip extends StatelessWidget {
  const ConectivityChip({super.key});

  @override
  Widget build(BuildContext context) {
    final hayConexion = ConnectivityScope.of(context).hayConexion;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: hayConexion ? AppColors.greenAccent : AppColors.atrasadas,
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

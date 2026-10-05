import 'package:flutter/material.dart';

import 'package:autofix/core/connectivity/connectivity_service.dart';
import 'package:autofix/core/connectivity/connectivity_scope.dart';
import 'package:autofix/shared/theme/app_colors.dart';

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
    // `desconectado`, NO `!hayConexion`: mientras el estado es desconocido no
    // hay evidencia de un corte, y acusarlo seria una banda roja Mentirosa en
    // cada arranque (y al abrir la app sin permiso de red, etc.).
    final desconectado = ConnectivityScope.of(context).desconectado;

    // `AnimatedSize` en vez de un `if` con SizedBox: cuando la variable del
    // banner pasa de 0 a 30, el layout se desliza en 250ms en vez de saltar.
    // Ahi se nota que la app esta "viva" y no que se rompió la pantalla.
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: desconectado
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
    // El chip SI distingue los tres estados: "comprobando..." es informacion
    // honesta mientras la plataforma no responde, y en una pantalla chica el
    // espacio es escaso.
    final estado = ConnectivityScope.of(context).estado;
    final hayConexion = estado == EstadoRed.conectado;
    final desconocido = estado == EstadoRed.desconocido;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorEstadoRed(estado),
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
            desconocido
                ? 'Comprobando...'
                : hayConexion
                ? 'En linea'
                : 'Sin conexion',
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

/// El color del chip segun el estado.
///
/// `desconocido` va en gris y no en rojo: todavia no hay un corte, y pintar de
/// alarma un estado transitorio entrena al usuario a ignorar la alarma real.
Color colorEstadoRed(EstadoRed estado) => switch (estado) {
  EstadoRed.conectado => AppColors.greenAccent,
  EstadoRed.desconocido => AppColors.placeholderGray,
  EstadoRed.desconectado => AppColors.atrasadas,
};

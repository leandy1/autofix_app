import 'package:flutter/material.dart';

import 'package:autofix/core/connectivity/connectivity_scope.dart';
import 'package:autofix/core/connectivity/connectivity_service.dart';
import 'package:autofix/core/connectivity/widgets/conectivity_banner.dart';

/// Punto de integracion de la unidad de Conectividad. NO es el root de la app:
/// envuelve al `AutoFixApp` de Leandy para no pelearnos el `main.dart`.
///
/// Leandy: en tu `lib/main.dart` son DOS lineas y ya esta.
///
///     import 'app/conectividad_app.dart';
///
///     void main() {
///       runApp(const ConectividadApp(child: AutoFixApp()));
///     }
///
/// y en tu `MaterialApp`, UNA linea mas:
///
///     MaterialApp(
///       builder: ConectividadApp.bannerBuilder,   // <-- asi
///       home: const LoginScreen(),
///     )
///
/// Por que `builder` y no un `Stack` por encima: `MaterialApp.builder` se
/// ejecuta ADENTRO del Navigator, asi el banner queda montado por encima de
/// TODA ruta (login, dashboard, citas, configuracion) y de los bottom sheets.
/// Si lo montamos con un `Stack` alrededor del MaterialApp, cada pantalla con
/// su propio Scaffold se lo taparia.
class ConectividadApp extends StatefulWidget {
  const ConectividadApp({required this.child, super.key});

  final Widget child;

  /// El callback que va en `MaterialApp.builder`. Lo pongo aca adentro para
  /// que sea un solo punto de integracion y nadie tenga que armar el Column a
  /// mano (y olvidarse del Expanded, que es el error clasico).
  static Widget bannerBuilder(BuildContext context, Widget? child) {
    return Column(
      children: [
        const ConectivityBanner(),
        Expanded(child: child ?? const SizedBox.shrink()),
      ],
    );
  }

  @override
  State<ConectividadApp> createState() => _ConectividadAppState();
}

class _ConectividadAppState extends State<ConectividadApp> {
  /// UNA sola instancia para toda la app. La suscripcion al Stream de red se
  /// crea aca una vez y no se pierde nunca al navegar, que es justamente el
  /// requisito: el banner tiene que verse en todas las pantallas.
  late final ConnectivityService _servicio = ConnectivityService();

  @override
  void dispose() {
    // Sin esto la suscucion sigue viva despues de que la app muere y cada
    // rebuild en caliente acumularia un listener nuevo -> fuga de memoria.
    _servicio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityScope(
      servicio: _servicio,
      child: widget.child,
    );
  }
}

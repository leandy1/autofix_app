import 'package:flutter/material.dart';

import '../core/connectivity/connectivity_scope.dart';
import '../core/connectivity/connectivity_service.dart';
import '../core/connectivity/widgets/conectivity_banner.dart';
import '../features/citas/presentation/citas_page.dart';

class AutoFixApp extends StatefulWidget {
  const AutoFixApp({super.key});

  @override
  State<AutoFixApp> createState() => _AutoFixAppState();
}

class _AutoFixAppState extends State<AutoFixApp> {
  /// Una sola instancia para toda la app: la suscripcion al Stream de red se
  /// crea una vez y nunca se pierde al navegar.
  late final ConnectivityService _conectividad = ConnectivityService();

  @override
  void dispose() {
    _conectividad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityScope(
      servicio: _conectividad,
      child: MaterialApp(
        title: 'AutoFix',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueGrey,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        // `builder` se ejecuta por debajo del Navigator, asi el banner queda
        // por encima de TODA ruta y permanece visible en cualquier pantalla.
        builder: (context, child) {
          return Column(
            children: [
              const ConectivityBanner(),
              Expanded(child: child ?? const SizedBox.shrink()),
            ],
          );
        },
        home: const CitasPage(),
      ),
    );
  }
}

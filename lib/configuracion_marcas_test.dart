import 'package:flutter/material.dart';

import 'screens/admin/configuracion_admin_screen_marcas.dart';

void main() {
  runApp(const ConfiguracionMarcasTestApp());
}

class ConfiguracionMarcasTestApp extends StatelessWidget {
  const ConfiguracionMarcasTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AutoFix - Configuración',
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: const ConfiguracionScreen(),
    );
  }
}

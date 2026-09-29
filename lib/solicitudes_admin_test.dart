import 'package:flutter/material.dart';

import 'screens/admin/citas_admin_solicitudes_screen.dart';

void main() {
  runApp(const SolicitudesAdminTestApp());
}

class SolicitudesAdminTestApp extends StatelessWidget {
  const SolicitudesAdminTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AutoFix - Solicitudes Admin',
      home: const CitasSolicitudesAdminScreen(),
    );
  }
}

import 'package:flutter/foundation.dart';

import 'package:autofix/core/auth/perfil_admin_cache.dart';
import 'package:autofix/core/auth/recordarme_prefs.dart';
import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/features/auth/controllers/cambio_password_controller.dart';

class PerfilAdminController extends ChangeNotifier {
  PerfilAdminController({CambioPasswordController? passwordController})
    : _passwordController = passwordController ?? CambioPasswordController();

  final CambioPasswordController _passwordController;
  bool _recordarmePorDefecto = true;

  bool get recordarmePorDefecto => _recordarmePorDefecto;

  String get _uidPerfil =>
      SesionAdmin.instance.adminUid ??
      SesionAdmin.instance.adminEmail ??
      'sin-sesion';

  Future<(String?, String?)> cargarDatos() => PerfilAdminCache.leer(_uidPerfil);

  Future<String> guardarDatos({
    required String nombre,
    required String telefono,
  }) async {
    final limpio = nombre.trim();
    if (limpio.length < 3) return 'El nombre debe tener al menos 3 caracteres.';
    final digitos = telefono.replaceAll(RegExp(r'\D'), '');
    if (digitos.isNotEmpty && (digitos.length < 10 || digitos.length > 15)) {
      return 'Escribe un teléfono válido (10 a 15 dígitos).';
    }
    await PerfilAdminCache.guardar(
      uid: _uidPerfil,
      nombre: limpio,
      telefono: telefono,
    );
    return 'Información guardada en este dispositivo';
  }

  Future<void> inicializarPreferencia() async {
    _recordarmePorDefecto = await RecordarmePrefs.habilitadoPorDefecto();
    notifyListeners();
  }

  Future<void> alternarRecordarmePorDefecto(bool valor) async {
    _recordarmePorDefecto = valor;
    notifyListeners();
    await RecordarmePrefs.setHabilitadoPorDefecto(valor);
  }

  Future<String> cambiarPassword({
    required String correo,
    required String nueva,
    required String repetir,
  }) => _passwordController.cambiar(
    correoCuenta: correo,
    nueva: nueva,
    repetir: repetir,
  );
}

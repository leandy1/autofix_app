import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:autofix/core/auth/credenciales_seguras.dart';
import 'package:autofix/features/cliente/data/cambios_password_repository.dart';

typedef AplicarPasswordEnNube = Future<void> Function(
  String correo,
  String nueva,
);

/// Cambio de contraseña reutilizable por clientes y administradores.
///
/// La fila SQLite solo contiene metadata y el secreto queda en el keystore.
/// SyncService aplica el cambio únicamente cuando Auth tiene abierta la cuenta
/// cuyo correo está asociado al registro de la cola.
class CambioPasswordController {
  CambioPasswordController({
    CambiosPasswordRepository? cola,
    AplicarPasswordEnNube? aplicarEnNube,
  }) : _cola = cola ?? CambiosPasswordRepository.instance,
       _aplicarEnNube = aplicarEnNube ?? _aplicarFirebase;

  final CambiosPasswordRepository _cola;
  final AplicarPasswordEnNube _aplicarEnNube;

  Future<String> cambiar({
    required String correoCuenta,
    required String nueva,
    required String repetir,
  }) async {
    final correo = correoCuenta.trim();
    if (correo.isEmpty) return 'No se encontró el correo de esta cuenta.';
    if (nueva.length < 6) {
      return 'La contraseña debe tener al menos 6 caracteres.';
    }
    if (nueva != repetir) return 'Las contraseñas no coinciden.';

    try {
      await _aplicarEnNube(correo, nueva);
      await _actualizarRecordamiento(correo, nueva);
      return 'Contraseña actualizada';
    } on FirebaseAuthException catch (e) {
      if (!_reintentable(e)) {
        return 'No se pudo cambiar la contraseña: ${e.message ?? e.code}';
      }
      return _encolar(correo, nueva);
    } catch (e) {
      debugPrint('CambioPasswordController: se encoló cambio ($e)');
      return _encolar(correo, nueva);
    }
  }

  Future<String> _encolar(String correo, String nueva) async {
    final guardado = await _cola.encolar(
      contrasena: nueva,
      correoCuenta: correo,
    );
    if (!guardado) return 'No se pudo guardar el cambio de contraseña.';
    await _actualizarRecordamiento(correo, nueva);
    return 'Guardada en cola, se aplicará al conectarse';
  }

  Future<void> _actualizarRecordamiento(String correo, String nueva) async {
    final credenciales = await CredencialesSeguras.leer();
    if (credenciales == null ||
        credenciales.usuario.trim().toLowerCase() != correo.toLowerCase()) {
      return;
    }
    await CredencialesSeguras.guardar(
      usuario: credenciales.usuario,
      contrasena: nueva,
    );
  }

  static Future<void> _aplicarFirebase(String correo, String nueva) async {
    final actual = FirebaseAuth.instance.currentUser;
    if (actual == null ||
        actual.isAnonymous ||
        actual.email?.trim().toLowerCase() != correo.toLowerCase()) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    await actual.updatePassword(nueva);
  }

  static bool _reintentable(FirebaseAuthException e) =>
      e.code == 'network-request-failed' ||
      e.code == 'requires-recent-login' ||
      e.code == 'user-missing-email' ||
      e.code == 'invalid-user-token' ||
      e.code == 'user-token-expired' ||
      e.code == 'no-current-user';
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Datos editables del admin almacenados localmente.
///
/// No se guardan en `tablaAdmins`: `DevModeSyncService` materializa esa tabla
/// con `ConflictAlgorithm.replace`, por lo que columnas locales adicionales se
/// perderían al sincronizar. Esta caché es independiente del perfil de taller.
class PerfilAdminCache {
  PerfilAdminCache._();

  static String _kNombre(String uid) => 'perfilAdmin.$uid.nombre';
  static String _kTelefono(String uid) => 'perfilAdmin.$uid.telefono';

  static Future<(String? nombre, String? telefono)> leer(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getString(_kNombre(uid)), prefs.getString(_kTelefono(uid)));
    } catch (e) {
      debugPrint('PerfilAdminCache: no se pudo leer ($e)');
      return (null, null);
    }
  }

  static Future<void> guardar({
    required String uid,
    required String nombre,
    required String telefono,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kNombre(uid), nombre.trim());
      await prefs.setString(_kTelefono(uid), telefono.trim());
    } catch (e) {
      debugPrint('PerfilAdminCache: no se pudo guardar ($e)');
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencia de PRODUCTO del "Recuérdame", separada de la sesion y de las
/// credenciales cifradas.
///
/// Guarda UNA sola cosa: si la casilla Recuérdame debe venir MARcada por
/// defecto en el login. La pregunta "¿hay credenciales guardadas ahora?"
/// no se responde aca sino leyendo el keystore (ver `CredencialesSeguras`),
/// que es quien de verdad sabe que quedo guardado.
///
/// Mismas tres reglas que el resto de la cache local: nunca lanza, clave con
/// prefijo (`recordarme.`) para que nadie desde otra feature la pise, y
/// default `true`: recordar la sesion es el comportamiento que el requisito
/// pide de fabrica, no una opcion que haya que ganarse.
class RecordarmePrefs {
  RecordarmePrefs._();

  static const String _kPorDefecto = 'recordarme.habilitadoPorDefecto';
  static const String _kUltimoRol = 'recordarme.ultimoRol';

  /// La preferencia "traer habilitado por defecto el Recuérdame".
  ///
  /// `true` por defecto: es el comportamiento que el requisito pide que venga
  /// activado de fabrica.
  static Future<bool> habilitadoPorDefecto() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kPorDefecto) ?? true;
    } catch (e) {
      debugPrint('RecordarmePrefs: no se pudo leer por defecto ($e)');
      return true;
    }
  }

  static Future<void> setHabilitadoPorDefecto(bool valor) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPorDefecto, valor);
    } catch (e) {
      debugPrint('RecordarmePrefs: no se pudo escribir por defecto ($e)');
    }
  }

  /// Rol que debe aparecer seleccionado en el login. Admin es el valor de
  /// migración para instalaciones anteriores que todavía no guardaban rol.
  static Future<String> ultimoRol() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final valor = prefs.getString(_kUltimoRol);
      return valor == 'cliente' ? 'cliente' : 'admin';
    } catch (e) {
      debugPrint('RecordarmePrefs: no se pudo leer el último rol ($e)');
      return 'admin';
    }
  }

  static Future<void> setUltimoRol(String rol) async {
    if (rol != 'admin' && rol != 'cliente') return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUltimoRol, rol);
    } catch (e) {
      debugPrint('RecordarmePrefs: no se pudo guardar el último rol ($e)');
    }
  }
}

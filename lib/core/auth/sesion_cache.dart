import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La sesion de admin tal como queda persistida en disco.
///
/// Es un DTO aparte de `SesionAdmin` a proposito: el singleton vive en memoria
/// y se puede construir sin leer el plugin, mientras que ESTE objeto solo
/// existe cuando la cache trae datos. Que venga de SharedPreferences o de una
/// tabla de SQLite es decision de [SesionCache], no de quien lo consume.
class SesionPersistida {
  const SesionPersistida({
    required this.tallerId,
    required this.adminUid,
    this.tallerNombre,
    this.adminEmail,
    this.guardadaEn,
  });

  /// Taller del admin. Es el filtro de TODO (citas, dashboard, sync), por eso
  /// es el unico campo obligatorio: sin el no hay sesion util.
  final String tallerId;

  final String adminUid;
  final String? tallerNombre;
  final String? adminEmail;

  /// Instante (ISO UTC) en que se guardo. No decide nada hoy, pero es lo que
  /// permitira ponerle TTL a la sesion sin inventar una columna despues.
  final DateTime? guardadaEn;
}

/// Caché de sesion en `SharedPreferences`.
///
/// ES LO QUE HACE POSIBLE EL ARRANQUE SIN INTERNET. El login real valida con
/// Firebase Auth y por eso SOLO funciona con red; la primera vez que el admin
/// entra, su sesion queda aca, y a partir de ese momento la app puede abrir el
/// Dashboard en un avion sin volver a pedir credenciales.
///
/// Tres reglas de este archivo:
///
/// 1. **NUNCA lanza.** Cada operacion esta envuelta en try/catch y devuelve un
///    resultado que el llamador puede leer (`null`, `false`). Si el plugin no
///    esta disponible (entorno de tests, plataforma no inicializada) la sesion
///    simplemente no se persiste, pero la app sigue andando: una cache que
///    truena es peor que una cache que no esta.
///
/// 2. **No conoce `SesionAdmin`.** Este archivo sabe de `SesionPersistida` y
///    de claves de prefs; el singleton sabe de memoria. Mezclarlos convertiria
///    cada prueba del singleton en una prueba que ademas depende del plugin.
///
/// 3. **Claves con prefijo `sesion.`.** SharedPreferences es un sola bolsa de
///    pares clave/valor para toda la app; el prefijo evita que un dia alguien
///    escriba `tallerId` desde otra feature y pise la sesion.
class SesionCache {
  SesionCache._();

  static const String _kTallerId = 'sesion.tallerId';
  static const String _kTallerNombre = 'sesion.tallerNombre';
  static const String _kAdminUid = 'sesion.adminUid';
  static const String _kAdminEmail = 'sesion.adminEmail';
  static const String _kGuardadaEn = 'sesion.guardadaEn';

  /// Escribe la sesion, pisando la anterior.
  static Future<void> guardar(SesionPersistida sesion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTallerId, sesion.tallerId);
      await prefs.setString(_kAdminUid, sesion.adminUid);
      // `setString(..., null)` no existe: un nombre o correo ausente se limpia
      // con `remove`, o la sesion siguiente heredaria el valor de la anterior.
      _escribirOQuitar(prefs, _kTallerNombre, sesion.tallerNombre);
      _escribirOQuitar(prefs, _kAdminEmail, sesion.adminEmail);
      await prefs.setString(_kGuardadaEn, DateTime.now().toUtc().toIso8601String());
    } catch (e) {
      // Sin cache la app arranca en el login la proxima vez. No mas que eso.
      debugPrint('SesionCache: no se pudo guardar la sesion ($e)');
    }
  }

  /// La sesion guardada, o `null` si no hay (o si no se pudo leer).
  static Future<SesionPersistida?> leer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tallerId = prefs.getString(_kTallerId);
      final adminUid = prefs.getString(_kAdminUid);

      // La sesion ES el taller: si esa clave falta o vino vacia de una version
      // vieja, no hay nada con lo que filtrar las citas, y restaurarla dejaria
      // el Dashboard pintando TODOS los talleres a la vez.
      if (tallerId == null || tallerId.isEmpty || adminUid == null) {
        return null;
      }

      final guardadaEn = prefs.getString(_kGuardadaEn);
      return SesionPersistida(
        tallerId: tallerId,
        adminUid: adminUid,
        tallerNombre: prefs.getString(_kTallerNombre),
        adminEmail: prefs.getString(_kAdminEmail),
        guardadaEn: guardadaEn == null ? null : DateTime.tryParse(guardadaEn),
      );
    } catch (e) {
      debugPrint('SesionCache: no se pudo leer la sesion ($e)');
      return null;
    }
  }

  /// Borra la sesion. Idempotente: borrar dos veces no es un error.
  static Future<void> borrar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kTallerId);
      await prefs.remove(_kTallerNombre);
      await prefs.remove(_kAdminUid);
      await prefs.remove(_kAdminEmail);
      await prefs.remove(_kGuardadaEn);
    } catch (e) {
      debugPrint('SesionCache: no se pudo borrar la sesion ($e)');
    }
  }

  static Future<void> _escribirOQuitar(
    SharedPreferences prefs,
    String clave,
    String? valor,
  ) async {
    if (valor == null) {
      await prefs.remove(clave);
    } else {
      await prefs.setString(clave, valor);
    }
  }
}

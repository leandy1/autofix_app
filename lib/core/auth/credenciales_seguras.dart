import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Usuario y contraseña recordados por el login, ya descifrados.
class CredencialesRecordadas {
  const CredencialesRecordadas({
    required this.usuario,
    required this.contrasena,
  });

  /// Tal cual lo escribio el usuario (correo o nombre de usuario).
  final String usuario;
  final String contrasena;
}

/// Backend de pares clave/valor cifrados.
///
/// Existe como interfaz propia y no como uso directo de `FlutterSecureStorage`
/// por una sola razon: las pruebas. Sin esta capa, verificar que "recuérdame"
/// guarda y borra credenciales exigiria un dispositivo con DPAPI/Keychain
/// andando, y un test que no puede correr no prueba nada.
abstract class AlmacenSeguro {
  Future<void> escribir(String clave, String valor);
  Future<String?> leer(String clave);
  Future<void> borrar(String clave);
}

/// El almacen real: `flutter_secure_storage` (DPAPI en Windows, Keychain en
/// iOS/macOS, Keystore cifrado en Android).
class _AlmacenDelPlugin implements AlmacenSeguro {
  const _AlmacenDelPlugin();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<void> escribir(String clave, String valor) =>
      _storage.write(key: clave, value: valor);

  @override
  Future<String?> leer(String clave) => _storage.read(key: clave);

  @override
  Future<void> borrar(String clave) => _storage.delete(key: clave);
}

/// Un almacen que vive solo en memoria: lo que usan las pruebas.
///
/// Va publico a proposito (y no anidado en el test) porque tambien lo usa
/// `CredencialesSeguras.usarAlmacenParaPruebas` para volver al plugin real
/// pasandole `null`.
class AlmacenSeguroEnMemoria implements AlmacenSeguro {
  final Map<String, String> _datos = <String, String>{};

  @override
  Future<void> escribir(String clave, String valor) async {
    _datos[clave] = valor;
  }

  @override
  Future<String?> leer(String clave) async => _datos[clave];

  @override
  Future<void> borrar(String clave) async {
    _datos.remove(clave);
  }

  /// Solo para las pruebas: ver que adentro no quedo nada.
  bool contieneClave(String clave) => _datos.containsKey(clave);
}

/// Las credenciales que el usuario decidio recordar, cifradas en el disco del
/// dispositivo.
///
/// ---------------------------------------------------------------
/// POR QUE CIFRADA Y POR QUE ACÁ
/// ---------------------------------------------------------------
/// Una contraseña en claro dentro de `SharedPreferences` es texto plano en un
/// archivo legible por cualquiera con acceso al equipo. En cambio,
/// `flutter_secure_storage` guarda el secreto en el keystore del sistema
/// operativo: en Windows usa DPAPI atado al usuario de Windows, en movil el
/// Keystore/Keychain del hardware. El usuario puede pedir "recuérdame" sin
/// regalar la contraseña a cambio.
///
/// El USUARIO (correo o nombre) tambien se cifra, aunque no es un secreto: si
/// estuviera en claro, cualquiera que abra el archivo de prefs sabria quien usa
/// la app. Para mostrar la mascara `san***` se descifra al vuelo, que es
/// exactamente lo que hace [usuarioEnmascarado].
///
/// Tres reglas, las mismas que `SesionCache`:
///
/// 1. **NUNCA lanza.** Si el keystore no esta disponible (tests, plataforma sin
///    inicializar, disco lleno), el recordamiento simplemente no persiste y la
///    app sigue funcionando.
/// 2. **No conoce la UI.** Este archivo guarda y devuelve texto; decidir que se
///    muestra enmascarado o que la contraseña queda deshabilitada es problema
///    del login.
/// 3. **Solo dos claves fijas.** Ver [_kUsuario] / [_kContrasena].
class CredencialesSeguras {
  CredencialesSeguras._();

  static const String _kUsuario = 'recordarme.usuario';
  static const String _kContrasena = 'recordarme.contrasena';

  static AlmacenSeguro _almacen = const _AlmacenDelPlugin();

  /// Cambia el backend. Solo para pruebas: con `null` vuelve al plugin real.
  @visibleForTesting
  static void usarAlmacenParaPruebas(AlmacenSeguro? almacen) {
    _almacen = almacen ?? const _AlmacenDelPlugin();
  }

  /// Guarda el par usuario/contraseña, pisando el anterior.
  static Future<void> guardar({
    required String usuario,
    required String contrasena,
  }) async {
    await guardarClave(_kUsuario, usuario);
    await guardarClave(_kContrasena, contrasena);
  }

  /// Las credenciales guardadas, o `null` si no hay (o no se pudieron leer).
  static Future<CredencialesRecordadas?> leer() async {
    try {
      final usuario = await leerClave(_kUsuario);
      final contrasena = await leerClave(_kContrasena);
      if (usuario == null ||
          usuario.isEmpty ||
          contrasena == null ||
          contrasena.isEmpty) {
        return null;
      }
      return CredencialesRecordadas(usuario: usuario, contrasena: contrasena);
    } catch (e) {
      debugPrint('CredencialesSeguras: no se pudieron leer ($e)');
      return null;
    }
  }

  /// Borra lo recordado. Idempotente: borrar dos veces no es un error.
  static Future<void> borrar() async {
    await borrarClave(_kUsuario);
    await borrarClave(_kContrasena);
  }

  // ------------------------------------------------------------------
  // API DE CLAVES ARBITRARIAS
  //
  // El "recuerdame" usa DOS claves fijas, pero hay otro secreto que guardar
  // con la misma proteccion: la contraseña pendiente de la cola de cambios
  // (`CambiosPasswordRepository`), que necesita una clave por fila. Sin esta
  // API generica ese repositorio tendria que importar `FlutterSecureStorage`
  // directamente y repetir el try/catch que vive aca.
  // ------------------------------------------------------------------

  /// Escribe un secreto bajo [clave]. Nunca lanza.
  static Future<void> guardarClave(String clave, String valor) async {
    try {
      await _almacen.escribir(clave, valor);
    } catch (e) {
      debugPrint('CredencialesSeguras: no se pudo guardar [$clave] ($e)');
    }
  }

  /// Lee un secreto. `null` si no existe o si no se pudo leer.
  static Future<String?> leerClave(String clave) async {
    try {
      return await _almacen.leer(clave);
    } catch (e) {
      debugPrint('CredencialesSeguras: no se pudo leer [$clave] ($e)');
      return null;
    }
  }

  /// `true` si la clave existe y trae valor.
  ///
  /// Existe porque `encolar` necesita SABER que el secreto quedo guardado
  /// antes de crear la fila que lo referencia: un `leerClave` que devuelve
  /// `null` no distingue "no existia" de "el keystore esta roto", y las dos
  /// cosas se resuelven distinto.
  static Future<bool> existeClave(String clave) async {
    final valor = await leerClave(clave);
    return valor != null && valor.isNotEmpty;
  }

  /// Borra un secreto. Idempotente.
  static Future<void> borrarClave(String clave) async {
    try {
      await _almacen.borrar(clave);
    } catch (e) {
      debugPrint('CredencialesSeguras: no se pudo borrar [$clave] ($e)');
    }
  }

  /// La mascara que se muestra en el campo de usuario (`san***`), o `null` si
  /// no hay nada recordado.
  static Future<String?> usuarioEnmascarado() async {
    final credenciales = await leer();
    if (credenciales == null) return null;
    return enmascarar(credenciales.usuario);
  }

  /// Los tres primeros caracteres del usuario seguidos de asteriscos.
  ///
  /// Top-level (metodo estatico puro) para que se pueda probar sin tocar el
  /// almacen: una mascara mal hecha es un detalle que se verifica en un
  /// segundo y que nadie deberia necesitar un keystore para comprobar.
  static String enmascarar(String usuario) {
    if (usuario.isEmpty) return usuario;
    // Cortar a los 3 primeros caracteres y no, digamos, a la mitad del correo:
    // tres bastan para que quien lo vea reconozca su cuenta sin exponer el
    // resto de la direccion.
    final visibles = usuario.length <= 3 ? usuario : usuario.substring(0, 3);
    return '$visibles***';
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:autofix/core/auth/credenciales_seguras.dart';
import 'package:autofix/core/auth/recordarme_prefs.dart';
import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/features/cliente/data/cambios_password_repository.dart';
import 'package:autofix/features/cliente/data/cliente_repository.dart';

/// Aplica el cambio de contraseña en la nube. Se puede inyectar una version
/// falsa para probar el flujo sin Firebase ni red.
typedef CambioPasswordEnNube = Future<void> Function(String contrasena);

/// Marca de que no hay (o no sirve) la sesion de Firebase Auth para cambiar la
/// contraseña.
///
/// Se define como excepcion propia y no se infiere del codigo del SDK porque
/// los codigos de `FirebaseAuthException` varian entre versiones, y confiar en
/// uno concreto ("user-missing-email") haria que un upgrade del paquete
/// cambiara el camino que toma la cola.
class _SinSesionEnNube implements Exception {
  const _SinSesionEnNube();
}

/// Las tres acciones de la pantalla "Editar Perfil".
///
/// ---------------------------------------------------------------
/// POR QUE UN CONTROLADOR Y NO LOS BOTONES SOLOS
/// ---------------------------------------------------------------
/// Las tres secciones comparten el mismo contrato con la pantalla: validan,
/// hacen su trabajo y DEVUELVEN el texto que hay que mostrar en el SnackBar.
/// Eso deja la UI reducida a "pintar lo que devuelva" y permite probar los
/// tres caminos (guardado, cambio online, cambio en cola, cooldown) sin montar
/// un solo widget.
///
/// El cambio de contraseña es el que mas se complica, y la razon es de
/// seguridad: **el secreto no viaja a la nube**. Se intenta aplicar con
/// `FirebaseAuth.updatePassword` y, si hoy no se puede (sin red, o sin una
/// sesion de Auth util), se encola localmente para que `SyncService` lo
/// reintente cuando vuelva la conexion. Ver [CambiosPasswordRepository].
class PerfilClienteController extends ChangeNotifier {
  PerfilClienteController({
    CambiosPasswordRepository? cola,
    ClienteRepository? repositorio,
    CambioPasswordEnNube? aplicarEnNube,
    DateTime Function()? reloj,
  }) : _cola = cola ?? CambiosPasswordRepository.instance,
       _repositorio = repositorio ?? ClienteRepository(),
       _aplicarEnNube = aplicarEnNube ?? _aplicarEnFirebaseAuth,
       _reloj = reloj ?? DateTime.now;

  final CambiosPasswordRepository _cola;
  final ClienteRepository _repositorio;
  final CambioPasswordEnNube _aplicarEnNube;
  final DateTime Function() _reloj;

  /// Ultimo instante en que se aviso del cambio de preferencia. Es la mitad
  /// del cooldown: sin esto, un usuario que mueve el switch cuatro veces
  /// seguidas se llena la pantalla de "El cambio surtió efecto".
  DateTime? _ultimoAvisoRecordarme;

  static const Duration _cooldownAviso = Duration(milliseconds: 1500);

  /// Guarda nombre/correo/teléfono en el perfil local. Devuelve el mensaje a
  /// mostrar.
  ///
  /// ---------------------------------------------------------------
  /// POR QUE ESCRIBE EN DOS LADOS
  /// ---------------------------------------------------------------
  /// Hasta la Fase 3 esto solo tocaba SharedPreferences, y el resultado era un
  /// "Información guardada" que era cierto en el instante en que se escribio y
  /// falso un segundo despues: una preferencia no sobrevive a la necesidad de
  /// sincronizar. [guardarDatos] escribe PRIMERO en SQLite via
  /// [ClienteRepository.guardarLocal] con `sync_status = 'pending'`, que es lo
  /// que `SyncService` sube cuando vuelva la red, y recien despues actualiza la
  /// sesión en memoria y su cache de preferencias.
  ///
  /// El orden no es decorativo: si SQLite falla, no se actualiza la sesión, y
  /// la pantalla puede decir "no se pudo guardar" sin que la app quede
  /// enseñando un nombre que nunca llego a estar en cola. La preferencia se
  /// escribe igual aunque aun no haya subido, porque es lo que el saludo del
  /// AppBar y el prellenado del formulario leen y necesitan ver el cambio ya.
  Future<String> guardarDatos({
    required String nombre,
    required String correo,
    required String telefono,
  }) async {
    final error = _validarDatos(
      nombre: nombre,
      correo: correo,
      telefono: telefono,
    );
    if (error != null) return error;

    final guardado = await _repositorio.guardarLocal(
      uid: _uidActual(),
      // El correo con el que la sesion guardo su fila la vez anterior. Es con
      // el que se BUSCA la fila; el parametro `correo` es el que se ESCRIBE.
      // Sin este, editar el correo dejaria la fila vieja atras y crearia otra.
      correoIdentidad: SesionCliente.instance.correo,
      nombre: nombre,
      correo: correo,
      telefono: telefono,
    );
    if (!guardado) return 'No se pudo guardar la información.';

    await SesionCliente.instance.guardarPerfil(
      nombre: nombre,
      correo: correo,
      telefono: telefono,
    );
    return 'Información guardada';
  }

  /// Cambia la contraseña: la aplica en la nube si hoy se puede, y si no la
  /// deja en cola local. Devuelve el mensaje a mostrar.
  Future<String> cambiarPassword({
    required String nueva,
    required String repetir,
  }) async {
    if (nueva.length < 6) {
      return 'La contraseña debe tener al menos 6 caracteres.';
    }
    if (nueva != repetir) return 'Las contraseñas no coinciden.';

    try {
      await _aplicarEnNube(nueva);
      await _refrescarRecordamiento(nueva);
      return 'Contraseña actualizada';
    } on _SinSesionEnNube {
      return _encolar(nueva);
    } on FirebaseAuthException catch (e) {
      if (_esFallaDeRed(e) || _esSesionNoUtil(e)) return _encolar(nueva);
      return 'No se pudo cambiar la contraseña: ${e.message ?? e.code}';
    } catch (e) {
      // Firebase sin inicializar (tests, arranque raro) o cualquier otra
      // falla: si no se pudo aplicar AHORA, la unica salida honesta es
      // encolarlo y reintentar, no perder el cambio.
      if (_esFallaDeRed(e)) return _encolar(nueva);
      debugPrint('PerfilClienteController: cambio de contraseña ($e)');
      return _encolar(nueva);
    }
  }

  /// Guarda la preferencia "traer habilitado por defecto el Recuérdame".
  ///
  /// Devuelve el mensaje, o `null` si esta dentro del cooldown de 1.5 s. La
  /// PREFERENCIA se guarda igual: el cooldown calla el aviso, no corta el
  /// guardado, porque silenciar un cambio real solo genera la sensacion de que
  /// el switch no sirve.
  Future<String?> alternarRecordarmePorDefecto(bool valor) async {
    await RecordarmePrefs.setHabilitadoPorDefecto(valor);

    final ahora = _reloj();
    final anterior = _ultimoAvisoRecordarme;
    if (anterior != null && ahora.difference(anterior) < _cooldownAviso) {
      return null;
    }
    _ultimoAvisoRecordarme = ahora;
    return 'El cambio surtió efecto';
  }

  /// Vuelve a la preferencia inicial de la pantalla (para un test o un
  /// "cancelar").
  void reiniciarCooldown() {
    _ultimoAvisoRecordarme = null;
  }

  Future<String> _encolar(String contrasena) async {
    final correoCliente = SesionCliente.instance.correo;
    if (correoCliente == null || correoCliente.trim().isEmpty) {
      return 'Guarda tu correo en el perfil antes de cambiar la contraseña.';
    }
    final guardado = await _cola.encolar(
      contrasena: contrasena,
      correoCuenta: correoCliente,
    );
    if (!guardado) {
      return 'No se pudo guardar el cambio de contraseña.';
    }
    // El cambio queda localmente aplicado (la app recordara la contraseña
    // nueva desde ya) y pendiente en la cola para la nube.
    await _refrescarRecordamiento(contrasena);
    return 'Guardada en cola, se aplicará al conectarse';
  }

  /// Actualiza la contraseña que el login tiene recordada, si hay alguna.
  ///
  /// Sin esto, el cliente que cambia su contraseña sin internet quedaria con
  /// la vieja guardada y no podria entrar con la nueva hasta que la cola se
  /// drenara.
  Future<void> _refrescarRecordamiento(String contrasena) async {
    final guardadas = await CredencialesSeguras.leer();
    if (guardadas == null) return;
    await CredencialesSeguras.guardar(
      usuario: guardadas.usuario,
      contrasena: contrasena,
    );
  }

  String? _validarDatos({
    required String nombre,
    required String correo,
    required String telefono,
  }) {
    if (nombre.trim().isEmpty) return 'Escribe tu nombre completo.';
    if (nombre.trim().length < 3) {
      return 'El nombre debe tener al menos 3 caracteres.';
    }

    final correoLimpio = correo.trim();
    if (correoLimpio.isEmpty) return 'Escribe tu correo electrónico.';
    if (!RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(correoLimpio)) {
      return 'Escribe un correo electrónico válido.';
    }

    final telefonoLimpio = telefono.trim();
    if (telefonoLimpio.isNotEmpty) {
      final digitos = telefonoLimpio.replaceAll(RegExp(r'\D'), '');
      if (digitos.length < 10 || digitos.length > 15) {
        return 'Escribe un teléfono válido (10 a 15 dígitos).';
      }
    }
    return null;
  }

  /// El uid de Firebase Auth si hay sesion, y `null` si no (o si Firebase
  /// ni siquiera esta inicializado, que es el caso del login sin red).
  ///
  /// `null` no es un error: [ClienteRepository.guardarLocal] usa en ese caso
  /// el correo normalizado como identidad local, que es justamente lo que hace
  /// posible editar el perfil sin internet.
  static String? _uidActual() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// El cambio real contra Firebase Auth.
  ///
  /// Lanza si no se puede hacer hoy; quien decide que hacer con el fallo es
  /// [cambiarPassword], porque "no hay red" y "no hay cuenta" se resuelven
  /// (y se comunican) distinto.
  static Future<void> _aplicarEnFirebaseAuth(String contrasena) async {
    final usuario = FirebaseAuth.instance.currentUser;
    if (usuario == null) throw const _SinSesionEnNube();
    if (usuario.isAnonymous) throw const _SinSesionEnNube();
    final correoCliente = SesionCliente.instance.correo?.trim().toLowerCase();
    if (correoCliente == null ||
        usuario.email?.trim().toLowerCase() != correoCliente) {
      // La app permite acceso local de cliente y una sesión Firebase de admin
      // puede coexistir. Nunca aplicar al usuario Firebase equivocado.
      throw const _SinSesionEnNube();
    }
    await usuario.updatePassword(contrasena);
  }

  /// `true` cuando el fallo vino de la falta de red.
  ///
  /// Mismo filtro por codigo que `LoginController._esFallaDeRed`: Auth y
  /// Firestore llaman distinto al mismo problema y un `contains` sobre el
  /// texto es la red de seguridad para el dia que aparezca otro codigo.
  static bool _esFallaDeRed(Object e) {
    if (e is FirebaseAuthException) return e.code == 'network-request-failed';
    if (e is FirebaseException) {
      return e.code == 'unavailable' || e.code.contains('network');
    }
    final texto = e.toString().toLowerCase();
    return texto.contains('network') ||
        texto.contains('socket') ||
        texto.contains('unavailable');
  }

  /// `true` cuando la sesion de Auth no sirve para [updatePassword]: usuario
  /// anonimo, sin email, o credenciales viejas (`requires-recent-login`).
  ///
  /// En todos los casos la respuesta es la misma: encolar y esperar a que
  /// haya una sesion aplicable. No se puede "re-autenticar" desde una
  /// pantalla de perfil sin pedirle la contraseña actual al usuario, que es
  /// exactamente lo que todavia no sabemos.
  static bool _esSesionNoUtil(Object e) {
    if (e is! FirebaseAuthException) return false;
    return e.code == 'user-missing-email' ||
        e.code == 'requires-recent-login' ||
        e.code == 'invalid-user-token' ||
        e.code == 'user-token-expired' ||
        e.code == 'no-current-user';
  }
}

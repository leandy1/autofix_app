import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:autofix/core/auth/credenciales_seguras.dart';
import 'package:autofix/core/auth/recordarme_prefs.dart';
import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/features/cliente/data/cliente_repository.dart';
import 'package:autofix/features/sync/sync_service.dart';
import 'package:autofix/features/talleres/data/taller_repository.dart';

enum LoginRole { admin, cliente }

class LoginController extends ChangeNotifier {
  static const String usuarioDev = 'dev';
  static const String contrasenaDev = '1234';

  LoginRole _selectedRole = LoginRole.admin;
  User? _currentUser;
  bool _cargando = false;
  String? _error;
  final FirebaseAuth? _authInyectado;
  final FirebaseFirestore? _firestoreInyectado;
  final ClienteRepository? _clientesInyectado;
  StreamSubscription<User?>? _authSubscription;

  FirebaseAuth get _auth => _authInyectado ?? FirebaseAuth.instance;
  FirebaseFirestore get _db =>
      _firestoreInyectado ?? FirebaseFirestore.instance;
  ClienteRepository get _clientes =>
      _clientesInyectado ?? ClienteRepository(firestore: _db);

  LoginController({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    ClienteRepository? clientes,
  }) : _authInyectado = auth,
       _firestoreInyectado = firestore,
       _clientesInyectado = clientes {
    try {
      _currentUser = _auth.currentUser;
      _authSubscription = _auth.authStateChanges().listen((user) {
        _currentUser = user;
        notifyListeners();
      });
    } catch (_) {
      // FirebaseAuth not active or initialized (e.g. test environment)
    }
  }

  LoginRole get selectedRole => _selectedRole;
  bool get cargando => _cargando;
  String? get error => _error;

  /// UID del usuario autenticado (anonimo o real). `null` si no hay sesion.
  String? get currentUid => _currentUser?.uid;

  void selectRole(LoginRole role) {
    if (_selectedRole == role) return;
    _selectedRole = role;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  /// Credenciales locales solo para UI de desarrollo. La autenticacion real
  /// usa email/password contra Firebase Auth.
  bool esAccesoDev(String usuario, String contrasena) =>
      usuario.trim() == usuarioDev && contrasena == contrasenaDev;

  bool esIntentoDevInvalido(String usuario, String contrasena) =>
      usuario.trim() == usuarioDev && contrasena != contrasenaDev;

  LoginRole submit() => _selectedRole;

  // ------------------------------------------------------------------
  // "RECUÉRDAME" (credenciales cifradas)
  //
  // El controlador decide QUE se guarda y CUANDO; el login solo decide si el
  // usuario lo marco. Asi el guardado no puede colgarse de un boton: se
  // persiste una unica vez, y siempre despues de validar con exito.
  // ------------------------------------------------------------------

  /// Guarda o borra las credenciales segun la decision del switch.
  ///
  /// Para guardar (`activo: true`) se llama SOLO despues de validar con exito:
  /// guardar antes dejaria en el keystore la contraseña de un intento fallido.
  /// El borrado (`activo: false`) sí puede ocurrir inmediatamente al desmarcar
  /// el switch, porque es una revocacion de la preferencia del usuario.
  ///
  /// Que "haya recordamiento" se deduce de que el keystore trae algo; no hace
  /// falta una bandera aparte que pueda desincronizarse de lo guardado.
  Future<void> persistirRecordamiento({
    required String usuario,
    required String contrasena,
    required bool activo,
  }) async {
    if (activo && usuario.trim().toLowerCase() != usuarioDev) {
      await CredencialesSeguras.guardar(
        usuario: usuario.trim(),
        contrasena: contrasena,
      );
    } else {
      await CredencialesSeguras.borrar();
    }
  }

  /// La mascara del usuario recordado (`san***`), o `null` si no hay nada.
  ///
  /// El login no puede leer el keystore directamente: esto mantiene la UI
  /// hablando con el controlador y no con el almacenamiento.
  Future<String?> usuarioRecordado() =>
      CredencialesSeguras.usuarioEnmascarado();

  /// Las credenciales reales guardadas, para entrar sin que el usuario vuelva
  /// a teclearlas. `null` si no hay.
  Future<CredencialesRecordadas?> credencialesRecordadas() =>
      CredencialesSeguras.leer();

  /// Con que estado ARRANCA el switch de Recuérdame (preferencia de perfil).
  Future<bool> recordarmePorDefecto() => RecordarmePrefs.habilitadoPorDefecto();

  Future<LoginRole> rolRecordado() async =>
      await RecordarmePrefs.ultimoRol() == 'cliente'
      ? LoginRole.cliente
      : LoginRole.admin;

  Future<void> persistirRol(LoginRole role) =>
      RecordarmePrefs.setUltimoRol(role.name);

  Future<bool> loginAdmin(
    String email,
    String password, {
    bool persistirSesion = false,
  }) async {
    _cargando = true;
    _error = null;
    notifyListeners();

    var authValidada = false;
    try {
      final creds = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      authValidada = true;
      final uid = creds.user?.uid;
      if (uid != null) {
        final doc = await _db.collection('admins').doc(uid).get();
        if (doc.exists) {
          if (doc.data()?['eliminado'] == true) {
            _error = 'Esta cuenta de administrador está deshabilitada.';
            await _cerrarAuthActual();
            return _terminarLogin(false);
          }
          final tallerId = doc.data()?['tallerId'] as String?;
          if (tallerId == null) {
            _error = 'La cuenta no tiene un taller asignado.';
            await _cerrarAuthActual();
          } else {
            final taller = await TallerRepository.instance.obtenerPorId(
              tallerId,
            );
            final tallerNombre =
                taller?.nombre ??
                doc.data()?['tallerNombre'] as String? ??
                'Taller';
            // `await` y no fire-and-forget: la sesión en memoria y su decisión
            // de persistencia deben terminar antes de navegar al Dashboard.
            await SesionCliente.instance.cerrar();
            await SesionAdmin.instance.iniciar(
              tallerId: tallerId,
              adminUid: uid,
              tallerNombre: tallerNombre,
              adminEmail: email.trim(),
              persistir: persistirSesion,
            );
            // Reiniciar SyncService con el nuevo UID de admin.
            await SyncService.instance.stop();
            try {
              await SyncService.instance.start();
            } catch (e) {
              debugPrint('LoginController: SyncService no arrancó ($e)');
            }
            return _terminarLogin(true);
          }
        } else {
          _error = 'El usuario no tiene permisos de administrador.';
          await _cerrarAuthActual();
        }
      }
    } on FirebaseAuthException catch (e) {
      if (authValidada) await _cerrarAuthActual();
      if (e.code == 'network-request-failed') {
        _error = _mensajeSinRed();
      } else if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        _error = 'Correo o contraseña incorrectos.';
      } else {
        _error = 'Error de autenticación: ${e.message}';
      }
    } catch (e) {
      if (authValidada) await _cerrarAuthActual();
      // Firestore (la consulta del doc `admins`) y el resto de los SDKs de
      // Firebase tiran `FirebaseException` con codigo 'unavailable' cuando no
      // hay red. Sin este filtro el usuario ve "Error desconocido:
      // [firebase_core/network-error]" en vez de una frase que pueda actuar.
      _error = _esFallaDeRed(e) ? _mensajeSinRed() : 'Error desconocido: $e';
    }

    return _terminarLogin(false);
  }

  /// Autentica al cliente en Firebase y valida que su UID pertenezca a la
  /// colección `clientes`, sin permitir entrar con una cuenta de admin.
  Future<ClientePerfil?> loginCliente(
    String email,
    String password, {
    bool persistirSesion = false,
  }) async {
    _cargando = true;
    _error = null;
    notifyListeners();
    var authValidada = false;
    try {
      final credenciales = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      authValidada = true;
      final uid = credenciales.user?.uid;
      if (uid == null) {
        _error = 'No se pudo identificar la cuenta de cliente.';
        await _cerrarAuthActual();
        return _terminarCliente(null);
      }

      final perfil = await _clientes.obtener(uid);
      if (perfil == null) {
        // Evita que una cuenta admin o un usuario sin perfil cliente acceda al
        // dashboard de cliente por cambiar el selector de rol.
        final admin = await _db.collection('admins').doc(uid).get();
        _error = admin.exists
            ? 'Esta cuenta pertenece a un administrador. Selecciona Admin.'
            : 'El usuario no tiene permisos de cliente.';
        await _cerrarAuthActual();
        return _terminarCliente(null);
      }

      await SesionAdmin.instance.cerrar();
      await SesionCliente.instance.iniciar(
        nombre: perfil.nombre,
        correo: perfil.correo,
        telefono: perfil.telefono,
        persistir: persistirSesion,
      );
      return _terminarCliente(perfil);
    } on FirebaseAuthException catch (e) {
      if (authValidada) await _cerrarAuthActual();
      _error = _mensajeAuth(e);
    } catch (e) {
      if (authValidada) await _cerrarAuthActual();
      _error = _esFallaDeRed(e)
          ? _mensajeSinRed()
          : 'No se pudo iniciar sesión como cliente: $e';
    }
    return _terminarCliente(null);
  }

  /// Repara el caso de una creación anterior que llegó a Auth pero falló antes
  /// de escribir `clientes/{uid}`. Solo se repara si la cuenta prueba posesión
  /// del correo/clave y NO existe un documento admin ni un perfil previo.
  Future<ClientePerfil?> _recuperarRegistroClienteExistente({
    required String nombre,
    required String correo,
    required String telefono,
    required String contrasena,
  }) async {
    try {
      final credenciales = await _auth.signInWithEmailAndPassword(
        email: correo.trim(),
        password: contrasena,
      );
      final uid = credenciales.user?.uid;
      if (uid == null) return null;
      final admin = await _db.collection('admins').doc(uid).get();
      if (admin.exists) {
        _error = 'Ese correo pertenece a una cuenta de administrador.';
        await _cerrarAuthActual();
        return null;
      }
      if (await _clientes.existeDocumento(uid)) {
        _error = 'Ya existe una cuenta de cliente con ese correo.';
        await _cerrarAuthActual();
        return null;
      }
      await _clientes.crear(
        uid: uid,
        nombre: nombre,
        correo: correo,
        telefono: telefono,
      );
      return ClientePerfil(
        uid: uid,
        nombre: nombre.trim(),
        correo: correo.trim().toLowerCase(),
        telefono: telefono.trim(),
      );
    } on FirebaseAuthException catch (e) {
      _error = _mensajeAuth(e);
      await _cerrarAuthActual();
      return null;
    } catch (e) {
      _error = _esFallaDeRed(e)
          ? 'No se pudo completar el registro por falta de conexión.'
          : 'No se pudo guardar el perfil del cliente: $e';
      await _cerrarAuthActual();
      return null;
    }
  }

  /// Crea la cuenta Auth y su documento Firestore `clientes/{uid}`.
  ///
  /// Crear un usuario en Firebase Auth inicia sesión automáticamente con él,
  /// que es lo esperado para el registro del cliente. No usa el patrón de app
  /// temporal de cuentas admin: ese patrón conserva la sesión del operador
  /// DEV, mientras que aquí la cuenta nueva debe convertirse en la sesión
  /// cliente activa.
  Future<ClientePerfil?> registrarCliente({
    required String nombre,
    required String correo,
    required String telefono,
    required String contrasena,
  }) async {
    _cargando = true;
    _error = null;
    notifyListeners();
    var authCreada = false;
    try {
      final creds = await _auth.createUserWithEmailAndPassword(
        email: correo.trim(),
        password: contrasena,
      );
      authCreada = true;
      final uid = creds.user?.uid;
      if (uid == null) {
        _error = 'Firebase no devolvió el identificador del cliente.';
        await _cerrarAuthActual();
        return _terminarCliente(null);
      }

      await _clientes.crear(
        uid: uid,
        nombre: nombre,
        correo: correo,
        telefono: telefono,
      );
      return _terminarCliente(
        ClientePerfil(
          uid: uid,
          nombre: nombre.trim(),
          correo: correo.trim().toLowerCase(),
          telefono: telefono.trim(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        final recuperado = await _recuperarRegistroClienteExistente(
          nombre: nombre,
          correo: correo,
          telefono: telefono,
          contrasena: contrasena,
        );
        if (recuperado != null) return _terminarCliente(recuperado);
        if (_error != null) return _terminarCliente(null);
      }
      _error = _mensajeAuth(e);
      if (authCreada) await _cerrarAuthActual();
    } catch (e) {
      _error = _esFallaDeRed(e)
          ? 'No se pudo completar el registro por falta de conexión. '
                'Comprueba tu red e inténtalo de nuevo.'
          : 'No se pudo guardar el perfil del cliente: $e';
      if (authCreada) await _cerrarAuthActual();
    }
    return _terminarCliente(null);
  }

  Future<void> _cerrarAuthActual() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // El usuario ya quedó rechazado en memoria local; no ocultar el mensaje
      // de permiso si Firebase no permite completar signOut.
    }
  }

  bool _terminarLogin(bool resultado) {
    _cargando = false;
    notifyListeners();
    return resultado;
  }

  ClientePerfil? _terminarCliente(ClientePerfil? perfil) {
    _cargando = false;
    notifyListeners();
    return perfil;
  }

  String _mensajeAuth(FirebaseAuthException error) {
    if (error.code == 'network-request-failed') return _mensajeSinRed();
    if (error.code == 'user-not-found' ||
        error.code == 'wrong-password' ||
        error.code == 'invalid-credential') {
      return 'Correo o contraseña incorrectos.';
    }
    if (error.code == 'email-already-in-use') {
      return 'Ya existe una cuenta con ese correo.';
    }
    if (error.code == 'weak-password') {
      return 'La contraseña debe tener al menos 6 caracteres.';
    }
    return 'Error de autenticación: ${error.message ?? error.code}';
  }

  /// `true` cuando el fallo vino de la falta de red y no de las credenciales.
  ///
  /// Se revisa por codigo y, en ultima instancia, por texto: los tres SDKs
  /// (Auth, Firestore) usan codigos distintos ('network-request-failed',
  /// 'unavailable') para el mismo problema, y un `contains` sobre el mensaje
  /// es la red de seguridad para el dia que aparezca uno nuevo.
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

  /// Lo que se le dice al usuario cuando no hay red para validar la cuenta.
  ///
  /// La segunda frase no es cortesia: es la instrucción que impide que alguien
  /// con la sesion ya guardada crea que su cuenta desaparecio porque la app no
  /// lo dejo entrar con internet.
  static String _mensajeSinRed() =>
      'Sin conexión a internet. Revisa tu red e intenta de nuevo; '
      'si ya iniciaste sesión antes, tu sesión guardada te dejará entrar.';
}

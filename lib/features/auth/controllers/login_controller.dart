import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:autofix/core/auth/sesion_admin.dart';
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

  LoginController() {
    try {
      _currentUser = FirebaseAuth.instance.currentUser;
      FirebaseAuth.instance.authStateChanges().listen((user) {
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

  /// Credenciales locales solo para UI de desarrollo. La autenticacion real
  /// usa email/password contra Firebase Auth.
  bool esAccesoDev(String usuario, String contrasena) =>
      usuario.trim() == usuarioDev && contrasena == contrasenaDev;

  bool esIntentoDevInvalido(String usuario, String contrasena) =>
      usuario.trim() == usuarioDev && contrasena != contrasenaDev;

  LoginRole submit() => _selectedRole;

  Future<bool> loginAdmin(String email, String password) async {
    _cargando = true;
    _error = null;
    notifyListeners();

    try {
      final creds = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = creds.user?.uid;
      if (uid != null) {
        final doc = await FirebaseFirestore.instance
            .collection('admins')
            .doc(uid)
            .get();
        if (doc.exists) {
          final tallerId = doc.data()?['tallerId'] as String?;
          if (tallerId == null) {
            _error = 'La cuenta no tiene un taller asignado.';
            await FirebaseAuth.instance.signOut();
            await FirebaseAuth.instance.signInAnonymously();
          } else {
            final taller = await TallerRepository.instance.obtenerPorId(
              tallerId,
            );
            final tallerNombre =
                taller?.nombre ??
                doc.data()?['tallerNombre'] as String? ??
                'Taller';
            // `await` y no fire-and-forget: la sesion tiene que estar EN DISCO
            // antes de que la pantalla navegue al Dashboard. Sin esto, cerrar la
            // app en el instante siguiente al login arrancaria la proxima vez en
            // el login, que es exactamente el caso offline que estamos cerrando.
            await SesionAdmin.instance.iniciar(
              tallerId: tallerId,
              adminUid: uid,
              tallerNombre: tallerNombre,
              adminEmail: email.trim(),
            );
            // Reiniciar SyncService con el nuevo UID de admin.
            await SyncService.instance.stop();
            await SyncService.instance.start();
            _cargando = false;
            notifyListeners();
            return true;
          }
        } else {
          _error = 'El usuario no tiene permisos de administrador.';
          await FirebaseAuth.instance.signOut();
          await FirebaseAuth.instance.signInAnonymously();
        }
      }
    } on FirebaseAuthException catch (e) {
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
      // Firestore (la consulta del doc `admins`) y el resto de los SDKs de
      // Firebase tiran `FirebaseException` con codigo 'unavailable' cuando no
      // hay red. Sin este filtro el usuario ve "Error desconocido:
      // [firebase_core/network-error]" en vez de una frase que pueda actuar.
      _error = _esFallaDeRed(e) ? _mensajeSinRed() : 'Error desconocido: $e';
    }

    _cargando = false;
    notifyListeners();
    return false;
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

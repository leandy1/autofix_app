import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/features/sync/sync_service.dart';

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
  /// es anonima y ya ocurrio en `main.dart`.
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
        final doc = await FirebaseFirestore.instance.collection('admins').doc(uid).get();
        if (doc.exists) {
          final tallerId = doc.data()?['tallerId'] as String?;
          if (tallerId == null) {
            _error = 'La cuenta no tiene un taller asignado.';
            await FirebaseAuth.instance.signOut();
            await FirebaseAuth.instance.signInAnonymously();
          } else {
            SesionAdmin.instance.iniciar(tallerId: tallerId, adminUid: uid);
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
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        _error = 'Correo o contraseña incorrectos.';
      } else {
        _error = 'Error de autenticación: ${e.message}';
      }
    } catch (e) {
      _error = 'Error desconocido: $e';
    }

    _cargando = false;
    notifyListeners();
    return false;
  }
}
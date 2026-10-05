import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

enum LoginRole { admin, cliente }

class LoginController extends ChangeNotifier {
  static const String usuarioDev = 'dev';
  static const String contrasenaDev = '1234';

  LoginRole _selectedRole = LoginRole.admin;
  User? _currentUser;

  LoginController() {
    _currentUser = FirebaseAuth.instance.currentUser;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _currentUser = user;
      notifyListeners();
    });
  }

  LoginRole get selectedRole => _selectedRole;

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
}
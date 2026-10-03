import 'package:flutter/foundation.dart';

enum LoginRole { admin, cliente }

class LoginController extends ChangeNotifier {
  static const String usuarioDev = 'dev';
  static const String contrasenaDev = '1234';

  LoginRole _selectedRole = LoginRole.admin;

  LoginRole get selectedRole => _selectedRole;

  void selectRole(LoginRole role) {
    if (_selectedRole == role) return;
    _selectedRole = role;
    notifyListeners();
  }

  bool esAccesoDev(String usuario, String contrasena) =>
      usuario.trim() == usuarioDev && contrasena == contrasenaDev;

  bool esIntentoDevInvalido(String usuario, String contrasena) =>
      usuario.trim() == usuarioDev && contrasena != contrasenaDev;

  LoginRole submit() => _selectedRole;
}

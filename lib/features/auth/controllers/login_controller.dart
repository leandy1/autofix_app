import 'package:flutter/foundation.dart';

enum LoginRole { admin, cliente }

class LoginController extends ChangeNotifier {
  LoginRole _selectedRole = LoginRole.admin;

  LoginRole get selectedRole => _selectedRole;

  void selectRole(LoginRole role) {
    if (_selectedRole == role) return;
    _selectedRole = role;
    notifyListeners();
  }

  LoginRole submit() => _selectedRole;
}

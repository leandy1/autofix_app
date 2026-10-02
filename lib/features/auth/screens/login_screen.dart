import 'package:flutter/material.dart';

import 'package:autofix/features/admin/screens/dashboard_admin_screen.dart';
import 'package:autofix/features/auth/controllers/login_controller.dart';
import 'package:autofix/features/cliente/screens/dashboard_cliente_screen.dart';
import 'package:autofix/shared/theme/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controladores para leer lo que el usuario escribe en cada campo.
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final LoginController _loginController = LoginController();

  @override
  void dispose() {
    // Buena práctica: liberar los controladores cuando la pantalla se destruye.
    _userController.dispose();
    _passwordController.dispose();
    _loginController.dispose();
    super.dispose();
  }

  void _handleLogin() {
    final role = _loginController.submit();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => role == LoginRole.admin
            ? const DashboardScreen()
            : const DashboardClienteScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              // Limita el ancho de la tarjeta en pantallas grandes (tablet/web),
              // igual que se ve centrada y angosta en el boceto de Figma.
              constraints: const BoxConstraints(maxWidth: 380),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.cardWhite,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias, // para que el header respete las esquinas redondeadas
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [_buildHeader(), _buildForm()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Encabezado oscuro con el nombre de la app y el subtítulo.
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: AppColors.headerNavy,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      child: Column(
        children: const [
          Text(
            'AutoFix',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'SISTEMA DE GESTIÓN',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  /// Formulario blanco con los campos de usuario, contraseña y el botón.
  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Iniciar Sesión',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.labelDark,
            ),
          ),
          const SizedBox(height: 24),

          _buildRoleSelector(),
          const SizedBox(height: 18),

          _buildLabeledField(
            label: 'Usuario',
            hint: 'Ingrese su usuario',
            controller: _userController,
          ),
          const SizedBox(height: 18),

          _buildLabeledField(
            label: 'Contraseña',
            hint: 'Ingrese su contraseña',
            controller: _passwordController,
            obscureText: true,
          ),
          const SizedBox(height: 26),

          _buildLoginButton(),
          const SizedBox(height: 20),

          const Text(
            '© 2026 Grupo Q',
            style: TextStyle(fontSize: 12, color: AppColors.footerGray),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSelector() {
    return ListenableBuilder(
      listenable: _loginController,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ingresar como',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.labelDark,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<LoginRole>(
              segments: const [
                ButtonSegment(
                  value: LoginRole.admin,
                  label: Text('Admin'),
                  icon: Icon(Icons.admin_panel_settings_outlined),
                ),
                ButtonSegment(
                  value: LoginRole.cliente,
                  label: Text('Cliente'),
                  icon: Icon(Icons.person_outline),
                ),
              ],
              selected: {_loginController.selectedRole},
              onSelectionChanged: (selection) {
                _loginController.selectRole(selection.first);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Campo de texto con su etiqueta arriba, reutilizable para Usuario y Contraseña.
  Widget _buildLabeledField({
    required String label,
    required String hint,
    required TextEditingController controller,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.labelDark,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.placeholderGray),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.inputBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppColors.orangePrimary,
                width: 1.5,
              ),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  /// Botón naranja "Ingresar", ocupa todo el ancho disponible.
  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orangePrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: const Text(
          'Ingresar',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

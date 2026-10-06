import 'package:flutter/material.dart';

import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/features/admin/screens/dashboard_admin_screen.dart';
import 'package:autofix/features/auth/controllers/login_controller.dart';
import 'package:autofix/features/cliente/screens/dashboard_cliente_screen.dart';
import 'package:autofix/features/devMode/screens/talleres_afiliados_screen.dart';
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

  /// Estado del switch "Recuérdame".
  bool _recordarme = true;

  /// `true` cuando hay credenciales guardadas y el login puede entrar sin que
  /// el usuario escriba nada: es el estado en el que el usuario ve `san***`
  /// y la contraseña deshabilitada.
  bool _hayRecordamiento = false;

  @override
  void initState() {
    super.initState();
    _cargarRecordamiento();
  }

  /// Carga lo que decide como se ve el formulario al abrir.
  ///
  /// Arranca en el estado "normal" (`_recordarme = true`, sin recordamiento)
  /// para que el PRIMER frame ya sea usable: si se esperara a leer el
  /// keystore, el formulario apareceria vacio y luego saltaria al estado
  /// recordado, que en pantalla se lee como un parpadeo.
  Future<void> _cargarRecordamiento() async {
    final usuario = await _loginController.usuarioRecordado();
    // Si hay credenciales guardadas, el switch esta MARcado por definicion:
    // no puede haber algo guardado con la casilla apagada.
    final porDefecto = usuario == null
        ? await _loginController.recordarmePorDefecto()
        : true;
    if (!mounted) return;

    setState(() {
      _hayRecordamiento = usuario != null;
      _recordarme = porDefecto;
      if (usuario != null) _userController.text = usuario;
    });
  }

  /// Alterna la casilla. Ver `login_screen.dart` para la regla de negocio.
  Future<void> _alternarRecordarme(bool valor) async {
    if (!valor) {
      // Desmarcar BORRA lo guardado y devuelve el formulario a su estado
      // editable. Dejar el usuario ahi seria seguir usando el recordamiento
      // aunque el usuario pidio no tenerlo.
      await _loginController.persistirRecordamiento(
        usuario: '',
        contrasena: '',
        activo: false,
      );
      if (!mounted) return;
      setState(() {
        _recordarme = false;
        _hayRecordamiento = false;
        _userController.clear();
        _passwordController.clear();
      });
      return;
    }

    // Marcado de nuevo: todavia NO se guarda nada. Se guardara la cuenta que
    // el usuario ingrese a continuacion, al validarla. Por eso no hay llamada
    // al controlador aca: "recordarme esta activo" se deduce de que HAY
    // credenciales en el keystore, y mientras no las haya no hay nada que
    // prender.
    if (!mounted) return;
    setState(() {
      _recordarme = true;
      _hayRecordamiento = false;
    });
  }

  @override
  void dispose() {
    // Buena práctica: liberar los controladores cuando la pantalla se destruye.
    _userController.dispose();
    _passwordController.dispose();
    _loginController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    var usuario = _userController.text;
    var contrasena = _passwordController.text;

    // Con credenciales guardadas, el boton entra CON ESAS: por eso el campo
    // de usuario muestra la mascara y el de contraseña esta deshabilitado.
    // Si el keystore estuviera roto (devuelve null), se cae al texto de los
    // campos y el usuario puede escribir a mano.
    if (_hayRecordamiento) {
      final guardadas = await _loginController.credencialesRecordadas();
      if (guardadas != null) {
        usuario = guardadas.usuario;
        contrasena = guardadas.contrasena;
      }
    }
    if (!mounted) return;

    if (_loginController.esAccesoDev(usuario, contrasena)) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TalleresAfiliadosScreen()),
      );
      return;
    }
    if (_loginController.esIntentoDevInvalido(usuario, contrasena)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La contraseña de desarrollador no es válida.'),
        ),
      );
      return;
    }

    final role = _loginController.submit();

    if (role == LoginRole.admin) {
      if (usuario.trim().isEmpty || contrasena.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresa correo y contraseña.')),
        );
        return;
      }
      final ok = await _loginController.loginAdmin(usuario, contrasena);
      if (!mounted) return;
      if (ok) {
        await _guardarRecordamiento(usuario, contrasena);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loginController.error ?? 'Error al iniciar sesión.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return;
    }

    // Cliente: acceso directo (sin autenticación por ahora).
    //
    // Aun asi abre sesion: sin esto, "Mis citas", el saludo del AppBar y el
    // prellenado del formulario no tendrian de donde leer la proxima vez que
    // se abra la app. Solo se completan campos VACIOS del perfil para no
    // pisar lo que el cliente ya cargo en Editar Perfil.
    final esCorreo = usuario.contains('@');
    final sesion = SesionCliente.instance;
    await sesion.iniciar(
      nombre: sesion.nombre ?? (esCorreo ? null : usuario.trim()),
      correo: sesion.correo ?? (esCorreo ? usuario.trim() : null),
    );
    await _guardarRecordamiento(usuario, contrasena);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardClienteScreen()),
    );
  }

  /// Persiste la decision del switch. Se llama SOLO tras un login exitoso.
  Future<void> _guardarRecordamiento(String usuario, String contrasena) async {
    await _loginController.persistirRecordamiento(
      usuario: usuario,
      contrasena: contrasena,
      activo: _recordarme,
    );
  }

  void _abrirRegistroCliente() {
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => _CrearCuentaClienteDialog(
        onAccountCreated: (nombre, correo, telefono, contrasena) async {
          // El registro es donde por primera vez se conocen los tres datos
          // que el prellenado del formulario de citas va a necesitar: se abren
          // la sesion y se guardan el perfil aca, no en la pantalla siguiente.
          await SesionCliente.instance.iniciar(
            nombre: nombre,
            correo: correo,
            telefono: telefono,
          );
          // Y si "Recuérdame" esta marcado, esta cuenta es la que queda
          // guardada, igual que si hubiera entrado por el boton Ingresar.
          await _guardarRecordamiento(correo, contrasena);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '¡Cuenta creada exitosamente! Bienvenido, $nombre.',
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.headerNavy,
            ),
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const DashboardClienteScreen()),
          );
        },
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
            // Con recordamiento el campo es SOLO lectura y muestra `san***`:
            // el usuario no reescribe su propio correo para entrar, y que
            // pudiera editarlo sin poder verlo completo solo genera ruido.
            readOnly: _hayRecordamiento,
          ),
          const SizedBox(height: 18),

          _buildLabeledField(
            label: 'Contraseña',
            hint: 'Ingrese su contraseña',
            controller: _passwordController,
            obscureText: true,
            // La contraseña esta DESHABILITADA: la que se usa es la guardada.
            enabled: !_hayRecordamiento,
          ),
          const SizedBox(height: 14),

          _buildRecordarme(),
          const SizedBox(height: 26),

          _buildLoginButton(),
          const SizedBox(height: 16),

          ListenableBuilder(
            listenable: _loginController,
            builder: (context, _) {
              if (_loginController.selectedRole != LoginRole.cliente) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '¿No tienes cuenta?',
                    style: TextStyle(fontSize: 13, color: AppColors.textGray),
                  ),
                  TextButton(
                    onPressed: _abrirRegistroCliente,
                    child: const Text(
                      'Crear una aquí',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.orangePrimary,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),

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

  /// La casilla "Recuérdame".
  ///
  /// El texto de la derecha cambia segun el estado para que se entienda que
  /// pasaría si se desmarca: no es decoracion, es lo que explica por qué la
  /// contraseña esta gris.
  Widget _buildRecordarme() {
    return Row(
      children: [
        Switch(
          value: _recordarme,
          onChanged: _alternarRecordarme,
          activeThumbColor: AppColors.orangePrimary,
        ),
        const SizedBox(width: 6),
        const Text(
          'Recuérdame',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.labelDark,
          ),
        ),
        const Spacer(),
        Text(
          _hayRecordamiento ? 'Sesión guardada' : '',
          style: const TextStyle(fontSize: 12, color: AppColors.textGray),
        ),
      ],
    );
  }

  /// Campo de texto con su etiqueta arriba, reutilizable para Usuario y Contraseña.
  Widget _buildLabeledField({
    required String label,
    required String hint,
    required TextEditingController controller,
    bool obscureText = false,
    bool enabled = true,
    bool readOnly = false,
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
          enabled: enabled,
          readOnly: readOnly,
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

class _CrearCuentaClienteDialog extends StatefulWidget {
  const _CrearCuentaClienteDialog({required this.onAccountCreated});

  final Future<void> Function(
    String nombre,
    String correo,
    String telefono,
    String contrasena,
  )
  onAccountCreated;

  @override
  State<_CrearCuentaClienteDialog> createState() =>
      _CrearCuentaClienteDialogState();
}

class _CrearCuentaClienteDialogState extends State<_CrearCuentaClienteDialog> {
  late final TextEditingController _nombreController;
  late final TextEditingController _correoController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmPasswordController;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _creando = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController();
    _correoController = TextEditingController();
    _telefonoController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _correoController.dispose();
    _telefonoController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  InputDecoration _decoracionCampo(String label, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.textGray),
      hintStyle: const TextStyle(
        color: AppColors.placeholderGray,
        fontSize: 13,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      suffixIcon: suffixIcon,
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
    );
  }

  void _submitForm() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _creando = true);

    Future<void>.delayed(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      final nombre = _nombreController.text.trim();
      final correo = _correoController.text.trim();
      final telefono = _telefonoController.text.trim();
      final contrasena = _passwordController.text;
      Navigator.of(context).pop();
      await widget.onAccountCreated(nombre, correo, telefono, contrasena);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.headerNavy,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Crear Cuenta',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Registro de nuevo cliente',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nombreController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _decoracionCampo('Nombre completo'),
                        validator: (valor) {
                          final v = valor?.trim() ?? '';
                          if (v.isEmpty) return 'Ingresa tu nombre completo.';
                          if (v.length < 3)
                            return 'El nombre debe tener al menos 3 caracteres.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _correoController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _decoracionCampo('Correo electrónico'),
                        validator: (valor) {
                          final v = valor?.trim() ?? '';
                          if (v.isEmpty)
                            return 'Ingresa tu correo electrónico.';
                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                              .hasMatch(v)) {
                            return 'Ingresa un correo electrónico válido.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _telefonoController,
                        keyboardType: TextInputType.phone,
                        decoration: _decoracionCampo('Teléfono'),
                        validator: (valor) {
                          final v = valor?.trim() ?? '';
                          if (v.isEmpty)
                            return 'Ingresa tu número de teléfono.';
                          final digitos = v.replaceAll(RegExp(r'\D'), '');
                          if (digitos.length < 10 || digitos.length > 15) {
                            return 'Ingresa un teléfono válido (10 a 15 dígitos).';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: _decoracionCampo(
                          'Contraseña',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: AppColors.textGray,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        validator: (valor) {
                          final v = valor ?? '';
                          if (v.isEmpty) return 'Ingresa una contraseña.';
                          if (v.length < 6)
                            return 'La contraseña debe tener al menos 6 caracteres.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        decoration: _decoracionCampo(
                          'Confirmar Contraseña',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: AppColors.textGray,
                            ),
                            onPressed: () => setState(
                              () => _obscureConfirmPassword =
                                  !_obscureConfirmPassword,
                            ),
                          ),
                        ),
                        validator: (valor) {
                          final v = valor ?? '';
                          if (v.isEmpty) return 'Confirma tu contraseña.';
                          if (v != _passwordController.text) {
                            return 'Las contraseñas no coinciden.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: Colors.white,
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _creando ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orangePrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _creando
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Registrarme',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

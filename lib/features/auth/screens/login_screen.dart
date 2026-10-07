import 'package:flutter/material.dart';

import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/connectivity/connectivity_scope.dart';
import 'package:autofix/features/admin/screens/dashboard_admin_screen.dart';
import 'package:autofix/features/auth/controllers/login_controller.dart';
import 'package:autofix/features/cliente/screens/dashboard_cliente_screen.dart';
import 'package:autofix/features/devMode/screens/talleres_afiliados_screen.dart';
import 'package:autofix/features/sync/sync_service.dart';
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
  late final Future<void> _cargaInicial;

  /// Estado del switch "Recuérdame".
  bool _recordarme = true;

  /// `true` cuando hay credenciales guardadas y el login puede entrar sin que
  /// el usuario escriba nada: es el estado en el que el usuario ve `san***`
  /// y la contraseña deshabilitada.
  bool _hayRecordamiento = false;
  bool _preferenciasCargadas = false;

  @override
  void initState() {
    super.initState();
    _cargaInicial = _cargarRecordamiento();
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
    final rol = await _loginController.rolRecordado();
    if (!mounted) return;

    _loginController.selectRole(rol);
    setState(() {
      _hayRecordamiento = usuario != null;
      _recordarme = porDefecto;
      _preferenciasCargadas = true;
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
      await SesionAdmin.instance.cerrar();
      await SesionCliente.instance.cerrar();
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

  /// `true` cuando el sistema afirma que no hay ninguna via de red.
  ///
  /// Se consulta en el instante en que se pulsa "Ingresar", no en `build`:
  /// usar `of` registraria una dependencia y repintaria todo el Login cada vez
  /// que cambie la red, para una informacion que solo se necesita al enviar.
  ///
  /// Sin `ConnectivityScope` en el arbol (tests, app montada a medias)
  /// devuelve `false` y el login sigue el camino normal de Firebase Auth, que
  /// es el que no puede quedarse callado.
  bool _sinRed() {
    final scope = context
        .getElementForInheritedWidgetOfExactType<ConnectivityScope>();
    final servicio = scope?.widget as ConnectivityScope?;
    return servicio?.notifier?.desconectado ?? false;
  }

  /// La sesion de este rol quedo restaurada en memoria al arrancar.
  ///
  /// Es lo que hace posible entrar sin red: sin esa sesion no hay perfil
  /// (cliente) ni taller (admin) con los que pintar el dashboard, y desde el
  /// login offline no hay forma de recuperarlos.
  bool _sesionLocalLista(LoginRole role) => role == LoginRole.admin
      ? SesionAdmin.instance.activa
      : SesionCliente.instance.activa;

  /// Entra al dashboard sin tocar la red, validando contra las credenciales
  /// que "Recuérdame" dejo guardadas en el keystore.
  ///
  /// Es el otro lado del login híbrido: con red la cuenta se valida contra
  /// Firebase Auth; sin red lo unico que se puede hacer es reconocer a alguien
  /// cuyas credenciales ya estan en ESTE dispositivo. Por eso avisa en vez de
  /// quedarse mudo cuando no hay nada guardado o lo tecleado no coincide.
  Future<void> _entrarSinRed({
    required String usuario,
    required String contrasena,
    required LoginRole role,
  }) async {
    final guardadas = await _loginController.credencialesRecordadas();
    if (!mounted) return;

    // Con recordamiento las cajas vienen enmascaradas (`san***`) y
    // `_handleLogin` ya las reemplazo por las credenciales reales; sin
    // recordamiento lo que llega es lo que el usuario acaba de teclear.
    final coincide =
        guardadas != null &&
        usuario.trim().toLowerCase() ==
            guardadas.usuario.trim().toLowerCase() &&
        contrasena == guardadas.contrasena;

    if (!coincide || !_sesionLocalLista(role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sin conexión. Solo puedes entrar con las credenciales guardadas '
            'en este dispositivo.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (role == LoginRole.admin) {
      await SesionCliente.instance.cerrar();
      // Mismo arranque que `loginAdmin` (stop + start): la cola local y el
      // listener de Firestore tienen que estar vivos para que, cuando vuelva
      // la red, lo pendiente se suba sin reiniciar la app.
      try {
        await SyncService.instance.stop();
        await SyncService.instance.start();
      } catch (e) {
        debugPrint('Login: SyncService no arrancó sin red ($e)');
      }
    } else {
      await SesionAdmin.instance.cerrar();
    }

    await _loginController.persistirRol(role);
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => role == LoginRole.admin
            ? const DashboardScreen()
            : const DashboardClienteScreen(),
      ),
    );
  }

  Future<void> _handleLogin() async {
    await _cargaInicial;
    if (!mounted) return;
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
      // La rama DEV no conserva sesión ni credenciales aunque el switch esté
      // marcado (también limpia una eventual entrada DEV de una versión vieja).
      await _loginController.persistirRecordamiento(
        usuario: usuario,
        contrasena: contrasena,
        activo: true,
      );
      // Brecha de seguridad: la pantalla DEV se apila CON el Login debajo, asi
      // que este `State` NO se destruye y los campos siguen con `dev` / `1234`
      // la proxima vez que el usuario regrese (al cerrar sesion en la pantalla
      // DEV). A diferencia de los otros dos ramos, aca no hay un
      // `pushReplacement` que vacie los controladores por arte de magia.
      _userController.clear();
      _passwordController.clear();
      if (!mounted) return;
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
      // LOGIN HIBRIDO: sin red no hay nada con que validar contra Auth, asi
      // que se valida contra las credenciales guardadas en este dispositivo.
      if (_sinRed()) {
        await _entrarSinRed(
          usuario: usuario,
          contrasena: contrasena,
          role: LoginRole.admin,
        );
        return;
      }
      // Primero valida Auth y permisos. La sesión queda en memoria, pero no en
      // disco; solo se persiste después de la confirmación explícita.
      final ok = await _loginController.loginAdmin(usuario, contrasena);
      if (!mounted) return;
      if (ok) {
        var recordarSesion = false;
        if (_recordarme) {
          recordarSesion = await _confirmarPersistenciaSesionAdmin() ?? false;
        }
        if (recordarSesion) {
          await SesionAdmin.instance.persistirActual();
          await _loginController.persistirRecordamiento(
            usuario: usuario,
            contrasena: contrasena,
            activo: true,
          );
        } else {
          await _loginController.persistirRecordamiento(
            usuario: '',
            contrasena: '',
            activo: false,
          );
          if (_recordarme) {
            setState(() => _recordarme = false);
          }
        }
        await _loginController.persistirRol(LoginRole.admin);
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

    if (usuario.trim().isEmpty || contrasena.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa correo y contraseña.')),
      );
      return;
    }

    // LOGIN HIBRIDO (mismo camino que en el rol admin): sin red, la validacion
    // se hace contra las credenciales del keystore y la sesion local que
    // `main()` restauro, en vez de intentar una llamada que no puede responder.
    if (_sinRed()) {
      await _entrarSinRed(
        usuario: usuario,
        contrasena: contrasena,
        role: LoginRole.cliente,
      );
      return;
    }

    final perfil = await _loginController.loginCliente(
      usuario,
      contrasena,
      persistirSesion: _recordarme,
    );
    if (!mounted) return;
    if (perfil == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loginController.error ?? 'No se pudo iniciar sesión.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    if (_recordarme) {
      await _loginController.persistirRecordamiento(
        usuario: usuario,
        contrasena: contrasena,
        activo: true,
      );
    } else {
      await _loginController.persistirRecordamiento(
        usuario: '',
        contrasena: '',
        activo: false,
      );
    }
    await _loginController.persistirRol(LoginRole.cliente);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardClienteScreen()),
    );
  }

  Future<bool?> _confirmarPersistenciaSesionAdmin() => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (contexto) => AlertDialog(
      title: const Text('Mantener sesión activa'),
      content: const Text(
        '¿Estás seguro de mantener la sesión activa luego de cerrar la app? '
        '(Se recomienda solo en dispositivos personales)',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(contexto).pop(false),
          child: const Text('NO'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(contexto).pop(true),
          child: const Text('SÍ'),
        ),
      ],
    ),
  );

  void _entrarComoInvitado() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DashboardClienteScreen(invitado: true),
      ),
    );
  }

  void _abrirRegistroCliente() {
    if (!_preferenciasCargadas) return;
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => _CrearCuentaClienteDialog(
        onAccountCreated: (nombre, correo, telefono, contrasena) async {
          final perfil = await _loginController.registrarCliente(
            nombre: nombre,
            correo: correo,
            telefono: telefono,
            contrasena: contrasena,
          );
          if (perfil == null) {
            return _loginController.error ?? 'No se pudo crear la cuenta.';
          }

          await SesionAdmin.instance.cerrar();
          await SesionCliente.instance.iniciar(
            nombre: perfil.nombre,
            correo: perfil.correo,
            telefono: perfil.telefono,
            persistir: _recordarme,
          );
          await _loginController.persistirRol(LoginRole.cliente);
          await _loginController.persistirRecordamiento(
            usuario: correo,
            contrasena: contrasena,
            activo: _recordarme,
          );
          return null;
        },
        onSuccess: () {
          if (!mounted) return;
          // Cada paso va en su PROPIO try: si el aviso falla, la navegacion
          // tiene que ocurrir igual. Envolviendo los dos juntos, un error de
          // `ScaffoldMessenger` dejaria al usuario en el formulario creyendo
          // que la cuenta no se creo.
          try {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cuenta creada y sincronizada con Firebase.'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.headerNavy,
              ),
            );
          } catch (e) {
            debugPrint('Login: no se pudo avisar la cuenta creada ($e)');
          }
          try {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const DashboardClienteScreen()),
            );
          } catch (e) {
            debugPrint('Login: no se pudo abrir el dashboard ($e)');
          }
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
            label: 'Correo electrónico / Usuario DEV',
            hint: 'nombre@ejemplo.com o dev',
            controller: _userController,
            keyboardType: TextInputType.emailAddress,
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
              return Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '¿No tienes cuenta?',
                    style: TextStyle(fontSize: 13, color: AppColors.textGray),
                  ),
                  TextButton(
                    onPressed: _preferenciasCargadas
                        ? _abrirRegistroCliente
                        : null,
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

          OutlinedButton.icon(
            onPressed: _entrarComoInvitado,
            icon: const Icon(Icons.map_outlined),
            label: const Text('Entrar como Invitado / Ver Mapa'),
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
              onSelectionChanged: _preferenciasCargadas
                  ? (selection) => _loginController.selectRole(selection.first)
                  : null,
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
          onChanged: _preferenciasCargadas ? _alternarRecordarme : null,
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
    TextInputType? keyboardType,
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
          keyboardType: keyboardType,
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
        onPressed: _preferenciasCargadas && !_loginController.cargando
            ? _handleLogin
            : null,
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
  const _CrearCuentaClienteDialog({
    required this.onAccountCreated,
    required this.onSuccess,
  });

  final Future<String?> Function(
    String nombre,
    String correo,
    String telefono,
    String contrasena,
  )
  onAccountCreated;
  final VoidCallback onSuccess;

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
  String? _error;
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

  Future<void> _submitForm() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _creando = true;
      _error = null;
    });
    final error = await widget.onAccountCreated(
      _nombreController.text.trim(),
      _correoController.text.trim(),
      _telefonoController.text.trim(),
      _passwordController.text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _creando = false;
        _error = error;
      });
      return;
    }
    // El cierre del dialogo y el ruteo post-registro van protegidos: ambos
    // corren con el contexto de este dialogo, que en el instante del `pop` deja
    // de estar montado. Si alguno truena, la cuenta YA existe en Firebase y el
    // error quedaria sin atender (ni pantalla roja en release).
    try {
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Login: no se pudo cerrar el dialogo de registro ($e)');
    }
    widget.onSuccess();
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
                      if (_error != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDECEC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
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

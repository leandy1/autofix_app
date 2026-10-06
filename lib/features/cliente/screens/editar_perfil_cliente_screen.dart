import 'package:flutter/material.dart';

import 'package:autofix/core/auth/recordarme_prefs.dart';
import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/features/cliente/presentation/perfil_cliente_controller.dart';
import 'package:autofix/features/cliente/widgets/cliente_section_widgets.dart';
import 'package:autofix/shared/theme/app_colors.dart';

/// Perfil del cliente, pensada para funcionar SIN internet.
///
/// ---------------------------------------------------------------
/// LAS TRES SECCIONES SON INDEPENDIENTES A PROPOSITO
/// ---------------------------------------------------------------
/// Cada bloque tiene su propio boton y su propio mensaje:
///
/// 1. Datos -> "Información guardada" (escribe en el perfil local).
/// 2. Contraseña -> "Contraseña actualizada" o "Guardada en cola, se aplicará
///    al conectarse" (ver `PerfilClienteController`).
/// 3. Configuracion -> "El cambio surtió efecto" (preferencia del Recuérdame).
///
/// Un solo boton para las tres habria obligado a que "guardar mi nombre"
/// tambien intente cambiar la contraseña, y a que el usuario no pudiera tocar
/// la preferencia sin reescribir todo el formulario.
///
/// Nada de esto pide red: el perfil es local y el cambio de contraseña se
/// encola si no se puede aplicar. Esa es justamente la diferencia entre esta
/// pantalla y un "guardar" que se queda esperando el timeout.
class EditarPerfilClienteScreen extends StatefulWidget {
  const EditarPerfilClienteScreen({super.key});

  @override
  State<EditarPerfilClienteScreen> createState() =>
      _EditarPerfilClienteScreenState();
}

class _EditarPerfilClienteScreenState extends State<EditarPerfilClienteScreen> {
  final PerfilClienteController _controller = PerfilClienteController();

  late final TextEditingController _nombreController;
  late final TextEditingController _correoController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _nuevaPasswordController;
  late final TextEditingController _repetirPasswordController;

  bool _recordarmePorDefecto = true;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(
      text: SesionCliente.instance.nombre ?? '',
    );
    _correoController = TextEditingController(
      text: SesionCliente.instance.correo ?? '',
    );
    _telefonoController = TextEditingController(
      text: SesionCliente.instance.telefono ?? '',
    );
    _nuevaPasswordController = TextEditingController();
    _repetirPasswordController = TextEditingController();
    _cargarPreferencia();
  }

  /// La preferencia se lee aparte (y despues) porque es una consulta a
  /// SharedPreferences y el perfil ya esta en memoria desde el arranque: no
  /// tiene sentido frenar el primer frame por un `bool`.
  Future<void> _cargarPreferencia() async {
    final valor = await RecordarmePrefs.habilitadoPorDefecto();
    if (!mounted) return;
    setState(() => _recordarmePorDefecto = valor);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _correoController.dispose();
    _telefonoController.dispose();
    _nuevaPasswordController.dispose();
    _repetirPasswordController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _mostrarAviso(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _guardarDatos() async {
    final mensaje = await _controller.guardarDatos(
      nombre: _nombreController.text,
      correo: _correoController.text,
      telefono: _telefonoController.text,
    );
    if (!mounted) return;
    _mostrarAviso(mensaje);
  }

  Future<void> _cambiarPassword() async {
    final mensaje = await _controller.cambiarPassword(
      nueva: _nuevaPasswordController.text,
      repetir: _repetirPasswordController.text,
    );
    if (!mounted) return;
    _mostrarAviso(mensaje);
    // Solo se limpian los campos si el cambio salio bien: si no coincide, el
    // usuario tiene que poder corregir lo que escribio sin volver a teclear
    // las dos contraseñas.
    if (mensaje == 'Contraseña actualizada' ||
        mensaje.startsWith('Guardada en cola')) {
      _nuevaPasswordController.clear();
      _repetirPasswordController.clear();
    }
  }

  Future<void> _alternarRecordarme(bool valor) async {
    // Se actualiza el estado ANTES de esperar: si no, el switch tarda un frame
    // en reflejar el toque y parece que no respondio.
    setState(() => _recordarmePorDefecto = valor);

    final aviso = await _controller.alternarRecordarmePorDefecto(valor);
    if (!mounted || aviso == null) return;
    _mostrarAviso(aviso);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.headerNavy,
        foregroundColor: Colors.white,
        title: const Text(
          'Editar Perfil',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const TituloSeccionCliente(
                  eyebrow: 'TU CUENTA',
                  title: 'Datos personales',
                  subtitle: 'Como te ve el taller cuando agendes',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nombreController,
                  textCapitalization: TextCapitalization.words,
                  decoration: clienteInputDecoration(
                    'Nombre completo',
                    hintText: 'Ej: María Pérez',
                    prefixIcon: Icons.person_outline,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _correoController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: clienteInputDecoration(
                    'Correo electrónico',
                    hintText: 'Ej: maria@correo.com',
                    prefixIcon: Icons.mail_outline,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _telefonoController,
                  keyboardType: TextInputType.phone,
                  decoration: clienteInputDecoration(
                    'Teléfono',
                    hintText: '809-000-0000',
                    prefixIcon: Icons.phone_outlined,
                  ),
                ),
                const SizedBox(height: 14),
                botonAccionCliente('Guardar cambios', onPressed: _guardarDatos),

                const SizedBox(height: 26),
                etiquetaFormularioCliente('Cambiar contraseña'),
                const SizedBox(height: 4),
                const Text(
                  'Si no tienes internet, el cambio queda guardado en tu '
                  'dispositivo y se aplica en cuanto vuelva la conexión.',
                  style: TextStyle(color: AppColors.textGray, fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nuevaPasswordController,
                  obscureText: true,
                  decoration: clienteInputDecoration(
                    'Nueva contraseña',
                    prefixIcon: Icons.lock_outline,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _repetirPasswordController,
                  obscureText: true,
                  decoration: clienteInputDecoration(
                    'Repetir contraseña',
                    prefixIcon: Icons.lock_reset_outlined,
                  ),
                ),
                const SizedBox(height: 14),
                botonAccionCliente(
                  'Actualizar contraseña',
                  onPressed: _cambiarPassword,
                ),

                const SizedBox(height: 26),
                etiquetaFormularioCliente('Configuración'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardWhite,
                    border: Border.all(color: AppColors.inputBorder),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SwitchListTile.adaptive(
                    value: _recordarmePorDefecto,
                    onChanged: _alternarRecordarme,
                    activeThumbColor: AppColors.orangePrimary,
                    title: const Text(
                      'Traer habilitado por defecto la opción Recuérdame',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.labelDark,
                      ),
                    ),
                    subtitle: const Text(
                      'Decide con que estado arranca la casilla en el login.',
                      style: TextStyle(fontSize: 12, color: AppColors.textGray),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

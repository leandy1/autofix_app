import 'package:flutter/material.dart';

import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/features/admin/presentation/perfil_admin_controller.dart';
import 'package:autofix/shared/theme/app_colors.dart';

class EditarPerfilAdminScreen extends StatefulWidget {
  const EditarPerfilAdminScreen({super.key});

  @override
  State<EditarPerfilAdminScreen> createState() =>
      _EditarPerfilAdminScreenState();
}

class _EditarPerfilAdminScreenState extends State<EditarPerfilAdminScreen> {
  final PerfilAdminController _controller = PerfilAdminController();
  final TextEditingController _nombre = TextEditingController();
  late final TextEditingController _email;
  final TextEditingController _telefono = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmarPassword = TextEditingController();
  bool _cargando = true;
  bool _guardando = false;
  bool _ocultarPassword = true;
  bool _ocultarConfirmacion = true;

  String get _correo => SesionAdmin.instance.adminEmail ?? '';

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: _correo);
    _cargar();
  }

  Future<void> _cargar() async {
    final datos = await _controller.cargarDatos();
    await _controller.inicializarPreferencia();
    if (!mounted) return;
    setState(() {
      _nombre.text = datos.$1 ?? _correo.split('@').first;
      _telefono.text = datos.$2 ?? '';
      _cargando = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _nombre.dispose();
    _email.dispose();
    _telefono.dispose();
    _password.dispose();
    _confirmarPassword.dispose();
    super.dispose();
  }

  void _aviso(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _guardarDatos() async {
    setState(() => _guardando = true);
    final mensaje = await _controller.guardarDatos(
      nombre: _nombre.text,
      telefono: _telefono.text,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    _aviso(mensaje);
  }

  Future<void> _cambiarPassword() async {
    setState(() => _guardando = true);
    final mensaje = await _controller.cambiarPassword(
      correo: _correo,
      nueva: _password.text,
      repetir: _confirmarPassword.text,
    );
    if (!mounted) return;
    setState(() {
      _guardando = false;
      _password.clear();
      _confirmarPassword.clear();
    });
    _aviso(mensaje);
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  Widget _seccion(String titulo, Widget contenido) => Card(
    color: AppColors.cardWhite,
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          contenido,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Editar Perfil'),
        backgroundColor: AppColors.headerNavy,
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _seccion(
                    'Datos del perfil',
                    Column(
                      children: [
                        TextField(
                          controller: _nombre,
                          textCapitalization: TextCapitalization.words,
                          decoration: _decoration(
                            'Nombre',
                            Icons.person_outline,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _email,
                          readOnly: true,
                          decoration: _decoration(
                            'Correo',
                            Icons.email_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _telefono,
                          keyboardType: TextInputType.phone,
                          decoration: _decoration(
                            'Teléfono',
                            Icons.phone_outlined,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _guardando ? null : _guardarDatos,
                            child: const Text('Guardar datos locales'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _seccion(
                    'Seguridad',
                    Column(
                      children: [
                        TextField(
                          controller: _password,
                          obscureText: _ocultarPassword,
                          decoration:
                              _decoration(
                                'Nueva contraseña',
                                Icons.lock_outline,
                              ).copyWith(
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () => _ocultarPassword = !_ocultarPassword,
                                  ),
                                  icon: Icon(
                                    _ocultarPassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirmarPassword,
                          obscureText: _ocultarConfirmacion,
                          decoration:
                              _decoration(
                                'Confirmar contraseña',
                                Icons.lock_reset_outlined,
                              ).copyWith(
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () => _ocultarConfirmacion =
                                        !_ocultarConfirmacion,
                                  ),
                                  icon: Icon(
                                    _ocultarConfirmacion
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonal(
                            onPressed: _guardando ? null : _cambiarPassword,
                            child: const Text('Cambiar contraseña'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sin conexión, el cambio se guarda cifrado y queda '
                          'pendiente para Firebase Auth.',
                          style: TextStyle(color: AppColors.textGray),
                        ),
                      ],
                    ),
                  ),
                  _seccion(
                    'Preferencias de inicio',
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Traer habilitado por defecto opción Recuérdame',
                      ),
                      value: _controller.recordarmePorDefecto,
                      activeThumbColor: AppColors.orangePrimary,
                      onChanged: _controller.alternarRecordarmePorDefecto,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

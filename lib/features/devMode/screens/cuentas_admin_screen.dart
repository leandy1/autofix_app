import 'package:flutter/material.dart';
import 'package:autofix/features/devMode/controllers/cuentas_admin_controller.dart';
import 'package:autofix/features/talleres/models/taller.dart';
import 'package:autofix/shared/theme/app_colors.dart';

class CuentasAdminScreen extends StatefulWidget {
  const CuentasAdminScreen({super.key});

  @override
  State<CuentasAdminScreen> createState() => _CuentasAdminScreenState();
}

class _CuentasAdminScreenState extends State<CuentasAdminScreen> {
  final CuentasAdminController _controller = CuentasAdminController();
  bool _verificandoAcceso = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChange);
    _controller.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mostrarVerificacionCorreo();
    });
  }

  @override
  void dispose() {
    _controller.stop();
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  /// Muestra un diálogo para verificar el correo del administrador
  /// contra la colección `adminUsers` en Firestore.
  Future<void> _mostrarVerificacionCorreo() async {
    if (_verificandoAcceso) return;

    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verificación de Acceso'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingrese su correo de administrador para gestionar cuentas:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Form(
              key: formKey,
              child: TextFormField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingrese su correo';
                  }
                  if (!value.contains('@')) {
                    return 'Correo inválido';
                  }
                  return null;
                },
                autofillHints: const [AutofillHints.email],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(dialogContext).pop(true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.orangePrimary),
            child: const Text('Verificar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (resultado != true) {
      // Si cancela, volver a la pantalla anterior
      if (mounted) Navigator.of(context).pop();
      return;
    }

    _verificandoAcceso = true;
    setState(() {});

    final verificado = await _controller.verificarAcceso(emailController.text.trim());

    _verificandoAcceso = false;

    if (!mounted) return;
    setState(() {});

    if (!verificado) {
      // Mostrar error y volver a pedir
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_controller.error ?? 'Correo no autorizado'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      await _mostrarVerificacionCorreo();
    } else {
      // Verificado: cargar datos
      await _controller.cargarDatos();
    }
  }

  Future<void> _sincronizar() async {
    if (!_controller.verificado) {
      await _mostrarVerificacionCorreo();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sincronizando con Firebase...')),
    );
    try {
      await _controller.sincronizar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _controller.error == null
                ? 'Sincronización completa.'
                : _controller.error!,
          ),
          backgroundColor:
              _controller.error == null ? Colors.green.shade800 : Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de sync: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  void _mostrarCrearAdmin() {
    if (!_controller.verificado) {
      _mostrarVerificacionCorreo();
      return;
    }

    final activos = _controller.talleres.where((t) => t.activo).toList();
    if (activos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay talleres disponibles para asociar.')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => _CrearAdminDialog(
        talleres: activos,
        onGuardar: (email, password, tallerId) async {
          final ok = await _controller.crearCuentaAdmin(
            email: email,
            password: password,
            tallerId: tallerId,
          );
          if (!context.mounted) return;
          if (ok) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cuenta de admin creada correctamente.')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_controller.error ?? 'Error desconocido')),
            );
          }
        },
      ),
    );
  }

  Future<void> _confirmarAccionAdmin(Map<String, dynamic> admin) async {
    if (!_controller.verificado) {
      await _mostrarVerificacionCorreo();
      return;
    }

    final eliminado = (admin['eliminado'] as bool?) ?? false;
    final uid = admin['uid']?.toString() ?? '';
    final email = admin['email'] ?? 'este correo';

    if (eliminado) {
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reactivar cuenta'),
          content: Text('¿Reactivar la cuenta $email?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.orangePrimary),
              child: const Text('Reactivar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmado != true) return;
      final ok = await _controller.reactivarAdmin(uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Cuenta reactivada.' : _controller.error ?? 'Error al reactivar.')),
      );
    } else {
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Eliminar cuenta admin'),
          content: Text('¿Dar de baja $email? La cuenta quedará inactiva y se podrá reactivar después.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Dar de baja', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmado != true) return;
      final ok = await _controller.eliminarAdmin(uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Cuenta dada de baja.' : _controller.error ?? 'Error al eliminar.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final verificado = _controller.verificado;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.headerNavy,
        foregroundColor: Colors.white,
        title: const Text('Cuentas Administrador', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Sincronizar',
            icon: const Icon(Icons.sync),
            onPressed: _controller.cargando || _verificandoAcceso ? null : _sincronizar,
          ),
          if (verificado)
            IconButton(
              tooltip: 'Crear Admin',
              icon: const Icon(Icons.add),
              onPressed: _controller.cargando ? null : _mostrarCrearAdmin,
            ),
          if (_controller.cargando || _verificandoAcceso)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          if (verificado)
            IconButton(
              tooltip: 'Cambiar cuenta',
              icon: const Icon(Icons.switch_account),
              onPressed: () {
                _controller.limpiarVerificacion();
                _mostrarVerificacionCorreo();
              },
            ),
        ],
      ),
      body: _verificandoAcceso
          ? const Center(child: CircularProgressIndicator())
          : _controller.cargando && _controller.admins.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : !verificado
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_outline, size: 64, color: AppColors.textGray),
                          const SizedBox(height: 16),
                          const Text(
                            'Verificación requerida',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.headerNavy),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Ingrese un correo autorizado para gestionar cuentas de administrador.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textGray),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _mostrarVerificacionCorreo,
                            icon: const Icon(Icons.verified_user),
                            label: const Text('Verificar correo'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.orangePrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _controller.admins.length,
                      itemBuilder: (context, index) {
                        final admin = _controller.admins[index];
                        final eliminado = (admin['eliminado'] as bool?) ?? false;
                        final tallerAsociado = _controller.talleres.where((t) => t.id == admin['tallerId']).firstOrNull;
                        final uid = admin['uid']?.toString() ?? '';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          color: eliminado ? const Color(0xFFF5F5F5) : null,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: eliminado ? Colors.grey : AppColors.orangePrimary,
                              child: Icon(eliminado ? Icons.person_off : Icons.person, color: Colors.white),
                            ),
                            title: Text(
                              admin['email'] ?? 'Sin email',
                              style: TextStyle(fontWeight: FontWeight.bold, color: eliminado ? Colors.grey : null),
                            ),
                            subtitle: Text(
                              eliminado
                                  ? 'Cuenta eliminada'
                                  : 'Taller: ${tallerAsociado?.nombre ?? 'Desconocido (${admin['tallerId']})'}',
                            ),
                            trailing: SizedBox(
                              width: 96,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (uid.isNotEmpty)
                                    IconButton(
                                      icon: Icon(
                                        eliminado ? Icons.refresh : Icons.delete_outline,
                                        color: eliminado ? Colors.green : Colors.redAccent,
                                        size: 20,
                                      ),
                                      tooltip: eliminado ? 'Reactivar' : 'Eliminar',
                                      onPressed: () => _confirmarAccionAdmin(admin),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

class _CrearAdminDialog extends StatefulWidget {
  final List<Taller> talleres;
  final Future<void> Function(String email, String password, String tallerId) onGuardar;

  const _CrearAdminDialog({required this.talleres, required this.onGuardar});

  @override
  State<_CrearAdminDialog> createState() => _CrearAdminDialogState();
}

class _CrearAdminDialogState extends State<_CrearAdminDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _tallerId;
  bool _guardando = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Nueva Cuenta Admin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Correo electrónico', border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v == null || v.isEmpty || !v.contains('@') ? 'Correo inválido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Contraseña', border: OutlineInputBorder()),
                obscureText: true,
                validator: (v) => v == null || v.length < 6 ? 'Mínimo 6 caracteres' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Asociar a taller', border: OutlineInputBorder()),
                initialValue: _tallerId,
                items: widget.talleres.map((t) => DropdownMenuItem(value: t.id, child: Text(t.nombre))).toList(),
                onChanged: (v) => setState(() => _tallerId = v),
                validator: (v) => v == null ? 'Seleccione un taller' : null,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _guardando ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    onPressed: _guardando
                        ? null
                        : () async {
                            if (!_formKey.currentState!.validate()) return;
                            setState(() => _guardando = true);
                            await widget.onGuardar(_email.text.trim(), _password.text, _tallerId!);
                            if (mounted) setState(() => _guardando = false);
                          },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.orangePrimary),
                    child: _guardando
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Guardar', style: TextStyle(color: Colors.white)),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
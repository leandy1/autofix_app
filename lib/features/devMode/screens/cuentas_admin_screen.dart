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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChange);
    _controller.cargarDatos();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  void _mostrarCrearAdmin() {
    if (_controller.talleres.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay talleres disponibles.')),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => _CrearAdminDialog(
        talleres: _controller.talleres,
        onGuardar: (email, password, tallerId) async {
          final ok = await _controller.crearCuentaAdmin(
            email: email,
            password: password,
            tallerId: tallerId,
          );
          if (!ctx.mounted) return;
          if (ok) {
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cuenta creada correctamente.')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_controller.error ?? 'Error')),
            );
          }
        },
      ),
    );
  }

  void _editarAdmin(Map<String, dynamic> admin) {
    if (_controller.talleres.isEmpty) return;
    final uid = admin['uid'] as String;
    String? tallerActual = admin['tallerId'] as String?;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        String? seleccionado = tallerActual;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Editar Admin'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Email: ${admin['email']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Taller asignado',
                    border: OutlineInputBorder(),
                  ),
                  value: _controller.talleres.any((t) => t.id == seleccionado)
                      ? seleccionado
                      : null,
                  items: _controller.talleres
                      .map(
                        (t) => DropdownMenuItem(
                          value: t.id,
                          child: Text(t.nombre),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => seleccionado = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orangePrimary,
                ),
                onPressed: seleccionado == null
                    ? null
                    : () async {
                        final ok = await _controller.editarAdmin(
                          uid,
                          seleccionado!,
                        );
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Taller actualizado.'
                                  : _controller.error ?? 'Error',
                            ),
                          ),
                        );
                      },
                child: const Text(
                  'Guardar',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _eliminarAdmin(Map<String, dynamic> admin) {
    final uid = admin['uid'] as String;
    final email = admin['email'] as String? ?? uid;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Admin'),
        content: Text(
          '¿Eliminar la cuenta de $email?\n\n'
          'Se eliminará del sistema, pero el usuario '
          'seguirá existiendo en Firebase Auth.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final ok = await _controller.eliminarAdmin(uid);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok ? 'Admin eliminado.' : _controller.error ?? 'Error',
                  ),
                ),
              );
            },
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.headerNavy,
        foregroundColor: Colors.white,
        title: const Text(
          'Cuentas Administrador',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Crear Admin',
            onPressed: _controller.cargando ? null : _mostrarCrearAdmin,
          ),
        ],
      ),
      body: _controller.cargando && _controller.admins.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _controller.admins.isEmpty
          ? const Center(
              child: Text(
                'No hay cuentas de admin.',
                style: TextStyle(color: AppColors.textGray),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _controller.admins.length,
              itemBuilder: (context, index) {
                final admin = _controller.admins[index];
                final taller = _controller.talleres
                    .where((t) => t.id == admin['tallerId'])
                    .firstOrNull;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.orangePrimary,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(
                      admin['email'] ?? 'Sin email',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Taller: ${taller?.nombre ?? 'Sin asignar'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.edit,
                            color: AppColors.orangePrimary,
                            size: 20,
                          ),
                          tooltip: 'Editar',
                          onPressed: () => _editarAdmin(admin),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: 20,
                          ),
                          tooltip: 'Eliminar',
                          onPressed: () => _eliminarAdmin(admin),
                        ),
                      ],
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
  final Future<void> Function(String email, String password, String tallerId)
  onGuardar;

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
              const Text(
                'Nueva Cuenta Admin',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v == null || v.isEmpty || !v.contains('@')
                    ? 'Correo inválido'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (v) =>
                    v == null || v.length < 6 ? 'Mínimo 6 caracteres' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Asociar a taller',
                  border: OutlineInputBorder(),
                ),
                value: _tallerId,
                items: widget.talleres
                    .map(
                      (t) =>
                          DropdownMenuItem(value: t.id, child: Text(t.nombre)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _tallerId = v),
                validator: (v) => v == null ? 'Seleccione un taller' : null,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _guardando
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _guardando
                        ? null
                        : () async {
                            if (!_formKey.currentState!.validate()) return;
                            setState(() => _guardando = true);
                            await widget.onGuardar(
                              _email.text.trim(),
                              _password.text,
                              _tallerId!,
                            );
                            if (mounted) setState(() => _guardando = false);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orangePrimary,
                    ),
                    child: _guardando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Guardar',
                            style: TextStyle(color: Colors.white),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

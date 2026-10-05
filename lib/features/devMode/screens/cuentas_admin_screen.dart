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
    setState(() {});
  }

  void _mostrarCrearAdmin() {
    if (_controller.talleres.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay talleres disponibles para asociar.')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => _CrearAdminDialog(
        talleres: _controller.talleres,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.headerNavy,
        foregroundColor: Colors.white,
        title: const Text('Cuentas Administrador', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _controller.admins.length,
              itemBuilder: (context, index) {
                final admin = _controller.admins[index];
                final tallerAsociado = _controller.talleres.where((t) => t.id == admin['tallerId']).firstOrNull;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.orangePrimary,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(admin['email'] ?? 'Sin email', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Taller: ${tallerAsociado?.nombre ?? 'Desconocido (${admin['tallerId']})'}'),
                    trailing: Text(admin['uid']?.toString().substring(0, 6) ?? '', style: const TextStyle(color: Colors.grey)),
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
                decoration: const InputDecoration(labelText: 'Correo electrnico', border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v == null || v.isEmpty || !v.contains('@') ? 'Correo invǭlido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Contrasea', border: OutlineInputBorder()),
                obscureText: true,
                validator: (v) => v == null || v.length < 6 ? 'Mnimo 6 caracteres' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Asociar a taller', border: OutlineInputBorder()),
                value: _tallerId,
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


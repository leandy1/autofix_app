import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:autofix/core/auth/credenciales_seguras.dart';
import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/data/limpieza_local.dart';
import 'package:autofix/core/database/semilla_inicial.dart';
import 'package:autofix/features/admin/screens/citas_admin_screen.dart';
import 'package:autofix/features/admin/screens/dashboard_admin_screen.dart';
import 'package:autofix/features/admin/screens/editar_perfil_admin_screen.dart';
import 'package:autofix/features/auth/screens/login_screen.dart';
import 'package:autofix/features/configuracion/models/grupo_servicio.dart';
import 'package:autofix/features/configuracion/models/marca.dart';
import 'package:autofix/features/configuracion/models/tecnico.dart';
import 'package:autofix/features/configuracion/models/tipo_servicio.dart';
import 'package:autofix/features/configuracion/presentation/configuracion_controller.dart';
import 'package:autofix/features/sync/sync_service.dart';
import 'package:autofix/shared/theme/app_colors.dart';

class ConfiguracionScreen extends StatefulWidget {
  final String? tallerId;

  const ConfiguracionScreen({super.key, this.tallerId});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  late final ConfiguracionController _cfg = ConfiguracionController(
    tallerId: widget.tallerId ?? SemillaInicial.talleres.first.id,
  );

  @override
  void initState() {
    super.initState();
    SyncService.instance.addListener(_alCambiarSync);
    _cfg.cargar();
  }

  @override
  void dispose() {
    SyncService.instance.removeListener(_alCambiarSync);
    _cfg.dispose();
    super.dispose();
  }

  void _alCambiarSync() {
    if (mounted) unawaited(_cfg.cargar(mostrarCarga: false));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildAppBar(),
        drawer: _buildDrawer(context),
        body: ListenableBuilder(
          listenable: _cfg,
          builder: (context, _) {
            if (_cfg.cargando) {
              return const Center(child: CircularProgressIndicator());
            }
            return TabBarView(
              children: <Widget>[
                _buildServiciosTab(),
                _buildTecnicosTab(),
                _buildCatalogosTab(),
              ],
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final taller = SesionAdmin.instance.tallerNombre ?? 'SISTEMA DE GESTIÓN';
    final email = SesionAdmin.instance.adminEmail ?? 'Admin';
    final inicial = email.isNotEmpty ? email[0].toUpperCase() : 'A';

    return AppBar(
      backgroundColor: AppColors.headerNavy,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'AutoFix',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              taller.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: CircleAvatar(
            backgroundColor: AppColors.orangePrimary,
            radius: 18,
            child: Text(
              inicial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
      bottom: const TabBar(
        indicatorColor: AppColors.orangePrimary,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white60,
        tabs: [
          Tab(icon: Icon(Icons.build_circle_outlined), text: 'Servicios'),
          Tab(icon: Icon(Icons.engineering_outlined), text: 'Técnicos'),
          Tab(icon: Icon(Icons.category_outlined), text: 'Catálogos'),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final taller = SesionAdmin.instance.tallerNombre ?? 'SISTEMA DE GESTIÓN';
    final email = SesionAdmin.instance.adminEmail ?? '';

    return Drawer(
      backgroundColor: AppColors.headerNavy,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AutoFix',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      taller,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.orangePrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _drawerItem(
              icon: Icons.grid_view_rounded,
              label: 'Dashboard',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DashboardScreen()),
              ),
            ),
            _drawerItem(
              icon: Icons.calendar_today_outlined,
              label: 'Citas',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const CitasScreen())),
            ),
            _drawerItem(
              icon: Icons.settings_outlined,
              label: 'Configuración',
              selected: true,
            ),
            _drawerItem(
              icon: Icons.manage_accounts_outlined,
              label: 'Editar Perfil',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const EditarPerfilAdminScreen(),
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: TextButton.icon(
                onPressed: _cerrarSesion,
                icon: const Icon(
                  Icons.logout,
                  size: 18,
                  color: Colors.redAccent,
                ),
                label: const Text(
                  'Cerrar Sesión',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cerrarSesion() async {
    await LimpiezaLocal.alCerrarSesion();
    await SesionAdmin.instance.cerrar();
    await CredencialesSeguras.borrar();
    await SyncService.instance.stop();
    try {
      await FirebaseAuth.instance.signOut();
      await FirebaseAuth.instance.signInAnonymously();
      await SyncService.instance.start();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    bool selected = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: selected
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color: selected ? AppColors.orangePrimary : Colors.white70,
          size: 20,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.orangePrimary : Colors.white70,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        shape: selected
            ? const Border(
                left: BorderSide(color: AppColors.orangePrimary, width: 3),
              )
            : null,
      ),
    );
  }

  Widget _tabScroll(List<Widget> children) => RefreshIndicator(
    onRefresh: _cfg.cargar,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: children,
    ),
  );

  Widget _intro({required String title, required String description}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            description,
            style: const TextStyle(color: AppColors.textGray, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _panel({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(14),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _addButton(String label, VoidCallback onPressed) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.orangePrimary,
        side: const BorderSide(color: AppColors.orangePrimary),
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
    ),
  );

  Widget _empty(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        const Icon(
          Icons.inbox_outlined,
          size: 36,
          color: AppColors.placeholderGray,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
      ],
    ),
  );

  Widget _fila({
    required String nombre,
    required String? detalle,
    required IconData icon,
    required VoidCallback editar,
    required VoidCallback eliminar,
  }) {
    return Card(
      color: AppColors.cardWhite,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE9EBEF)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.orangePrimary.withValues(alpha: 0.12),
          child: Icon(icon, color: AppColors.orangePrimary, size: 20),
        ),
        title: Text(
          nombre,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: detalle == null ? null : Text(detalle),
        trailing: Wrap(
          spacing: 2,
          children: [
            IconButton(
              tooltip: 'Editar $nombre',
              onPressed: editar,
              icon: const Icon(Icons.edit_outlined),
              color: AppColors.textGray,
            ),
            IconButton(
              tooltip: 'Eliminar $nombre',
              onPressed: eliminar,
              icon: const Icon(Icons.delete_outline),
              color: Colors.redAccent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiciosTab() => _tabScroll([
    _intro(
      title: 'Servicios y precios',
      description: 'Administra lo que ofrece el taller y el precio vigente.',
    ),
    _panel(
      title: 'Catálogo de servicios',
      child: Column(
        children: [
          _addButton('Agregar servicio', () => unawaited(_editarServicio())),
          const SizedBox(height: 12),
          if (_cfg.tiposServicio.isEmpty)
            _empty('Aún no hay servicios configurados para este taller.')
          else
            for (final servicio in _cfg.tiposServicio)
              _fila(
                nombre: servicio.nombre,
                detalle: _cfg.formatearPrecio(servicio.precio),
                icon: Icons.build_outlined,
                editar: () => unawaited(_editarServicio(servicio)),
                eliminar: () => unawaited(
                  _confirmarEliminar(
                    nombre: servicio.nombre,
                    accion: () => _cfg.eliminarTipoServicio(servicio.id!),
                  ),
                ),
              ),
        ],
      ),
    ),
  ]);

  Widget _buildTecnicosTab() => _tabScroll([
    _intro(
      title: 'Personal técnico',
      description: 'Mantén actualizado el equipo disponible para las citas.',
    ),
    _panel(
      title: 'Técnicos',
      child: Column(
        children: [
          _addButton('Agregar técnico', () => unawaited(_editarTecnico())),
          const SizedBox(height: 12),
          if (_cfg.tecnicos.isEmpty)
            _empty('Aún no hay técnicos configurados para este taller.')
          else
            for (final tecnico in _cfg.tecnicos)
              _fila(
                nombre: tecnico.nombre,
                detalle: tecnico.activo ? 'Disponible' : 'No disponible',
                icon: Icons.engineering_outlined,
                editar: () => unawaited(_editarTecnico(tecnico)),
                eliminar: () => unawaited(
                  _confirmarEliminar(
                    nombre: tecnico.nombre,
                    accion: () => _cfg.eliminarTecnico(tecnico.id!),
                  ),
                ),
              ),
        ],
      ),
    ),
  ]);

  Widget _buildCatalogosTab() => _tabScroll([
    _intro(
      title: 'Catálogos del taller',
      description: 'Organiza las marcas de vehículos y los grupos de servicio.',
    ),
    _panel(
      title: 'Marcas de vehículo',
      child: Column(
        children: [
          _addButton('Agregar marca', () => unawaited(_editarMarca())),
          const SizedBox(height: 12),
          if (_cfg.marcas.isEmpty)
            _empty('Aún no hay marcas registradas.')
          else
            for (final marca in _cfg.marcas)
              _fila(
                nombre: marca.nombre,
                detalle: null,
                icon: Icons.directions_car_outlined,
                editar: () => unawaited(_editarMarca(marca)),
                eliminar: () => unawaited(
                  _confirmarEliminar(
                    nombre: marca.nombre,
                    accion: () => _cfg.eliminarMarca(marca.id!),
                  ),
                ),
              ),
        ],
      ),
    ),
    _panel(
      title: 'Grupos de servicios',
      child: Column(
        children: [
          _addButton('Agregar grupo', () => unawaited(_editarGrupo())),
          const SizedBox(height: 12),
          if (_cfg.gruposServicio.isEmpty)
            _empty('Aún no hay grupos de servicios.')
          else
            for (final grupo in _cfg.gruposServicio)
              _fila(
                nombre: grupo.nombre,
                detalle: null,
                icon: Icons.folder_outlined,
                editar: () => unawaited(_editarGrupo(grupo)),
                eliminar: () => unawaited(
                  _confirmarEliminar(
                    nombre: grupo.nombre,
                    accion: () => _cfg.eliminarGrupoServicio(grupo.id!),
                  ),
                ),
              ),
        ],
      ),
    ),
  ]);

  Future<void> _editarServicio([TipoServicio? servicio]) async {
    final guardado = await _mostrarEditor(
      titulo: servicio == null ? 'Nuevo servicio' : 'Editar servicio',
      nombreInicial: servicio?.nombre ?? '',
      precioInicial: servicio?.precio.toString() ?? '',
      requierePrecio: true,
      guardar: (nombre, precio) => servicio == null
          ? _cfg.guardarTipoServicio(nombre, precio)
          : _cfg.editarTipoServicio(servicio.id!, nombre, precio),
    );
    if (guardado) {
      _mostrarExito(
        servicio == null ? 'Servicio guardado.' : 'Servicio actualizado.',
      );
    }
  }

  Future<void> _editarTecnico([Tecnico? tecnico]) async {
    final guardado = await _mostrarEditor(
      titulo: tecnico == null ? 'Nuevo técnico' : 'Editar técnico',
      nombreInicial: tecnico?.nombre ?? '',
      guardar: (nombre, _) => tecnico == null
          ? _cfg.guardarTecnico(nombre)
          : _cfg.editarTecnico(tecnico.id!, nombre),
    );
    if (guardado) {
      _mostrarExito(
        tecnico == null ? 'Técnico guardado.' : 'Técnico actualizado.',
      );
    }
  }

  Future<void> _editarMarca([Marca? marca]) async {
    final guardado = await _mostrarEditor(
      titulo: marca == null ? 'Nueva marca' : 'Editar marca',
      nombreInicial: marca?.nombre ?? '',
      guardar: (nombre, _) => marca == null
          ? _cfg.guardarMarca(nombre)
          : _cfg.editarMarca(marca.id!, nombre),
    );
    if (guardado) {
      _mostrarExito(marca == null ? 'Marca guardada.' : 'Marca actualizada.');
    }
  }

  Future<void> _editarGrupo([GrupoServicio? grupo]) async {
    final guardado = await _mostrarEditor(
      titulo: grupo == null ? 'Nuevo grupo' : 'Editar grupo',
      nombreInicial: grupo?.nombre ?? '',
      guardar: (nombre, _) => grupo == null
          ? _cfg.guardarGrupoServicio(nombre)
          : _cfg.editarGrupoServicio(grupo.id!, nombre),
    );
    if (guardado) {
      _mostrarExito(grupo == null ? 'Grupo guardado.' : 'Grupo actualizado.');
    }
  }

  Future<bool> _mostrarEditor({
    required String titulo,
    required String nombreInicial,
    String precioInicial = '',
    required Future<bool> Function(String nombre, String? precio) guardar,
    bool requierePrecio = false,
  }) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (_) => _CatalogoEditorDialog(
        titulo: titulo,
        nombreInicial: nombreInicial,
        precioInicial: precioInicial,
        requierePrecio: requierePrecio,
        errorActual: () => _cfg.error,
        guardar: guardar,
      ),
    );
    return resultado == true;
  }

  Future<void> _confirmarEliminar({
    required String nombre,
    required Future<bool> Function() accion,
  }) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
        title: const Text('Confirmar eliminación'),
        content: Text(
          '¿Estás seguro de que deseas eliminar "$nombre"? '
          'Las citas históricas no se verán afectadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    final eliminado = await accion();
    if (!mounted) return;
    if (eliminado) {
      _mostrarExito('Se eliminó "$nombre".');
    } else {
      _mostrarError(_cfg.error ?? 'No se pudo eliminar el registro.');
    }
  }

  void _mostrarExito(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(mensaje), backgroundColor: Colors.red.shade700),
      );
  }
}

class _CatalogoEditorDialog extends StatefulWidget {
  const _CatalogoEditorDialog({
    required this.titulo,
    required this.nombreInicial,
    required this.precioInicial,
    required this.requierePrecio,
    required this.errorActual,
    required this.guardar,
  });

  final String titulo;
  final String nombreInicial;
  final String precioInicial;
  final bool requierePrecio;
  final String? Function() errorActual;
  final Future<bool> Function(String nombre, String? precio) guardar;

  @override
  State<_CatalogoEditorDialog> createState() => _CatalogoEditorDialogState();
}

class _CatalogoEditorDialogState extends State<_CatalogoEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _precioController;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.nombreInicial);
    _precioController = TextEditingController(text: widget.precioInicial);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _precioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nombreController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                validator: (valor) => valor?.trim().isNotEmpty == true
                    ? null
                    : 'El nombre es obligatorio.',
              ),
              if (widget.requierePrecio) ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: _precioController,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: false,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Precio (RD\$)',
                    prefixIcon: Icon(Icons.payments_outlined),
                    helperText: 'Usa un monto entero igual o mayor que cero.',
                  ),
                  validator: (valor) =>
                      ConfiguracionController.leerPrecio(valor) == null
                      ? 'Ingresa un precio válido, no negativo.'
                      : null,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _guardando ? null : _guardar,
          icon: _guardando
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: const Text('Guardar'),
        ),
      ],
    );
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    final guardado = await widget.guardar(
      _nombreController.text.trim(),
      widget.requierePrecio ? _precioController.text : null,
    );
    if (!mounted) return;
    if (guardado) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _error = widget.errorActual() ?? 'No se pudo guardar el registro.';
      });
    }
  }
}

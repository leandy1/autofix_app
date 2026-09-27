import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'dashboard_screen.dart';
import 'citas_screen.dart';
import 'login_screen.dart';

/// Un servicio individual con su nombre y precio (ej: "Cambio de aceite y filtro", RD$800).
class ServicioItem {
  String nombre;
  double precio;
  ServicioItem({required this.nombre, required this.precio});
}

/// Un grupo de servicios (ej: "Carrocería"), que contiene varios ServicioItem.
class GrupoServicio {
  String nombre;
  List<ServicioItem> servicios;
  bool expandido;
  GrupoServicio({required this.nombre, List<ServicioItem>? servicios, this.expandido = true})
      : servicios = servicios ?? [];
}

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  // ---------------------------------------------------------------------
  // Todas las listas empiezan VACÍAS a propósito. La pantalla es funcional
  // (agregar/eliminar funciona de verdad), pero sin datos de ejemplo.
  // ---------------------------------------------------------------------
  final List<ServicioItem> _tiposServicio = [];
  final List<String> _tecnicos = [];
  final List<String> _estados = [];
  final List<String> _marcasVehiculo = [];
  final List<GrupoServicio> _gruposServicios = [];

  // Controladores de los campos "Agregar..." de cada sección.
  final TextEditingController _nombreServicioController = TextEditingController();
  final TextEditingController _precioServicioController = TextEditingController();
  final TextEditingController _tecnicoController = TextEditingController();
  final TextEditingController _estadoController = TextEditingController();
  final TextEditingController _marcaController = TextEditingController();
  final TextEditingController _grupoController = TextEditingController();

  @override
  void dispose() {
    _nombreServicioController.dispose();
    _precioServicioController.dispose();
    _tecnicoController.dispose();
    _estadoController.dispose();
    _marcaController.dispose();
    _grupoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      drawer: _buildDrawer(context),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Configuración del Sistema',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textDark)),
            const SizedBox(height: 16),
            _buildTiposDeServicioCard(),
            const SizedBox(height: 16),
            _buildListaSimpleCard(
              titulo: 'Técnicos',
              hint: 'Ej: Juan Pérez',
              controller: _tecnicoController,
              lista: _tecnicos,
              onAgregar: (valor) => setState(() => _tecnicos.add(valor)),
              onEliminar: (index) => setState(() => _tecnicos.removeAt(index)),
            ),
            const SizedBox(height: 16),
            _buildListaSimpleCard(
              titulo: 'Estados',
              hint: 'Ej: En diagnóstico',
              controller: _estadoController,
              lista: _estados,
              onAgregar: (valor) => setState(() => _estados.add(valor)),
              onEliminar: (index) => setState(() => _estados.removeAt(index)),
            ),
            const SizedBox(height: 16),
            _buildListaSimpleCard(
              titulo: 'Marcas de Vehículo',
              hint: 'Ej: Nissan',
              controller: _marcaController,
              lista: _marcasVehiculo,
              onAgregar: (valor) => setState(() => _marcasVehiculo.add(valor)),
              onEliminar: (index) => setState(() => _marcasVehiculo.removeAt(index)),
            ),
            const SizedBox(height: 16),
            _buildGruposDeServiciosCard(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // AppBar + Drawer (mismos que en el resto de las pantallas).
  // ---------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.headerNavy,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: 0,
      title: const Padding(
        padding: EdgeInsets.only(left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('AutoFix', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            Text('SISTEMA DE GESTIÓN',
                style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: CircleAvatar(
            backgroundColor: AppColors.orangePrimary,
            radius: 18,
            child: const Text('L', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.headerNavy,
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AutoFix', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    Text('SISTEMA DE GESTIÓN', style: TextStyle(color: Colors.white60, fontSize: 11)),
                  ],
                ),
              ),
            ),
            _drawerItem(
              icon: Icons.grid_view_rounded,
              label: 'Dashboard',
              selected: false,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DashboardScreen())),
            ),
            _drawerItem(
              icon: Icons.calendar_today_outlined,
              label: 'Citas',
              selected: false,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CitasScreen())),
            ),
            _drawerItem(icon: Icons.settings_outlined, label: 'Configuración', selected: true),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.logout, size: 18, color: Colors.redAccent),
                label: const Text('Cerrar Sesión', style: TextStyle(color: Colors.redAccent)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    return Container(
      color: selected ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: selected ? AppColors.orangePrimary : Colors.white70, size: 20),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.orangePrimary : Colors.white70,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        shape: selected ? const Border(left: BorderSide(color: AppColors.orangePrimary, width: 3)) : null,
      ),
    );
  }

  /// Contenedor blanco reutilizable para cada sección de configuración.
  Widget _sectionCard({required String titulo, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  /// Campo de texto + botón "Agregar" reutilizable, con el mismo estilo del
  /// boceto (input con borde gris claro, botón naranja al lado).
  Widget _buildCampoAgregar({
    required TextEditingController controller,
    required String hint,
    required VoidCallback onAgregar,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.placeholderGray, fontSize: 13),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.inputBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.orangePrimary, width: 1.5),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: onAgregar,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orangePrimary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Agregar', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Sección "Tipos de Servicio" — tiene nombre + precio (dos campos).
  // ---------------------------------------------------------------------

  Widget _buildTiposDeServicioCard() {
    return _sectionCard(
      titulo: 'Tipos de Servicio',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nombreServicioController,
            decoration: InputDecoration(
              hintText: 'Ej: Cambio de frenos',
              hintStyle: const TextStyle(color: AppColors.placeholderGray, fontSize: 13),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.inputBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.orangePrimary, width: 1.5),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _precioServicioController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Precio RD\$',
                    hintStyle: const TextStyle(color: AppColors.placeholderGray, fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.inputBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.orangePrimary, width: 1.5),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _agregarTipoServicio,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orangePrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Agregar', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_tiposServicio.isEmpty)
            _textoVacio('No hay tipos de servicio registrados aún.')
          else
            ..._tiposServicio.asMap().entries.map((entry) {
              final index = entry.key;
              final servicio = entry.value;
              return _filaItemConPrecio(
                nombre: servicio.nombre,
                precio: servicio.precio,
                onEliminar: () => setState(() => _tiposServicio.removeAt(index)),
              );
            }),
        ],
      ),
    );
  }

  void _agregarTipoServicio() {
    final nombre = _nombreServicioController.text.trim();
    final precioTexto = _precioServicioController.text.trim();
    if (nombre.isEmpty || precioTexto.isEmpty) return;
    final precio = double.tryParse(precioTexto) ?? 0;
    setState(() {
      _tiposServicio.add(ServicioItem(nombre: nombre, precio: precio));
      _nombreServicioController.clear();
      _precioServicioController.clear();
    });
  }

  // ---------------------------------------------------------------------
  // Secciones simples (Técnicos, Estados, Marcas de Vehículo): un solo
  // campo de texto + lista con botón de eliminar.
  // ---------------------------------------------------------------------

  Widget _buildListaSimpleCard({
    required String titulo,
    required String hint,
    required TextEditingController controller,
    required List<String> lista,
    required void Function(String valor) onAgregar,
    required void Function(int index) onEliminar,
  }) {
    return _sectionCard(
      titulo: titulo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCampoAgregar(
            controller: controller,
            hint: hint,
            onAgregar: () {
              final valor = controller.text.trim();
              if (valor.isEmpty) return;
              onAgregar(valor);
              controller.clear();
            },
          ),
          const SizedBox(height: 12),
          if (lista.isEmpty)
            _textoVacio('No hay elementos registrados aún.')
          else
            ...lista.asMap().entries.map((entry) => _filaItemSimple(
                  nombre: entry.value,
                  onEliminar: () => onEliminar(entry.key),
                )),
        ],
      ),
    );
  }

  Widget _textoVacio(String mensaje) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(mensaje, style: const TextStyle(color: AppColors.textGray, fontSize: 13)),
    );
  }

  Widget _filaItemSimple({required String nombre, required VoidCallback onEliminar}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F1F3))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(nombre, style: const TextStyle(fontSize: 13, color: AppColors.textDark)),
          InkWell(
            onTap: onEliminar,
            child: const Icon(Icons.close, size: 16, color: Colors.redAccent),
          ),
        ],
      ),
    );
  }

  Widget _filaItemConPrecio({required String nombre, required double precio, required VoidCallback onEliminar}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F1F3))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(nombre, style: const TextStyle(fontSize: 13, color: AppColors.textDark)),
          Row(
            children: [
              Text('RD\$ ${precio.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, color: AppColors.textGray)),
              const SizedBox(width: 10),
              InkWell(
                onTap: onEliminar,
                child: const Icon(Icons.close, size: 16, color: Colors.redAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Sección "Grupos de Servicios": cada grupo es una tarjeta expandible que
  // contiene una sublista de servicios (tomados de "Tipos de Servicio").
  // ---------------------------------------------------------------------

  Widget _buildGruposDeServiciosCard() {
    return _sectionCard(
      titulo: 'Grupos de Servicios',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCampoAgregar(
            controller: _grupoController,
            hint: 'Ej: Electricidad',
            onAgregar: () {
              final nombre = _grupoController.text.trim();
              if (nombre.isEmpty) return;
              setState(() {
                _gruposServicios.add(GrupoServicio(nombre: nombre));
                _grupoController.clear();
              });
            },
          ),
          const SizedBox(height: 12),
          if (_gruposServicios.isEmpty)
            _textoVacio('No hay grupos de servicios creados aún.')
          else
            ..._gruposServicios.asMap().entries.map((entry) => _buildGrupoAcordeon(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _buildGrupoAcordeon(int indexGrupo, GrupoServicio grupo) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(grupo.nombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            leading: InkWell(
              onTap: () => setState(() => grupo.expandido = !grupo.expandido),
              child: AnimatedRotation(
                turns: grupo.expandido ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.keyboard_arrow_down, color: AppColors.textGray),
              ),
            ),
            trailing: InkWell(
              onTap: () => setState(() => _gruposServicios.removeAt(indexGrupo)),
              child: const Icon(Icons.close, size: 18, color: Colors.redAccent),
            ),
          ),
          if (grupo.expandido) ...[
            if (grupo.servicios.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: _textoVacio('Este grupo aún no tiene servicios.'),
              )
            else
              ...grupo.servicios.asMap().entries.map((entry) {
                final indexServicio = entry.key;
                final servicio = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _filaItemConPrecio(
                    nombre: servicio.nombre,
                    precio: servicio.precio,
                    onEliminar: () => setState(() => grupo.servicios.removeAt(indexServicio)),
                  ),
                );
              }),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _abrirSelectorDeServicios(grupo),
                  icon: const Icon(Icons.add, size: 16, color: AppColors.orangePrimary),
                  label: const Text('Agregar Servicio', style: TextStyle(color: AppColors.orangePrimary, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Abre la ventana modal (como en tu captura 3) para elegir, con checkboxes,
  /// cuáles servicios de "Tipos de Servicio" se agregan a este grupo.
  Future<void> _abrirSelectorDeServicios(GrupoServicio grupo) async {
    if (_tiposServicio.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero agrega servicios en "Tipos de Servicio".')),
      );
      return;
    }

    // Copia local de selección, para no modificar nada hasta presionar "Confirmar".
    final Set<String> seleccionados = {};

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Seleccionar Servicios',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                      const SizedBox(height: 12),
                      ..._tiposServicio.map((servicio) {
                        final yaEstaEnGrupo = grupo.servicios.any((s) => s.nombre == servicio.nombre);
                        final marcado = seleccionados.contains(servicio.nombre);
                        return CheckboxListTile(
                          value: marcado,
                          onChanged: yaEstaEnGrupo
                              ? null // ya está en el grupo, no se puede volver a marcar
                              : (checked) {
                                  setDialogState(() {
                                    if (checked == true) {
                                      seleccionados.add(servicio.nombre);
                                    } else {
                                      seleccionados.remove(servicio.nombre);
                                    }
                                  });
                                },
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            servicio.nombre,
                            style: TextStyle(fontSize: 14, color: yaEstaEnGrupo ? AppColors.textGray : AppColors.textDark),
                          ),
                          secondary: Text('RD\$ ${servicio.precio.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 13, color: AppColors.textGray)),
                        );
                      }),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancelar', style: TextStyle(color: AppColors.textGray)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: seleccionados.isEmpty
                                ? null
                                : () {
                                    setState(() {
                                      for (final nombre in seleccionados) {
                                        final servicio = _tiposServicio.firstWhere((s) => s.nombre == nombre);
                                        grupo.servicios.add(ServicioItem(nombre: servicio.nombre, precio: servicio.precio));
                                      }
                                    });
                                    Navigator.of(context).pop();
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.orangePrimary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: AppColors.orangePrimary.withValues(alpha: 0.4),
                              elevation: 0,
                            ),
                            child: const Text('Confirmar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
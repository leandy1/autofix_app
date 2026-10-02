import 'package:flutter/material.dart';

import '../../models/demo_admin_data.dart';
import '../../models/vehicle_make.dart';
import '../../services/car_api_service.dart';
import '../../services/vehicle_catalog_service.dart';
import '../../theme/app_colors.dart';
import 'dashboard_admin_screen.dart';
import 'citas_admin_screen.dart';
import '../auth/login_screen.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  // Controladores solo para que los campos de texto funcionen visualmente.
  // Los botones "Agregar" no guardan nada — eso se conecta en otro archivo.
  final TextEditingController _nombreServicioController = TextEditingController();
  final TextEditingController _precioServicioController = TextEditingController();
  final TextEditingController _tecnicoController = TextEditingController();
  final TextEditingController _estadoController = TextEditingController();
  final TextEditingController _marcaController = TextEditingController();
  final TextEditingController _grupoController = TextEditingController();
final CarApiService _carApiService = CarApiService();  late final VehicleCatalogService _vehicleCatalogService =      VehicleCatalogService(carApi: _carApiService);  List<VehicleMake> _marcasDisponibles = [];  bool _cargandoMarcas = false;  String? _errorMarcas;

  // Solo para la demo visual del acordeón "Grupos de Servicios".
  bool _grupoDemoExpandido = true;

  @override
  void initState() {
    super.initState();
    _cargarMarcas();
  }

  Future<void> _cargarMarcas() async {
    setState(() {
      _cargandoMarcas = true;
      _errorMarcas = null;
    });

    try {
      final marcas = await _vehicleCatalogService.getMakes();
      if (!mounted) return;
      setState(() {
        _marcasDisponibles = marcas;
        _cargandoMarcas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMarcas = 'No se pudieron cargar las marcas.';
        _cargandoMarcas = false;
      });
    }
  }

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
              items: demoTecnicosConfiguracion,
            ),
            const SizedBox(height: 16),
            _buildListaSimpleCard(
              titulo: 'Estados',
              hint: 'Ej: En diagnóstico',
              controller: _estadoController,
              items: demoEstadosConfiguracion,
            ),
            const SizedBox(height: 16),
            _buildMarcasVehiculoCard(),
            const SizedBox(height: 16),
            _buildGruposDeServiciosCard(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // AppBar + Drawer
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

  /// Usa Material (no Container) para que el ListTile no lance el warning
  /// de "background color or ink splashes may be invisible".
  Widget _drawerItem({
    required IconData icon,
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    return Material(
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

  /// Contenedor blanco reutilizable para cada sección.
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

  /// Campo de texto + botón "Agregar" — el botón no hace nada por ahora,
  /// solo está ahí para que se vea y se sienta el diseño completo.
  Widget _buildCampoAgregar({required TextEditingController controller, required String hint}) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: _decoracionInput(hint),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () {}, // Sin lógica: la conexión con datos se hace en otro archivo.
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

  InputDecoration _decoracionInput(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.placeholderGray, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.inputBorder)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.orangePrimary, width: 1.5)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  // ---------------------------------------------------------------------
  // "Tipos de Servicio" — el formulario y el listado usan datos de demostración.
  // ---------------------------------------------------------------------

  Widget _buildTiposDeServicioCard() {
    return _sectionCard(
      titulo: 'Tipos de Servicio',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(controller: _nombreServicioController, decoration: _decoracionInput('Ej: Cambio de frenos')),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _precioServicioController,
                  keyboardType: TextInputType.number,
                  decoration: _decoracionInput('Precio RD\$'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {}, // Sin lógica.
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
          for (final servicio in demoServiciosAdmin)
            _filaItemDemo(nombre: servicio.nombre, precio: servicio.precio),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Secciones simples: Técnicos, Estados, Marcas de Vehículo.
  // ---------------------------------------------------------------------

  Widget _buildMarcasVehiculoCard() {
    return _sectionCard(
      titulo: 'Marcas de Vehículo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCampoAgregar(controller: _marcaController, hint: 'Ej: Nissan'),
          const SizedBox(height: 12),
          if (_cargandoMarcas)
            const Center(child: CircularProgressIndicator())
          else if (_errorMarcas != null)
            Text(
              _errorMarcas!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            )
          else
            for (final marca in _marcasDisponibles)
              _filaItemDemo(nombre: marca.name),
        ],
      ),
    );
  }

  Widget _buildListaSimpleCard({
    required String titulo,
    required String hint,
    required TextEditingController controller,
    required List<String> items,
  }) {
    return _sectionCard(
      titulo: titulo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCampoAgregar(controller: controller, hint: hint),
          const SizedBox(height: 12),
          for (final item in items) _filaItemDemo(nombre: item),
        ],
      ),
    );
  }

  Widget _filaItemDemo({required String nombre, String? precio}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F1F3)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(nombre, style: const TextStyle(fontSize: 13, color: AppColors.textDark)),
          Row(
            children: [
              if (precio != null) ...[
                Text(precio, style: const TextStyle(fontSize: 13, color: AppColors.textGray)),
                const SizedBox(width: 10),
              ],
              const Icon(Icons.close, size: 16, color: Colors.redAccent),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // "Grupos de Servicios" — se deja UNA tarjeta de ejemplo fija (no una
  // lista real) solo para mostrar cómo se ve un grupo expandido, con su
  // acordeón funcionando (abrir/cerrar) y el modal de selección de
  // servicios abriendo y cerrando.
  // ---------------------------------------------------------------------

  Widget _buildGruposDeServiciosCard() {
    return _sectionCard(
      titulo: 'Grupos de Servicios',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCampoAgregar(controller: _grupoController, hint: 'Ej: Electricidad'),
          const SizedBox(height: 12),
          _buildGrupoDemoAcordeon(),
        ],
      ),
    );
  }

  Widget _buildGrupoDemoAcordeon() {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          ListTile(
            title: Text(
              demoGruposServiciosAdmin.first.nombre,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            leading: InkWell(
              onTap: () => setState(() => _grupoDemoExpandido = !_grupoDemoExpandido),
              child: AnimatedRotation(
                turns: _grupoDemoExpandido ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.keyboard_arrow_down, color: AppColors.textGray),
              ),
            ),
            trailing: const Icon(Icons.close, size: 18, color: Colors.redAccent),
          ),
          if (_grupoDemoExpandido) ...[
            for (final servicio in demoGruposServiciosAdmin.first.servicios)
              _filaItemDemo(
                nombre: servicio.nombre,
                precio: servicio.precio,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _abrirSelectorDeServiciosDemo,
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

  /// Modal de ejemplo "Seleccionar Servicios" — los checkboxes se pueden
  /// marcar/desmarcar (interacción básica), pero "Confirmar" solo cierra
  /// el modal, no guarda nada.
  void _abrirSelectorDeServiciosDemo() {
    final Set<String> seleccionados = {};
    showDialog(
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
                      ...demoServiciosAdmin.map((servicio) {
                        final marcado = seleccionados.contains(servicio.nombre);
                        return CheckboxListTile(
                          value: marcado,
                          onChanged: (checked) {
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
                            style: const TextStyle(fontSize: 14),
                          ),
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
                            onPressed: () => Navigator.of(context).pop(), // Solo cierra, no guarda.
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.orangePrimary,
                              foregroundColor: Colors.white,
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
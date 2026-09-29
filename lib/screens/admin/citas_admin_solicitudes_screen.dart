import 'package:flutter/material.dart';

import '../../models/demo_admin_data.dart';
import '../../models/solicitud_admin.dart';
import '../../models/vehicle_make.dart';
import '../../theme/app_colors.dart';
import '../../widgets/admin/solicitudes_admin_section.dart';
import '../../services/car_api_service.dart';
import '../../services/solicitudes_admin_service.dart';
import '../../services/vehicle_catalog_service.dart';
import '../auth/login_screen.dart';
import 'dashboard_admin_screen.dart';
import 'configuracion_admin_screen.dart';

const Map<String, Color> kColorPorEstado = {
  'ATRASADAS': AppColors.atrasadas,
  'Pendiente': AppColors.pendientes,
  'Esperando Pieza': AppColors.esperandoPieza,
  'En proceso': AppColors.enProceso,
  'Completado': AppColors.completado,
};

class CitasSolicitudesAdminScreen extends StatefulWidget {
  const CitasSolicitudesAdminScreen({super.key});

  @override
  State<CitasSolicitudesAdminScreen> createState() => _CitasSolicitudesAdminScreenState();
}

class _CitasSolicitudesAdminScreenState extends State<CitasSolicitudesAdminScreen> {
  final SolicitudesAdminService _solicitudesService =
      SolicitudesAdminService();

  final VehicleCatalogService _vehicleCatalogService =
      VehicleCatalogService(
    carApi: CarApiService(),
  );
  DateTime _fechaSeleccionada = DateTime.now();
  bool _filtrosExpandido = false;
  String? _categoriaExpandida = 'En proceso';

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
            _buildHeroCard(),
            const SizedBox(height: 16),
            SolicitudesAdminSection(service: _solicitudesService),
            const SizedBox(height: 16),
            _buildFiltrosAvanzados(),
            const SizedBox(height: 16),
            for (final categoria in kColorPorEstado.keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildEstadoAccordion(
                  nombre: categoria,
                  color: kColorPorEstado[categoria]!,
                  expanded: _categoriaExpandida == categoria,
                  onTap: () => setState(() {
                    _categoriaExpandida = _categoriaExpandida == categoria
                        ? null
                        : categoria;
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }

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
            Text(
              'AutoFix',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'SISTEMA DE GESTIÓN',
              style: TextStyle(
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
            child: const Text(
              'L',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
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
                    Text(
                      'AutoFix',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'SISTEMA DE GESTIÓN',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            _drawerItem(
              icon: Icons.grid_view_rounded,
              label: 'Dashboard',
              selected: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DashboardScreen()),
              ),
            ),
            _drawerItem(
              icon: Icons.calendar_today_outlined,
              label: 'Citas',
              selected: true,
            ),
            _drawerItem(
              icon: Icons.settings_outlined,
              label: 'Configuración',
              selected: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConfiguracionScreen()),
              ),
            ),
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

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required bool selected,
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

  Widget _buildHeroCard() {
    final bool esHoy = _esMismoDia(_fechaSeleccionada, DateTime.now());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.headerNavy,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CITAS DE',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            esHoy ? 'Hoy' : _formatearFechaLarga(_fechaSeleccionada),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _navCircleButton(
                Icons.chevron_left,
                onTap: () {
                  setState(
                    () => _fechaSeleccionada = _fechaSeleccionada.subtract(
                      const Duration(days: 1),
                    ),
                  );
                },
              ),
              _buildCampoFechaHero(),
              _navCircleButton(
                Icons.chevron_right,
                onTap: () {
                  setState(
                    () => _fechaSeleccionada = _fechaSeleccionada.add(
                      const Duration(days: 1),
                    ),
                  );
                },
              ),
              ElevatedButton.icon(
                onPressed: _abrirFormularioNuevaCita,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nueva'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orangePrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCampoFechaHero() {
    return InkWell(
      onTap: () async {
        final nuevaFecha = await showDatePicker(
          context: context,
          initialDate: _fechaSeleccionada,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (nuevaFecha != null) setState(() => _fechaSeleccionada = nuevaFecha);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 40,
        constraints: const BoxConstraints(minWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatearFechaCorta(_fechaSeleccionada),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.calendar_today_outlined,
              color: Colors.white54,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navCircleButton(IconData icon, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white38),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
    );
  }

  Widget _buildFiltrosAvanzados() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _filtrosExpandido = !_filtrosExpandido),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_alt_outlined,
                    size: 18,
                    color: AppColors.textGray,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Filtros avanzados',
                      style: TextStyle(color: AppColors.textGray, fontSize: 14),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _filtrosExpandido ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _filtrosExpandido
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Buscar por cliente, vehículo o placa...',
                  hintStyle: const TextStyle(
                    color: AppColors.placeholderGray,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 18,
                    color: AppColors.textGray,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.inputBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppColors.orangePrimary,
                      width: 1.5,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            secondChild: const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoAccordion({
    required String nombre,
    required Color color,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    final solicitudes = switch (nombre) {
      'ATRASADAS' => _solicitudesService.atrasadas,
      'Pendiente' => _solicitudesService.pendientes,
      'Esperando Pieza' => _solicitudesService.esperandoPieza,
      'En proceso' => _solicitudesService.enProceso,
      'Completado' => _solicitudesService.completadas,
      _ => const <SolicitudAdmin>[],
    };

    final cantidadVisible = solicitudes.length;

    return Column(
      children: [
        Material(
          color: color,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      nombre.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    child: Text(
                      '$cantidadVisible',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: solicitudes.isEmpty
                ? const Text(
                    'No hay solicitudes en este estado.',
                    style: TextStyle(
                      color: AppColors.textGray,
                      fontSize: 13,
                    ),
                  )
                : Column(
                    children: [
                      for (final solicitud in solicitudes)
                        _SolicitudEstadoAdminCard(
                          solicitud: solicitud,
                          puedeCompletar: nombre != 'Completado',
                          onCompletar: () {
                            final resultado =
                                _solicitudesService.completarSolicitud(
                              solicitud.id,
                            );

                            if (resultado) {
                              setState(() {});

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Solicitud marcada como completada.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                    ],
                  ),
          ),
          secondChild: const SizedBox(
            width: double.infinity,
            height: 0,
          ),
        ),
      ],
    );
  }


  Widget _tituloSeccionModal(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textGray,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  void _abrirFormularioNuevaCita() {
    final clienteController = TextEditingController();
    final telefonoController = TextEditingController();
    final anioController = TextEditingController();
    final placaController = TextEditingController();
    final descripcionController = TextEditingController();

    String? marcaSeleccionada;
    String? modeloSeleccionado;
    String? tecnicoSeleccionado;
    String estadoSeleccionado = 'Pendiente';

    DateTime fecha = DateTime.now();
    TimeOfDay? hora;

    List<VehicleMake> marcas = [];
    List<String> modelos = [];

    bool cargandoMarcas = true;
    bool cargandoModelos = false;

    String? errorMarcas;
    String? errorModelos;

    final Set<String> serviciosMarcados = {};

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (cargandoMarcas && errorMarcas == null && marcas.isEmpty) {
              _vehicleCatalogService.getMakes().then((resultado) {
                if (!context.mounted) {
                  return;
                }

                setDialogState(() {
                  marcas = resultado;
                  cargandoMarcas = false;
                });
              }).catchError((error) {
                if (!context.mounted) {
                  return;
                }

                setDialogState(() {
                  cargandoMarcas = false;
                  errorMarcas = error.toString();
                });
              });
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 460,
                  maxHeight: 680,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: const BoxDecoration(
                        color: AppColors.headerNavy,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Nueva Cita',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: Material(
                        color: AppColors.background,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(18),

                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _tituloSeccionModal('DATOS DEL CLIENTE'),
                              TextField(
                                controller: clienteController,
                                decoration: _decoracionCampo('Nombre completo')
                                    .copyWith(hintText: 'Nombre del cliente'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: telefonoController,
                                keyboardType: TextInputType.phone,
                                decoration: _decoracionCampo('Teléfono')
                                    .copyWith(hintText: '809-000-0000'),
                              ),
                              const SizedBox(height: 16),
                              _tituloSeccionModal('DATOS DEL VEHÍCULO'),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      initialValue: marcaSeleccionada,
                                      decoration: _decoracionCampo('Marca'),
                                      hint: Text(
                                        cargandoMarcas
                                            ? 'Cargando...'
                                            : errorMarcas != null
                                                ? 'Error al cargar'
                                                : 'Seleccionar',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      items: marcas
                                          .map(
                                            (marca) => DropdownMenuItem<String>(
                                              value: marca.name,
                                              child: Text(
                                                marca.name,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: cargandoMarcas
                                          ? null
                                          : (valor) {
                                              setDialogState(() {
                                                marcaSeleccionada = valor;
                                                modeloSeleccionado = null;
                                                modelos = [];
                                                errorModelos = null;
                                                cargandoModelos =
                                                    valor != null;
                                              });

                                              if (valor == null) {
                                                return;
                                              }

                                              _vehicleCatalogService
                                                  .getModels(make: valor)
                                                  .then((resultado) {
                                                if (!context.mounted) {
                                                  return;
                                                }

                                                setDialogState(() {
                                                  modelos = resultado;
                                                  cargandoModelos = false;
                                                });
                                              }).catchError((error) {
                                                if (!context.mounted) {
                                                  return;
                                                }

                                                setDialogState(() {
                                                  cargandoModelos = false;
                                                  errorModelos =
                                                      error.toString();
                                                });
                                              });
                                            },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child:
                                        DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      initialValue: modeloSeleccionado,
                                      decoration: _decoracionCampo('Modelo'),
                                      hint: Text(
                                        marcaSeleccionada == null
                                            ? 'Selecciona marca'
                                            : cargandoModelos
                                                ? 'Cargando...'
                                                : errorModelos != null
                                                    ? 'Error al cargar'
                                                    : 'Seleccionar',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      items: modelos
                                          .map(
                                            (modelo) =>
                                                DropdownMenuItem<String>(
                                              value: modelo,
                                              child: Text(
                                                modelo,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged:
                                          marcaSeleccionada == null ||
                                              cargandoModelos
                                          ? null
                                          : (valor) => setDialogState(
                                              () => modeloSeleccionado = valor,
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: anioController,
                                      keyboardType: TextInputType.number,
                                      decoration: _decoracionCampo('Año')
                                          .copyWith(hintText: '2020'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: placaController,
                                      decoration: _decoracionCampo('Placa')
                                          .copyWith(hintText: 'A123456'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _tituloSeccionModal('SERVICIOS'),
                              const Text(
                                'Seleccionar servicios',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textGray,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.inputBorder,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      color: const Color(0xFFF3F5F8),
                                      child: const Text(
                                        'TIPOS DE SERVICIO',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textGray,
                                        ),
                                      ),
                                    ),
                                    ...demoServiciosAdmin.map(
                                      (servicio) => CheckboxListTile(
                                        dense: true,
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                        value: serviciosMarcados.contains(
                                          servicio.nombre,
                                        ),
                                        onChanged: (checked) {
                                          setDialogState(() {
                                            if (checked == true) {
                                              serviciosMarcados.add(
                                                servicio.nombre,
                                              );
                                            } else {
                                              serviciosMarcados.remove(
                                                servicio.nombre,
                                              );
                                            }
                                          });
                                        },
                                        title: Text(
                                          '${servicio.nombre} · ${servicio.precio}',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              _tituloSeccionModal('ASIGNACIÓN'),
                              DropdownButtonFormField<String>(
                                initialValue: tecnicoSeleccionado,
                                decoration: _decoracionCampo('Técnico'),
                                hint: const Text(
                                  'Seleccionar técnico',
                                  style: TextStyle(fontSize: 13),
                                ),
                                items: demoTecnicosAdmin
                                    .map(
                                      (t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(
                                          t,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (valor) => setDialogState(
                                  () => tecnicoSeleccionado = valor,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        final nuevaFecha = await showDatePicker(
                                          context: context,
                                          initialDate: fecha,
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime(2100),
                                        );
                                        if (nuevaFecha != null)
                                          setDialogState(
                                            () => fecha = nuevaFecha,
                                          );
                                      },
                                      child: InputDecorator(
                                        decoration: _decoracionCampo('Fecha'),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _formatearFechaCorta(fecha),
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                            const Icon(
                                              Icons.calendar_today_outlined,
                                              size: 16,
                                              color: AppColors.textGray,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        final nuevaHora = await showTimePicker(
                                          context: context,
                                          initialTime: hora ?? TimeOfDay.now(),
                                        );
                                        if (nuevaHora != null)
                                          setDialogState(
                                            () => hora = nuevaHora,
                                          );
                                      },
                                      child: InputDecorator(
                                        decoration: _decoracionCampo('Hora'),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              hora == null
                                                  ? '--:--'
                                                  : hora!.format(context),
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                            const Icon(
                                              Icons.access_time,
                                              size: 16,
                                              color: AppColors.textGray,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                initialValue: estadoSeleccionado,
                                decoration: _decoracionCampo('Estado'),
                                items:
                                    const [
                                      'Pendiente',
                                      'Esperando Pieza',
                                      'En proceso',
                                      'Atrasada',
                                      'Completado',
                                    ]
                                        .map(
                                          (e) => DropdownMenuItem<String>(
                                            value: e,
                                            child: Text(
                                              e,
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (valor) => setDialogState(
                                  () => estadoSeleccionado =
                                      valor ?? estadoSeleccionado,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: descripcionController,
                                maxLines: 3,
                                decoration: _decoracionCampo('Descripción')
                                    .copyWith(
                                      hintText:
                                          'Notas adicionales sobre la cita...',
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      color: AppColors.headerNavy,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              final cliente =
                                  clienteController.text.trim();
                              final telefono =
                                  telefonoController.text.trim();
                              final anio =
                                  int.tryParse(anioController.text.trim());
                              final placa =
                                  placaController.text.trim();
                              final descripcion =
                                  descripcionController.text.trim();

                              if (cliente.isEmpty ||
                                  telefono.isEmpty ||
                                  marcaSeleccionada == null ||
                                  modeloSeleccionado == null ||
                                  anio == null ||
                                  placa.isEmpty ||
                                  hora == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Completa todos los datos obligatorios.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              if (serviciosMarcados.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Selecciona al menos un servicio.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              _solicitudesService.agregarSolicitud(
                                cliente: cliente,
                                telefono: telefono,
                                taller: 'AutoFix Central',
                                marcaVehiculo: marcaSeleccionada!,
                                modeloVehiculo: modeloSeleccionado!,
                                anioVehiculo: anio,
                                placa: placa,
                                servicios: serviciosMarcados.toList(),
                                fecha: fecha,
                                hora: hora!,
                                descripcion: descripcion,
                                estado: _estadoDesdeTexto(
                                  estadoSeleccionado,
                                ),
                              );

                              Navigator.of(context).pop();
                              setState(() {});

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Cita guardada correctamente.',
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.orangePrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Guardar Cita',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  EstadoSolicitudAdmin _estadoDesdeTexto(String estado) {
    switch (estado) {
      case 'Esperando Pieza':
        return EstadoSolicitudAdmin.esperandoPieza;
      case 'En proceso':
        return EstadoSolicitudAdmin.enProceso;
      case 'Atrasada':
        return EstadoSolicitudAdmin.atrasada;
      case 'Completado':
        return EstadoSolicitudAdmin.completada;
      case 'Pendiente':
      default:
        return EstadoSolicitudAdmin.pendiente;
    }
  }

  InputDecoration _decoracionCampo(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.textGray),
      hintStyle: const TextStyle(
        color: AppColors.placeholderGray,
        fontSize: 13,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: AppColors.orangePrimary,
          width: 1.5,
        ),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  bool _esMismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatearFechaCorta(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  String _formatearFechaLarga(DateTime fecha) {
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return '${fecha.day} de ${meses[fecha.month - 1]}';
  }
}

class _SolicitudEstadoAdminCard extends StatelessWidget {
  const _SolicitudEstadoAdminCard({
    required this.solicitud,
    required this.puedeCompletar,
    required this.onCompletar,
  });

  final SolicitudAdmin solicitud;
  final bool puedeCompletar;
  final VoidCallback onCompletar;

  @override
  Widget build(BuildContext context) {
    final fecha =
        '${solicitud.fecha.day.toString().padLeft(2, '0')}/'
        '${solicitud.fecha.month.toString().padLeft(2, '0')}/'
        '${solicitud.fecha.year}';

    final hora =
        '${solicitud.hora.hour.toString().padLeft(2, '0')}:'
        '${solicitud.hora.minute.toString().padLeft(2, '0')}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            solicitud.cliente,
            style: const TextStyle(
              color: AppColors.labelDark,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            solicitud.telefono,
            style: const TextStyle(
              color: AppColors.textGray,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            solicitud.vehiculo,
            style: const TextStyle(
              color: AppColors.labelDark,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Servicios: ${solicitud.servicios.join(', ')}',
            style: const TextStyle(
              color: AppColors.textGray,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Fecha: $fecha · $hora',
            style: const TextStyle(
              color: AppColors.textGray,
              fontSize: 12,
            ),
          ),
          if (solicitud.descripcion.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              solicitud.descripcion,
              style: const TextStyle(
                color: AppColors.textGray,
                fontSize: 12,
              ),
            ),
          ],
          if (puedeCompletar) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: onCompletar,
                icon: const Icon(
                  Icons.check_circle_outline,
                  size: 17,
                ),
                label: const Text('Marcar como completada'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.completado,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

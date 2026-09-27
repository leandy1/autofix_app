import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'configuracion_screen.dart';

/// --- Modelos de datos ---

/// Un servicio dentro de una cita (nombre + precio).
class ServicioCita {
  final String nombre;
  final double precio;
  const ServicioCita({required this.nombre, required this.precio});
}

/// Una cita completa. La lista de citas de la pantalla empieza vacía;
/// esta clase solo define la "forma" de los datos.
class Cita {
  final int numero;
  String cliente;
  String telefono;
  String marca;
  String modelo;
  String anio;
  String placa;
  String tecnico;
  DateTime fecha;
  TimeOfDay? hora;
  String estado; // 'Pendiente' | 'Esperando Pieza' | 'En proceso' | 'Completado'
  List<ServicioCita> servicios;
  String descripcion;

  Cita({
    required this.numero,
    required this.cliente,
    required this.telefono,
    required this.marca,
    required this.modelo,
    required this.anio,
    required this.placa,
    required this.tecnico,
    required this.fecha,
    this.hora,
    required this.estado,
    required this.servicios,
    required this.descripcion,
  });

  double get total => servicios.fold(0, (suma, s) => suma + s.precio);

  /// Una cita está "atrasada" si su fecha ya pasó y todavía no está completada.
  bool get atrasada => estado != 'Completado' && fecha.isBefore(DateTime.now());
}

/// Colores fijos para cada estado posible de una cita.
const Map<String, Color> kColorPorEstado = {
  'Pendiente': Color(0xFFF0A020),
  'Esperando Pieza': Color(0xFF3E7BF0),
  'En proceso': Color(0xFF8B5CF6),
  'Completado': Color(0xFF22C55E),
};
const Color kColorAtrasada = Color(0xFFE0554F);

class CitasScreen extends StatefulWidget {
  const CitasScreen({super.key});

  @override
  State<CitasScreen> createState() => _CitasScreenState();
}

class _CitasScreenState extends State<CitasScreen> {
  // ---------------------------------------------------------------------
  // Estado general de la pantalla.
  // ---------------------------------------------------------------------

  // Lista de citas: empieza vacía. Se llena solo cuando el usuario crea
  // citas nuevas con el formulario "+ Nueva".
  final List<Cita> _citas = [];
  int _siguienteNumero = 1;

  // Lista auxiliar para el checklist de servicios del formulario. También
  // empieza vacía: lo ideal a futuro es que venga compartida desde la
  // pantalla de Configuración (por ejemplo con el paquete "provider"), pero
  // por ahora cada pantalla maneja su propia información.
  final List<String> _tiposServicioDisponibles = [];

  DateTime _fechaSeleccionada = DateTime.now();

  bool _filtrosExpandido = false;
  final TextEditingController _busquedaController = TextEditingController();
  String _textoBusqueda = '';

  // Qué acordeón de estado está expandido actualmente (null = ninguno).
  String? _categoriaExpandida;

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final citasFiltradas = _citasFiltradas();
    final categorias = _agruparPorCategoria(citasFiltradas);

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
            _buildFiltrosAvanzados(),
            const SizedBox(height: 16),
            for (final categoria in categorias.keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildEstadoAccordion(
                  nombre: categoria,
                  color: categoria == 'ATRASADAS' ? kColorAtrasada : kColorPorEstado[categoria]!,
                  citas: categorias[categoria]!,
                  expanded: _categoriaExpandida == categoria,
                  onTap: () {
                    setState(() {
                      _categoriaExpandida = _categoriaExpandida == categoria ? null : categoria;
                    });
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Filtrado y agrupación de citas.
  // ---------------------------------------------------------------------

  List<Cita> _citasFiltradas() {
    if (_textoBusqueda.trim().isEmpty) return _citas;
    final query = _textoBusqueda.toLowerCase();
    return _citas.where((c) {
      return c.cliente.toLowerCase().contains(query) ||
          '${c.marca} ${c.modelo}'.toLowerCase().contains(query) ||
          c.placa.toLowerCase().contains(query);
    }).toList();
  }

  /// Agrupa las citas en las 5 categorías que se ven como barras de color.
  /// Usamos un Map con orden de inserción para que siempre aparezcan en el
  /// mismo orden: Atrasadas, Pendiente, Esperando Pieza, En proceso, Completado.
  Map<String, List<Cita>> _agruparPorCategoria(List<Cita> citas) {
    final Map<String, List<Cita>> resultado = {
      'ATRASADAS': [],
      'Pendiente': [],
      'Esperando Pieza': [],
      'En proceso': [],
      'Completado': [],
    };
    for (final cita in citas) {
      if (cita.atrasada) {
        resultado['ATRASADAS']!.add(cita);
      } else {
        resultado[cita.estado]?.add(cita);
      }
    }
    return resultado;
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
            _drawerItem(icon: Icons.calendar_today_outlined, label: 'Citas', selected: true),
            _drawerItem(
              icon: Icons.settings_outlined,
              label: 'Configuración',
              selected: false,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConfiguracionScreen())),
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
      color: selected ? Colors.white.withValues(alpha:0.06) : Colors.transparent,
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

  // ---------------------------------------------------------------------
  // Tarjeta oscura "CITAS DE / <fecha>" con selector de fecha funcional
  // y el botón "+ Nueva".
  // ---------------------------------------------------------------------

  Widget _buildHeroCard() {
    final bool esHoy = _esMismoDia(_fechaSeleccionada, DateTime.now());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.headerNavy, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CITAS DE',
              style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(esHoy ? 'Hoy' : _formatearFechaLarga(_fechaSeleccionada),
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _navCircleButton(Icons.chevron_left, onTap: () {
                setState(() => _fechaSeleccionada = _fechaSeleccionada.subtract(const Duration(days: 1)));
              }),
              _buildCampoFechaHero(),
              _navCircleButton(Icons.chevron_right, onTap: () {
                setState(() => _fechaSeleccionada = _fechaSeleccionada.add(const Duration(days: 1)));
              }),
              ElevatedButton.icon(
                onPressed: _abrirFormularioNuevaCita,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nueva'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orangePrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Campo con la fecha seleccionada (ej: "21/09/2026") que abre el
  /// calendario nativo de Flutter al tocarlo.
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
          color: Colors.white.withValues(alpha:0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatearFechaCorta(_fechaSeleccionada), style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(width: 10),
            const Icon(Icons.calendar_today_outlined, color: Colors.white54, size: 16),
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
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white38)),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Barra "Filtros avanzados", ahora expandible con un buscador funcional.
  // ---------------------------------------------------------------------

  Widget _buildFiltrosAvanzados() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 8, offset: const Offset(0, 2))],
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
                  const Icon(Icons.filter_alt_outlined, size: 18, color: AppColors.textGray),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Filtros avanzados', style: TextStyle(color: AppColors.textGray, fontSize: 14)),
                  ),
                  AnimatedRotation(
                    turns: _filtrosExpandido ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down, color: AppColors.textGray),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _filtrosExpandido ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextField(
                controller: _busquedaController,
                onChanged: (valor) => setState(() => _textoBusqueda = valor),
                decoration: InputDecoration(
                  hintText: 'Buscar por cliente, vehículo o placa...',
                  hintStyle: const TextStyle(color: AppColors.placeholderGray, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textGray),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
            secondChild: const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Acordeón por categoría de estado, con las tarjetas de cada cita real.
  // ---------------------------------------------------------------------

  Widget _buildEstadoAccordion({
    required String nombre,
    required Color color,
    required List<Cita> citas,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        Material(
          color: color,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      nombre.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5),
                    ),
                  ),
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: Colors.white.withValues(alpha:0.25),
                    child: Text('${citas.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: citas.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.cardWhite,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: const Text('No hay citas en este estado.', style: TextStyle(color: AppColors.textGray, fontSize: 13)),
                  )
                : Column(
                    children: citas
                        .map((cita) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _buildCitaCard(cita),
                            ))
                        .toList(),
                  ),
          ),
          secondChild: const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Tarjeta individual de una cita (dentro de un acordeón expandido).
  // ---------------------------------------------------------------------

  Widget _buildCitaCard(Cita cita) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFF1F3F6), borderRadius: BorderRadius.circular(6)),
                child: Text('#${cita.numero}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              _buildEstadoDropdown(cita),
            ],
          ),
          const SizedBox(height: 12),
          _filaDosDatos('CLIENTE', cita.cliente, 'TELÉFONO', cita.telefono),
          const SizedBox(height: 10),
          _filaDosDatos('VEHÍCULO', '${cita.marca} ${cita.modelo} ${cita.anio}'.trim(), 'PLACA', cita.placa),
          const SizedBox(height: 10),
          _filaDosDatos('TÉCNICO', cita.tecnico, 'FECHA', _formatearFechaHora(cita)),
          const SizedBox(height: 10),
          const Text('SERVICIOS', style: TextStyle(fontSize: 10, color: AppColors.textGray, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: cita.servicios
                .map((s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFDFF5E6), borderRadius: BorderRadius.circular(6)),
                      child: Text(s.nombre, style: const TextStyle(fontSize: 11, color: Color(0xFF15803D))),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('RD\$ ${cita.total.toStringAsFixed(0)}',
                  style: const TextStyle(color: AppColors.greenAccent, fontSize: 18, fontWeight: FontWeight.w800)),
              OutlinedButton(
                onPressed: () => _abrirDetalleCita(cita),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textDark,
                  side: const BorderSide(color: AppColors.inputBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Ver detalle'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filaDosDatos(String label1, String valor1, String label2, String valor2) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _datoEtiquetado(label1, valor1)),
        const SizedBox(width: 12),
        Expanded(child: _datoEtiquetado(label2, valor2)),
      ],
    );
  }

  Widget _datoEtiquetado(String label, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textGray, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(valor.isEmpty ? '—' : valor, style: const TextStyle(fontSize: 13, color: AppColors.textDark)),
      ],
    );
  }

  /// Badge de estado que, al tocarlo, abre un menú para cambiar el estado
  /// de la cita directamente desde la tarjeta (igual que tu captura 4).
  Widget _buildEstadoDropdown(Cita cita) {
    final color = kColorPorEstado[cita.estado] ?? AppColors.textGray;
    return PopupMenuButton<String>(
      onSelected: (nuevoEstado) => setState(() => cita.estado = nuevoEstado),
      itemBuilder: (context) => kColorPorEstado.keys.map((estado) {
        return PopupMenuItem<String>(
          value: estado,
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: kColorPorEstado[estado], shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(estado, style: TextStyle(fontWeight: estado == cita.estado ? FontWeight.w700 : FontWeight.normal)),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha:0.15), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(cita.estado, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            Icon(Icons.keyboard_arrow_down, color: color, size: 16),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Modal "Información de la cita" (ver detalle).
  // ---------------------------------------------------------------------

  void _abrirDetalleCita(Cita cita) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    color: AppColors.headerNavy,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                  child: Column(
                    children: [
                      Text('CITA #${cita.numero}',
                          style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
                      const SizedBox(height: 4),
                      const Text('INFORMACIÓN DE LA CITA',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _tituloSeccionModal('CLIENTE'),
                        _filaDosDatos('Nombre', cita.cliente, 'Teléfono', cita.telefono),
                        const SizedBox(height: 16),
                        _tituloSeccionModal('VEHÍCULO'),
                        _filaDosDatos('Marca', cita.marca, 'Modelo', cita.modelo),
                        const SizedBox(height: 10),
                        _filaDosDatos('Año', cita.anio, 'Placa', cita.placa),
                        const SizedBox(height: 10),
                        _datoEtiquetado('Técnico', cita.tecnico),
                        const SizedBox(height: 16),
                        _tituloSeccionModal('SERVICIOS'),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: cita.servicios
                              .map((s) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: const Color(0xFFDFF5E6), borderRadius: BorderRadius.circular(6)),
                                    child: Text(s.nombre, style: const TextStyle(fontSize: 11, color: Color(0xFF15803D))),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 8),
                        Text('RD\$ ${cita.total.toStringAsFixed(0)}',
                            style: const TextStyle(color: AppColors.greenAccent, fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 16),
                        _tituloSeccionModal('ESTADO'),
                        Row(
                          children: [
                            _buildEstadoDropdown(cita),
                            const SizedBox(width: 10),
                            Text(_formatearFechaHora(cita), style: const TextStyle(color: AppColors.textGray, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _tituloSeccionModal('DESCRIPCIÓN'),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFFF3F5F8), borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            cita.descripcion.isEmpty ? 'Sin descripción.' : cita.descripcion,
                            style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _confirmarEliminarCita(cita);
                        },
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                        child: const Text('Eliminar'),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _abrirFormularioNuevaCita(citaExistente: cita);
                        },
                        child: const Text('Editar'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.headerNavy, foregroundColor: Colors.white),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tituloSeccionModal(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(texto, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textGray, letterSpacing: 0.5)),
    );
  }

  void _confirmarEliminarCita(Cita cita) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar cita?'),
        content: Text('Se eliminará la cita #${cita.numero} de ${cita.cliente}. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              setState(() => _citas.remove(cita));
              Navigator.of(context).pop();
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Formulario "Nueva Cita" (también se reutiliza para "Editar").
  // ---------------------------------------------------------------------

  void _abrirFormularioNuevaCita({Cita? citaExistente}) {
    final formKey = GlobalKey<FormState>();
    final nombreController = TextEditingController(text: citaExistente?.cliente ?? '');
    final telefonoController = TextEditingController(text: citaExistente?.telefono ?? '');
    final marcaController = TextEditingController(text: citaExistente?.marca ?? '');
    final modeloController = TextEditingController(text: citaExistente?.modelo ?? '');
    final anioController = TextEditingController(text: citaExistente?.anio ?? '');
    final placaController = TextEditingController(text: citaExistente?.placa ?? '');
    final tecnicoController = TextEditingController(text: citaExistente?.tecnico ?? '');
    final descripcionController = TextEditingController(text: citaExistente?.descripcion ?? '');

    DateTime fecha = citaExistente?.fecha ?? DateTime.now();
    TimeOfDay? hora = citaExistente?.hora;
    String estado = citaExistente?.estado ?? 'Pendiente';
    final Set<String> serviciosSeleccionados = {
      if (citaExistente != null) ...citaExistente.servicios.map((s) => s.nombre),
    };
    bool mostrarErrorServicios = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460, maxHeight: 680),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: const BoxDecoration(
                        color: AppColors.headerNavy,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(citaExistente == null ? 'Nueva Cita' : 'Editar Cita',
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                          InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _tituloSeccionModal('DATOS DEL CLIENTE'),
                              _campoTexto(nombreController, 'Nombre completo', 'Nombre del cliente', requerido: true),
                              const SizedBox(height: 10),
                              _campoTexto(telefonoController, 'Teléfono', '809-000-0000', requerido: true),
                              const SizedBox(height: 16),
                              _tituloSeccionModal('DATOS DEL VEHÍCULO'),
                              Row(
                                children: [
                                  Expanded(child: _campoTexto(marcaController, 'Marca', 'Ej: Toyota', requerido: true)),
                                  const SizedBox(width: 10),
                                  Expanded(child: _campoTexto(modeloController, 'Modelo', 'Ej: Corolla', requerido: true)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(child: _campoTexto(anioController, 'Año', '2020', teclado: TextInputType.number)),
                                  const SizedBox(width: 10),
                                  Expanded(child: _campoTexto(placaController, 'Placa', 'A123456', requerido: true)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _tituloSeccionModal('SERVICIOS'),
                              const Text('Seleccionar servicios', style: TextStyle(fontSize: 12, color: AppColors.textGray)),
                              const SizedBox(height: 6),
                              Container(
                                decoration: BoxDecoration(border: Border.all(color: AppColors.inputBorder), borderRadius: BorderRadius.circular(8)),
                                child: Column(
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      color: const Color(0xFFF3F5F8),
                                      child: const Text('TIPOS DE SERVICIO',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textGray)),
                                    ),
                                    if (_tiposServicioDisponibles.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Text(
                                          'No hay tipos de servicio registrados.\nAgrégalos primero en Configuración.',
                                          style: TextStyle(fontSize: 12, color: AppColors.textGray),
                                        ),
                                      )
                                    else
                                      ..._tiposServicioDisponibles.map((nombre) {
                                        return CheckboxListTile(
                                          dense: true,
                                          controlAffinity: ListTileControlAffinity.leading,
                                          value: serviciosSeleccionados.contains(nombre),
                                          onChanged: (checked) {
                                            setDialogState(() {
                                              if (checked == true) {
                                                serviciosSeleccionados.add(nombre);
                                              } else {
                                                serviciosSeleccionados.remove(nombre);
                                              }
                                            });
                                          },
                                          title: Text(nombre, style: const TextStyle(fontSize: 13)),
                                        );
                                      }),
                                  ],
                                ),
                              ),
                              if (mostrarErrorServicios)
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Text('Selecciona al menos un servicio.', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                                ),
                              const SizedBox(height: 16),
                              _tituloSeccionModal('ASIGNACIÓN'),
                              _campoTexto(tecnicoController, 'Técnico', 'Ej: Técnico 1'),
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
                                        if (nuevaFecha != null) setDialogState(() => fecha = nuevaFecha);
                                      },
                                      child: InputDecorator(
                                        decoration: _decoracionCampo('Fecha'),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(_formatearFechaCorta(fecha), style: const TextStyle(fontSize: 13)),
                                            const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textGray),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        final nuevaHora = await showTimePicker(context: context, initialTime: hora ?? TimeOfDay.now());
                                        if (nuevaHora != null) setDialogState(() => hora = nuevaHora);
                                      },
                                      child: InputDecorator(
                                        decoration: _decoracionCampo('Hora'),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(hora == null ? '--:--' : hora!.format(context), style: const TextStyle(fontSize: 13)),
                                            const Icon(Icons.access_time, size: 16, color: AppColors.textGray),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                initialValue: estado,
                                decoration: _decoracionCampo('Estado'),
                                items: kColorPorEstado.keys
                                    .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13))))
                                    .toList(),
                                onChanged: (valor) => setDialogState(() => estado = valor ?? estado),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: descripcionController,
                                maxLines: 3,
                                decoration: _decoracionCampo('Descripción').copyWith(hintText: 'Notas adicionales sobre la cita...'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            final formularioValido = formKey.currentState?.validate() ?? false;
                            if (serviciosSeleccionados.isEmpty) {
                              setDialogState(() => mostrarErrorServicios = true);
                            }
                            if (!formularioValido || serviciosSeleccionados.isEmpty) return;

                            final serviciosFinales =
                                serviciosSeleccionados.map((nombre) => ServicioCita(nombre: nombre, precio: 0)).toList();

                            setState(() {
                              if (citaExistente != null) {
                                citaExistente
                                  ..cliente = nombreController.text.trim()
                                  ..telefono = telefonoController.text.trim()
                                  ..marca = marcaController.text.trim()
                                  ..modelo = modeloController.text.trim()
                                  ..anio = anioController.text.trim()
                                  ..placa = placaController.text.trim()
                                  ..tecnico = tecnicoController.text.trim()
                                  ..fecha = fecha
                                  ..hora = hora
                                  ..estado = estado
                                  ..servicios = serviciosFinales
                                  ..descripcion = descripcionController.text.trim();
                              } else {
                                _citas.add(Cita(
                                  numero: _siguienteNumero++,
                                  cliente: nombreController.text.trim(),
                                  telefono: telefonoController.text.trim(),
                                  marca: marcaController.text.trim(),
                                  modelo: modeloController.text.trim(),
                                  anio: anioController.text.trim(),
                                  placa: placaController.text.trim(),
                                  tecnico: tecnicoController.text.trim(),
                                  fecha: fecha,
                                  hora: hora,
                                  estado: estado,
                                  servicios: serviciosFinales,
                                  descripcion: descripcionController.text.trim(),
                                ));
                              }
                            });
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.orangePrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Guardar Cita', style: TextStyle(fontWeight: FontWeight.w700)),
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

  Widget _campoTexto(
    TextEditingController controller,
    String label,
    String hint, {
    bool requerido = false,
    TextInputType? teclado,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: teclado,
      decoration: _decoracionCampo(label).copyWith(hintText: hint),
      validator: requerido ? (valor) => (valor == null || valor.trim().isEmpty) ? 'Campo obligatorio' : null : null,
    );
  }

  InputDecoration _decoracionCampo(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.textGray),
      hintStyle: const TextStyle(color: AppColors.placeholderGray, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.inputBorder)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.orangePrimary, width: 1.5)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  // ---------------------------------------------------------------------
  // Utilidades de formato de fecha.
  // ---------------------------------------------------------------------

  bool _esMismoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatearFechaCorta(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  String _formatearFechaLarga(DateTime fecha) {
    const meses = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
    ];
    return '${fecha.day} de ${meses[fecha.month - 1]}';
  }

  String _formatearFechaHora(Cita cita) {
    final fecha = _formatearFechaCorta(cita.fecha);
    if (cita.hora == null) return fecha;
    final h = cita.hora!.hour.toString().padLeft(2, '0');
    final m = cita.hora!.minute.toString().padLeft(2, '0');
    return '$fecha $h:$m';
  }
}
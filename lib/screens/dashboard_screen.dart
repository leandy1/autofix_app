import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';
import 'citas_screen.dart';
import 'configuracion_screen.dart';

/// Modelo simple para representar una fila de la tabla "Citas del día".
/// Más adelante esto puede moverse a lib/models/cita.dart y llenarse desde
/// una base de datos real en vez de datos de ejemplo.
class CitaResumen {
  final String cliente;
  final String vehiculo;
  final String placa;
  final String servicio;

  const CitaResumen({
    required this.cliente,
    required this.vehiculo,
    required this.placa,
    required this.servicio,
  });
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Datos de ejemplo, iguales a los que se ven en el boceto de Figma.
  static const List<CitaResumen> _citasDelDia = [
    CitaResumen(cliente: 'Luis Castillo', vehiculo: 'Toyota RAV4', placa: 'E567890', servicio: 'Motor, Correa'),
    CitaResumen(cliente: 'Pedro Núñez', vehiculo: 'Honda CR-V', placa: 'G789012', servicio: 'Aire'),
    CitaResumen(cliente: 'Isabel Reyes', vehiculo: 'Honda Accord', placa: 'L234567', servicio: 'Correa de tiempo'),
    CitaResumen(cliente: 'Natalia Flores', vehiculo: 'Ford Edge', placa: 'R890123', servicio: 'Sistema de frenos'),
    CitaResumen(cliente: 'Lucía Medina', vehiculo: 'Suzuki Jimny', placa: 'T012345', servicio: 'Alineación y balanceo'),
  ];

  // Fecha que se muestra en la tarjeta oscura del Dashboard.
  DateTime _fechaSeleccionada = DateTime.now();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context),
      drawer: _buildDrawer(context),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroCard(),
            const SizedBox(height: 16),
            _buildStatCard(
              icon: Icons.directions_car_filled_outlined,
              iconColor: AppColors.blueAccent,
              label: 'VEHÍCULOS EN EL TALLER',
              value: '2',
              description: 'Estado: En proceso',
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              icon: Icons.description_outlined,
              iconColor: AppColors.orangePrimary,
              label: 'ÓRDENES ABIERTAS',
              value: '6',
              description: 'Pendiente + Esperando Pieza + En proceso',
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              icon: Icons.check_circle_outline,
              iconColor: AppColors.greenAccent,
              label: 'COMPLETADAS HOY',
              value: '0',
              description: null,
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              icon: Icons.attach_money,
              iconColor: AppColors.headerNavy,
              label: 'INGRESOS DEL DÍA',
              value: 'RD\$ 0',
              description: 'Solo citas completadas',
            ),
            const SizedBox(height: 20),
            _buildCitasDelDia(),
          ],
        ),
      ),
    );
  }

  /// Barra superior: ícono de menú (abre el Drawer), título y avatar del usuario.
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.headerNavy,
      iconTheme: IconThemeData(color: AppColors.background),
      elevation: 0,
      titleSpacing: 0,
      title: const Padding(
        padding: EdgeInsets.only(left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('AutoFix',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
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

  /// Menú lateral (Drawer) con la navegación principal de la app.
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
            _drawerItem(icon: Icons.grid_view_rounded, label: 'Dashboard', selected: true),
            _drawerItem(
              icon: Icons.calendar_today_outlined,
              label: 'Citas',
              selected: false,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CitasScreen())),
            ),
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
                  // Cierra sesión y regresa al Login, limpiando el historial de navegación.
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

  /// Un ítem individual del menú lateral. Si "selected" es true, se resalta en
  /// naranja (igual que "Dashboard" en el boceto de Figma).
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
        shape: selected
            ? const Border(left: BorderSide(color: AppColors.orangePrimary, width: 3))
            : null,
      ),
    );
  }

  /// Tarjeta oscura superior: "DASHBOARD / <fecha>" con selector de fecha funcional.
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
          const Text('DASHBOARD',
              style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(esHoy ? 'Hoy' : _formatearFechaLarga(_fechaSeleccionada),
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Row(
            children: [
              _navCircleButton(Icons.chevron_left, onTap: () {
                setState(() => _fechaSeleccionada = _fechaSeleccionada.subtract(const Duration(days: 1)));
              }),
              const SizedBox(width: 10),
              Expanded(child: _buildCampoFechaHero()),
              const SizedBox(width: 10),
              _navCircleButton(Icons.chevron_right, onTap: () {
                setState(() => _fechaSeleccionada = _fechaSeleccionada.add(const Duration(days: 1)));
              }),
            ],
          ),
        ],
      ),
    );
  }

  /// Campo con la fecha seleccionada que abre el calendario nativo de Flutter.
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
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha:0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatearFechaCorta(_fechaSeleccionada), style: const TextStyle(color: Colors.white, fontSize: 14)),
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

  /// Tarjeta blanca de resumen (Vehículos en el taller, Órdenes abiertas, etc.)
  /// con una barra de color a la izquierda que identifica cada categoría.
  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String? description,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: iconColor, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: iconColor.withValues(alpha:0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textGray, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: AppColors.textDark, fontSize: 22, fontWeight: FontWeight.w800)),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(description, style: const TextStyle(color: AppColors.textGray, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sección inferior: título "Citas del día" + badge con el total, y la tabla.
  Widget _buildCitasDelDia() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Citas del día', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFF1F3F6), borderRadius: BorderRadius.circular(20)),
                  child: Text('${_citasDelDia.length} citas',
                      style: const TextStyle(fontSize: 12, color: AppColors.textGray, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(AppColors.headerNavy),
              headingTextStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              dataTextStyle: const TextStyle(color: AppColors.textDark, fontSize: 13),
              columns: const [
                DataColumn(label: Text('Cliente')),
                DataColumn(label: Text('Vehículo')),
                DataColumn(label: Text('Placa')),
                DataColumn(label: Text('Servicio')),
              ],
              rows: _citasDelDia
                  .map((c) => DataRow(cells: [
                        DataCell(Text(c.cliente, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(c.vehiculo)),
                        DataCell(Text(c.placa)),
                        DataCell(Text(c.servicio)),
                      ]))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
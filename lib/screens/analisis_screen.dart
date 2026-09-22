import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_colors.dart';
import 'dashboard_screen.dart';
import 'citas_screen.dart';
import 'configuracion_screen.dart';
import 'login_screen.dart';


class IngresoDia {
  final String etiquetaFecha; // ej: "26 ago"
  final double monto;
  const IngresoDia({required this.etiquetaFecha, required this.monto});
}

class ServicioSolicitado {
  final String nombre;
  final int cantidad;
  final Color color;
  const ServicioSolicitado({required this.nombre, required this.cantidad, required this.color});
}

class TecnicoRendimiento {
  final String nombre;
  final int citas;
  final double ingresos;
  final Color color;
  const TecnicoRendimiento({required this.nombre, required this.citas, required this.ingresos, required this.color});
}

class CitaPeriodo {
  final int numero;
  final String cliente;
  final String vehiculo;
  final List<String> servicios;
  final String tecnico;
  final String estado;
  final double monto;
  final String fecha;
  const CitaPeriodo({
    required this.numero,
    required this.cliente,
    required this.vehiculo,
    required this.servicios,
    required this.tecnico,
    required this.estado,
    required this.monto,
    required this.fecha,
  });
}

class AnalisisScreen extends StatefulWidget {
  const AnalisisScreen({super.key});

  @override
  State<AnalisisScreen> createState() => _AnalisisScreenState();
}

class _AnalisisScreenState extends State<AnalisisScreen> {
  // --- Estado del período seleccionado (Hoy / 7 días / 30 días / Personalizado) ---
  String _periodoSeleccionado = '30 días';
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  
  final double _ingresosTotales = 0;
  final int _citasTotales = 0;
  final int _completadas = 0;
  final double _promedioPorCita = 0;

  final List<IngresoDia> _ingresosPorDia = const [];


  final Map<String, int> _citasPorEstado = const {
    'Pendiente': 0,
    'Esperando Pieza': 0,
    'En proceso': 0,
    'Completado': 0,
  };

  final List<ServicioSolicitado> _serviciosMasSolicitados = const [];
  final List<TecnicoRendimiento> _rendimientoPorTecnico = const [];
  final List<CitaPeriodo> _citasDelPeriodo = const [];

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
            _buildStatsGrid(),
            const SizedBox(height: 16),
            _buildIngresosPorDiaCard(),
            const SizedBox(height: 16),
            _buildCitasPorEstadoCard(),
            const SizedBox(height: 16),
            _buildServiciosMasSolicitadosCard(),
            const SizedBox(height: 16),
            _buildRendimientoPorTecnicoCard(),
            const SizedBox(height: 16),
            _buildCitasDelPeriodoCard(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // AppBar + Drawer (idénticos en estructura a Dashboard/Citas, solo cambia
  // cuál ítem queda marcado como seleccionado).
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
            _drawerItem(icon: Icons.show_chart, label: 'Análisis', selected: true),
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

  // ---------------------------------------------------------------------
  // Selector de fecha personalizado (aparece solo cuando el período
  // elegido es "Personalizado").
  // ---------------------------------------------------------------------

  Future<void> _seleccionarFecha({required bool esFechaDesde}) async {
    final DateTime? fechaElegida = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (fechaElegida != null) {
      setState(() {
        if (esFechaDesde) {
          _fechaDesde = fechaElegida;
        } else {
          _fechaHasta = fechaElegida;
        }
      });
    }
  }

  String _formatearFecha(DateTime? fecha) {
    if (fecha == null) return '--/--/----';
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  Widget _buildCampoFecha({required bool esFechaDesde, required DateTime? fecha}) {
    return InkWell(
      onTap: () => _seleccionarFecha(esFechaDesde: esFechaDesde),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 150,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatearFecha(fecha), style: const TextStyle(color: Colors.white, fontSize: 13)),
            const Icon(Icons.calendar_today_outlined, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Tarjeta oscura superior: título "Análisis", botón "Generar Reporte" y
  // los chips de período (Hoy / 7 días / 30 días / Personalizado).
  // ---------------------------------------------------------------------

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.headerNavy, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AUTOFIX',
                        style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
                    SizedBox(height: 4),
                    Text('Análisis', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  // todo: generar el reporte real (PDF/Excel) con los datos del período.
                },
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Generar Reporte'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 172, 51, 51),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _textoSubtitulo(),
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...['Hoy', '7 días', '30 días', 'Personalizado'].map((periodo) {
                final bool activo = periodo == _periodoSeleccionado;
                return ChoiceChip(
                  label: Text(periodo),
                  selected: activo,
                  onSelected: (_) => setState(() => _periodoSeleccionado = periodo),
                  selectedColor: AppColors.orangePrimary,
                  backgroundColor: const Color.fromRGBO(13, 27, 53, 1).withValues(alpha: 0.87),
                  labelStyle: TextStyle(color: activo ? Colors.white : Colors.white70, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                );
              }),
              if (_periodoSeleccionado == 'Personalizado') ...[
                _buildCampoFecha(esFechaDesde: true, fecha: _fechaDesde),
                const Text('—', style: TextStyle(color: Colors.white54)),
                _buildCampoFecha(esFechaDesde: false, fecha: _fechaHasta),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Texto pequeño debajo del título "Análisis".
  /// - Si el período es "Personalizado" y ya hay fechas elegidas, muestra el
  ///   rango (ej: "22 ago – 20 sept · 21 citas").
  /// - En cualquier otro caso, muestra el período junto con el total de citas.
  String _textoSubtitulo() {
    if (_periodoSeleccionado == 'Personalizado' && _fechaDesde != null && _fechaHasta != null) {
      return '${_formatearFechaCorta(_fechaDesde!)} – ${_formatearFechaCorta(_fechaHasta!)} · $_citasTotales citas';
    }
    return 'Últimos $_periodoSeleccionado · $_citasTotales citas';
  }

  /// Formatea una fecha como "22 ago" (día + mes abreviado en español).
  String _formatearFechaCorta(DateTime fecha) {
    const meses = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sept', 'oct', 'nov', 'dic',
    ];
    return '${fecha.day} ${meses[fecha.month - 1]}';
  }

  // ---------------------------------------------------------------------
  // Grid 2x2 de tarjetas de resumen numérico.
  // ---------------------------------------------------------------------

  Widget _buildStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          icon: Icons.attach_money,
          iconColor: AppColors.greenAccent,
          label: 'INGRESOS TOTALES',
          value: 'RD\$ ${_ingresosTotales.toStringAsFixed(0)}',
        ),
        _buildStatCard(
          icon: Icons.calendar_month_outlined,
          iconColor: AppColors.blueAccent,
          label: 'CITAS TOTALES',
          value: '$_citasTotales',
        ),
        _buildStatCard(
          icon: Icons.check_circle_outline,
          iconColor: AppColors.greenAccent,
          label: 'COMPLETADAS',
          value: '$_completadas',
        ),
        _buildStatCard(
          icon: Icons.show_chart,
          iconColor: AppColors.orangePrimary,
          label: 'PROMEDIO/CITA',
          value: 'RD\$ ${_promedioPorCita.toStringAsFixed(0)}',
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: iconColor, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(color: AppColors.textGray, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: AppColors.textDark, fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Contenedor base reutilizable para cada tarjeta blanca con título.
  // ---------------------------------------------------------------------

  Widget _sectionCard({required String title, Widget? trailing, required Widget child}) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title.toUpperCase(),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark, letterSpacing: 0.4)),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  /// Mensaje reutilizable para cuando una sección todavía no tiene datos.
  Widget _emptyState(String mensaje) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(Icons.insert_chart_outlined, color: AppColors.textGray, size: 28),
          const SizedBox(height: 8),
          Text(mensaje, style: const TextStyle(color: AppColors.textGray, fontSize: 13), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Gráfico de barras: "Ingresos por día".
  // ---------------------------------------------------------------------

  Widget _buildIngresosPorDiaCard() {
    return _sectionCard(
      title: 'Ingresos por día',
      child: _ingresosPorDia.isEmpty
          ? _emptyState('No hay datos de ingresos en este período todavía.')
          : SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= _ingresosPorDia.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(_ingresosPorDia[index].etiquetaFecha,
                                style: const TextStyle(fontSize: 10, color: AppColors.textGray)),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: _ingresosPorDia.asMap().entries.map((entry) {
                    return BarChartGroupData(x: entry.key, barRods: [
                      BarChartRodData(
                        toY: entry.value.monto,
                        color: AppColors.orangePrimary,
                        width: 18,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ]);
                  }).toList(),
                ),
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------
  // Gráfico de dona: "Citas por estado".
  // ---------------------------------------------------------------------

  Widget _buildCitasPorEstadoCard() {
    final total = _citasPorEstado.values.fold<int>(0, (a, b) => a + b);
    final coloresPorEstado = {
      'Pendiente': const Color(0xFFF0A020),
      'Esperando Pieza': const Color(0xFF3E7BF0),
      'En proceso': const Color(0xFF8B5CF6),
      'Completado': const Color(0xFF22C55E),
    };

    return _sectionCard(
      title: 'Citas por estado',
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 55,
                    sections: total == 0
                        ? [
                            // Cuando no hay datos, dibujamos un anillo gris completo
                            // en vez de dejarlo en blanco, para que se note que es
                            // un estado "vacío" y no un error visual.
                            PieChartSectionData(
                              value: 1,
                              color: const Color(0xFFE5E7EB),
                              showTitle: false,
                              radius: 26,
                            ),
                          ]
                        : _citasPorEstado.entries
                            .where((e) => e.value > 0)
                            .map((e) => PieChartSectionData(
                                  value: e.value.toDouble(),
                                  color: coloresPorEstado[e.key],
                                  showTitle: false,
                                  radius: 26,
                                ))
                            .toList(),
                  ),
                ),
                Text('$total', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textDark)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: _citasPorEstado.entries.map((e) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: coloresPorEstado[e.key], shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('${e.key} ${e.value}', style: const TextStyle(fontSize: 12, color: AppColors.textDark)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // "Servicios más solicitados": lista de barras horizontales.
  // ---------------------------------------------------------------------

  Widget _buildServiciosMasSolicitadosCard() {
    return _sectionCard(
      title: 'Servicios más solicitados',
      child: _serviciosMasSolicitados.isEmpty
          ? _emptyState('Aún no hay servicios registrados.')
          : Column(
              children: _serviciosMasSolicitados.map((s) => _buildBarraHorizontal(
                    nombre: s.nombre,
                    valor: s.cantidad,
                    maximo: _serviciosMasSolicitados.map((e) => e.cantidad).reduce((a, b) => a > b ? a : b),
                    color: s.color,
                  )).toList(),
            ),
    );
  }

  // ---------------------------------------------------------------------
  // "Rendimiento por técnico": barras horizontales + tabla resumen.
  // ---------------------------------------------------------------------

  Widget _buildRendimientoPorTecnicoCard() {
    return _sectionCard(
      title: 'Rendimiento por técnico',
      child: _rendimientoPorTecnico.isEmpty
          ? _emptyState('Aún no hay datos de técnicos en este período.')
          : Column(
              children: [
                ..._rendimientoPorTecnico.map((t) => _buildBarraHorizontal(
                      nombre: t.nombre,
                      valor: t.citas,
                      maximo: _rendimientoPorTecnico.map((e) => e.citas).reduce((a, b) => a > b ? a : b),
                      color: t.color,
                    )),
                const SizedBox(height: 12),
                _buildTablaTecnicos(),
              ],
            ),
    );
  }

  Widget _buildTablaTecnicos() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.headerNavy),
          headingTextStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          dataTextStyle: const TextStyle(color: AppColors.textDark, fontSize: 13),
          columns: const [
            DataColumn(label: Text('Técnico')),
            DataColumn(label: Text('Citas')),
            DataColumn(label: Text('Ingresos')),
          ],
          rows: _rendimientoPorTecnico
              .map((t) => DataRow(cells: [
                    DataCell(Text(t.nombre)),
                    DataCell(Text('${t.citas}')),
                    DataCell(Text('RD\$ ${t.ingresos.toStringAsFixed(0)}',
                        style: const TextStyle(color: AppColors.greenAccent, fontWeight: FontWeight.w600))),
                  ]))
              .toList(),
        ),
      ),
    );
  }

  /// Barra horizontal reutilizable (usada tanto en Servicios como en Técnicos).
  Widget _buildBarraHorizontal({required String nombre, required int valor, required int maximo, required Color color}) {
    final double proporcion = maximo == 0 ? 0 : valor / maximo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(nombre, style: const TextStyle(fontSize: 12, color: AppColors.textDark), overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: proporcion,
                minHeight: 10,
                backgroundColor: const Color(0xFFEDEFF2),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 20,
            child: Text('$valor', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // "Citas del período": tabla detallada.
  // ---------------------------------------------------------------------

  Widget _buildCitasDelPeriodoCard() {
    return _sectionCard(
      title: 'Citas del período',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFFF1F3F6), borderRadius: BorderRadius.circular(20)),
        child: Text('(${_citasDelPeriodo.length})',
            style: const TextStyle(fontSize: 12, color: AppColors.textGray, fontWeight: FontWeight.w600)),
      ),
      child: _citasDelPeriodo.isEmpty
          ? _emptyState('No hay citas registradas en este período.')
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(AppColors.headerNavy),
                  headingTextStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  dataTextStyle: const TextStyle(color: AppColors.textDark, fontSize: 13),
                  columns: const [
                    DataColumn(label: Text('#')),
                    DataColumn(label: Text('Cliente')),
                    DataColumn(label: Text('Vehículo')),
                    DataColumn(label: Text('Servicios')),
                    DataColumn(label: Text('Técnico')),
                    DataColumn(label: Text('Estado')),
                    DataColumn(label: Text('Monto')),
                    DataColumn(label: Text('Fecha')),
                  ],
                  rows: _citasDelPeriodo
                      .map((c) => DataRow(cells: [
                            DataCell(Text('#${c.numero}')),
                            DataCell(Text(c.cliente, style: const TextStyle(fontWeight: FontWeight.w600))),
                            DataCell(Text(c.vehiculo)),
                            DataCell(Text(c.servicios.join(', '))),
                            DataCell(Text(c.tecnico)),
                            DataCell(_buildEstadoBadge(c.estado)),
                            DataCell(Text('RD\$ ${c.monto.toStringAsFixed(0)}',
                                style: const TextStyle(color: AppColors.greenAccent, fontWeight: FontWeight.w700))),
                            DataCell(Text(c.fecha)),
                          ]))
                      .toList(),
                ),
              ),
            ),
    );
  }

  Widget _buildEstadoBadge(String estado) {
    final Color color = estado == 'Completado' ? AppColors.greenAccent : AppColors.textGray;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(estado, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/auth/credenciales_seguras.dart';
import 'package:autofix/core/data/limpieza_local.dart';
import 'package:autofix/features/admin/presentation/dashboard_admin_controller.dart';
import 'package:autofix/features/auth/screens/login_screen.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/sync/sync_service.dart';
import 'package:autofix/shared/theme/app_colors.dart';

import 'citas_admin_screen.dart';
import 'configuracion_admin_screen.dart';
import 'editar_perfil_admin_screen.dart';

/// Pantalla principal del administrador.
///
/// No recibe datos por constructor ni lee `demo_admin_data.dart`: todo lo que
/// muestra sale de [DashboardAdminController], que a su vez lee SQLite.
///
/// Se elimino el parametro `data` del boceto anterior a proposito: un campo con
/// valor por defecto de datos falsos es la forma mas comoda de que un mock se
/// quede en produccion, porque la pantalla sigue compilando y nadie se da
/// cuenta de que esta viendo numeros inventados.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Un solo controller para las cuatro tarjetas y la lista del dia. La pantalla
  // no abre la base ni se importa `demo_admin_data.dart`: si hace falta un
  // numero nuevo, se agrega al controller y no a un `const` de ejemplo.
  final DashboardAdminController _ctrl = DashboardAdminController();

  @override
  void initState() {
    super.initState();
    // Las sesiones Admin recordadas entran directamente al Dashboard y no
    // pasan por LoginController. Arranca aquí también para descargar catálogos
    // y citas del taller en esos arranques.
    unawaited(_iniciarSyncDeSesion());
    // Sin `await`: la pantalla aparece de inmediato y el `ListenableBuilder`
    // pinta el estado que haya cuando terminen las lecturas. Una base local
    // tarda milisegundos y no amerita una pantalla de carga propia, aunque el
    // controller si distingue esa primera carga de un refresco posterior.
    _ctrl.cargar();
  }

  Future<void> _iniciarSyncDeSesion() async {
    if (!SesionAdmin.instance.activa) return;
    try {
      await SyncService.instance.start();
    } catch (error) {
      debugPrint('DashboardAdmin: SyncService no arrancó ($error)');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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

  /// Meses en tres letras para los rotulos cortos de las tarjetas.
  ///
  /// Lista a mano y no `DateFormat('MMM', 'es')`: `DateFormat` con un locale
  /// que no es el por defecto necesita `initializeDateFormatting`, que nadie
  /// llamo, y sin eso revienta en runtime. Ademas aqui sale 'oct.' con punto,
  /// que no entra bien en un rotulo en mayusculas.
  static const List<String> _mesesCorto = <String>[
    'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', //
    'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC',
  ];

  /// Rotulo de fecha para las tarjetas, en mayusculas: 'HOY' o 'EL 15 OCT'.
  ///
  /// Un KPI con la palabra HOY pegada no puede dejar de decir HOY. El admin
  /// navega con las flechas a un jueves y la tarjeta seguiria anunciando
  /// "COMPLETADAS HOY" con los numeros del jueves: el numero es correcto y el
  /// texto miente, que es peor, porque el admin no tiene forma de saber que
  /// esta leyendo otro dia.
  String _rotuloFechaTarjeta() {
    final fecha = _ctrl.fecha;
    if (_esMismoDia(fecha, DateTime.now())) return 'HOY';
    return 'EL ${fecha.day} ${_mesesCorto[fecha.month - 1]}';
  }

  /// Rotulo de fecha para los titulos con capitalizacion normal.
  ///
  /// Devuelve la PREPOSICION con el dia adentro ('de hoy' / 'del 15 oct') y no
  /// solo el dia, porque las dos frases donde se usa ya llevan su propia
  /// preposicion: "Citas de ..." y "No hay citas ...". Si esta devolviera solo
  /// 'del 15 oct' habria que pegarle un 'de' adelante y salia "Citas de del 15
  /// oct", que es la forma en que se nota que el helper se extrajo medio penso.
  String _cuando() {
    final fecha = _ctrl.fecha;
    if (_esMismoDia(fecha, DateTime.now())) return 'de hoy';
    return 'del ${fecha.day} ${_mesesCorto[fecha.month - 1].toLowerCase()}';
  }

  /// Color de un estado, tomado de los mismos tokens de `AppColors` que usa la
  /// pantalla de Citas.
  ///
  /// Vive en la vista y no en `Cita` a proposito: el modelo no debe saber de
  /// colores. Se replica el mapeo de `citas_admin_screen.dart` en vez de
  /// importarlo porque el de alla es privado a esa pantalla; cuando haga falta
  /// en tres sitios, lo que corresponde es un helper compartido en `core/mapa` o
  /// `shared/theme`, no un cuarto `switch`.
  Color _colorDeEstado(EstadoCita estado) => switch (estado) {
    EstadoCita.pendiente => AppColors.pendientes,
    EstadoCita.aceptada => AppColors.greenAccent,
    EstadoCita.rechazada => AppColors.atrasadas,
    EstadoCita.esperandoPieza => AppColors.esperandoPieza,
    EstadoCita.enProceso => AppColors.enProceso,
    EstadoCita.completado => AppColors.completado,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context),
      drawer: _buildDrawer(context),
      // `ListenableBuilder` y no `setState`: el `setState` de esta pantalla es
      // para el dialogo del escaner. Los datos los decide el controller y el
      // solo avisa cuando hay que repintar, igual que hace Configuracion.
      body: ListenableBuilder(
        listenable: _ctrl,
        builder: (context, _) => _buildCuerpo(context),
      ),
    );
  }

  Widget _buildCuerpo(BuildContext context) {
    // Solo la PRIMERA carga tapa la pantalla. Un refresco con datos ya pintados
    // no lo hace: tapar todo para volver a pintar lo mismo se siente como que
    // la app se trabo.
    if (_ctrl.cargando) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.orangePrimary),
      );
    }

    return RefreshIndicator(
      // Sirve para cuando el admin cambia el estado de una cita en la pantalla de
      // Citas y vuelve aqui: sin esto, el Dashboard sigue mostrando los numeros
      // de antes del cambio hasta que cierre la app.
      onRefresh: _ctrl.recargar,
      color: AppColors.orangePrimary,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_ctrl.error != null) ...[
              _buildAvisoDeError(_ctrl.error!),
              const SizedBox(height: 12),
            ],
            _buildHeroCard(),
            const SizedBox(height: 16),
            _buildStatCard(
              icon: Icons.directions_car_filled_outlined,
              iconColor: AppColors.blueAccent,
              label: 'VEHÍCULOS EN EL TALLER',
              value: '${_ctrl.vehiculosEnTaller}',
              description: 'Estado: En proceso',
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              icon: Icons.description_outlined,
              iconColor: AppColors.orangePrimary,
              label: 'ÓRDENES ABIERTAS',
              value: '${_ctrl.ordenesAbiertas}',
              description: 'Pendiente + Esperando Pieza + En proceso',
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              icon: Icons.check_circle_outline,
              iconColor: AppColors.greenAccent,
              label: 'COMPLETADAS ${_rotuloFechaTarjeta()}',
              value: '${_ctrl.completadas}',
              description: null,
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              icon: Icons.attach_money,
              iconColor: AppColors.headerNavy,
              label: 'INGRESOS ${_rotuloFechaTarjeta()}',
              value: _ctrl.formatearDinero(_ctrl.ingresos),
              description: 'Solo citas completadas',
            ),
            const SizedBox(height: 20),
            _buildGraficoDeEstados(),
            const SizedBox(height: 20),
            _buildQrScannerCard(),
            const SizedBox(height: 20),
            _buildCitasDelDia(),
          ],
        ),
      ),
    );
  }

  /// Franja de error, arriba de todo, sin tapar lo que ya se pudo leer.
  ///
  /// Se muestra encima de los numeros y no en vez de ellos: si la lectura de las
  /// citas del dia fallo pero el resumen global se pudo hacer, volver a cero es
  /// peor que avisar y dejar lo demas a la vista.
  Widget _buildAvisoDeError(String mensaje) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: AppColors.atrasadas, width: 4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.atrasadas, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(
                color: AppColors.labelDark,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
          TextButton(
            onPressed: _ctrl.recargar,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  /// Hueco reservado para el grafico de `fl_chart`.
  ///
  /// Va aqui y no al final del `Column` porque la caja de datos ya esta lista:
  /// `_ctrl.conteoPorEstado` (los cuatro estados, en numero) y `_ctrl.atrasadas`
  /// son exactamente lo que necesita una barra o un anillo. Falta la direccion
  /// del diseno, asi que por ahora dice que falta y no inventa una visualizacion
  /// que despues haya que tirar.
  /// Anillo de reparto por estado, con el total de citas en el hueco.
  ///
  /// Un anillo y no un pastel cheio porque el hueco del centro es lo unico que
  /// cabe sin tapar informacion: el total, que es el dato que el admin busca
  /// primero ("de cuantas citas estamos hablando"). Con pastel lleno ese total
  /// tendria que ir en un titulo suelto o encima del grafico.
  ///
  /// Es GLOBAL a proposito, mientras las tarjetas de completadas e ingresos son
  /// del dia: un reparto por estado de una sola jornada casi siempre es un pastel
  /// de un solo sector, y un pastel de un solo sector no informa nada. Por eso
  /// lleva el pie 'Acumulado, no solo hoy', para que no se lea como si fuera de
  /// la fecha que se esta mirando.
  ///
  /// Sin porcentajes en la leyenda, a proposito: cuatro porcentajes redondeados
  /// a entero suman 101 o 99 la mayoria de las veces, y antes de que el negocio
  /// defina como se reparte el redondeo, un 101% visible es peor que no
  /// enseñarlo. La proporcion ya se ve en el anillo; la cifra exacta, al lado.
  Widget _buildGraficoDeEstados() {
    final reparto = _ctrl.repartoPorEstado;
    final total = _ctrl.totalCitas;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // `Expanded` en el titulo y no `spaceBetween` con dos textos
              // sueltos: el conteo de la derecha depende de la base ('153 en
              // total'), y sin esto el encabezado revienta en cuanto el numero
              // crece.
              const Expanded(
                child: Text(
                  'Citas por estado',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '$total en total',
                style: const TextStyle(
                  color: AppColors.textGray,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Acumulado, no solo hoy',
            style: TextStyle(color: AppColors.textGray, fontSize: 11),
          ),
          const SizedBox(height: 12),
          if (total == 0)
            // `PieChart` con `sections: []` no dibuja nada, pero el `PieChartData`
            // calcula `sumValue` con `reduce` sobre la lista vacia y revienta. En
            // una base sin citas (taller nuevo, o el admin todavia no ha
            // agendado) el grafico tiene que ser un texto, no un crash.
            const SizedBox(
              height: 140,
              child: Center(
                child: Text(
                  'Todavía no hay citas registradas.',
                  style: TextStyle(color: AppColors.textGray, fontSize: 13),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sections: <PieChartSectionData>[
                        for (final r in reparto)
                          PieChartSectionData(
                            value: r.cantidad.toDouble(),
                            color: _colorDeEstado(r.estado),
                            radius: 56,
                            // El numero va en el centro y en la leyenda, repetido
                            // dentro de la curva no aporta y en un sector chico se
                            // lee mas como manchas que como texto.
                            showTitle: false,
                          ),
                      ],
                      centerSpaceRadius: 38,
                      // El "hueco" tiene que ser el color de la tarjeta o se ve
                      // un disco flotando encima del blanco.
                      centerSpaceColor: AppColors.cardWhite,
                      sectionsSpace: 2,
                      // El toque queda apagado a proposito: la interaccion util
                      // (que sector toco) ya esta resuelta por la leyenda, que es
                      // texto y se puede leer de un vistazo. Un tooltip flotante
                      // encima del grafico taparia justo el sector que explica.
                      pieTouchData: PieTouchData(enabled: false),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$total',
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'citas',
                        style: TextStyle(
                          color: AppColors.textGray,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (final r in reparto) _buildFilaDeLeyenda(r.estado, r.cantidad),
          ],
        ],
      ),
    );
  }

  /// Fila de la leyenda: punto de color, nombre del estado y su cantidad.
  Widget _buildFilaDeLeyenda(EstadoCita estado, int cantidad) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _colorDeEstado(estado),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              estado.etiqueta,
              style: const TextStyle(color: AppColors.textDark, fontSize: 13),
            ),
          ),
          Text(
            '$cantidad',
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Barra superior: ícono de menú (abre el Drawer), título y avatar del usuario.
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final taller = _ctrl.tallerNombre ?? 'SISTEMA DE GESTIÓN';
    final email = _ctrl.adminEmail ?? 'Admin';
    final inicial = email.isNotEmpty ? email[0].toUpperCase() : 'A';

    return AppBar(
      backgroundColor: AppColors.headerNavy,
      iconTheme: const IconThemeData(color: AppColors.background),
      elevation: 0,
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
    );
  }

  /// Menú lateral (Drawer) con la navegación principal de la app.
  Widget _buildDrawer(BuildContext context) {
    final taller = _ctrl.tallerNombre ?? 'SISTEMA DE GESTIÓN';
    final email = _ctrl.adminEmail ?? '';

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
              selected: true,
            ),
            _drawerItem(
              icon: Icons.calendar_today_outlined,
              label: 'Citas',
              selected: false,
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const CitasScreen())),
            ),
            _drawerItem(
              icon: Icons.settings_outlined,
              label: 'Configuración',
              selected: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConfiguracionScreen()),
              ),
            ),
            _drawerItem(
              icon: Icons.manage_accounts_outlined,
              label: 'Editar Perfil',
              selected: false,
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
                onPressed: () async {
                  // `await` porque cerrar sesion ahora tambien borra la caché
                  // local de sesion: sin este orden el proximo arranque entraria
                  // solo al Dashboard y pareceria que el logout no sirvio.
                  //
                  // ANTES de eso va la decision de limpieza local (reglas 1 y
                  // 2 de `LimpiezaLocal`): lee el keystore y purga las citas y
                  // el perfil locales si el usuario NO pidio recordar. Va
                  // primero porque despues `CredencialesSeguras.borrar()`
                  // se lleva la unica evidencia del recordamiento, y porque el
                  // ultimo push necesita la sesion de Auth todavia abierta.
                  await LimpiezaLocal.alCerrarSesion();
                  await SesionAdmin.instance.cerrar();
                  await CredencialesSeguras.borrar();
                  await SyncService.instance.stop();
                  try {
                    await FirebaseAuth.instance.signOut();
                    await FirebaseAuth.instance.signInAnonymously();
                    await SyncService.instance.start();
                  } catch (_) {}
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  }
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

  /// Un ítem individual del menú lateral. Si "selected" es true, se resalta en
  /// naranja (igual que "Dashboard" en el boceto de Figma).
  Widget _drawerItem({
    required IconData icon,
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    return Container(
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

  /// Tarjeta oscura superior: "DASHBOARD / fecha" con selector de fecha funcional.
  Widget _buildHeroCard() {
    final fecha = _ctrl.fecha;
    final bool esHoy = _esMismoDia(fecha, DateTime.now());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.headerNavy,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'DASHBOARD',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            esHoy ? 'Hoy' : _formatearFechaLarga(fecha),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _navCircleButton(Icons.chevron_left, onTap: _ctrl.diaAnterior),
              const SizedBox(width: 10),
              Expanded(child: _buildCampoFechaHero()),
              const SizedBox(width: 10),
              _navCircleButton(Icons.chevron_right, onTap: _ctrl.diaSiguiente),
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
          initialDate: _ctrl.fecha,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (nuevaFecha != null) await _ctrl.seleccionarFecha(nuevaFecha);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatearFechaCorta(_ctrl.fecha),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            // Spinner chico dentro del encabezado mientras se releen las citas
            // del dia. Va ahi y no en un banner porque el unico feedback que
            // importa al cambiar la fecha es "ya casi".
            if (_ctrl.actualizando)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white54,
                ),
              )
            else
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrScannerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
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
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.orangePrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.qr_code_scanner,
                  color: AppColors.orangePrimary,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Escanear QR de cita',
                      style: TextStyle(
                        color: AppColors.labelDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Consulta rápidamente la información de una cita.',
                      style: TextStyle(
                        color: AppColors.textGray,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.inputBorder),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 126,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 126,
                        height: 112,
                        decoration: BoxDecoration(
                          color: AppColors.headerNavy,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.qr_code_2_rounded,
                          color: Colors.white,
                          size: 76,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 28),
                          decoration: BoxDecoration(
                            color: AppColors.orangePrimary,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.orangePrimary.withValues(
                                  alpha: 0.65,
                                ),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'Lector QR · Escaneo simulado',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textGray,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _mostrarCitaEscaneada,
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('Simular escaneo de cita'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.headerNavy,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarCitaEscaneada() {
    // Antes era `demoCitaCompletadaAdmin`: un `SolicitudCitaCliente` de mentira.
    // Ahora muestra una cita REAL de la base. El boton sigue siendo una
    // simulacion (no hay camara todavia), pero lo que ensena es un dato que el
    // admin podria encontrar el mismo en la pantalla de Citas.
    final cita = _ctrl.citasDia.isEmpty ? null : _ctrl.citasDia.first;

    if (cita == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No hay citas para el ${_formatearFechaCorta(_ctrl.fecha)} que escanear.',
          ),
        ),
      );
      return;
    }

    final ahora = DateTime.now();
    final etiquetaEstado = cita.esAtrasada(ahora)
        ? Cita.etiquetaAtrasadas
        : cita.estado.etiqueta;
    final colorEstado = cita.esAtrasada(ahora)
        ? AppColors.atrasadas
        : _colorDeEstado(cita.estado);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Row(
          children: [
            Icon(
              cita.estado == EstadoCita.completado
                  ? Icons.check_circle
                  : Icons.build_circle_outlined,
              color: colorEstado,
              size: 24,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Cita encontrada · ${cita.identificadorParaPantalla}',
                style: const TextStyle(
                  color: AppColors.headerNavy,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _InfoCitaEscaneada(
                label: 'ESTADO',
                value: etiquetaEstado,
                valueColor: colorEstado,
              ),
              _InfoCitaEscaneada(label: 'CLIENTE', value: cita.cliente),
              _InfoCitaEscaneada(
                label: 'TELÉFONO',
                value: cita.telefono.isEmpty ? 'No indicado' : cita.telefono,
              ),
              _InfoCitaEscaneada(label: 'VEHÍCULO', value: cita.vehiculo),
              _InfoCitaEscaneada(
                label: 'PLACA',
                value: cita.placa.isEmpty ? 'No indicada' : cita.placa,
              ),
              _InfoCitaEscaneada(
                label: 'FECHA Y HORA',
                // `fechaCita` viene en UTC de la base; se muestra
                // en el horario local del taller.
                value:
                    '${_formatearFechaCorta(cita.fechaCita.toLocal())} · ${DateFormat('hh:mm a').format(cita.fechaCita.toLocal())}',
              ),
              _InfoCitaEscaneada(
                label: 'SERVICIOS',
                value: cita.servicios.isEmpty
                    ? 'Sin servicios registrados'
                    : cita.servicios.join(', '),
              ),
              _InfoCitaEscaneada(
                label: 'TECNICO',
                value: cita.tecnico.isEmpty ? 'Sin asignar' : cita.tecnico,
              ),
              _InfoCitaEscaneada(
                label: 'TOTAL',
                value: _ctrl.formatearDinero(cita.total),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
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
                Expanded(
                  // 'Citas del día' con la flecha de la fecha en otro dia es la
                  // misma mentira que el rotulo de las tarjetas: el titulo
                  // nombra un dia que no es el que se esta mirando.
                  child: Text(
                    'Citas ${_cuando()}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3F6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_ctrl.citasDia.length} citas',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textGray,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_ctrl.citasDia.isEmpty)
            // Un `DataTable` sin filas pinta solo la cabecera azul y parece una
            // tabla rota. Este dia no hay nada agendado, que es un dato
            // legitimo, y se dice. El texto nombra el dia, por la misma razon
            // que el titulo de arriba.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Text(
                'No hay citas ${_cuando()}.',
                style: const TextStyle(color: AppColors.textGray, fontSize: 13),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(AppColors.headerNavy),
                headingTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                dataTextStyle: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 13,
                ),
                columns: const [
                  DataColumn(label: Text('Cliente')),
                  DataColumn(label: Text('Vehículo')),
                  DataColumn(label: Text('Placa')),
                  DataColumn(label: Text('Servicio')),
                ],
                rows: _ctrl.citasDia
                    .map(
                      (Cita c) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              c.cliente,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          DataCell(Text(c.vehiculo)),
                          DataCell(
                            Text(c.placa.isEmpty ? 'Sin placa' : c.placa),
                          ),
                          DataCell(
                            Text(
                              c.servicios.isEmpty
                                  ? 'Sin servicio'
                                  : c.servicios.join(', '),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoCitaEscaneada extends StatelessWidget {
  const _InfoCitaEscaneada({
    required this.label,
    required this.value,
    this.valueColor = AppColors.labelDark,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 98,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textGray,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

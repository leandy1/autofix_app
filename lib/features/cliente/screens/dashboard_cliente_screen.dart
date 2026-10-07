import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/core/auth/credenciales_seguras.dart';
import 'package:autofix/core/data/limpieza_local.dart';
import 'package:autofix/features/talleres/data/taller_repository.dart';
import 'package:autofix/features/talleres/models/taller.dart';
import 'package:autofix/features/sync/sync_service.dart';
import 'package:autofix/shared/theme/app_colors.dart';
import 'package:autofix/features/auth/screens/login_screen.dart';

import 'agendar_cita_cliente_section.dart';
import 'editar_perfil_cliente_screen.dart';
import 'mis_citas_cliente_section.dart';
import 'talleres_mapa_screen.dart';

class DashboardClienteScreen extends StatefulWidget {
  const DashboardClienteScreen({this.invitado = false, super.key});

  /// El invitado solo explora mapa/talleres; no tiene sesión ni puede agendar.
  final bool invitado;

  @override
  State<DashboardClienteScreen> createState() => _DashboardClienteScreenState();
}

class _DashboardClienteScreenState extends State<DashboardClienteScreen> {
  int _selectedSection = 0;
  String _selectedWorkshop = 'AutoFix Central';

  /// Identificador del taller elegido. Viaja del mapa al formulario y es lo que
  /// se guarda en `citas.taller_id`.
  /// UUID del taller elegido (`String?` desde la v7, no `int?`).
  String? _tallerSeleccionadoId;

  static const _sectionTitles = [
    'Talleres cercanos',
    'Agendar cita',
    'Mis citas',
  ];

  @override
  void initState() {
    super.initState();
    if (!widget.invitado) unawaited(_iniciarSyncEnSegundoPlano());
    _resolverTallerInicial();
  }

  /// Mantiene viva la escucha de conectividad también en la sesión cliente,
  /// para que las citas y cambios de contraseña pendientes se reintenten al
  /// recuperar red.
  Future<void> _iniciarSyncEnSegundoPlano() async {
    try {
      await SyncService.instance.start();
    } catch (e) {
      debugPrint('DashboardCliente: SyncService no arrancó ($e)');
    }
  }

  /// El nombre por defecto es 'AutoFix Central', pero el formulario necesita el
  /// `id` para guardar. Se resuelve contra la base; si ese taller no
  /// existe, queda sin seleccionar y el usuario elige uno desde el mapa.
  ///
  /// El `try` no es cosmético: este metodo se llama desde `initState` con
  /// fire-and-forget, asi que un error de SQLite aqui seria un futuro rechazado
  /// que nadie atrapa. En release eso se va al log y desaparece sin mas, que
  /// fue como se oculto el crash del registro.
  Future<void> _resolverTallerInicial() async {
    try {
      final taller = await TallerRepository.instance.obtenerPorNombre(
        _selectedWorkshop,
      );
      if (!mounted || taller == null) return;
      setState(() => _tallerSeleccionadoId = taller.id);
    } catch (e) {
      debugPrint(
        'DashboardCliente: no se pudo resolver el taller inicial ($e)',
      );
    }
  }

  void _changeSection(int index) {
    setState(() => _selectedSection = index);
  }

  /// Punto único de selección: lo usan el mapa y el selector del formulario.
  void _seleccionarTaller(Taller taller) {
    setState(() {
      _selectedWorkshop = taller.nombre;
      _tallerSeleccionadoId = taller.id;
      _selectedSection = widget.invitado ? 0 : 1;
    });
    if (widget.invitado) unawaited(_pedirSesionParaAgendar());
  }

  /// Si el mapa puede ofrecer "Agendar cita" en esta sesión.
  ///
  /// No alcanza con mirar `invitado` ni con mirar la sesión por separado: un
  /// invitado entra con `DashboardClienteScreen(invitado: true)` y la sesión
  /// local de otro usuario puede seguir restaurada en el dispositivo. Las dos,
  /// juntas, y el mapa repite el chequeo de sesión por su cuenta.
  ///
  /// Mientras esto sea `false` el callback viaja en `null`, que es como
  /// [TalleresMapaScreen] decide desactivar el boton: el Bug 4 existia
  /// justamente porque a un invitado se le pasaba el callback "por las dudas"
  /// y el dialogo de sesion aparecia solo DESPUES del toque.
  bool get _puedeAgendar => !widget.invitado && SesionCliente.haySesion;

  Future<void> _pedirSesionParaAgendar() async {
    final iniciarSesion = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Inicia sesión para agendar'),
        content: const Text(
          'Como invitado puedes explorar talleres y el mapa. Para agendar una '
          'cita, inicia sesión con tu cuenta o crea una.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Seguir viendo'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Iniciar sesión'),
          ),
        ],
      ),
    );
    if (iniciarSesion == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _cerrarSesion() async {
    // La sesion se apaga ANTES de navegar: si se hiciera despues (o nunca),
    // el proximo arranque entraria solo al dashboard y el usuario creeria que
    // no cerro nada. El PERFIL se conserva a proposito, para que la proxima
    // vez que entre el formulario de citas siga prellenado.
    if (!widget.invitado) {
      // PRIMERO la decision de limpieza (reglas 1 y 2 de `LimpiezaLocal`):
      // lee el keystore para saber si el usuario pidio recordar, y purga las
      // citas y el perfil locales si NO lo hizo. Tiene que pasar antes de
      // cualquier `CredencialesSeguras.borrar()` y antes del `signOut`,
      // porque el ultimo push necesita la sesion de Auth todavia abierta.
      //
      // Va DENTRO del `if (!invitado)`: el invitado tambien llega a este
      // metodo por el boton de salir, y el no tiene sesion que cerrar ni
      // permiso para purgar los datos de quien este recordado en el
      // dispositivo.
      await LimpiezaLocal.alCerrarSesion();
      await SyncService.instance.stop();
      await SesionCliente.instance.cerrar();
      await CredencialesSeguras.borrar();
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        debugPrint('DashboardCliente: no se pudo cerrar Firebase Auth ($e)');
      }
    }
    if (!mounted) return;
    if (widget.invitado) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  /// Abre Editar Perfil y, al volver, repinta el saludo.
  ///
  /// El `setState` no es cosmético: el nombre vive en un singleton que ya
  /// cambio, pero `build` no se vuelve a llamar solo al hacer `pop`. Sin este
  /// llamado, cambiar el nombre en el perfil dejaria el AppBar con el viejo
  /// hasta el proximo cambio de seccion.
  Future<void> _editarPerfil() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EditarPerfilClienteScreen()),
    );
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.headerNavy,
        foregroundColor: Colors.white,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AutoFix',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              _sectionTitles[_selectedSection],
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          // Saludo junto al cerrar sesion. Es texto y no un `ListTile`: el
          // AppBar es una barra de 56px y lo que hace falta ahi es el nombre,
          // no una tarjeta. `ellipsis` porque un nombre largo no puede empujar
          // los dos botones fuera de pantalla.
          if (!widget.invitado)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  '¡Hola, ${SesionCliente.instance.nombreVisible}!',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (!widget.invitado)
            IconButton(
              tooltip: 'Editar perfil',
              onPressed: _editarPerfil,
              icon: const Icon(Icons.manage_accounts_outlined),
            ),
          IconButton(
            tooltip: widget.invitado ? 'Volver al login' : 'Cerrar sesión',
            onPressed: _cerrarSesion,
            icon: Icon(widget.invitado ? Icons.login : Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.025, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_selectedSection),
                child: switch (_selectedSection) {
                  0 => TalleresMapaScreen(
                    embeddido: true,
                    tallerSeleccionadoId: _tallerSeleccionadoId,
                    onTallerSelected: _puedeAgendar ? _seleccionarTaller : null,
                  ),
                  1 => AgendarCitaClienteSection(
                    tallerSeleccionado: _selectedWorkshop,
                    tallerSeleccionadoId: _tallerSeleccionadoId,
                    onTallerSelected: (taller) {
                      setState(() {
                        _selectedWorkshop = taller.nombre;
                        _tallerSeleccionadoId = taller.id;
                      });
                    },
                  ),
                  _ => const MisCitasClienteSection(),
                },
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: widget.invitado
          ? null
          : NavigationBar(
              selectedIndex: _selectedSection,
              onDestinationSelected: _changeSection,
              backgroundColor: AppColors.cardWhite,
              indicatorColor: AppColors.orangePrimary.withValues(alpha: 0.14),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.location_on_outlined),
                  selectedIcon: Icon(Icons.location_on),
                  label: 'Talleres',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: 'Agendar',
                ),
                NavigationDestination(
                  icon: Icon(Icons.confirmation_number_outlined),
                  selectedIcon: Icon(Icons.confirmation_number),
                  label: 'Mis citas',
                ),
              ],
            ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:autofix/core/auth/nombre_amigable.dart';
import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/features/admin/screens/dashboard_admin_screen.dart';
import 'package:autofix/features/auth/screens/login_screen.dart';
import 'package:autofix/features/cliente/screens/dashboard_cliente_screen.dart';
import 'package:autofix/features/sync/sync_service.dart';
import 'package:autofix/shared/theme/app_colors.dart';

/// Primera pantalla de la app: decide entre Dashboard y Login.
///
/// ---------------------------------------------------------------
/// POR QUE EXISTE (y por que no es un FutureBuilder)
/// ---------------------------------------------------------------
/// El requisito es que un usuario con sesion guardada entre DIRECTO a su
/// dashboard aunque este sin internet. Para que eso no tenga parpadeo ni
/// pantalla de carga, la sesion se restaura en `main()` antes del `runApp`, de
/// modo que al llegar aca el dato ya esta en memoria y la decision es
/// SINCRONICA: el PRIMER frame ya es la pantalla correcta.
///
/// Un `FutureBuilder` que leyera la cache adentro del `build` mostraria un
/// frame de splash cada arranque (el estado inicial del future), y el test que
/// afirma "la app arranca en el login" dejaria de ser deterministico.
///
/// No verifica la sesion contra Firebase a proposito: esa verificacion requiere
/// red y es exactamente lo que no debe bloquear el arranque. Si el token de
/// Auth vencio, el `SyncService` lo resuelve cuando haya conexion; los datos
/// que el usuario viene a ver (citas, talleres) estan en SQLite y son locales.
class RutaInicial extends StatefulWidget {
  const RutaInicial({super.key});

  @override
  State<RutaInicial> createState() => _RutaInicialState();
}

class _RutaInicialState extends State<RutaInicial> {
  /// El aviso de "sesion restaurada" se muestra UNA vez por arranque, y solo
  /// si de verdad se restauro algo. Sin esta bandera, cualquier rebuild del
  /// `home` repetiria el mensaje.
  bool _anuncioHecho = false;

  @override
  void initState() {
    super.initState();
    final hayAdmin = SesionAdmin.instance.activa;
    final hayCliente = SesionCliente.instance.activa;

    if (hayAdmin) {
      // Sin `await`: el Dashboard se pinta YA y el motor de sincronizacion
      // arranca en paralelo. Es el MISMO arranque que hace el login tras
      // validar credenciales, asi que una sesion fresca y una restaurada
      // terminan con el mismo `SyncService` corriendo: subidas, contador de
      // `CITA-XXXX` y `onSnapshot` funcionan igual vinieran de la red o no.
      //
      // Si Firestore no esta disponible (sin red la primera vez, o Firebase sin
      // inicializar) el fallo se traga aca: no debe impedir entrar al Dashboard.
      unawaited(_arrancarSyncEnSegundoPlano());
    }

    if (hayAdmin || hayCliente) {
      // En un `addPostFrameCallback` y no aca: el `ScaffoldMessenger` vive
      // arriba del Navigator y aun no se sabe si responde durante el
      // `initState`. Ademas, el aviso no debe empujar el primer frame.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _anunciarSesionRestaurada(),
      );
    }
  }

  Future<void> _arrancarSyncEnSegundoPlano() async {
    try {
      await SyncService.instance.start();
    } catch (e) {
      debugPrint('RutaInicial: SyncService no arranco ($e)');
    }
  }

  /// El saludo de la bienvenida: el nombre del cliente si es su sesión, y el
  /// correo del admin (parte antes de la `@`) si es la del taller.
  String get _nombreDeLaSesion {
    if (SesionAdmin.instance.activa) {
      return nombreAmigable(SesionAdmin.instance.adminEmail, reserva: 'admin');
    }
    return SesionCliente.instance.nombreVisible;
  }

  void _anunciarSesionRestaurada() {
    if (_anuncioHecho || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    _anuncioHecho = true;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Sesión restaurada: Bienvenido de nuevo, $_nombreDeLaSesion',
        ),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.headerNavy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (SesionAdmin.instance.activa) {
      return const DashboardScreen();
    }
    if (SesionCliente.instance.activa) {
      return const DashboardClienteScreen();
    }
    return const LoginScreen();
  }
}

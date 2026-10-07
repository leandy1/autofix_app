import 'package:flutter/material.dart';

import 'package:autofix/features/auth/screens/login_screen.dart';

/// Primera pantalla de la app: SIEMPRE el Login.
///
/// ---------------------------------------------------------------
/// POR QUE YA NO DECIDE ENTRE DASHBOARD Y LOGIN
/// ---------------------------------------------------------------
/// Este widget decidia por su cuenta: con la sesion que `main()` restauro desde
/// SharedPreferences, el primer frame era directamente el Dashboard. Ese bypass
/// es el Bug 3: el usuario con sesion guardada no veia nunca el Login, asi que
/// nunca veia `san***` con la clave deshabilitada esperando a que pulse
/// "Ingresar".
///
/// La sesion restaurada sigue existiendo y sigue siendo local (SharedPreferences,
/// sin tocar la red), pero ahora viaja HASTA el Login en memoria y se le muestra
/// ahi: el usuario decide si entrar. Esa decision es la que dispara la validacion
/// (contra Firebase Auth si hay red, contra las credenciales guardadas si no).
///
/// Tampoco arranca `SyncService`: sincronizar antes de que nadie se autentique
/// significaria empujar la cola del usuario anterior con el token del nuevo. El
/// arranque de la sincronizacion vive en cada dashboard, que es quien sabe con
/// que sesion esta trabajando. Lo que SI se sincroniza sin sesion es el catalogo
/// global (talleres y admins), porque no pertenece a nadie: ver
/// `CatalogoSyncService`, que se dispara desde `main()`.
///
/// ---------------------------------------------------------------
/// POR QUE NO HAY SNACKBAR DE "SESION RESTAURADA"
/// ---------------------------------------------------------------
/// Este widget mostraba un aviso flotante ("Sesion restaurada: Bienvenido de
/// nuevo, {nombre}") al arranque con sesion guardada. Es redundante: el Login
/// ya declara esa misma informacion en dos lugares mejores (el campo de usuario
/// con la mascara `san***` y el texto de "Sesion guardada" junto al check de
/// "Recuerdame"), que ademas estan donde el usuario esta mirando cuando decide
/// si entra. Un SnackBar encima solo competia con el formulario y se perdia en
/// 4 segundos. Se elimino en la fase de optimizacion de UX.
///
/// Al no quedar estado que observar, el widget es un `StatelessWidget`: la
/// decision es "pintar el Login" y no cambia durante la vida de la pantalla.
class RutaInicial extends StatelessWidget {
  const RutaInicial({super.key});

  @override
  Widget build(BuildContext context) {
    // Sin excepciones: ni sesion de admin ni sesion de cliente saltan el
    // formulario. El Login es quien muestra la sesion recordada y quien
    // resuelve, con red o sin ella, si esa sesion entra.
    return const LoginScreen();
  }
}

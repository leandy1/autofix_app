import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autofix/core/auth/credenciales_seguras.dart';
import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/cliente/data/cliente_repository.dart';
import 'package:autofix/features/cliente/data/vehiculo_repository.dart';
import 'package:autofix/features/sync/sync_service.dart';

/// Ciclo de vida de los datos LOCALES de un usuario (citas, perfil y vehículos).
///
/// ---------------------------------------------------------------
/// LAS TRES REGLAS QUE ESTE ARCHIVO HACE CUMPLIR
/// ---------------------------------------------------------------
/// 1. **Recuerdame DESACTIVADO = datos temporales.** La app funciona normal y
///    sincroniza todo, pero al cerrar sesion (o al arrancar de nuevo sin
///    sesion) la copia local se purga: nadie pidio guardarla, asi que no
///    debería ocupar espacio ni quedar a disposicion del proximo usuario.
/// 2. **Recuerdame ACTIVADO = datos permanentes.** Mientras la sesion siga
///    restaurandose al abrir la app, las citas y el perfil locales se
///    conservan: es lo que permite entrar offline y ver el historial sin red.
///    Por eso [alArrancar] no purga cuando hay sesion restaurada.
/// 3. **Cambio de usuario = purga total.** Si entra una cuenta distinta a la
///    que dejo los datos, se borran ANTES de arrancar la sincronizacion, para
///    que el `onSnapshot` del usuario nuevo no conviva con filas del anterior
///    y para que su `pushPending` jamas suba la cola del otro.
///
/// ---------------------------------------------------------------
/// QUE SE BORRA Y QUE NO
/// ---------------------------------------------------------------
/// Se borra: `citas`, `clientes` (perfil local) y `vehiculos` del usuario, más
/// la sesión de perfil en SharedPreferences.
///
/// NO se borra: `talleres`, `admins` ni los catalogos de Configuracion. Esos
/// son datos PERMANENTES de la plataforma (Bloque 2), no de una persona, y
/// vaciarlos en un logout dejaria al dispositivo sin mapa ni sin cuentas hasta
/// la proxima sincronizacion.
///
/// NO se borra NADA de Firebase. Toda esta logica es local; lo unico que se
/// acerca a la nube es el ultimo push de lo pendiente, para no tirar un cambio
/// que el usuario hizo sin red.
class LimpiezaLocal {
  LimpiezaLocal._();

  static const String _kUltimoUid = 'limpieza.ultimoUid';

  // ------------------------------------------------------------------
  // PUNTOS DE ENTRADA (los tres que la app llama)
  // ------------------------------------------------------------------

  /// Arranque de la app. Regla 1 y 2: sin sesion restaurada, purgar; con
  /// sesion, conservar.
  ///
  /// Se llama DESPUES de `runApp` y sin `await`: es limpieza de fondo y no
  /// debe demorar el primer frame.
  static Future<void> alArrancar({required bool haySesion}) async {
    if (haySesion) return;
    await purgar(motivo: 'arranque sin sesion');
  }

  /// Cierre de sesion. Regla 1: solo purga si el usuario NO pidio recordar.
  ///
  /// TIENE que correr ANTES de `CredencialesSeguras.borrar()`: la unica
  /// evidencia de que alguien entro con "Recuerdame" son esas credenciales en
  /// el keystore, y el logout de todas las pantallas las borra.
  static Future<void> alCerrarSesion() async {
    if (await hayRecordamiento()) return;
    await purgar(motivo: 'logout sin recordarme');
  }

  /// Login exitoso. Regla 3: purga si la cuenta que entro no es la que dejo
  /// los datos locales.
  ///
  /// [uid] `null` o vacio significa "sin sesion de Firebase Auth" (login sin
  /// red contra las credenciales del keystore). Ahi no se purga: sin uid no
  /// hay con que comparar, y ese camino solo puede ser la MISMA persona que
  /// dejo el recordamiento en este dispositivo.
  static Future<void> alIniciarSesion({required String? uid}) async {
    if (uid == null || uid.trim().isEmpty) return;
    final nuevo = uid.trim();
    final previo = await _leerUltimoUid();
    if (previo == null || previo.isEmpty || previo == nuevo) {
      // Primera cuenta del dispositivo, o la misma de siempre.
      await _guardarUltimoUid(nuevo);
      return;
    }

    await purgar(motivo: 'cambio de usuario ($previo -> $nuevo)');
    await _guardarUltimoUid(nuevo);
  }

  /// `true` si alguien entro con "Recuerdame" (hay credenciales guardadas).
  ///
  /// Nunca lanza: si el keystore no responde se asume QUE SI hay recordamiento
  /// y se conservan los datos. Es la postura conservadora: perder espacio es
  /// preferible a tirar el historial de alguien.
  static Future<bool> hayRecordamiento() async {
    try {
      return await CredencialesSeguras.leer() != null;
    } catch (e) {
      debugPrint('LimpiezaLocal: no se pudo leer el recordamiento ($e)');
      return true;
    }
  }

  // ------------------------------------------------------------------
  // EL PURGE EN SI
  // ------------------------------------------------------------------

  /// Borra la copia local de citas y perfil. Nunca lanza.
  ///
  /// El orden de los cuatro pasos no es cosmético:
  ///
  /// 1. **Parar el listener.** Si el `onSnapshot` sigue vivo mientras se
  ///    borra, cualquier documento que llegue vuelve a insertar filas en una
  ///    base que acabamos de vaciar.
  /// 2. **Ultimo push, solo con red y solo si hay algo que subir.** Una cita
  ///    creada sin internet y nunca subida se perderia con el `DELETE`. Se
  ///    intenta una ultima vez mientras la sesion de Auth todavia esta
  ///    abierta. Con timeout corto: un logout no se puede quedar colgado
  ///    esperando al SDK de Firestore. El chequeo de pendientes va ANTES que
  ///    el de conectividad a proposito: leer `hayConexion` construye el
  ///    `ConnectivityService`, y eso no vale la pena si no hay nada pendiente.
  /// 3. **Borrar.** `citas`, `clientes` y `vehiculos`, fisicamente.
  /// 4. **Olvidar la sesion de perfil.** Lo que quedo en SharedPreferences
  ///    tambien es dato local del usuario.
  static Future<void> purgar({required String motivo}) async {
    try {
      await SyncService.instance.stop();
    } catch (e) {
      debugPrint('LimpiezaLocal: no se pudo parar SyncService ($e)');
    }

    try {
      if (await _hayPendientes() && SyncService.instance.hayConexion) {
        await SyncService.instance.pushPending().timeout(
          const Duration(seconds: 5),
        );
      }
    } catch (e) {
      // Sin red, con la red inestable o tardando mas de 5s: se purga igual.
      // Lo que quede `pending` seguira existiendo en la nube si ya se subio
      // antes; lo que no, se asume temporal (esa es la regla 1).
      debugPrint('LimpiezaLocal: no se pudo hacer el ultimo push ($e)');
    }

    var citas = 0;
    var perfiles = 0;
    var vehiculos = 0;
    try {
      citas = await CitaRepository.instance.borrarTodas();
      perfiles = await ClienteRepository().borrarLocalTodo();
      vehiculos = await VehiculoRepository.instance.borrarLocalTodo();
      await SesionCliente.instance.olvidarTodo();
    } catch (e) {
      debugPrint('LimpiezaLocal: purge incompleto ($e)');
    }

    debugPrint(
      '[LimpiezaLocal] purge ($motivo): $citas citas, $perfiles perfiles, '
      '$vehiculos vehículos',
    );
  }

  // ------------------------------------------------------------------
  // QUIEN DEJO LOS DATOS
  // ------------------------------------------------------------------

  /// `true` si hay algo en las colas de subida local.
  ///
  /// Existe para no consultar la conectividad cuando no hace falta: el
  /// `DELETE` de `purgar` no pierde nada si las dos colas estan vacias, y
  /// construir el `ConnectivityService` tiene un costo (canal de plataforma,
  /// suscripcion) que no se paga si no hay nada que subir.
  static Future<bool> _hayPendientes() async {
    final citas = await CitaRepository.instance.obtenerPendientesDeSync(
      limite: 1,
    );
    if (citas.isNotEmpty) return true;
    final citasFallidas = await CitaRepository.instance.obtenerFallidasDeSync(
      limite: 1,
    );
    if (citasFallidas.isNotEmpty) return true;
    final perfiles = await ClienteRepository().pendientesDeSync(limite: 1);
    if (perfiles.isNotEmpty) return true;
    final correo = SesionCliente.instance.correo?.trim().toLowerCase();
    if (correo == null || correo.isEmpty) return false;
    final vehiculos = await VehiculoRepository.instance.pendientesDeSync(
      correo,
    );
    return vehiculos.isNotEmpty;
  }

  static Future<String?> _leerUltimoUid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kUltimoUid);
    } catch (e) {
      debugPrint('LimpiezaLocal: no se pudo leer el ultimo uid ($e)');
      return null;
    }
  }

  static Future<void> _guardarUltimoUid(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUltimoUid, uid);
    } catch (e) {
      debugPrint('LimpiezaLocal: no se pudo guardar el ultimo uid ($e)');
    }
  }
}

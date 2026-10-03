import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/services.dart';

/// Plataforma de red falsa: deja empujar cambios de estado a mano.
///
/// `Connectivity.onConnectivityChanged` delega en `ConnectivityPlatform.instance`
/// en CADA acceso, asi que sustituir la instancia es lo unico que hace falta
/// para que el servicio de la app escuche este stream y no el del dispositivo.
///
/// Vive en `test/support/` porque lo necesitan los tests de Conectividad Y los
/// de la app: sin esto, el banner solo se puede probar "montado" por accidente
/// (en el entorno de test el plugin no esta registrado y todo parece offline).
class RedFalsa extends ConnectivityPlatform {
  RedFalsa({this.estado = const [ConnectivityResult.wifi]});

  final _controller = StreamController<List<ConnectivityResult>>.broadcast();

  List<ConnectivityResult> estado;

  /// Retraso de la lectura inicial, para simular un MethodChannel lento.
  Duration retardoInicial = Duration.zero;

  /// Emula un plugin no registrado: `checkConnectivity` tira `Exception`.
  bool lecturaInicialFalla = false;

  /// Emula una falla que NO es `Exception` sino `Error`. Un `catch (on
  /// Exception)` se escapa de estas y dejaba el banner muerto.
  bool lecturaInicialRevienta = false;

  int lecturasIniciales = 0;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    lecturasIniciales++;
    if (lecturaInicialFalla) throw MissingPluginException('sin plugin');
    if (lecturaInicialRevienta) throw StateError('falla interna del plugin');
    if (retardoInicial > Duration.zero) {
      await Future<void>.delayed(retardoInicial);
    }
    return estado;
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  /// Simula al usuario apagando o encendiendo el Wi-Fi / los datos en vivo.
  void emitir(List<ConnectivityResult> nuevo) {
    estado = nuevo;
    _controller.add(nuevo);
  }

  /// Emula un stream que muere sin error (el sistema lo mata en background y
  /// el canal no vuelve).
  void revocarStream() => _controller.close();

  Future<void> dispose() => _controller.close();
}
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Fuente de verdad del estado de red de la app.
///
/// Es un [ChangeNotifier] porque el estado de conectividad se observa, no se
/// consulta. La suscripcion al [Stream] vive aqui, a nivel de aplicacion, de
/// modo que sobrevive a la navegacion entre pantallas.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService() {
    _iniciar();
  }

  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _suscripcion;

  List<ConnectivityResult> _resultados = const [ConnectivityResult.none];
  bool _hayConexion = false;

  List<ConnectivityResult> get resultados => List.unmodifiable(_resultados);

  bool get hayConexion => _hayConexion;

  /// Lee el estado actual y abre la escucha continua de cambios.
  ///
  /// El `try/catch` NO es paranoia: `checkConnectivity()` cruza un MethodChannel
  /// y puede reventar con `MissingPluginException` si el plugin no esta
  /// registrado para la plataforma actual (emuladores raros, desktop, tests) o
  /// si la plataforma se negaba. Sin este catch, ese error sube como async
  /// sin manejar y Flutter lo reporta como excepcion no capturada: la app
  /// arranca "crashada" en background por un problema de red que no es grave.
  /// Peor: si este futuro falla, la suscripcion de abajo NUNCA se crea y el
  /// banner queda muerto para toda la sesion. Por eso la suscripcion va FUERA
  /// del try: registrarla es lo importante, leer el estado inicial es lo
  /// secundario.
  Future<void> _iniciar() async {
    try {
      _aplicar(await _connectivity.checkConnectivity());
    } on Exception catch (e) {
      debugPrint('ConnectivityService: no se pudo leer el estado inicial ($e)');
    }

    try {
      _suscripcion = _connectivity.onConnectivityChanged.listen(
        _aplicar,
        // `onError` aparte porque un error en un Stream NO se propaga al
        // `catch` de arriba: viaja por el canal de error del propio listener.
        onError: (Object e) =>
            debugPrint('ConnectivityService: error en el stream ($e)'),
      );
    } on Exception catch (e) {
      // El `.listen()` tambien puede reventar al ACTIVAR el canal, y ese error
      // sale por el `try` porque es sincrono, no por `onError`. Si se llega
      // aca, la app arranca igual: el banner se queda en el estado inicial
      // (`_hayConexion = false`, o sea "sin conexion"), que es la postura
      // segura para una app que sin red igual guarda todo en SQLite.
      // Si esto se rompe en produccion, la extension natural es un
      // `Timer.periodic` que vuelva a pedir `checkConnectivity()`.
      debugPrint('ConnectivityService: no se pudo abrir el stream ($e)');
    }
  }

  void _aplicar(List<ConnectivityResult> resultados) {
    // El plugin reporta una lista porque un dispositivo puede estar conectado
    // a varias redes a la vez (wifi + datos moviles). Sin red significa que
    // la unica via disponible es [ConnectivityResult.none].
    final hayConexion =
        resultados.isNotEmpty && !resultados.contains(ConnectivityResult.none);

    if (hayConexion == _hayConexion && resultados.length == _resultados.length) {
      return;
    }

    _resultados = List.unmodifiable(resultados);
    _hayConexion = hayConexion;
    notifyListeners();
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }
}

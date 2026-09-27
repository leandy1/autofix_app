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
  Future<void> _iniciar() async {
    _aplicar(await _connectivity.checkConnectivity());
    _suscripcion = _connectivity.onConnectivityChanged.listen(_aplicar);
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

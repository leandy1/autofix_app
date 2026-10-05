import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Estado de red segun lo que la app puede afirmar en este instante.
///
/// El tercer estado es el que evita la mentira: al arrancar todavia no se sabe
/// si hay red, asi que no se acusa corte hasta tener evidencia.
enum EstadoRed {
  /// Todavia no se consulto al sistema. No se muestra ni se oculta nada.
  desconocido,

  /// El sistemaairo confirma que no hay ninguna via disponible.
  desconectado,

  /// Hay al menos una via disponible (wifi, datos moviles, ethernet, vpn).
  conectado,
}

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

  /// Reintentos de reescuchar si el stream muere. Acotado a proposito: si la
  /// plataforma quedo inutilizable, insistir para siempre es un bucle que
  /// quema bateria sin chance de éxito.
  static const int _maxReintentos = 3;
  static const Duration _esperaReintento = Duration(seconds: 2);

  int _reintentos = 0;
  bool _descartado = false;

  List<ConnectivityResult> _resultados = const <ConnectivityResult>[];
  EstadoRed _estado = EstadoRed.desconocido;

  List<ConnectivityResult> get resultados => List.unmodifiable(_resultados);

  EstadoRed get estado => _estado;

  /// Atajo para "se que hay red". Miente por omision mientras el estado es
  /// [EstadoRed.desconocido], asi que para decidir QUE MOSTRAR hay que usar
  /// [estado] o [desconectado].
  bool get hayConexion => _estado == EstadoRed.conectado;

  /// Lo unico que debe mirar el banner para enseñar la alarma: hay evidencia
  /// de que se perdio la red, no solo que aun no sabemos.
  bool get desconectado => _estado == EstadoRed.desconectado;

  Future<void> _iniciar() async {
    // ORDEN IMPORTA: primero la escucha, despues la lectura inicial.
    //
    // Al reves (leer primero, suscribir despues) hay una ventana en la que la
    // app esta sorda: si el usuario apaga el Wi-Fi mientras el MethodChannel
    // responde, ese corte no lo ve nadie y el banner queda mostrando "en linea"
    // hasta el siguiente cambio de red, que puede no llegar nunca.
    _escuchar();

    try {
      _aplicar(await _connectivity.checkConnectivity());
    } catch (e) {
      // `catch` sin tipo, no `on Exception`: un `Error` (por ejemplo un
      // `StateError` del propio plugin) NO implementa `Exception` y se escapaba,
      // dejando la app con la lectura inicial a medias. El estado se queda en
      // [EstadoRed.desconocido], que es la postura honesta: no sabemos, no
      // acusamos.
      debugPrint('ConnectivityService: no se pudo leer el estado inicial ($e)');
    }
  }

  void _escuchar() {
    _suscripcion?.cancel();
    _suscripcion = _connectivity.onConnectivityChanged.listen(
      _aplicar,
      // `onError` aparte porque un error en un Stream NO se propaga como
      // excepcion de llamada: viaja por el canal de error del propio listener.
      onError: (Object e) {
        debugPrint('ConnectivityService: error en el stream ($e)');
        _rearmar();
      },
      // El stream puede cerrarse sin error (lo que pasa cuando el sistema lo
      // mata en background y el canal no vuelve). Sin esto el servicio queda
      // escuchando al vacio y el banner congelado para el resto de la sesion.
      onDone: () {
        debugPrint('ConnectivityService: el stream se cerro');
        _rearmar();
      },
      cancelOnError: false,
    );
  }

  void _rearmar() {
    if (_descartado || _reintentos >= _maxReintentos) return;
    _reintentos++;

    Future<void>.delayed(_esperaReintento, () async {
      if (_descartado) return;
      _escuchar();
      try {
        _aplicar(await _connectivity.checkConnectivity());
      } catch (e) {
        debugPrint('ConnectivityService: reintento $_reintentos fallo ($e)');
      }
    });
  }

  void _aplicar(List<ConnectivityResult> resultados) {
    // El plugin reporta una lista porque un dispositivo puede estar conectado
    // a varias redes a la vez (wifi + datos moviles). Sin red significa que la
    // unica via disponible es [ConnectivityResult.none].
    final hay =
        resultados.isNotEmpty && !resultados.contains(ConnectivityResult.none);

    final nuevoEstado = hay ? EstadoRed.conectado : EstadoRed.desconectado;

    // Comparar la lista COMPLETA, no su longitud: pasar de [wifi] a [mobile]
    // mantiene "en linea", asi que el banner no cambia, pero el transporte si
    // y un consumidor que dibuje el icono tiene que enterarse. Con el codigo
    // anterior (comparar solo `length`) ese cambio se tragaba en silencio.
    if (nuevoEstado == _estado && listEquals(_resultados, resultados)) {
      return;
    }

    _reintentos = 0;
    _resultados = List<ConnectivityResult>.unmodifiable(resultados);
    _estado = nuevoEstado;
    notifyListeners();
  }

  @override
  void dispose() {
    // Sin `_descartado`, un reintento pendiente podria volver a llamar
    // `notifyListeners()` sobre un `ChangeNotifier` ya liberado.
    _descartado = true;
    _suscripcion?.cancel();
    super.dispose();
  }
}
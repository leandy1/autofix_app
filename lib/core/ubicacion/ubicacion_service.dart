// =============================================================================
// ubicacion_service.dart
// FLUJO DE PERMISOS + POSICIÓN DEL DISPOSITIVO
//
// VERIFICADO contra geolocator 14.1.1.
//
// NOTA IMPORTANTE (geolocator >= 13.0.0):
//   `getCurrentPosition(desiredAccuracy: ...)` quedo DEPRECADO y en 14.x ya no es
//   la forma correcta. Hay que pasar `locationSettings: LocationSettings(...)`.
//   Tu código original usaba la API vieja; por eso el `flutter analyze` te tiraba
//   deprecated warnings.
//
// Dónde va este archivo en tu proyecto:
//     lib/core/ubicacion/ubicacion_service.dart
// =============================================================================

import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Por qué no se pudo obtener la ubicación. Para que la UI pueda reaccionar
/// distinto a cada caso en vez de pintar un mensaje genérico.
enum EstadoUbicacion {
  /// Ubicación obtained correctamente.
  ok,

  /// El GPS del dispositivo está apagado (ajustes del sistema).
  servicioDesactivado,

  /// El usuario denied el permiso. Puede volver a preguntar.
  permisoDenegado,

  /// El usuario eligió "no volver a preguntar". Solo se resuelve en Ajustes.
  permisoDenegadoPermanente,

  /// El permiso está bien pero el GPS no entregó posición (ej: indoors).
  errorDesconocido,
}

class ResultadoUbicacion {
  const ResultadoUbicacion.ok(this.position)
    : estado = EstadoUbicacion.ok,
      mensaje = '';

  const ResultadoUbicacion.fallido(this.estado, this.mensaje) : position = null;

  final EstadoUbicacion estado;
  final Position? position;
  final String mensaje;

  bool get esOk => estado == EstadoUbicacion.ok;
}

/// Servicio de ubicación. Sin UI: solo lógica. La UI decide cómo mostrarlo.
class UbicacionService {
  const UbicacionService();

  /// Pide los permisos que falten y devuelve la posición del cliente.
  ///
  /// El orden importa y es el correcto:
  ///   1. ¿El GPS está encendido?  (si no, pedir permiso no sirve de nada)
  ///   2. ¿Ya tenemos permiso?     (no molestar al usuario si ya lo dio)
  ///   3. ¿Permiso denegado?       (preguntar)
  ///   4. ¿deniedForever?          (ya no se puede preguntar: ir a Ajustes)
  ///   5. Leer posición.
  Future<ResultadoUbicacion> obtenerPosicion() async {
    // 1. Servicio de ubicación
    final servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) {
      return const ResultadoUbicacion.fallido(
        EstadoUbicacion.servicioDesactivado,
        'El servicio de ubicación está desactivado. Actívalo en los ajustes del sistema.',
      );
    }

    // 2 y 3. Permisos
    var permiso = await Geolocator.checkPermission();

    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }

    // 4. Denegado en esta sesión: se puede volver a intentar luego.
    if (permiso == LocationPermission.denied) {
      return const ResultadoUbicacion.fallido(
        EstadoUbicacion.permisoDenegado,
        'Los permisos de ubicación fueron denegados.',
      );
    }

    // 4b. Denegado para siempre: pedir otra vez no muestra nada.
    //     Solo se resuelve abriendo los ajustes de la app.
    if (permiso == LocationPermission.deniedForever) {
      return const ResultadoUbicacion.fallido(
        EstadoUbicacion.permisoDenegadoPermanente,
        'El permiso de ubicación está denegado de forma permanente. '
        'Actívalo desde los ajustes de la aplicación.',
      );
    }

    // 5. Posición.
    try {
      // geolocator >= 13: así se pide la precisión. NO usar desiredAccuracy:.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return ResultadoUbicacion.ok(position);
    } on TimeoutException {
      return const ResultadoUbicacion.fallido(
        EstadoUbicacion.errorDesconocido,
        'No se pudo obtener la ubicación a tiempo. Intenta de nuevo.',
      );
    } catch (_) {
      return const ResultadoUbicacion.fallido(
        EstadoUbicacion.errorDesconocido,
        'Ocurrió un error al obtener la ubicación.',
      );
    }
  }

  /// Abre los ajustes de la aplicación (para el caso deniedForever).
  ///
  /// ⚠️ UX: NO lo llames solo. Muestra un botón "Abrir ajustes" y que el usuario
  ///    lo pulse. Arrastrar al usuario a Ajustes sin explicar por qué es una de
  ///    las quejas más comunes en las reseñas de apps.
  Future<bool> abrirAjustesDeLaApp() => Geolocator.openAppSettings();

  /// Abre los ajustes de ubicación del SISTEMA (para GPS apagado).
  Future<bool> abrirAjustesDeUbicacion() => Geolocator.openLocationSettings();
}

/// Distancia en kilómetros entre dos coordenadas, redondeada a 1 decimal.
///
/// `Geolocator.distanceBetween` sigue existiendo en geolocator 14.x
/// (devuelve metros, en double). Esta función existe para que el resto de tu
/// código no tenga que acordarse de dividir entre 1000 y redondear.
double distanciaEnKm({
  required double lat1,
  required double lng1,
  required double lat2,
  required double lng2,
}) {
  final metros = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  return double.parse((metros / 1000).toStringAsFixed(1));
}

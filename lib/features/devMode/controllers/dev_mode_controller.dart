import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;

import 'package:autofix/features/talleres/data/taller_repository.dart';
import 'package:autofix/features/talleres/models/taller.dart';

class DevModeController extends ChangeNotifier {
  DevModeController({TallerRepository? talleres})
    : _talleresRepository = talleres ?? TallerRepository.instance;

  final TallerRepository _talleresRepository;
  List<Taller> _talleres = const [];
  bool _cargando = false;
  String? _error;

  List<Taller> get talleres => List.unmodifiable(_talleres);
  bool get cargando => _cargando;
  String? get error => _error;

  static double? leerCoordenada(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  static String formatearCoordenada(double value) =>
      value.toString().replaceAll('.', ',');

  static String? validarCoordenada(
    String? value, {
    required double minimo,
    required double maximo,
    required String nombre,
  }) {
    final coordenada = leerCoordenada(value ?? '');
    if (coordenada == null || !coordenada.isFinite) {
      return 'Escribe una $nombre válida.';
    }
    if (coordenada < minimo || coordenada > maximo) {
      return 'La $nombre debe estar entre $minimo y $maximo.';
    }
    return null;
  }

  Future<void> cargarTalleres() async {
    _cargando = true;
    _error = null;
    notifyListeners();

    try {
      _talleres = await _talleresRepository.obtenerTodas();
    } on Exception catch (error) {
      _error = _mensajeDe(error);
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  Future<void> _sincronizarConFirebase(String id) async {
    try {
      final guardado = await _talleresRepository.obtenerPorId(id);
      if (guardado != null) {
        await FirebaseFirestore.instance
            .collection('talleres')
            .doc(id)
            .set(guardado.toMap(), SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('[DevModeController] Error sincronizando taller $id a Firebase: $e');
    }
  }

  Future<bool> guardarTaller(Taller taller) async {
    final nombre = taller.nombre.trim();
    if (nombre.isEmpty) {
      return _fallar('El nombre del taller no puede quedar vacío.');
    }
    if (!taller.latitud.isFinite ||
        taller.latitud < -90 ||
        taller.latitud > 90) {
      return _fallar('Escribe una latitud válida entre -90 y 90.');
    }
    if (!taller.longitud.isFinite ||
        taller.longitud < -180 ||
        taller.longitud > 180) {
      return _fallar('Escribe una longitud válida entre -180 y 180.');
    }

    final tallerLimpio = taller.copyWith(
      nombre: nombre,
      direccion: taller.direccion.trim(),
      telefono: taller.telefono.trim(),
    );

    try {
      String idTaller;
      if (tallerLimpio.id == null) {
        final existente = await _talleresRepository.obtenerPorNombre(nombre);
        if (existente != null) {
          if (existente.activo) {
            return _fallar('Ya existe un taller con ese nombre.');
          }
          final actualizarTaller = existente.copyWith(
            nombre: nombre,
            direccion: tallerLimpio.direccion,
            telefono: tallerLimpio.telefono,
            latitud: tallerLimpio.latitud,
            longitud: tallerLimpio.longitud,
            activo: true,
          );
          await _talleresRepository.actualizar(actualizarTaller);
          idTaller = actualizarTaller.id!;
        } else {
          idTaller = await _talleresRepository.crear(tallerLimpio);
        }
      } else {
        await _talleresRepository.actualizar(tallerLimpio);
        idTaller = tallerLimpio.id!;
      }

      await _sincronizarConFirebase(idTaller);

      _talleres = await _talleresRepository.obtenerTodas();
      _error = null;
      notifyListeners();
      return true;
    } on Exception catch (error) {
      return _fallar(_mensajeDe(error));
    }
  }

  /// El id es el UUID del taller (`String`) desde la v7, no el autoincremento.
  Future<bool> darDeBajaTaller(String id) async {
    try {
      await _talleresRepository.darDeBaja(id);
      
      await _sincronizarConFirebase(id);

      _talleres = await _talleresRepository.obtenerTodas();
      _error = null;
      notifyListeners();
      return true;
    } on Exception catch (error) {
      return _fallar(_mensajeDe(error));
    }
  }

  bool _fallar(String mensaje) {
    _error = mensaje;
    notifyListeners();
    return false;
  }

  String _mensajeDe(Exception error) {
    if (error is DatabaseException && error.isUniqueConstraintError()) {
      return 'Ya existe un taller con ese nombre.';
    }
    return 'No se pudo guardar el taller: $error';
  }
}

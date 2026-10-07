import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Cliente pequeño para NHTSA vPIC. No requiere API key y solamente consulta
/// los datos necesarios para los selectores de marca, año y modelo.
class CatalogoVehiculosApi {
  CatalogoVehiculosApi({http.Client? cliente, this.preferencias})
    : _cliente = cliente ?? http.Client();

  static const String _host = 'vpic.nhtsa.dot.gov';
  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _cliente;
  final SharedPreferences? preferencias;
  SharedPreferences? _preferencias;

  Future<List<String>> obtenerMarcas({required bool enLinea}) async {
    const claveCache = 'catalogo_vehiculos_marcas_vpic_v1';
    if (!enLinea) {
      return await _leerCache(claveCache) ?? const <String>[];
    }

    final uri = Uri.https(_host, '/api/vehicles/GetMakesForVehicleType/car', {
      'format': 'json',
    });
    try {
      final json = await _obtenerJson(uri);
      final resultados = _resultados(json);
      final marcas =
          resultados
              .map((item) => item['MakeName']?.toString().trim() ?? '')
              .where((nombre) => nombre.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (marcas.isEmpty) {
        throw const FormatException('La API no devolvió marcas.');
      }
      await _guardarCache(claveCache, marcas);
      return marcas;
    } on Object {
      final cache = await _leerCache(claveCache);
      if (cache != null) return cache;
      rethrow;
    }
  }

  Future<List<String>> obtenerModelos({
    required String marca,
    required int anio,
    required bool enLinea,
  }) async {
    final claveCache =
        'catalogo_vehiculos_modelos_vpic_v1_${Uri.encodeComponent(marca.toLowerCase())}_$anio';
    if (!enLinea) {
      return await _leerCache(claveCache) ?? const <String>[];
    }

    final segmentoMarca = Uri.encodeComponent(marca.trim());
    final uri = Uri.parse(
      'https://$_host/api/vehicles/GetModelsForMakeYear/'
      'make/$segmentoMarca/modelyear/$anio?format=json',
    );
    try {
      final json = await _obtenerJson(uri);
      final modelos =
          _resultados(json)
              .map(
                (item) =>
                    (item['Model_Name'] ?? item['ModelName'])
                        ?.toString()
                        .trim() ??
                    '',
              )
              .where((nombre) => nombre.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      await _guardarCache(claveCache, modelos);
      return modelos;
    } on Object {
      final cache = await _leerCache(claveCache);
      if (cache != null) return cache;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _obtenerJson(Uri uri) async {
    final respuesta = await _cliente
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(_timeout);
    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      throw http.ClientException(
        'NHTSA respondió HTTP ${respuesta.statusCode}.',
        uri,
      );
    }
    final decoded = jsonDecode(respuesta.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'La respuesta de NHTSA no es un objeto JSON.',
      );
    }
    return decoded;
  }

  List<Map<String, dynamic>> _resultados(Map<String, dynamic> json) {
    final raw = json['Results'];
    if (raw is! List) {
      throw const FormatException('La respuesta de NHTSA no contiene Results.');
    }
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<List<String>?> _leerCache(String clave) async {
    try {
      final preferencias = await _obtenerPreferencias();
      if (preferencias == null) return null;
      final contenido = preferencias.getString(clave);
      if (contenido == null) return null;
      final decoded = jsonDecode(contenido);
      if (decoded is! List) return null;
      return decoded.map((valor) => valor.toString()).toList(growable: false);
    } on Object {
      return null;
    }
  }

  Future<void> _guardarCache(String clave, List<String> valores) async {
    try {
      final preferencias = await _obtenerPreferencias();
      if (preferencias == null) return;
      await preferencias.setString(clave, jsonEncode(valores));
    } on Object {
      // El guardado local del vehículo no depende de que el plugin de prefs esté
      // disponible; la UI tiene además marcas comunes y entrada manual.
    }
  }

  Future<SharedPreferences?> _obtenerPreferencias() async {
    try {
      return _preferencias ??=
          preferencias ?? await SharedPreferences.getInstance();
    } on Object {
      return null;
    }
  }

  void close() => _cliente.close();
}

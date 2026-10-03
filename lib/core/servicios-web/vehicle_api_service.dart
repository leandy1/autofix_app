import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/vehicle_make.dart';

class VehicleApiService {
  VehicleApiService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<VehicleMake>> obtenerMarcas() async {
    final uri = Uri.https(
      'carapi.app',
      '/api/makes/v2',
    );

    final response = await _client
        .get(
          uri,
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Error al consultar las marcas (HTTP ${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('La API devolvió un formato inválido.');
    }

    final rows = decoded['data'];

    if (rows is! List) {
      throw Exception('La API devolvió una lista de marcas inválida.');
    }

    return rows
        .whereType<Map<String, dynamic>>()
        .map(VehicleMake.fromCarApi)
        .toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
  }

  Future<List<String>> obtenerModelos({
    required String marca,
    int? anio,
  }) async {
    final queryParameters = <String, String>{
      'make': marca,
    };

    if (anio != null) {
      queryParameters['year'] = '$anio';
    }

    final uri = Uri.https(
      'carapi.app',
      '/api/models/v2',
      queryParameters,
    );

    final response = await _client
        .get(
          uri,
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Error al consultar los modelos (HTTP ${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic> || decoded['data'] is! List) {
      throw Exception('La API devolvió un formato de modelos inválido.');
    }

    final rows = decoded['data'] as List;

    return rows
        .whereType<Map<String, dynamic>>()
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort(
        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );
  }

}

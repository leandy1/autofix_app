import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/vehicle_make.dart';

class CarApiException implements Exception {
  const CarApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CarApiService {
  CarApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<VehicleMake>> getMakes() async {
    final uri = Uri.https('carapi.app', '/api/makes/v2');

    final response = await _client
        .get(
          uri,
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 20));

    final json = _decode(response);
    final rows = json['data'];

    if (rows is! List) {
      throw const CarApiException(
        'CarAPI devolvió una lista de marcas inválida.',
      );
    }

    return rows
        .whereType<Map<String, dynamic>>()
        .map(VehicleMake.fromCarApi)
        .toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
  }

  Future<List<String>> getModels({
    required String make,
    int? year,
  }) async {
    final queryParameters = <String, String>{
      'make': make,
    };

    if (year != null) {
      queryParameters['year'] = '$year';
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

    final json = _decode(response);
    final rows = json['data'];

    if (rows is! List) {
      throw const CarApiException(
        'CarAPI devolvió una lista de modelos inválida.',
      );
    }

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

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CarApiException(
        'Error de CarAPI (HTTP ${response.statusCode}). '
        'Comprueba conexión y disponibilidad de datos.',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw const CarApiException(
        'CarAPI devolvió JSON con formato inválido.',
      );
    }

    return decoded;
  }

  void close() => _client.close();
}

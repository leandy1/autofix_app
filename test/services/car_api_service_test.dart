import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../lib/services/car_api_service.dart';

void main() {
  group('CarApiService', () {
    test('obtiene marcas desde CarAPI', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/makes/v2');

        return http.Response(
          '''
          {
            "data": [
              {"id": 1, "name": "Toyota"},
              {"id": 2, "name": "Honda"}
            ]
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = CarApiService(client: client);

      final makes = await service.getMakes();

      expect(makes.length, 2);
      expect(makes[0].name, 'Honda');
      expect(makes[1].name, 'Toyota');
      expect(makes.every((make) => !make.isCustom), isTrue);
    });

    test('obtiene modelos por marca sin año', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/models/v2');
        expect(request.url.queryParameters['make'], 'Toyota');
        expect(request.url.queryParameters.containsKey('year'), isFalse);

        return http.Response(
          '''
          {
            "data": [
              {"id": 1, "name": "Camry"},
              {"id": 2, "name": "Corolla"}
            ]
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = CarApiService(client: client);

      final models = await service.getModels(make: 'Toyota');

      expect(models, ['Camry', 'Corolla']);
    });

    test('lanza CarApiException ante un error HTTP', () async {
      final client = MockClient((request) async {
        return http.Response(
          '{"message":"Server error"}',
          500,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = CarApiService(client: client);

      expect(
        () => service.getMakes(),
        throwsA(isA<CarApiException>()),
      );
    });
  });
}

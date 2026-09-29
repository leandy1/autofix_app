import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import "package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart";
import "package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart";

import '../../lib/models/vehicle_make.dart';
import '../../lib/services/car_api_service.dart';
import '../../lib/services/vehicle_catalog_service.dart';

class FakeCarApiService extends CarApiService {
  FakeCarApiService({
    required this.makes,
    required this.models,
  });

  final List<VehicleMake> makes;
  final List<String> models;

  @override
  Future<List<VehicleMake>> getMakes() async => makes;

  @override
  Future<List<String>> getModels({
    required String make,
    int? year,
  }) async {
    return models;
  }
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('VehicleCatalogService', () {
    test('combina marcas de CarAPI con marcas personalizadas', () async {
      final preferences = SharedPreferencesAsync();
      await preferences.clear();

      final carApi = FakeCarApiService(
        makes: const [
          VehicleMake(name: 'Toyota', isCustom: false),
          VehicleMake(name: 'Honda', isCustom: false),
        ],
        models: const [],
      );

      final service = VehicleCatalogService(
        carApi: carApi,
        preferences: preferences,
      );

      await service.addCustomMake('Nissan');

      final makes = await service.getMakes();

      expect(makes.map((make) => make.name), [
        'Honda',
        'Nissan',
        'Toyota',
      ]);

      expect(
        makes.firstWhere((make) => make.name == 'Nissan').isCustom,
        isTrue,
      );
    });

    test('no duplica una marca personalizada', () async {
      final preferences = SharedPreferencesAsync();
      await preferences.clear();

      final carApi = FakeCarApiService(
        makes: const [],
        models: const [],
      );

      final service = VehicleCatalogService(
        carApi: carApi,
        preferences: preferences,
      );

      await service.addCustomMake('Nissan');
      await service.addCustomMake('nissan');

      final makes = await service.getMakes();

      expect(
        makes.where((make) => make.name.toLowerCase() == 'nissan').length,
        1,
      );
    });

    test('obtiene modelos mediante CarAPI', () async {
      final preferences = SharedPreferencesAsync();
      await preferences.clear();

      final carApi = FakeCarApiService(
        makes: const [],
        models: const ['Camry', 'Corolla'],
      );

      final service = VehicleCatalogService(
        carApi: carApi,
        preferences: preferences,
      );

      final models = await service.getModels(make: 'Toyota');

      expect(models, ['Camry', 'Corolla']);
    });
  });
}

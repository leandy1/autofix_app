import 'package:shared_preferences/shared_preferences.dart';

import '../models/vehicle_make.dart';
import 'car_api_service.dart';

class VehicleCatalogService {
  VehicleCatalogService({
    required this.carApi,
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  final CarApiService carApi;
  final SharedPreferencesAsync _preferences;

  static const _customMakesKey = 'autofix_custom_vehicle_makes';

  Future<List<VehicleMake>> getMakes() async {
    final customNames =
        await _preferences.getStringList(_customMakesKey) ?? <String>[];

    final apiMakes = await carApi.getMakes();

    final names = <String, VehicleMake>{
      for (final make in apiMakes) _key(make.name): make,
    };

    for (final name in customNames) {
      names.putIfAbsent(
        _key(name),
        () => VehicleMake.custom(name),
      );
    }

    return names.values.toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
  }

  Future<VehicleMake> addCustomMake(String input) async {
    final name = input.trim();

    if (name.length < 2) {
      throw const CarApiException('Escribe una marca válida.');
    }

    final saved =
        await _preferences.getStringList(_customMakesKey) ?? <String>[];

    final duplicate = saved.any(
      (item) => _key(item) == _key(name),
    );

    if (!duplicate) {
      saved.add(name);
      await _preferences.setStringList(
        _customMakesKey,
        saved,
      );
    }

    return VehicleMake.custom(name);
  }

  Future<List<String>> getModels({
    required String make,
    int? year,
  }) {
    return carApi.getModels(
      make: make,
      year: year,
    );
  }

  String _key(String value) => value.trim().toLowerCase();
}

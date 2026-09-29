class VehicleMake {
  const VehicleMake({
    required this.name,
    required this.isCustom,
  });

  final String name;
  final bool isCustom;

  factory VehicleMake.fromCarApi(Map<String, dynamic> json) {
    return VehicleMake(
      name: json['name'] as String,
      isCustom: false,
    );
  }

  factory VehicleMake.custom(String name) {
    return VehicleMake(name: name, isCustom: true);
  }
}

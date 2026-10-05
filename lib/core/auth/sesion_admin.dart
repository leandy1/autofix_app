/// Sesión activa del administrador.
///
/// Singleton liviano que guarda el `tallerId` del admin logueado para que
/// todos los componentes (CitasController, SyncService) filtren por taller
/// sin tener que pasarse el dato unos a otros.
class SesionAdmin {
  SesionAdmin._();

  static final SesionAdmin instance = SesionAdmin._();

  String? _tallerId;
  String? _adminUid;

  /// `tallerId` del admin autenticado, o `null` si no hay sesión de admin.
  String? get tallerId => _tallerId;

  /// UID de Firebase Auth del admin, o `null` si no hay sesión.
  String? get adminUid => _adminUid;

  /// `true` si hay un admin logueado con taller asignado.
  bool get activa => _tallerId != null;

  void iniciar({required String tallerId, required String adminUid}) {
    _tallerId = tallerId;
    _adminUid = adminUid;
  }

  void cerrar() {
    _tallerId = null;
    _adminUid = null;
  }
}


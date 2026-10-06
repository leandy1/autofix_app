/// Sesión activa del administrador.
///
/// Singleton liviano que guarda el `tallerId` del admin logueado para que
/// todos los componentes (CitasController, SyncService) filtren por taller
/// sin tener que pasarse el dato unos a otros.
class SesionAdmin {
  SesionAdmin._();

  static final SesionAdmin instance = SesionAdmin._();

  String? _tallerId;
  String? _tallerNombre;
  String? _adminUid;
  String? _adminEmail;

  /// `tallerId` del admin autenticado, o `null` si no hay sesión de admin.
  String? get tallerId => _tallerId;

  /// Nombre del taller asignado al admin.
  String? get tallerNombre => _tallerNombre;

  /// UID de Firebase Auth del admin, o `null` si no hay sesión.
  String? get adminUid => _adminUid;

  /// Correo del admin autenticado.
  String? get adminEmail => _adminEmail;

  /// `true` si hay un admin logueado con taller asignado.
  bool get activa => _tallerId != null;

  void iniciar({
    required String tallerId,
    required String adminUid,
    String? tallerNombre,
    String? adminEmail,
  }) {
    _tallerId = tallerId;
    _adminUid = adminUid;
    _tallerNombre = tallerNombre;
    _adminEmail = adminEmail;
  }

  void cerrar() {
    _tallerId = null;
    _tallerNombre = null;
    _adminUid = null;
    _adminEmail = null;
  }
}

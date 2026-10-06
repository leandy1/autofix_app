import 'package:autofix/core/auth/sesion_cache.dart';

/// Sesión activa del administrador.
///
/// Singleton liviano que guarda el `tallerId` del admin logueado para que
/// todos los componentes (CitasController, SyncService) filtren por taller
/// sin tener que pasarse el dato unos a otros.
///
/// ---------------------------------------------------------------
/// PERSISTENCIA (Modo "Recuérdame" / arranque offline)
/// ---------------------------------------------------------------
/// La sesión vive en memoria (rapida, sincronica) Y en disco ([SesionCache]).
/// El flujo completo es:
///
///   1. Login con internet -> [iniciar] llena la memoria y persiste.
///   2. Siguiente arranque sin internet -> `main()` llama a [restaurar] ANTES
///      de montar la primera pantalla, la memoria ya tiene el `tallerId` y la
///      ruta inicial entra directo al Dashboard sin tocar Firebase.
///   3. Cerrar sesión -> [cerrar] limpia memoria y disco, para que el proximo
///      arranque vuelva al login.
///
/// Los dos pasos de escritura (memoria y disco) ocurren ANTES del primer
/// `await` o inmediatamente despues: si el plugin de prefs no esta disponible
/// (tests, plataforma rara), la sesion sigue viva para ESTA ejecucion aunque
/// no se pueda recordar para la proxima.
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

  /// Abre sesión en memoria y la deja persistida en disco.
  ///
  /// El caller (LoginController) debe `await` esto para que el login recien
  /// entonces navegue al Dashboard: si no, una app cerrada a mitad del guardado
  /// arrancaria la proxima vez sin sesion.
  Future<void> iniciar({
    required String tallerId,
    required String adminUid,
    String? tallerNombre,
    String? adminEmail,
  }) async {
    _tallerId = tallerId;
    _adminUid = adminUid;
    _tallerNombre = tallerNombre;
    _adminEmail = adminEmail;
    await SesionCache.guardar(
      SesionPersistida(
        tallerId: tallerId,
        adminUid: adminUid,
        tallerNombre: tallerNombre,
        adminEmail: adminEmail,
      ),
    );
  }

  /// Cierra sesión en memoria Y borra la caché local.
  ///
  /// Sin el borrado de disco, "Cerrar sesión" dejaria la sesion guardada y el
  /// proximo arranque entraria solo al Dashboard: el usuario creeria que no
  /// cerro nada.
  Future<void> cerrar() async {
    _tallerId = null;
    _tallerNombre = null;
    _adminUid = null;
    _adminEmail = null;
    await SesionCache.borrar();
  }

  /// Restaura la sesión guardada en la última ejecución.
  ///
  /// Devuelve `true` si había una: es lo que la ruta inicial mira para decidir
  /// entre Dashboard y Login en el PRIMER frame, sin esperas ni spinner.
  ///
  /// Si ya hay sesión en memoria (se llamo al login o ya se restauro) no hace
  /// nada y devuelve `true`: volver a leer el disco solo podria pisar datos
  /// vivos con una caché mas vieja.
  Future<bool> restaurar() async {
    if (activa) return true;
    final guardada = await SesionCache.leer();
    if (guardada == null) return false;
    _tallerId = guardada.tallerId;
    _adminUid = guardada.adminUid;
    _tallerNombre = guardada.tallerNombre;
    _adminEmail = guardada.adminEmail;
    return true;
  }
}

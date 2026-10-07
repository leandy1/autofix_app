import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autofix/core/auth/nombre_amigable.dart';

/// Sesión y perfil del cliente, en un solo objeto.
///
/// ---------------------------------------------------------------
/// POR QUE UNA CLAVE Y NO DOS
/// ---------------------------------------------------------------
/// El cliente valida su identidad en Firebase Auth. Este singleton mantiene
/// una copia local del perfil y la decisión de Recuérdame para que el dashboard
/// y el formulario de citas puedan abrir sin red tras una sesión recordada.
/// Sin este singleton, el saludo del AppBar ("¡Hola, Maria!"), el prellenado
/// del formulario de citas y Editar Perfil no tendrian una fuente local común.
///
/// Guarda el PERFIL (nombre/correo/teléfono) y la bandera de SESIÓN activa en
/// la misma tanda de claves porque se escriben juntos siempre; pero son dos
/// cosas y [cerrar] lo demuestra: apaga la sesión y DEJA el perfil.
///
/// Por qué [cerrar] conserva el perfil: al cerrar sesión el cliente no borra
/// su identidad, solo sale de la app. Si se tirara el nombre, la proxima vez
/// que entre el formulario de citas estaria vacío, que es justo lo que el
/// requisito de prellenado quiere evitar. Solo [olvidarTodo] borra los datos.
///
/// Igual que `SesionAdmin`: la memoria se llena ANTES del primer `await`
/// (o inmediatamente despues de leer el plugin), para que una app que no puede
/// persistir al menos funcione durante ESTA ejecucion.
class SesionCliente {
  SesionCliente._();

  static final SesionCliente instance = SesionCliente._();

  static const String _kActiva = 'sesionCliente.activa';
  static const String _kNombre = 'sesionCliente.nombre';
  static const String _kCorreo = 'sesionCliente.correo';
  static const String _kTelefono = 'sesionCliente.telefono';

  String? _nombre;
  String? _correo;
  String? _telefono;
  bool _activa = false;

  /// `true` cuando el cliente entro y no cerro sesión: es lo que la ruta
  /// inicial mira para arrancar directo en su dashboard.
  bool get activa => _activa;

  String? get nombre => _nombre;
  String? get correo => _correo;
  String? get telefono => _telefono;

  /// Como se le habla en el saludo y en la bienvenida.
  ///
  /// Usa el nombre si lo hay; si no, el correo (la mascara antes de la `@`);
  /// y si no hay ninguno, "cliente".
  String get nombreVisible =>
      nombreAmigable(_nombre ?? _correo, reserva: 'cliente');

  /// `true` cuando hay una sesión de cliente utilizable.
  ///
  /// Mira las DOS fuentes porque son caminos de entrada distintos y ambos
  /// legitimos: la de Firebase Auth (login con red) y la local que `main()`
  /// restauro desde SharedPreferences (login sin red, validando contra las
  /// credenciales del keystore).
  ///
  /// La que NO cuenta es la del invitado: ese rol no tiene sesión de ninguna
  /// de las dos formas, y es lo que impide que vea "Agendar cita".
  ///
  /// Nunca lanza: si Firebase no esta inicializado (tests, plataforma rara)
  /// se queda con la sesion local.
  static bool get haySesion {
    try {
      if (FirebaseAuth.instance.currentUser != null) return true;
    } catch (e) {
      debugPrint(
        'SesionCliente: sin Firebase Auth, usando la sesion local ($e)',
      );
    }
    return instance.activa;
  }

  /// Abre sesión en memoria y, si [persistir] es `true`, la guarda localmente.
  ///
  /// Los parametros son `String?` y `null` significa "no se, no toques": el
  /// `null` significa que la fuente no trae ese dato y no debe borrar un valor
  /// anterior del perfil local.
  Future<void> iniciar({
    String? nombre,
    String? correo,
    String? telefono,
    bool persistir = true,
  }) async {
    _activa = true;
    _aplicar(nombre: nombre, correo: correo, telefono: telefono);
    if (persistir) {
      await _persistir();
    } else {
      await _borrarPersistenciaSesion();
    }
  }

  /// Actualiza el perfil desde la pantalla de Editar Perfil.
  ///
  /// Aca si se escriben los tres campos siempre (el formulario los tiene
  /// todos), y un campo vacio BORRA: que el usuario borre su teléfono y que
  /// quede el viejo seria mentirle sobre lo que guardo.
  Future<void> guardarPerfil({
    required String nombre,
    required String correo,
    required String telefono,
  }) async {
    _aplicar(nombre: nombre, correo: correo, telefono: telefono);
    await _persistir();
  }

  /// Cierra sesión dejando el perfil intacto. Ver el por qué en la doc de la
  /// clase.
  Future<void> cerrar() async {
    _activa = false;
    await _persistir();
  }

  /// Restaura la sesión del último arranque. Devuelve `true` si había una.
  Future<bool> restaurar() async {
    if (_activa) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kActiva) != true) return false;
      _nombre = prefs.getString(_kNombre);
      _correo = prefs.getString(_kCorreo);
      _telefono = prefs.getString(_kTelefono);
      _activa = true;
      return true;
    } catch (e) {
      debugPrint('SesionCliente: no se pudo restaurar ($e)');
      return false;
    }
  }

  /// Borra sesión Y perfil, de memoria y de disco.
  ///
  /// Solo para pruebas y para un futuro "eliminar mi cuenta" local: [cerrar]
  /// es el camino normal de logout.
  Future<void> olvidarTodo() async {
    _nombre = null;
    _correo = null;
    _telefono = null;
    _activa = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kActiva);
      await prefs.remove(_kNombre);
      await prefs.remove(_kCorreo);
      await prefs.remove(_kTelefono);
    } catch (e) {
      debugPrint('SesionCliente: no se pudo olvidar todo ($e)');
    }
  }

  void _aplicar({String? nombre, String? correo, String? telefono}) {
    // `null` = no tocar (el que llama no sabe); `''` = borrar el dato.
    if (nombre != null) _nombre = _normalizar(nombre);
    if (correo != null) _correo = _normalizar(correo);
    if (telefono != null) _telefono = _normalizar(telefono);
  }

  String? _normalizar(String valor) {
    final limpio = valor.trim();
    return limpio.isEmpty ? null : limpio;
  }

  Future<void> _persistir() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kActiva, _activa);
      await _escribirOQuitar(prefs, _kNombre, _nombre);
      await _escribirOQuitar(prefs, _kCorreo, _correo);
      await _escribirOQuitar(prefs, _kTelefono, _telefono);
    } catch (e) {
      debugPrint('SesionCliente: no se pudo persistir ($e)');
    }
  }

  Future<void> _borrarPersistenciaSesion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kActiva);
    } catch (e) {
      debugPrint('SesionCliente: no se pudo borrar la sesión guardada ($e)');
    }
  }

  /// `setString(..., null)` no existe: un campo vacio se limpia con `remove`,
  /// o el proximo perfil heredaria el valor del anterior.
  Future<void> _escribirOQuitar(
    SharedPreferences prefs,
    String clave,
    String? valor,
  ) async {
    if (valor == null) {
      await prefs.remove(clave);
    } else {
      await prefs.setString(clave, valor);
    }
  }
}

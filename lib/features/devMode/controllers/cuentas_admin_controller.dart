import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:autofix/features/devMode/sync/devmode_sync_service.dart';
import 'package:autofix/features/talleres/models/taller.dart';
import 'package:autofix/features/talleres/data/taller_repository.dart';

class CuentasAdminController extends ChangeNotifier {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  final TallerRepository _talleresRepository = TallerRepository.instance;

  bool _cargando = false;
  String? _error;
  List<Taller> _talleres = [];
  List<Map<String, dynamic>> _admins = [];
  bool _verificado = false;
  String? _emailVerificado;

  /// Verifica si el email está en la colección `adminUsers` de Firestore.
  /// Si pasa, marca `_verificado = true` y permite operaciones.
  Future<bool> verificarAcceso(String email) async {
    _cargando = true;
    _error = null;
    notifyListeners();

    try {
      final normalizado = email.trim().toLowerCase();
      final doc = await _db.collection('adminUsers').doc(normalizado).get();
      
      if (doc.exists) {
        _verificado = true;
        _emailVerificado = normalizado;
        _cargando = false;
        notifyListeners();
        return true;
      } else {
        _error = 'Este correo no tiene permisos de administrador de cuentas.';
        _cargando = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Error al verificar permisos: $e';
      _cargando = false;
      notifyListeners();
      return false;
    }
  }

  /// Limpia la verificación (ej. al salir de la pantalla)
  void limpiarVerificacion() {
    _verificado = false;
    _emailVerificado = null;
    notifyListeners();
  }

  bool get verificado => _verificado;
  String? get emailVerificado => _emailVerificado;

  bool get cargando => _cargando;
  String? get error => _error;
  List<Taller> get talleres => _talleres;
  List<Map<String, dynamic>> get admins => _admins;

  Future<void> start() async {
    await DevModeSyncService.instance.start();
  }

  Future<void> stop() async {
    await DevModeSyncService.instance.stop();
  }

  /// Fuerza una sincronizacion completa: reinicia el sync service
  /// (que hace el push inicial de talleres a Firebase) y recarga la data
  /// directamente de Firestore.
  Future<void> sincronizar() async {
    if (!_verificado) {
      _error = 'Debe verificar su correo antes de sincronizar.';
      notifyListeners();
      return;
    }
    await DevModeSyncService.instance.stop();
    await DevModeSyncService.instance.start();
    await cargarDatos();
  }

  Future<void> cargarDatos() async {
    if (!_verificado) {
      _error = 'Debe verificar su correo antes de cargar datos.';
      notifyListeners();
      return;
    }
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      _talleres = await _talleresRepository.obtenerTodas();
      _admins = await _cargarAdminsDesdeFirebase();
    } catch (e) {
      _error = e.toString();
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  /// Carga las cuentas admin directamente de Firestore para tener la data
  /// fresca desde Auth/Firebase, no del cache local de SQLite que puede estar
  /// desactualizado.
  Future<List<Map<String, dynamic>>> _cargarAdminsDesdeFirebase() async {
    final snap = await _db.collection('admins').get();
    return snap.docs.map((d) {
      final data = d.data();
      return <String, dynamic>{
        'uid': d.id,
        'email': data['email'] as String? ?? '',
        'tallerId': data['tallerId'] as String? ?? '',
        'tallerNombre': data['tallerNombre'] as String?,
        'creado_en': (data['creado_en'] as Timestamp?)
            ?.toDate()
            .toUtc()
            .toIso8601String(),
        'actualizado_en': (data['actualizado_en'] as Timestamp?)
            ?.toDate()
            .toUtc()
            .toIso8601String(),
        'eliminado': (data['eliminado'] as bool?) ?? false,
        'authExists': true,
      };
    }).toList();
  }

  Future<bool> crearCuentaAdmin({
    required String email,
    required String password,
    required String tallerId,
  }) async {
    if (!_verificado) {
      _error = 'Debe verificar su correo antes de crear cuentas.';
      notifyListeners();
      return false;
    }

    _cargando = true;
    _error = null;
    notifyListeners();

    final normalizado = email.trim().toLowerCase();

    Future<DocumentSnapshot<Map<String, dynamic>>?> buscarEnFirestore(
      String emailBuscado,
    ) async {
      final snap = await _db
          .collection('admins')
          .where('email', isEqualTo: emailBuscado)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty ? snap.docs.first : null;
    }

    try {
      DocumentSnapshot<Map<String, dynamic>>? admin = await buscarEnFirestore(
        normalizado,
      );

      if (admin == null && email != normalizado) {
        admin = await buscarEnFirestore(email);
      }

      if (admin != null) {
        final eliminado = (admin.data()?['eliminado'] as bool?) ?? false;

        if (eliminado) {
          await admin.reference.update({
            'eliminado': false,
            'tallerId': tallerId,
            'tallerNombre': null,
            'actualizado_en': FieldValue.serverTimestamp(),
          });
          await cargarDatos();
          return true;
        }
        _error = 'Ya existe una cuenta asociada a ese correo.';
        _cargando = false;
        notifyListeners();
        return false;
      }

      final tempApp = await Firebase.initializeApp(
        name: 'tempApp_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);

      final creds = await tempAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = creds.user!.uid;

      await _db.collection('admins').doc(uid).set({
        'email': normalizado,
        'tallerId': tallerId,
        'tallerNombre': null,
        'creado_en': FieldValue.serverTimestamp(),
        'actualizado_en': FieldValue.serverTimestamp(),
        'eliminado': false,
      });

      await tempApp.delete();

      await cargarDatos();
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        DocumentSnapshot<Map<String, dynamic>>? admin = await buscarEnFirestore(
          normalizado,
        );
        if (admin == null && email != normalizado) {
          admin = await buscarEnFirestore(email);
        }

        if (admin != null) {
          final eliminado = (admin.data()?['eliminado'] as bool?) ?? false;
          if (eliminado) {
            await admin.reference.update({
              'eliminado': false,
              'tallerId': tallerId,
              'tallerNombre': null,
              'actualizado_en': FieldValue.serverTimestamp(),
            });
            await cargarDatos();
            _cargando = false;
            notifyListeners();
            return true;
          }
          _error = 'Ya existe una cuenta asociada a ese correo.';
        } else {
          _error =
              'Ese correo ya está asociado a una cuenta de Firebase Auth. '
              'Elimina el usuario de Auth desde la consola y vuelve a intentar.';
        }
      } else {
        _error = 'Error de autenticación: ${e.message}';
      }
      _cargando = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Error al crear cuenta: $e';
      _cargando = false;
      notifyListeners();
      return false;
    }
  }

  /// Cambia el taller asignado a un admin.
  Future<bool> editarAdmin(String uid, String nuevoTallerId) async {
    if (!_verificado) {
      _error = 'Debe verificar su correo antes de editar.';
      notifyListeners();
      return false;
    }
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      await _db.collection('admins').doc(uid).update({
        'tallerId': nuevoTallerId,
        'actualizado_en': FieldValue.serverTimestamp(),
      });
      await cargarDatos();
      return true;
    } catch (e) {
      _error = 'Error al editar admin: $e';
      _cargando = false;
      notifyListeners();
      return false;
    }
  }

  /// Baja logica del admin en Firestore: marca `eliminado = true`.
  ///
  /// No borra el documento para preservar la trazabilidad y para que el
  /// listener de sincronizacion refleje la baja en los demas dispositivos.
  /// El usuario de Firebase Auth asociado sigue existiendo; para eliminarlo
  /// hace falta el Admin SDK (Cloud Function/backend).
  Future<bool> eliminarAdmin(String uid) async {
    if (!_verificado) {
      _error = 'Debe verificar su correo antes de eliminar.';
      notifyListeners();
      return false;
    }
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      await _db.collection('admins').doc(uid).update({
        'eliminado': true,
        'actualizado_en': FieldValue.serverTimestamp(),
      });
      await cargarDatos();
      return true;
    } catch (e) {
      _error = 'Error al eliminar admin: $e';
      _cargando = false;
      notifyListeners();
      return false;
    }
  }

  /// Reactiva una cuenta admin que fue dada de baja (`eliminado = true`).
  Future<bool> reactivarAdmin(String uid) async {
    if (!_verificado) {
      _error = 'Debe verificar su correo antes de reactivar.';
      notifyListeners();
      return false;
    }
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      await _db.collection('admins').doc(uid).update({
        'eliminado': false,
        'actualizado_en': FieldValue.serverTimestamp(),
      });
      await cargarDatos();
      return true;
    } catch (e) {
      _error = 'Error al reactivar admin: $e';
      _cargando = false;
      notifyListeners();
      return false;
    }
  }
}

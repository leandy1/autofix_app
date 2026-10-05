import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:autofix/features/talleres/models/taller.dart';
import 'package:autofix/features/talleres/data/taller_repository.dart';

class CuentasAdminController extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TallerRepository _talleresRepository = TallerRepository.instance;

  bool _cargando = false;
  String? _error;
  List<Taller> _talleres = [];
  List<Map<String, dynamic>> _admins = [];

  bool get cargando => _cargando;
  String? get error => _error;
  List<Taller> get talleres => _talleres;
  List<Map<String, dynamic>> get admins => _admins;

  Future<void> cargarDatos() async {
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      _talleres = await _talleresRepository.obtenerTodas();
      final snap = await _db.collection('admins').get();
      _admins = snap.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  Future<bool> crearCuentaAdmin({
    required String email,
    required String password,
    required String tallerId,
  }) async {
    _cargando = true;
    _error = null;
    notifyListeners();

    try {
      // Usar app secundaria temporal para no desloguear al usuario actual
      final tempApp = await Firebase.initializeApp(
        name: 'tempApp_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      
      final creds = await tempAuth.createUserWithEmailAndPassword(
        email: email, 
        password: password
      );
      
      final uid = creds.user!.uid;
      
      await _db.collection('admins').doc(uid).set({
        'email': email,
        'tallerId': tallerId,
        'creado_en': FieldValue.serverTimestamp(),
      });
      
      await tempApp.delete();
      
      await cargarDatos();
      return true;
    } catch (e) {
      _error = 'Error al crear cuenta: $e';
      _cargando = false;
      notifyListeners();
      return false;
    }
  }
}


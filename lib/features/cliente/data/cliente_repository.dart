import 'package:cloud_firestore/cloud_firestore.dart';

/// Perfil del cliente sincronizado en `clientes/{uid}`.
class ClientePerfil {
  const ClientePerfil({
    required this.uid,
    required this.nombre,
    required this.correo,
    required this.telefono,
  });

  final String uid;
  final String nombre;
  final String correo;
  final String telefono;

  factory ClientePerfil.desdeFirestore(
    String uid,
    Map<String, dynamic> datos,
  ) => ClientePerfil(
    uid: uid,
    nombre: datos['nombre'] as String? ?? '',
    correo: datos['correo'] as String? ?? datos['email'] as String? ?? '',
    telefono: datos['telefono'] as String? ?? '',
  );
}

/// Persistencia Firebase de perfiles cliente.
///
/// Los clientes se guardan en su propia colección, separada de `admins` y
/// `talleres`, que administra `DevModeSyncService`. La contraseña solo vive en
/// Firebase Auth; nunca forma parte del documento Firestore.
class ClienteRepository {
  ClienteRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _coleccion =>
      _db.collection('clientes');

  Future<void> crear({
    required String uid,
    required String nombre,
    required String correo,
    required String telefono,
  }) async {
    final ahora = FieldValue.serverTimestamp();
    await _coleccion.doc(uid).set(<String, Object?>{
      'uid': uid,
      'nombre': nombre.trim(),
      'correo': correo.trim().toLowerCase(),
      'email': correo.trim().toLowerCase(),
      'telefono': telefono.trim(),
      'creado_en': ahora,
      'actualizado_en': ahora,
      'eliminado': false,
    }, SetOptions(merge: true));
  }

  Future<ClientePerfil?> obtener(String uid) async {
    final snapshot = await _coleccion.doc(uid).get();
    if (!snapshot.exists) return null;
    final datos = snapshot.data();
    if (datos == null || datos['eliminado'] == true) return null;
    return ClientePerfil.desdeFirestore(uid, datos);
  }

  Future<bool> existeDocumento(String uid) async =>
      (await _coleccion.doc(uid).get()).exists;
}

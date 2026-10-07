import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autofix/core/auth/credenciales_seguras.dart';
import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/core/auth/sesion_cache.dart';
import 'package:autofix/features/auth/controllers/login_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SesionAdmin.instance.cerrar();
    await SesionCliente.instance.olvidarTodo();
    CredencialesSeguras.usarAlmacenParaPruebas(AlmacenSeguroEnMemoria());
  });

  tearDown(() async {
    await CredencialesSeguras.borrar();
    CredencialesSeguras.usarAlmacenParaPruebas(null);
  });

  test('DEV no se guarda aunque Recuérdame esté marcado', () async {
    final controller = LoginController(auth: MockFirebaseAuth());
    await controller.persistirRecordamiento(
      usuario: 'dev',
      contrasena: '1234',
      activo: true,
    );

    expect(await CredencialesSeguras.leer(), isNull);
    controller.dispose();
  });

  test(
    'la sesión Admin solo queda en disco cuando se pide persistir',
    () async {
      await SesionAdmin.instance.iniciar(
        tallerId: 'taller-1',
        adminUid: 'admin-1',
        adminEmail: 'admin@example.com',
        persistir: false,
      );
      expect(await SesionCache.leer(), isNull);

      await SesionAdmin.instance.persistirActual();
      expect((await SesionCache.leer())?.adminEmail, 'admin@example.com');
    },
  );

  test('el rol seleccionado se recuerda localmente', () async {
    final controller = LoginController(auth: MockFirebaseAuth());

    expect(await controller.rolRecordado(), LoginRole.admin);
    await controller.persistirRol(LoginRole.cliente);

    expect(await controller.rolRecordado(), LoginRole.cliente);
    controller.dispose();
  });

  test('registro crea Auth y el perfil separado en clientes/{uid}', () async {
    final auth = MockFirebaseAuth();
    final firestore = FakeFirebaseFirestore();
    final controller = LoginController(auth: auth, firestore: firestore);

    final perfil = await controller.registrarCliente(
      nombre: 'Ana Torres',
      correo: 'ANA@example.com',
      telefono: '8095551234',
      contrasena: 'secreto123',
    );

    expect(perfil, isNotNull);
    expect(auth.currentUser?.email, 'ANA@example.com');
    final documento = await firestore
        .collection('clientes')
        .doc(perfil!.uid)
        .get();
    expect(documento.data()?['nombre'], 'Ana Torres');
    expect(documento.data()?['correo'], 'ana@example.com');
    expect(documento.data()?['telefono'], '8095551234');
    expect(documento.data()?.containsKey('password'), isFalse);
    controller.dispose();
  });

  test(
    'login cliente requiere perfil cliente y carga los datos sincronizados',
    () async {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'cliente-1', email: 'ana@example.com'),
      );
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('clientes').doc('cliente-1').set({
        'nombre': 'Ana Torres',
        'correo': 'ana@example.com',
        'telefono': '8095551234',
        'eliminado': false,
      });
      final controller = LoginController(auth: auth, firestore: firestore);

      final perfil = await controller.loginCliente(
        'ana@example.com',
        'secreto123',
      );

      expect(perfil?.nombre, 'Ana Torres');
      expect(SesionCliente.instance.activa, isTrue);
      expect(SesionCliente.instance.telefono, '8095551234');
      controller.dispose();
    },
  );

  test('una cuenta admin no puede entrar seleccionando Cliente', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'admin-1', email: 'admin@example.com'),
    );
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('admins').doc('admin-1').set({
      'email': 'admin@example.com',
      'tallerId': 'taller-1',
    });
    final controller = LoginController(auth: auth, firestore: firestore);

    final perfil = await controller.loginCliente(
      'admin@example.com',
      'secreto123',
    );

    expect(perfil, isNull);
    expect(controller.error, contains('pertenece a un administrador'));
    expect(auth.currentUser, isNull);
    controller.dispose();
  });
}

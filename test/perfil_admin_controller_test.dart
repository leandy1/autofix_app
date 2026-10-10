import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:autofix/core/auth/credenciales_seguras.dart';
import 'package:autofix/core/auth/perfil_admin_cache.dart';
import 'package:autofix/core/auth/recordarme_prefs.dart';
import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/admin/presentation/perfil_admin_controller.dart';
import 'package:autofix/features/auth/controllers/cambio_password_controller.dart';
import 'package:autofix/features/cliente/data/cambios_password_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_perfil_admin_test.db';
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await DatabaseHelper.resetParaPruebas();
    await SesionAdmin.instance.cerrar();
    CredencialesSeguras.usarAlmacenParaPruebas(AlmacenSeguroEnMemoria());
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  tearDown(() async {
    await CredencialesSeguras.borrar();
    CredencialesSeguras.usarAlmacenParaPruebas(null);
  });

  test(
    'guarda los datos locales y cambia el valor inicial de Recuérdame',
    () async {
      await SesionAdmin.instance.iniciar(
        tallerId: 'taller-1',
        adminUid: 'admin-1',
        adminEmail: 'admin@example.com',
        persistir: false,
      );
      final controller = PerfilAdminController();
      await controller.inicializarPreferencia();
      expect(controller.recordarmePorDefecto, isTrue);

      expect(
        await controller.guardarDatos(
          nombre: 'Luis Admin',
          telefono: '8095551234',
        ),
        'Información guardada en este dispositivo',
      );
      await controller.alternarRecordarmePorDefecto(false);

      expect(await PerfilAdminCache.leer('admin-1'), (
        'Luis Admin',
        '8095551234',
      ));
      expect(await RecordarmePrefs.habilitadoPorDefecto(), isFalse);
      controller.dispose();
    },
  );

  test(
    'cambio offline queda en la cola compartida y asociado al admin',
    () async {
      await SesionAdmin.instance.iniciar(
        tallerId: 'taller-1',
        adminUid: 'admin-1',
        adminEmail: 'admin@example.com',
        persistir: false,
      );
      final password = CambioPasswordController(
        aplicarEnNube: (_, _) async {
          throw FirebaseAuthException(code: 'network-request-failed');
        },
      );
      final controller = PerfilAdminController(passwordController: password);

      final mensaje = await controller.cambiarPassword(
        correo: 'admin@example.com',
        nueva: 'nueva123',
        repetir: 'nueva123',
      );

      final pendientes = await CambiosPasswordRepository.instance.pendientes();
      expect(mensaje, 'Guardada en cola, se aplicará al conectarse');
      expect(pendientes, hasLength(1));
      expect(pendientes.single.correoCuenta, 'admin@example.com');
      expect(
        await CambiosPasswordRepository.instance.leerContrasena(
          pendientes.single,
        ),
        'nueva123',
      );
      controller.dispose();
    },
  );
}

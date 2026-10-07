import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/auth/sesion_cache.dart';

/// Un disco que siempre falla: el caso real de "el plugin no esta disponible"
/// (entorno de tests, plataforma no inicializada, almacenamiento roto).
///
/// `extends` y no `implements` a proposito: la base pone el token de
/// plataforma en su constructor, y con `implements` el setter de `instance`
/// lo rechazaria con un `PlatformInterface.verify` fallido.
class _DiscoQueFalla extends SharedPreferencesStorePlatform {
  Never _fallar() => throw Exception('disco lleno');

  @override
  Future<Map<String, Object>> getAll() async => _fallar();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      _fallar();

  @override
  Future<bool> remove(String key) async => _fallar();

  @override
  Future<bool> clear() async => _fallar();
}

void main() {
  setUp(() {
    // Binding primero: sin el, cualquier llamada a canal de plataforma muere
    // con "Binding has not yet been initialized" en vez de con nuestro error.
    TestWidgetsFlutterBinding.ensureInitialized();
    // Deja la cache de prefs en memoria (y anula la instancia cacheada) para
    // que cada test arranque con un disco limpio.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  setUp(() async {
    // La sesion es un singleton: sin esto, un test dejaria el tallerId puesto
    // y el siguiente arrancaria "logueado".
    await SesionAdmin.instance.cerrar();
  });

  group('arranque sin sesion', () {
    test('no hay sesion y restaurar devuelve false', () async {
      expect(SesionAdmin.instance.activa, isFalse);
      expect(SesionAdmin.instance.tallerId, isNull);
      expect(await SesionAdmin.instance.restaurar(), isFalse);
      expect(SesionAdmin.instance.activa, isFalse);
    });
  });

  group('guardar', () {
    test('iniciar llena la memoria y deja la sesion en disco', () async {
      await SesionAdmin.instance.iniciar(
        tallerId: 'taller-1',
        adminUid: 'uid-1',
        tallerNombre: 'Global Refriauto',
        adminEmail: 'admin@autofix.do',
      );

      expect(SesionAdmin.instance.activa, isTrue);
      expect(SesionAdmin.instance.tallerId, 'taller-1');
      expect(SesionAdmin.instance.adminUid, 'uid-1');

      final guardada = await SesionCache.leer();
      expect(guardada, isNotNull);
      expect(guardada!.tallerId, 'taller-1');
      expect(guardada.adminUid, 'uid-1');
      expect(guardada.tallerNombre, 'Global Refriauto');
      expect(guardada.adminEmail, 'admin@autofix.do');
      expect(guardada.guardadaEn, isNotNull);
    });
  });

  group('restaurar', () {
    test('levanta la sesion que dejo la ejecucion anterior', () async {
      // Simula el cierre de la app: memoria vacia, disco con la sesion.
      await SesionCache.guardar(
        const SesionPersistida(
          tallerId: 'taller-9',
          adminUid: 'uid-9',
          tallerNombre: 'Taller Los Prados',
          adminEmail: 'otro@autofix.do',
        ),
      );
      expect(SesionAdmin.instance.activa, isFalse);

      expect(await SesionAdmin.instance.restaurar(), isTrue);

      expect(SesionAdmin.instance.activa, isTrue);
      expect(SesionAdmin.instance.tallerId, 'taller-9');
      expect(SesionAdmin.instance.tallerNombre, 'Taller Los Prados');
      expect(SesionAdmin.instance.adminEmail, 'otro@autofix.do');
    });

    test('no pisa una sesion que ya esta viva en memoria', () async {
      await SesionAdmin.instance.iniciar(tallerId: 'vivo', adminUid: 'uid-vivo');
      // El disco tiene otra cosa (una cache mas vieja, o datos de otro admin).
      await SesionCache.guardar(
        const SesionPersistida(tallerId: 'disco-viejo', adminUid: 'uid-viejo'),
      );

      expect(await SesionAdmin.instance.restaurar(), isTrue);
      expect(SesionAdmin.instance.tallerId, 'vivo');
    });

    test('una cache sin taller no se restaura', () async {
      // Sin tallerId no hay con que filtrar las citas: restaurarla dejaria el
      // Dashboard de admin pintando los talleres de todos los admins.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'sesion.adminUid': 'uid-sin-taller',
      });

      expect(await SesionCache.leer(), isNull);
      expect(await SesionAdmin.instance.restaurar(), isFalse);
      expect(SesionAdmin.instance.activa, isFalse);
    });

    test('un tallerId vacio se trata como sesion inexistente', () async {
      await SesionCache.guardar(
        const SesionPersistida(tallerId: '', adminUid: 'uid-1'),
      );

      expect(await SesionCache.leer(), isNull);
      expect(await SesionAdmin.instance.restaurar(), isFalse);
    });
  });

  group('cerrar', () {
    test('limpia la memoria y el disco', () async {
      await SesionAdmin.instance.iniciar(
        tallerId: 'taller-1',
        adminUid: 'uid-1',
        tallerNombre: 'AutoFix Central',
      );

      await SesionAdmin.instance.cerrar();

      expect(SesionAdmin.instance.activa, isFalse);
      expect(SesionAdmin.instance.tallerId, isNull);
      expect(SesionAdmin.instance.adminUid, isNull);
      expect(await SesionCache.leer(), isNull);
      // Y la proxima ejecucion vuelve al login, que es el punto del borrado.
      expect(await SesionAdmin.instance.restaurar(), isFalse);
    });
  });

  group('disco inaccesible', () {
    test('la sesion sigue viva en memoria aunque no se pueda guardar', () async {
      // Cache limpia y store roto: `getInstance()` y todo lo que venga
      // despues van a explotar dentro de SesionCache, no en el llamador.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      SharedPreferencesStorePlatform.instance = _DiscoQueFalla();

      await SesionAdmin.instance.iniciar(tallerId: 'taller-roto', adminUid: 'u');

      // La sesion de ESTA ejecucion funciona: lo que no se pudo fue grabar.
      expect(SesionAdmin.instance.activa, isTrue);
      expect(SesionAdmin.instance.tallerId, 'taller-roto');
      expect(await SesionCache.leer(), isNull);
    });

    test('cerrar no lanza con el disco roto', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      SharedPreferencesStorePlatform.instance = _DiscoQueFalla();
      await SesionAdmin.instance.iniciar(tallerId: 't', adminUid: 'u');

      await expectLater(SesionAdmin.instance.cerrar(), completes);

      // Aunque el borrado falle, la memoria tiene que quedar limpia: si no,
      // el usuario seguira "logueado" en esta ejecucion tras cerrar sesion.
      expect(SesionAdmin.instance.activa, isFalse);
    });
  });
}

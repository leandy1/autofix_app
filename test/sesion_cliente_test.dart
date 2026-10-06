import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autofix/core/auth/sesion_cliente.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SesionCliente.instance.olvidarTodo();
  });

  test('iniciar y restaurar conserva el perfil y la sesión', () async {
    await SesionCliente.instance.iniciar(
      nombre: 'María Pérez',
      correo: 'maria@example.com',
      telefono: '8095551234',
    );
    await SesionCliente.instance.cerrar();

    expect(SesionCliente.instance.activa, isFalse);
    expect(SesionCliente.instance.nombre, 'María Pérez');
    expect(await SesionCliente.instance.restaurar(), isFalse);

    // Abrir sesión otra vez guarda el estado activo sin perder el perfil.
    await SesionCliente.instance.iniciar();
    await SesionCliente.instance.olvidarTodo();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sesionCliente.activa': true,
      'sesionCliente.nombre': 'María Pérez',
      'sesionCliente.correo': 'maria@example.com',
      'sesionCliente.telefono': '8095551234',
    });

    expect(await SesionCliente.instance.restaurar(), isTrue);
    expect(SesionCliente.instance.nombreVisible, 'María Pérez');
    expect(SesionCliente.instance.correo, 'maria@example.com');
    expect(SesionCliente.instance.telefono, '8095551234');
  });

  test(
    'cerrar mantiene el perfil disponible para precargar una cita',
    () async {
      await SesionCliente.instance.iniciar(
        nombre: 'Juan Soto',
        correo: 'juan@example.com',
        telefono: '8095550000',
      );

      await SesionCliente.instance.cerrar();

      expect(SesionCliente.instance.activa, isFalse);
      expect(SesionCliente.instance.nombre, 'Juan Soto');
      expect(SesionCliente.instance.correo, 'juan@example.com');
      expect(SesionCliente.instance.telefono, '8095550000');
    },
  );
}

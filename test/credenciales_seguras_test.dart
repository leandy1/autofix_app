import 'package:flutter_test/flutter_test.dart';

import 'package:autofix/core/auth/credenciales_seguras.dart';

void main() {
  late AlmacenSeguroEnMemoria almacen;

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    CredencialesSeguras.usarAlmacenParaPruebas(almacen);
  });

  tearDown(() async {
    await CredencialesSeguras.borrar();
    CredencialesSeguras.usarAlmacenParaPruebas(null);
  });

  test('guarda, lee y borra las credenciales en el almacen seguro', () async {
    await CredencialesSeguras.guardar(
      usuario: 'sam@example.com',
      contrasena: 'secreto-123',
    );

    expect(await CredencialesSeguras.leer(), isA<CredencialesRecordadas>());
    final credenciales = await CredencialesSeguras.leer();
    expect(credenciales?.usuario, 'sam@example.com');
    expect(credenciales?.contrasena, 'secreto-123');
    expect(await CredencialesSeguras.usuarioEnmascarado(), 'sam***');

    await CredencialesSeguras.borrar();
    expect(await CredencialesSeguras.leer(), isNull);
  });

  test('la máscara no expone usuarios de tres caracteres o menos', () {
    expect(CredencialesSeguras.enmascarar('sam'), 'sam***');
    expect(CredencialesSeguras.enmascarar('xy'), 'xy***');
    expect(CredencialesSeguras.enmascarar(''), '');
  });
}

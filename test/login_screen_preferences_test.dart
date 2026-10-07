import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autofix/core/auth/credenciales_seguras.dart';
import 'package:autofix/features/auth/controllers/login_controller.dart';
import 'package:autofix/features/auth/screens/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'recordarme.ultimoRol': 'cliente',
      'recordarme.habilitadoPorDefecto': false,
    });
    CredencialesSeguras.usarAlmacenParaPruebas(AlmacenSeguroEnMemoria());
  });

  tearDown(() {
    CredencialesSeguras.usarAlmacenParaPruebas(null);
  });

  testWidgets(
    'restaura rol Cliente y preferencia sin habilitar el login antes',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

      // Mientras las preferencias locales no han terminado de cargar, el
      // selector y el ingreso no deben aceptar el valor temporal Admin.
      final botonIngresar = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Ingresar'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(botonIngresar.onPressed, isNull);

      await tester.pumpAndSettle();
      final selector = tester.widget<SegmentedButton<LoginRole>>(
        find.byType(SegmentedButton<LoginRole>),
      );
      expect(selector.selected, {LoginRole.cliente});

      final recordar = tester.widget<Switch>(find.byType(Switch));
      expect(recordar.value, isFalse);
    },
  );
}

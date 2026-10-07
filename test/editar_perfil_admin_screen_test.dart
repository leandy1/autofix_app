import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/features/admin/screens/editar_perfil_admin_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SesionAdmin.instance.cerrar();
    await SesionAdmin.instance.iniciar(
      tallerId: 'taller-1',
      adminUid: 'admin-1',
      adminEmail: 'admin@example.com',
      persistir: false,
    );
  });

  testWidgets('muestra las tres áreas del perfil y la preferencia Recuérdame', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: EditarPerfilAdminScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Editar Perfil'), findsOneWidget);
    expect(find.text('Datos del perfil'), findsOneWidget);
    expect(find.text('Seguridad'), findsOneWidget);
    expect(find.text('admin@example.com'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('Preferencias de inicio'), findsOneWidget);
    expect(
      find.text('Traer habilitado por defecto opción Recuérdame'),
      findsOneWidget,
    );
  });
}

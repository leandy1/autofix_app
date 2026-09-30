import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autofix/app/conectividad_app.dart';
import 'package:autofix/screens/auth/login_screen.dart';
import 'package:autofix/theme/app_colors.dart';

/// El banner de Conectividad es el requisito: tiene que verse en TODA pantalla
/// sin que cada una lo monte. Eso se rompe de formas que el analyzer no ve
/// (alguien saca el `builder`, o mueve el `ConectividadApp` por fuera del
/// `MaterialApp` y cada `Scaffold` tapa el banner), asi que va fijo en test.
void main() {
  Widget montarApp() => const ConectividadApp(child: AutoFixApp());

  testWidgets('el banner queda montado dentro del Navigator', (tester) async {
    await tester.pumpWidget(montarApp());
    await tester.pump();

    // Busca el banner en el arbol del `MaterialApp`, no en el de arriba: si
    // alguien lo deja envuelto por fuera, el `find` igual lo encuentra y el
    // test pasa mentiroso.
    final banner = find.descendant(
      of: find.byType(MaterialApp),
      matching: find.byIcon(Icons.wifi_off),
    );
    expect(banner, findsOneWidget);
  });

  testWidgets('el banner sobrevive a la navegacion entre pantallas', (tester) async {
    await tester.pumpWidget(montarApp());
    await tester.pump();

    // `builder` de `MaterialApp` rebuildea el Navigator entero; si el banner
    // vivia en un `StatefulWidget` hermano, esta pantalla nueva lo perderia.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.background,
          body: const Center(child: Text('Pantalla secundaria')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pantalla secundaria'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MaterialApp),
        matching: find.byIcon(Icons.wifi_off),
      ),
      findsOneWidget,
    );
  });

  testWidgets('el banner no se superpone con la pantalla', (tester) async {
    await tester.pumpWidget(montarApp());
    await tester.pumpAndSettle();

    // Si se montara con un `Stack` por fuera del `MaterialApp` en vez de con
    // `builder`, el banner y el contenido ocuparian el mismo sitio. El alto del
    // banner tiene que estar DESCONTADO del alto disponible para el hijo.
    final column = tester.widget<Column>(find.byType(Column).first);
    expect(
      column.children.whereType<Expanded>(),
      isNotEmpty,
      reason: 'el hijo del banner debe ir dentro de un Expanded',
    );
  });

  testWidgets('la app arranca en el login de Leandy', (tester) async {
    await tester.pumpWidget(montarApp());
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}

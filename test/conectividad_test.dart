import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autofix/app/conectividad_app.dart';
import 'package:autofix/core/connectivity/connectivity_service.dart';
import 'package:autofix/main.dart' show AutoFixApp;

import 'support/red_falsa.dart';

void main() {
  late RedFalsa red;
  late ConnectivityPlatform original;

  setUp(() {
    original = ConnectivityPlatform.instance;
    red = RedFalsa();
    ConnectivityPlatform.instance = red;
  });

  tearDown(() async {
    ConnectivityPlatform.instance = original;
    await red.dispose();
  });

  Finder banner() => find.byIcon(Icons.wifi_off);

  group('el servicio', () {
    test('arranca leyendo el estado real, no asumiendo offline', () async {
      red.estado = const [ConnectivityResult.wifi];
      final servicio = ConnectivityService();
      await Future<void>.delayed(Duration.zero);

      expect(servicio.hayConexion, isTrue);
      servicio.dispose();
    });

    test('notifica cuando se apaga el wifi en vivo', () async {
      red.estado = const [ConnectivityResult.wifi];
      final servicio = ConnectivityService();
      await Future<void>.delayed(Duration.zero);

      var avisos = 0;
      servicio.addListener(() => avisos++);

      red.emitir([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);

      expect(servicio.hayConexion, isFalse);
      expect(avisos, greaterThan(0), reason: 'nadie fue avisado del corte');
      servicio.dispose();
    });

    test('notifica cuando se pasa de wifi a datos moviles', () async {
      // Ambos estados son "en linea", asi que el banner no cambia, pero el
      // transporte SI: un consumidor que dibuje el icono tiene que enterarse.
      red.estado = const [ConnectivityResult.wifi];
      final servicio = ConnectivityService();
      await Future<void>.delayed(Duration.zero);

      var avisos = 0;
      servicio.addListener(() => avisos++);

      red.emitir([ConnectivityResult.mobile]);
      await Future<void>.delayed(Duration.zero);

      expect(servicio.resultados, [ConnectivityResult.mobile]);
      expect(avisos, greaterThan(0));
      servicio.dispose();
    });

    test('no se queda mudo si la lectura inicial falla', () async {
      // Sin esto el banner queda muerto para toda la sesion: la suscripcion
      // nunca se creaba.
      red.lecturaInicialFalla = true;
      final servicio = ConnectivityService();
      await Future<void>.delayed(Duration.zero);

      red.emitir([ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);

      expect(servicio.hayConexion, isTrue);
      servicio.dispose();
    });

    test('tampoco se queda mudo si la falla no es una Exception', () async {
      red.lecturaInicialRevienta = true;
      final servicio = ConnectivityService();
      await Future<void>.delayed(Duration.zero);

      red.emitir([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);

      expect(servicio.hayConexion, isFalse);
      servicio.dispose();
    });

    test('arranca en estado desconocido, sin presumir corte', () async {
      red.retardoInicial = const Duration(seconds: 1);
      red.estado = const [ConnectivityResult.wifi];
      final servicio = ConnectivityService();

      // Sin esperar: el MethodChannel todavia no respondio.
      expect(
        servicio.estado,
        EstadoRed.desconocido,
        reason: 'no se puede acusar corte sin evidencia',
      );
      servicio.dispose();
    });
  });

  group('el banner en pantalla', () {
    testWidgets('aparece al apagar el wifi y desaparece al volver', (
      tester,
    ) async {
      red.estado = const [ConnectivityResult.wifi];
      await tester.pumpWidget(const ConectividadApp(child: AutoFixApp()));
      await tester.pumpAndSettle();

      expect(banner(), findsNothing, reason: 'arranca en linea');

      red.emitir([ConnectivityResult.none]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

expect(
        banner(),
        findsOneWidget,
        reason: 'la alarma tiene que ir dentro del Navigator',
      );

      red.emitir([ConnectivityResult.wifi]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(banner(), findsNothing, reason: 'debe irse al volver la conexion');
    });

    testWidgets('no grita "Sin conexion" antes de saber el estado', (
      tester,
    ) async {
      // Arranca desconocido: sin red real que consultar todavia, no hay
      // evidencia de corte. Mostrar la alarma seria mentir.
      red.retardoInicial = const Duration(seconds: 1);
      red.estado = const [ConnectivityResult.wifi];

      await tester.pumpWidget(const ConectividadApp(child: AutoFixApp()));
      await tester.pump();

expect(
        banner(),
        findsNothing,
        reason: 'con el estado inicial pendiente no se acusa corte',
      );

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(banner(), findsNothing);
    });

    testWidgets('reacciona dentro del Navigator, no sobre el', (
      tester,
    ) async {
      red.estado = const [ConnectivityResult.none];
      await tester.pumpWidget(const ConectividadApp(child: AutoFixApp()));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(MaterialApp), matching: banner()),
        findsOneWidget,
      );

      red.emitir([ConnectivityResult.wifi]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.descendant(of: find.byType(MaterialApp), matching: banner()),
        findsNothing,
      );
    });
  });
}
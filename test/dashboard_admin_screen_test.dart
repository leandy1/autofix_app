import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/admin/screens/dashboard_admin_screen.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/shared/theme/app_colors.dart';

/// Prueba de punta a punta del Dashboard: pantalla -> controller -> SQLite.
///
/// El punto de este archivo es EL QUE NO SE PUEDE COMPROBAR CON `flutter
/// analyze`: que la pantalla ya no este leyendo `demo_admin_data.dart`. Compilar
/// sin errores no dice nada, porque una pantalla que mezcla numeros del mock con
/// los de la base se ve bien y solo se delata mirando los valores.
///
/// Por eso se siembran cifras que NO coinciden con el demo (`demoDashboardAdmin`
/// decia '2' vehiculos, '6' ordenes, 'RD$ 0' ingresos y 5 citas) y se verifica
/// que en pantalla aparezcan las de la base.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // `databaseFactoryFfiNoIsolate` y NO el `databaseFactoryFfi` de los demas
    // archivos de test. La version normal manda el SQL a un isolate de fondo, y
    // `testWidgets` corre dentro de un `FakeAsync` que congela ese isolate: el
    // `pumpWidget` se queda esperando una respuesta que no llega nunca y el test
    // cuelga en vez de fallar. La version sin isolate corre en el mismo isolate
    // del test, que es justo lo que hace falta aca.
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_dashboard_widget.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    await DatabaseHelper.resetParaPruebas();
    // ABRIR la base aqui, fuera del `FakeAsync` de `testWidgets`, es
    // obligatorio. Si la primera apertura ocurre adentro del test, se queda
    // esperando en una promesa que `FakeAsync` nunca completa y el test CUELGA
    // en vez de fallar (se probo: no hay excepcion ni timeout que lo corte).
    // Con la conexion ya abierta, las consultas de la pantalla si corren
    // normales adentro de `testWidgets`.
    await DatabaseHelper.instance.base;
  });

  final repo = CitaRepository.instance;

  Cita cita({
    required DateTime fecha,
    required String cliente,
    EstadoCita estado = EstadoCita.pendiente,
    int total = 0,
  }) => Cita(
    cliente: cliente,
    telefono: '809-555-0000',
    vehiculo: 'Toyota RAV4',
    placa: 'A123456',
    servicios: const <String>['Frenos'],
    fechaCita: fecha,
    estado: estado,
    total: total,
  );

  DateTime diaDeHoy(int hora) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, hora, 0);
  }

  /// Dia de hoy mas [dias], a medianoche: la misma aritmetica que hacen las
  /// flechas del encabezado.
  DateTime dia(int dias) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + dias);
  }

  /// Los mismos meses cortos que usa la pantalla. Se duplican a proposito: si el
  /// rotulo cambia de 'oct' a 'oct.', el test tiene que romperse, porque el
  /// formato del texto es parte de lo que se esta fijando aqui.
  const List<String> meses = <String>[
    'ene', 'feb', 'mar', 'abr', 'may', 'jun', //
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  Future<void> sembrarBaseDePrueba() async {
    final base = DateTime.now();
    for (final c in <Cita>[
      // HOY: 2 completadas (RD$ 3,000 + RD$ 1,500) y 1 en proceso.
      cita(
        fecha: diaDeHoy(9),
        cliente: 'Cliente Real Uno',
        estado: EstadoCita.completado,
        total: 3000,
      ),
      cita(
        fecha: diaDeHoy(11),
        cliente: 'Cliente Real Dos',
        estado: EstadoCita.completado,
        total: 1500,
      ),
      cita(
        fecha: diaDeHoy(14),
        cliente: 'Cliente Real Tres',
        estado: EstadoCita.enProceso,
      ),
      // AYER: 1 pendiente y 1 esperando pieza -> dan de rango las ordenes
      // abiertas, que son del taller y no del dia.
      cita(
        fecha: base.subtract(const Duration(days: 1)),
        cliente: 'Cliente De Ayer Uno',
        estado: EstadoCita.pendiente,
      ),
      cita(
        fecha: base.subtract(const Duration(days: 1)),
        cliente: 'Cliente De Ayer Dos',
        estado: EstadoCita.esperandoPieza,
      ),
    ]) {
      await repo.crear(c);
    }
  }

  Future<void> abrirDashboard(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
    // `pumpAndSettle` y no un `pump`: el controller hace tres consultas a
    // SQLite en `initState` y las tarjetas solo se pintan cuando llegan.
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 8),
    );
  }

  testWidgets('las tarjetas muestran los numeros que hay en la base', (
    tester,
  ) async {
    await sembrarBaseDePrueba();
    await abrirDashboard(tester);

    // Ingresos: 3,000 + 1,500 de las completadas de hoy. El `demoDashboardAdmin`
    // decia 'RD$ 0' y '5 citas', asi que si aparece el dato del mock, esta
    // pantalla todavia no se desenchufo.
    expect(find.text(r'RD$ 4,500'), findsOneWidget);
    expect(find.text(r'RD$ 0'), findsNothing);
    expect(find.text('5 citas'), findsNothing);

    // El badge de la lista del dia: 3 citas agendadas para hoy.
    expect(find.text('3 citas'), findsOneWidget);

    // Y los clientes reales aparecen en la tabla.
    expect(find.text('Cliente Real Uno'), findsOneWidget);
    expect(find.text('Cliente Real Dos'), findsOneWidget);
    expect(find.text('Cliente Real Tres'), findsOneWidget);
  });

  testWidgets('ya no aparece ningun cliente del demo viejo', (tester) async {
    await sembrarBaseDePrueba();
    await abrirDashboard(tester);

    // Los cinco nombres de `demoDashboardAdmin`. Si alguno sale, el mock sigue
    // conectado por algun lado.
    for (final fantasma in <String>[
      'Luis Castillo',
      'Pedro Núñez',
      'Isabel Reyes',
      'Natalia Flores',
      'Lucía Medina',
    ]) {
      expect(
        find.text(fantasma),
        findsNothing,
        reason: 'quedo un dato del demo: $fantasma',
      );
    }
  });

  testWidgets('la flecha de atras cambia a los numeros de ayer', (
    tester,
  ) async {
    await sembrarBaseDePrueba();
    await abrirDashboard(tester);

    expect(find.text(r'RD$ 4,500'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    // Ayer: ninguna completada, asi que 0 ingresos y 2 citas. Si el boton
    // nombro mas simple de pintar que de conectar, esto saldria igual que antes.
    expect(find.text(r'RD$ 0'), findsOneWidget);
    expect(find.text('2 citas'), findsOneWidget);
    expect(find.text('Cliente Real Uno'), findsNothing);
    expect(find.text('Cliente De Ayer Uno'), findsOneWidget);
  });

  testWidgets('un dia sin citas lo dice, en vez de pintar una tabla vacia', (
    tester,
  ) async {
    await sembrarBaseDePrueba();
    await abrirDashboard(tester);

    // Dos dias adelante no hay nada agendado en esta base de prueba.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(
      find.text('No hay citas de hoy.'),
      findsNothing,
      reason: 'ya no es hoy: el mensaje no puede seguir diciendo hoy',
    );
    expect(
      find.text(
        'No hay citas del ${dia(2).day} ${meses[dia(2).month - 1]}.',
      ),
      findsOneWidget,
    );
    expect(find.text('0 citas'), findsOneWidget);
  });

  testWidgets('con la base vacia la pantalla no truena', (tester) async {
    // El caso del taller recien instalado, que es el primero que ve el admin.
    await abrirDashboard(tester);

    expect(find.text('ÓRDENES ABIERTAS'), findsOneWidget);
    expect(find.text(r'RD$ 0'), findsOneWidget);
    expect(find.text('0 citas'), findsOneWidget);
    expect(find.text('No hay citas de hoy.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('rotulos honestos', () {
    testWidgets('con hoy seleccionado el rotulo dice HOY', (tester) async {
      await sembrarBaseDePrueba();
      await abrirDashboard(tester);

      expect(find.text('COMPLETADAS HOY'), findsOneWidget);
      expect(find.text('INGRESOS HOY'), findsOneWidget);
      expect(find.text('Citas de hoy'), findsOneWidget);
    });

    testWidgets('al moverse de dia el rotulo nombra ese dia, no HOY', (
      tester,
    ) async {
      await sembrarBaseDePrueba();
      await abrirDashboard(tester);

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      // No se comprueba el texto exacto ('EL 15 OCT') sino que el rotulo cambie
      // de forma: si el dia 15 cae en octubre y el 16 en noviembre, la cadena
      // exacta del test seria correcta hoy y falsa manana.
      final textos = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>();

      expect(
        textos.any((t) => t.startsWith('COMPLETADAS EL ')),
        isTrue,
        reason: 'el rotulo de completadas tiene que decir que dia es',
      );
      expect(
        textos.any((t) => t.startsWith('INGRESOS EL ')),
        isTrue,
        reason: 'el rotulo de ingresos tiene que decir que dia es',
      );
      expect(
        textos.any((t) => t.startsWith('Citas del ')),
        isTrue,
        reason: 'el titulo de la tabla tiene que decir que dia es',
      );

      // Y la palabra HOY no puede quedar colgando en ninguna parte.
      expect(find.text('COMPLETADAS HOY'), findsNothing);
      expect(find.text('INGRESOS HOY'), findsNothing);
      expect(find.text('Citas de hoy'), findsNothing);
    });
  });

  group('grafico de reparto por estado', () {
    testWidgets('los sectores salen de la base, con el total de verdad', (
      tester,
    ) async {
      await sembrarBaseDePrueba();
      await abrirDashboard(tester);

      // 5 citas: 2 completadas, 1 en proceso, 1 pendiente y 1 esperando pieza.
      expect(find.text('Citas por estado'), findsOneWidget);
      expect(find.text('5 en total'), findsOneWidget);

      // El anillo es `fl_chart`: si la pantalla volviera al texto de ejemplo,
      // este `find` no encuentra nada y el grafico no se esta dibujando.
      expect(find.byType(PieChart), findsOneWidget);

      // El total en el hueco central del anillo. El encabezado dice '5 en
      // total', que es otra cadena, asi que este '5' es el del centro.
      expect(find.text('5'), findsOneWidget);

      // La leyenda trae los cuatro estados con su cantidad.
      for (final fila in <String, String>{
        'Pendiente': '1',
        'Esperando Pieza': '1',
        'En proceso': '1',
        'Completado': '2',
      }.entries) {
        expect(
          find.text(fila.key),
          findsOneWidget,
          reason: 'falta ${fila.key} en la leyenda',
        );
        expect(
          find.descendant(
            of: find.ancestor(
              of: find.text(fila.key),
              matching: find.byType(Row),
            ),
            matching: find.text(fila.value),
          ),
          findsOneWidget,
          reason: 'la cantidad de ${fila.key} no esta junto a su nombre',
        );
      }
    });

    testWidgets('los colores del anillo son los de AppColors', (tester) async {
      await sembrarBaseDePrueba();
      await abrirDashboard(tester);

      final data = tester.widget<PieChart>(find.byType(PieChart)).data;
      final colores = data.sections
          .map((s) => s.color)
          .toSet()
          .toList(growable: false);

      expect(colores, contains(AppColors.completado));
      expect(colores, contains(AppColors.enProceso));
      expect(colores, contains(AppColors.pendientes));
      expect(colores, contains(AppColors.esperandoPieza));

      // Y el valor de cada sector es el conteo real, no un numero inventado.
      expect(
        data.sections.map((s) => s.value).reduce((a, b) => a + b),
        5.0,
        reason: 'los sectores tienen que sumar el total de citas',
      );
    });

    testWidgets('con la base vacia el grafico es un texto, no un crash', (
      tester,
    ) async {
      await abrirDashboard(tester);

      expect(find.byType(PieChart), findsNothing);
      expect(find.text('Todavía no hay citas registradas.'), findsOneWidget);
      expect(find.text('0 en total'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

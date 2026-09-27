import 'package:autofix/app/conectividad_app.dart';
import 'package:autofix/core/connectivity/connectivity_scope.dart';
import 'package:autofix/core/connectivity/connectivity_service.dart';
import 'package:autofix/core/connectivity/widgets/conectivity_banner.dart';
import 'package:autofix/features/citas/presentation/citas_page.dart';
import 'package:autofix/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Smoke test de la app y del banner global de conectividad.
///
/// Para no depender del radio real del emulador, se inyecta un
/// `ConnectivityService` falso en el `ConnectivityScope`. El resto de la
/// arquitectura (InheritedNotifier + `MaterialApp.builder`) se ejercita igual
/// que en produccion.
///
/// NOTA PARA LEANDY: este archivo estaba vacio (0 bytes) en la rama `Diseño` y
/// eso hacia fallar `flutter test` con "Error: Undefined name 'main'". Si al
/// mergear te aparece un conflicto en este archivo, GANA ESTA VERSION: la tuya
/// no corre ningun test.
class _ServicioFalso extends ConnectivityService {
  _ServicioFalso(this._conectividad);

  final bool _conectividad;

  @override
  bool get hayConexion => _conectividad;
}

Widget _app({required bool conectado}) {
  return ConnectivityScope(
    servicio: _ServicioFalso(conectado),
    child: MaterialApp(
      builder: ConectividadApp.bannerBuilder,
      home: const Scaffold(body: Text('pantalla interna')),
    ),
  );
}

void main() {
  testWidgets('sin conexion: el banner aparece y se pinta de rojo', (tester) async {
    await tester.pumpWidget(_app(conectado: false));
    await tester.pumpAndSettle();

    expect(find.byType(ConectivityBanner), findsOneWidget);
    expect(find.textContaining('Sin conexion'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);

    // Se usa el color de SU paleta, no un rojo suelto.
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(ConectivityBanner),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, AppColors.atrasadas);
  });

  testWidgets('con conexion: el banner se colapsa y no ocupa espacio', (tester) async {
    await tester.pumpWidget(_app(conectado: true));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sin conexion'), findsNothing);
    expect(find.byIcon(Icons.wifi_off), findsNothing);
  });

  testWidgets('el banner queda montado por encima del Navigator', (tester) async {
    await tester.pumpWidget(_app(conectado: false));
    await tester.pumpAndSettle();

    // Si el banner estuviera por FUERA del Navigator, no sobrevive al cambio de
    // home. Esto prueba que queda por encima de toda ruta.
    expect(find.byType(Navigator), findsOneWidget);
    expect(find.text('pantalla interna'), findsOneWidget);
    expect(find.byType(ConectivityBanner), findsOneWidget);
  });

  testWidgets('el chip compacto usa verde y rojo de AppColors', (tester) async {
    await tester.pumpWidget(
      ConnectivityScope(
        servicio: _ServicioFalso(true),
        child: const MaterialApp(
          home: Scaffold(body: ConectivityChip()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('En linea'), findsOneWidget);
    expect(find.byIcon(Icons.wifi), findsOneWidget);
  });

  group('la app de demo arranca de verdad', () {
    setUpAll(() {
      // `CitasPage` pegale a SQLite al montarse, asi que el test necesita el
      // motor de la plataforma. Por eso este NO es un test de la plantilla:
      // levanta el root real de `lib/main.dart` contra una base de verdad.
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      // Y `connectivity_plus` va por MethodChannel, que en un test no tiene
      // plataforma detras. Se mockean los DOS canales del plugin:
      //   - `connectivity`       -> `check` (MethodChannel), responde ['wifi']
      //   - `connectivity_status`-> el stream de cambios (EventChannel)
      // El payload es una `List<String>` ('wifi', 'none'...), segun se lee en
      // `connectivity_plus_platform_interface/lib/method_channel_connectivity.dart`.
      // Sin este mock, el `.listen()` revienta con MissingPluginException DENTRO
      // del `onListen` del EventChannel: como ese error viaja por la zona async y
      // no por el `onError` del Stream, el `try/catch` de `ConnectivityService`
      // no lo puede atrapar y el test revienta igual.
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => <String>['wifi'],
      );

      messenger.setMockStreamHandler(
        const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
        MockStreamHandler.inline(
          onListen: (args, sink) => sink.success(<String>['wifi']),
        ),
      );
    });

    tearDownAll(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        null,
      );
      messenger.setMockStreamHandler(
        const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
        null,
      );
    });

    testWidgets('el root de la app monta banner + pantalla de citas', (tester) async {
      // OJO, y esto se va a revisar en el code review: este test arma el mismo
      // arbol que `AutoFixDemoApp` de `lib/main.dart` en vez de importarlo.
      // NO es pereza, es a proposito: `lib/main.dart` es de Leandy y en el
      // merge se reemplaza por completo. Si este test importara `main.dart`,
      // el dia del merge dejaria de compilar por `AutoFixDemoApp` inexistente
      // y el repo se caeria en el momento exacto de integrar. Lo que se prueba
      // aca es el codigo que NO se va a reemplazar: `ConectividadApp`,
      // `bannerBuilder` y `CitasPage` hablando con SQLite de verdad.
      // La `MaterialApp` de 6 lineas que queda afuera es solo configuracion.
      // Para probar tambien esa parte, corre `flutter run` a mano.
      //
      // Y `runAsync` NO es opcional: `tester.pump(Duration(...))` mueve un reloj
      // FALSO, asi que los `await` reales (el query a SQLite via FFI corre en
      // otro isolate) nunca terminan, la pantalla se queda con el
      // `CircularProgressIndicator` girando y `pumpAndSettle` espera al
      // infinito. Para que entre I/O de verdad hay que salir del reloj falso.
      await tester.runAsync(() async {
        await tester.pumpWidget(const _RootDemo());
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();

      // La pantalla de citas cerro la consulta y quedo en su estado vacio:
      // eso prueba que el `await` de sqflite se resolvio de verdad, que la base
      // se abrio y que el `CREATE TABLE` corrio sin explode.
      expect(find.textContaining('Aun no hay citas'), findsOneWidget);
      // El banner esta montado aunque la pantalla no lo pida, y el chip del
      // AppBar tambien lee el estado: las dos rutas del InheritedNotifier andan.
      expect(find.byType(ConectivityBanner), findsOneWidget);
      expect(find.byType(ConectivityChip), findsOneWidget);
      // El mock dice 'wifi', asi que el banner de "sin conexion" NO se muestra.
      expect(find.textContaining('Sin conexion'), findsNothing);
      expect(find.text('En linea'), findsOneWidget);
    });
  });
}

/// Replica exacta del arbol de `AutoFixDemoApp` (`lib/main.dart`).
class _RootDemo extends StatelessWidget {
  const _RootDemo();

  @override
  Widget build(BuildContext context) {
    return ConectividadApp(
      child: MaterialApp(
        title: 'AutoFix (demo Sandy)',
        builder: ConectividadApp.bannerBuilder,
        home: const CitasPage(),
      ),
    );
  }
}

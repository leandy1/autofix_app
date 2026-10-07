import 'package:autofix/features/cliente/data/catalogo_vehiculos_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('obtiene y normaliza las marcas de NHTSA vPIC', () async {
    late Uri uriSolicitada;
    final api = CatalogoVehiculosApi(
      cliente: MockClient((request) async {
        uriSolicitada = request.url;
        return http.Response(
          '{"Results":[{"MakeName":"Toyota"},{"MakeName":"Honda"},'
          '{"MakeName":"Toyota"},{"MakeName":" "}]}',
          200,
        );
      }),
    );
    addTearDown(api.close);

    final marcas = await api.obtenerMarcas(enLinea: true);

    expect(uriSolicitada.host, 'vpic.nhtsa.dot.gov');
    expect(uriSolicitada.path, '/api/vehicles/GetMakesForVehicleType/car');
    expect(uriSolicitada.queryParameters['format'], 'json');
    expect(marcas, ['Honda', 'Toyota']);
  });

  test('consulta modelos con marca y año, y parsea Model_Name', () async {
    late Uri uriSolicitada;
    final api = CatalogoVehiculosApi(
      cliente: MockClient((request) async {
        uriSolicitada = request.url;
        return http.Response(
          '{"Results":[{"Model_Name":"Civic"},{"Model_Name":"Accord"},'
          '{"Model_Name":"Civic"}]}',
          200,
        );
      }),
    );
    addTearDown(api.close);

    final modelos = await api.obtenerModelos(
      marca: 'Honda',
      anio: 2022,
      enLinea: true,
    );

    expect(uriSolicitada.path, contains('GetModelsForMakeYear'));
    expect(uriSolicitada.path, contains('make/Honda/modelyear/2022'));
    expect(uriSolicitada.queryParameters['format'], 'json');
    expect(modelos, ['Accord', 'Civic']);
  });

  test('modo sin conexión no realiza solicitudes HTTP', () async {
    var llamadas = 0;
    final api = CatalogoVehiculosApi(
      cliente: MockClient((_) async {
        llamadas++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.close);

    final marcas = await api.obtenerMarcas(enLinea: false);
    final modelos = await api.obtenerModelos(
      marca: 'Toyota',
      anio: 2020,
      enLinea: false,
    );

    expect(marcas, isEmpty); // la UI complementa la caché con marcas comunes
    expect(modelos, isEmpty); // el formulario deja escribir el modelo a mano
    expect(llamadas, 0);
  });

  test('cachea marcas de la API y las conserva disponibles offline', () async {
    final online = CatalogoVehiculosApi(
      cliente: MockClient(
        (_) async => http.Response('{"Results":[{"MakeName":"Toyota"}]}', 200),
      ),
    );
    expect(await online.obtenerMarcas(enLinea: true), ['Toyota']);
    online.close();

    var llamadasOffline = 0;
    final offline = CatalogoVehiculosApi(
      cliente: MockClient((_) async {
        llamadasOffline++;
        return http.Response('{}', 500);
      }),
    );
    addTearDown(offline.close);

    expect(await offline.obtenerMarcas(enLinea: false), ['Toyota']);
    expect(llamadasOffline, 0);
  });

  test('rechaza HTTP no exitoso y respuestas JSON sin Results', () async {
    final apiHttp = CatalogoVehiculosApi(
      cliente: MockClient((_) async => http.Response('sin servicio', 503)),
    );
    addTearDown(apiHttp.close);
    await expectLater(
      apiHttp.obtenerMarcas(enLinea: true),
      throwsA(isA<http.ClientException>()),
    );

    final apiJson = CatalogoVehiculosApi(
      cliente: MockClient((_) async => http.Response('{"Message":"ok"}', 200)),
    );
    addTearDown(apiJson.close);
    await expectLater(
      apiJson.obtenerMarcas(enLinea: true),
      throwsA(isA<FormatException>()),
    );
  });
}

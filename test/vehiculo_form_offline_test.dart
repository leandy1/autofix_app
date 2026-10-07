import 'package:autofix/features/cliente/widgets/agenda_cliente_widgets.dart';
import 'package:autofix/features/cliente/models/vehiculo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sólo muestra Registrar otro cuando ya hay selección', (
    tester,
  ) async {
    const id = '11111111-1111-4111-8111-111111111111';
    const vehiculo = Vehiculo(
      id: id,
      clienteId: 'cliente@autofix.test',
      marca: 'Toyota',
      modelo: 'Corolla',
      anio: 2022,
    );

    Widget vista({required bool seleccionado}) => MaterialApp(
      home: Scaffold(
        body: VehiculoPlaceholderCliente(
          formularioVisible: false,
          seleccionado: seleccionado,
          resumenVehiculo: seleccionado ? vehiculo.resumen : null,
          marcaController: TextEditingController(),
          modeloController: TextEditingController(),
          anioController: TextEditingController(),
          placaController: TextEditingController(),
          errorFormulario: null,
          marcasDisponibles: const [],
          modelosDisponibles: const [],
          aniosDisponibles: const [],
          cargandoMarcas: false,
          cargandoModelos: false,
          mensajeCatalogo: null,
          onMarcaSelected: (_) {},
          onAnioSelected: (_) {},
          onModeloSelected: (_) {},
          onRecargarCatalogo: () {},
          vehiculosRegistrados: const [vehiculo],
          vehiculoSeleccionadoId: seleccionado ? id : null,
          onVehiculoRegistradoSelected: (_) {},
          onAgregarVehiculo: () {},
          onPressed: () {},
          onCancel: () {},
          onSave: () {},
        ),
      ),
    );

    await tester.pumpWidget(vista(seleccionado: false));
    expect(find.text('Registrar vehículo'), findsOneWidget);
    expect(find.text('Registrar otro vehículo'), findsNothing);

    await tester.pumpWidget(vista(seleccionado: true));
    expect(find.text('Editar vehículo'), findsOneWidget);
    expect(find.text('Registrar otro vehículo'), findsOneWidget);
  });

  testWidgets('permite completar marca, año y modelo manualmente sin red', (
    tester,
  ) async {
    final marca = TextEditingController();
    final modelo = TextEditingController();
    final anio = TextEditingController();
    final placa = TextEditingController();
    var guardado = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VehiculoPlaceholderCliente(
              formularioVisible: true,
              seleccionado: false,
              resumenVehiculo: null,
              marcaController: marca,
              modeloController: modelo,
              anioController: anio,
              placaController: placa,
              errorFormulario: null,
              marcasDisponibles: const ['Toyota'],
              modelosDisponibles: const [],
              aniosDisponibles: const ['2022'],
              cargandoMarcas: false,
              cargandoModelos: false,
              mensajeCatalogo: 'Sin conexión: puedes escribir el vehículo.',
              onMarcaSelected: (valor) => marca.text = valor ?? '',
              onAnioSelected: (valor) => anio.text = valor ?? '',
              onModeloSelected: (valor) => modelo.text = valor ?? '',
              onRecargarCatalogo: () {},
              vehiculosRegistrados: const [],
              vehiculoSeleccionadoId: null,
              onVehiculoRegistradoSelected: (_) {},
              onAgregarVehiculo: () {},
              onPressed: () {},
              onCancel: () {},
              onSave: () => guardado = true,
            ),
          ),
        ),
      ),
    );

    final selectores = find.byType(DropdownButtonFormField<String>);
    await tester.tap(selectores.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ingresar marca manualmente…').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate((w) => w is TextField && w.controller == marca),
      'Toyota',
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2022').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ingresar modelo manualmente…').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate((w) => w is TextField && w.controller == modelo),
      'Corolla',
    );
    await tester.enterText(
      find.byWidgetPredicate((w) => w is TextField && w.controller == placa),
      'A123456',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
    await tester.pump();

    expect(guardado, isTrue);
    expect(marca.text, 'Toyota');
    expect(modelo.text, 'Corolla');
    expect(anio.text, '2022');
    expect(placa.text, 'A123456');
  });
}

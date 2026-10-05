import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autofix/features/admin/screens/citas_admin_screen.dart';
import 'package:autofix/shared/models/cita_admin.dart';

void main() {
  testWidgets('muestra la cita con el diseño de admin y el estado correcto', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // v7: el id es un UUID en texto, no un numero. Antes era `id: 42`.
    const idCita = '55555555-5555-4555-8555-555555555555';

    final cita = CitaAdmin(
      id: idCita,
      cliente: 'Ana López',
      telefono: '8091234567',
      marca: 'Toyota',
      modelo: 'Corolla',
      anio: '2022',
      placa: 'A123456',
      servicios: const ['Cambio de aceite', 'Lavado'],
      fecha: DateTime(2026, 9, 29),
      hora: const TimeOfDay(hour: 10, minute: 30),
      estado: EstadoCitaAdmin.enProceso,
      descripcion: 'Revisión general',
      tecnico: 'Carlos',
      total: 7500,
      syncStatus: 'synced',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CitaAdminCard(cita: cita)),
      ),
    );

    expect(find.text('Ana López'), findsOneWidget);
    expect(find.text('En proceso'), findsOneWidget);
    expect(find.text('Toyota Corolla 2022'), findsOneWidget);
    expect(find.text('A123456'), findsOneWidget);
    expect(find.text(r'RD$ 7500'), findsOneWidget);

    await tester.tap(find.text('Ver detalle'));
    await tester.pumpAndSettle();
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Eliminar'), findsOneWidget);
    expect(find.text('Cerrar'), findsOneWidget);
    expect(tester.getRect(find.text('Editar')).right, lessThan(360));
    expect(
      (tester.getCenter(find.text('Eliminar')).dy -
              tester.getCenter(find.text('Editar')).dy)
          .abs(),
      lessThan(1),
    );
    expect(
      (tester.getCenter(find.text('Eliminar')).dy -
              tester.getCenter(find.text('Cerrar')).dy)
          .abs(),
      lessThan(1),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Nombre'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Apellido'), findsOneWidget);
    expect(find.text('López'), findsOneWidget);
    expect(find.text('Teléfono'), findsOneWidget);
    expect(find.text('Cédula'), findsNothing);
    expect(find.text('Correo'), findsNothing);
    expect(find.text('Color'), findsNothing);
  });

  testWidgets('invoca editar y eliminar desde la vista de detalle', (
    tester,
  ) async {
    // v7: `eliminado` era un `int` que se comparaba contra el `id` que la tarjeta
    // dispara. Ahora el id viaja como texto, asi que el `String?` inicializado en
    // `null` es lo que distingue "no se disparo el callback" de "se disparo con
    // este id": con un valor inicial inventado, un callback que nunca corre
    // pasaria el test.
    const idCita = '77777777-7777-4777-8777-777777777777';

    final cita = CitaAdmin(
      id: idCita,
      cliente: 'Beatriz',
      telefono: '8092223344',
      marca: 'Honda',
      modelo: 'Civic',
      anio: '2021',
      placa: 'B765432',
      servicios: const ['Cambio de aceite'],
      fecha: DateTime(2026, 10, 2),
      hora: const TimeOfDay(hour: 11, minute: 0),
      estado: EstadoCitaAdmin.pendiente,
      descripcion: 'Alineación',
      tecnico: 'Técnico 1',
      total: 2500,
      syncStatus: 'pending',
    );

    var editado = false;
    String? eliminado;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CitaAdminCard(
            cita: cita,
            onEdited: (_) => editado = true,
            onDeleted: (id) => eliminado = id,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ver detalle'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(editado, isTrue);

    await tester.tap(find.text('Ver detalle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(eliminado, idCita);
  });
}

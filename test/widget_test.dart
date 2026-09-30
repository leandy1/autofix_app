import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autofix/models/cita_admin.dart';
import 'package:autofix/screens/admin/citas_admin_screen.dart';

void main() {
  testWidgets('muestra la cita con el diseño de admin y el estado correcto', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cita = CitaAdmin(
      id: 42,
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
}

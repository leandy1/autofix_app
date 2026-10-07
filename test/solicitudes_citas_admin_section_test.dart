import 'package:autofix/features/admin/widgets/solicitudes_citas_admin_section.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Cita cita({
    required String id,
    required String codigo,
    required EstadoCita estado,
  }) => Cita(
    id: id,
    codigoVisible: codigo,
    cliente: 'Cliente $codigo',
    vehiculo: 'Toyota Corolla',
    fechaCita: DateTime.utc(2026, 10, 7, 14),
    estado: estado,
  );

  testWidgets('lista sólo pendientes y ofrece aceptar o rechazar', (
    tester,
  ) async {
    final cambios = <String, EstadoCita>{};
    final citas = [
      cita(
        id: '11111111-1111-4111-8111-111111111111',
        codigo: 'CITA-0041',
        estado: EstadoCita.pendiente,
      ),
      cita(
        id: '22222222-2222-4222-8222-222222222222',
        codigo: 'CITA-0042',
        estado: EstadoCita.pendiente,
      ),
      cita(
        id: '33333333-3333-4333-8333-333333333333',
        codigo: 'CITA-0043',
        estado: EstadoCita.aceptada,
      ),
      cita(
        id: '44444444-4444-4444-8444-444444444444',
        codigo: 'CITA-0044',
        estado: EstadoCita.rechazada,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SolicitudesCitasAdminSection(
              citas: citas,
              onCambiarEstado: (cita, estado) async {
                cambios[cita.id!] = estado;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('CITA-0041'), findsOneWidget);
    expect(find.text('CITA-0042'), findsOneWidget);
    expect(find.text('CITA-0043'), findsNothing);
    expect(find.text('CITA-0044'), findsNothing);
    expect(find.text('11111111-1111-4111-8111-111111111111'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Aceptar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Rechazar').last);
    await tester.pumpAndSettle();

    expect(cambios[citas[0].id], EstadoCita.aceptada);
    expect(cambios[citas[1].id], EstadoCita.rechazada);
  });
}

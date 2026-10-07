import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/cliente/widgets/accion_qr_cita_cliente.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  Cita cita(EstadoCita estado) => Cita(
    cliente: 'Cliente',
    correoCliente: 'cliente@ejemplo.com',
    vehiculo: 'Honda Civic 2022',
    fechaCita: DateTime.utc(2026, 11, 3, 14),
    estado: estado,
    codigoVisible: 'CITA-0042',
  );

  testWidgets('sólo una cita aceptada muestra y abre el QR real', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccionQrCitaCliente(cita: cita(EstadoCita.pendiente)),
        ),
      ),
    );
    expect(find.text('Ver Código QR'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccionQrCitaCliente(cita: cita(EstadoCita.aceptada)),
        ),
      ),
    );
    expect(find.text('Ver Código QR'), findsOneWidget);

    await tester.tap(find.text('Ver Código QR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('CITA-0042'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

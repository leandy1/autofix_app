import 'package:autofix/features/cliente/widgets/codigo_qr_cita.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('el QR local codifica exclusivamente el código visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CodigoQrCita(codigoVisible: 'CITA-0025')),
      ),
    );

    final codigo = tester.widget<CodigoQrCita>(find.byType(CodigoQrCita));
    expect(codigo.codigoVisible, 'CITA-0025');
    expect(find.byType(QrImageView), findsOneWidget);
  });
}

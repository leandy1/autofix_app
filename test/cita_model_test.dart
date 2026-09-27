import 'package:autofix/features/citas/models/cita.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cita', () {
    final cita = Cita(
      id: 1,
      codigoQr: 'QR-001',
      cliente: 'Ana Torres',
      vehiculo: 'Toyota Hilux',
      descripcion: 'Cambio de aceite',
      fechaCita: DateTime(2026, 10, 1, 9, 30),
      estado: EstadoCita.pendiente,
      creadoEn: DateTime(2026, 9, 1),
    );

    test('viaja de objeto a fila y vuelve sin perder datos', () {
      final recuperada = Cita.fromMap(cita.toMap());

      expect(recuperada.id, cita.id);
      expect(recuperada.codigoQr, cita.codigoQr);
      expect(recuperada.cliente, cita.cliente);
      expect(recuperada.vehiculo, cita.vehiculo);
      expect(recuperada.descripcion, cita.descripcion);
      expect(recuperada.fechaCita, cita.fechaCita);
      expect(recuperada.estado, cita.estado);
    });

    test('no incluye la clave id cuando la cita todavia no fue insertada', () {
      final sinId = Cita(
        codigoQr: 'QR-002',
        cliente: 'Luis Paz',
        vehiculo: 'Honda Civic',
        fechaCita: DateTime(2026, 10, 2, 10),
      );
      expect(sinId.toMap().containsKey('id'), isFalse);
    });

    test('copyWith conserva el id original', () {
      expect(cita.copyWith(estado: EstadoCita.completada).id, cita.id);
    });

    test('un estado desconocido en la base cae en pendiente', () {
      expect(EstadoCita.desdeTexto('inventado'), EstadoCita.pendiente);
    });
  });
}

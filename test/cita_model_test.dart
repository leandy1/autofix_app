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
      expect(cita.copyWith(estado: EstadoCita.completado).id, cita.id);
    });

    test('un estado desconocido en la base cae en pendiente', () {
      expect(EstadoCita.desdeNombre('inventado'), EstadoCita.pendiente);
    });

    test('la etiqueta coincide con la llave de kColorPorEstado de Leandy', () {
      // Si esto falla, el color del acordeon de Leandy deja de matchear.
      expect(EstadoCita.pendiente.etiqueta, 'Pendiente');
      expect(EstadoCita.esperandoPieza.etiqueta, 'Esperando Pieza');
      expect(EstadoCita.enProceso.etiqueta, 'En proceso');
      expect(EstadoCita.completado.etiqueta, 'Completado');
    });

    test('ATRASADAS es derivado, no un estado guardado', () {
      final vencida = cita.copyWith(fechaCita: DateTime(2020, 1, 1));
      expect(vencida.etiquetaUI, 'ATRASADAS');
      expect(vencida.copyWith(estado: EstadoCita.completado).etiquetaUI, 'Completado');
      expect(cita.etiquetaUI, 'Pendiente');
    });

    test('los servicios sobreviven al viaje a JSON y vuelven', () {
      final conServicios = cita.copyWith(servicios: const ['Frenos', 'Alineación']);
      final vuelta = Cita.fromMap(conServicios.toMap());
      expect(vuelta.servicios, ['Frenos', 'Alineación']);
    });
  });
}

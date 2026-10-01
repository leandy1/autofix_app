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
      // Instante fijo: el modelo no lee el reloj, se lo pasan.
      final ahora = DateTime(2026, 9, 15, 12);
      final vencida = cita.copyWith(fechaCita: DateTime(2020, 1, 1));
      expect(vencida.etiquetaUI(ahora), 'ATRASADAS');
      expect(
        vencida.copyWith(estado: EstadoCita.completado).etiquetaUI(ahora),
        'Completado',
      );
      expect(cita.etiquetaUI(ahora), 'Pendiente');
    });

    test('esAtrasada depende del instante recibido, no del reloj', () {
      final pendiente = cita.copyWith(fechaCita: DateTime(2026, 10, 1, 9, 30));
      // Dos dispositivos con el mismo "ahora" tienen que coincidir siempre.
      expect(pendiente.esAtrasada(DateTime(2026, 10, 1, 10)), isTrue);
      expect(pendiente.esAtrasada(DateTime(2026, 10, 1, 9)), isFalse);
    });

    test('una cita completada no cae en ATRASADAS aunque la hora haya pasado', () {
      final completada = cita
          .copyWith(fechaCita: DateTime(2020, 1, 1))
          .copyWith(estado: EstadoCita.completado);
      expect(completada.esAtrasada(DateTime(2026, 9, 15)), isFalse);
    });

    test('las claves de fila coinciden con la tabla citas', () {
      // El modelo guarda las claves como literales para no depender de la capa de
      // datos. Este test es el que avisa si el CREATE TABLE se desincroniza: el
      // chequeo real por PRAGMA vive en `cita_repository_test.dart`.
      final claves = cita.toMap().keys.toSet();
      expect(claves, containsAll(<String>{
        'codigo_qr',
        'cliente',
        'vehiculo',
        'fecha_cita',
        'estado',
        'servicios',
      }));
    });

    test('los servicios sobreviven al viaje a JSON y vuelven', () {
      final conServicios = cita.copyWith(servicios: const ['Frenos', 'Alineación']);
      final vuelta = Cita.fromMap(conServicios.toMap());
      expect(vuelta.servicios, ['Frenos', 'Alineación']);
    });
  });
}

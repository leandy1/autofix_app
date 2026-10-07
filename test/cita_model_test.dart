import 'package:autofix/features/citas/models/cita.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cita', () {
    // v7: el id es un UUID en texto, no un autoincremento. Se usa un valor fijo y
    // NO `Uuid.instancia.generar()` a proposito: este test compara el `id` que
    // entra con el que sale, y un id aleatorio pasa igual de todos modos, asi que
    // fijo se lee mas claro.
    // Las fechas van en UTC y con el `Z` explicito, no con `DateTime(2026, 10, 1,
    // 9, 30)`.
    //
    // El motivo es que ese constructor sin `isUtc` devuelve HORA LOCAL, y el
    // modelo escribe UTC (`aIsoUtc`). Con la maquina en UTC-4, las 9:30 locales se
    // guardan como '13:30Z' y al releer el objeto da 13:30: el test fallaba en
    // cualquier zona horaria que no fuera UTC, y pasaba solo porque el que lo
    // escribio tenia el reloj en UTC.
    //
    // `DateTime.utc` ademas hace el test HONESTO sobre el contrato: si el modelo
    // dejara de convertir a UTC, este test lo detecta en vez de acomodarse.
    final cita = Cita(
      id: '11111111-1111-4111-8111-111111111111',
      cliente: 'Ana Torres',
      correoCliente: 'ana@example.com',
      vehiculo: 'Toyota Hilux',
      descripcion: 'Cambio de aceite',
      fechaCita: DateTime.utc(2026, 10, 1, 13, 30),
      estado: EstadoCita.pendiente,
      creadoEn: DateTime.utc(2026, 9, 1),
    );

    test('viaja de objeto a fila y vuelve sin perder datos', () {
      final recuperada = Cita.fromMap(cita.toMap());

      expect(recuperada.id, cita.id);
      expect(recuperada.cliente, cita.cliente);
      expect(recuperada.correoCliente, cita.correoCliente);
      expect(recuperada.vehiculo, cita.vehiculo);
      expect(recuperada.descripcion, cita.descripcion);
      expect(recuperada.fechaCita, cita.fechaCita);
      expect(recuperada.estado, cita.estado);
    });

    test('lee campos de Firestore además de correo del cliente', () {
      final documentoFirestore = cita.toMap()..['ownerUid'] = 'uid-del-cliente';

      final recuperada = Cita.fromMap(documentoFirestore);

      expect(recuperada.correoCliente, 'ana@example.com');
      expect(recuperada.id, cita.id);
    });

    test('recupera una fila legacy con columnas nuevas ausentes o nulas', () {
      final legacy = Cita.fromMap(<String, Object?>{
        'id': 'legacy-id',
        'cliente': null,
        'telefono': null,
        'vehiculo': null,
        'fecha_cita': '2026-11-03T14:00:00.000Z',
        'estado': null,
      });

      expect(legacy.id, 'legacy-id');
      expect(legacy.cliente, isEmpty);
      expect(legacy.correoCliente, isEmpty);
      expect(legacy.vehiculo, isEmpty);
      expect(legacy.tallerId, isNull);
      expect(legacy.estado, EstadoCita.pendiente);
      expect(legacy.codigoVisible, 'PENDIENTE');
    });

    test(
      'la fecha se escribe SIEMPRE en UTC con la Z, nunca en hora local',
      () {
        // El contrato que hace comparables dos citas de dos husos distintos. Si
        // `toMap` dejara de usar `aIsoUtc`, este test falla al instante.
        final fila = cita.toMap();
        expect(fila['fecha_cita'], '2026-10-01T13:30:00.000Z');
      },
    );

    test('no incluye la clave id cuando la cita todavia no fue insertada', () {
      final sinId = Cita(
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

    test('recupera también etiquetas antiguas de estado recibidas de la nube', () {
      expect(EstadoCita.desdeNombre('Aceptada'), EstadoCita.aceptada);
      expect(EstadoCita.desdeNombre('RECHAZADA'), EstadoCita.rechazada);
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

    test('esAtrasada compara fechas e ignora la hora de la cita', () {
      final pendiente = cita.copyWith(fechaCita: DateTime(2026, 10, 1, 9, 30));
      expect(pendiente.esAtrasada(DateTime(2026, 10, 1, 10)), isFalse);
      expect(pendiente.esAtrasada(DateTime(2026, 10, 1, 9)), isFalse);
      expect(pendiente.esAtrasada(DateTime(2026, 10, 2, 0)), isTrue);
    });

    test(
      'una cita completada no cae en ATRASADAS aunque la fecha haya pasado',
      () {
        final completada = cita
            .copyWith(fechaCita: DateTime(2020, 1, 1))
            .copyWith(estado: EstadoCita.completado);
        expect(completada.esAtrasada(DateTime(2026, 9, 15)), isFalse);
      },
    );

    test('las claves de fila coinciden con la tabla citas', () {
      // El modelo guarda las claves como literales para no depender de la capa de
      // datos. Este test es el que avisa si el CREATE TABLE se desincroniza: el
      // chequeo real por PRAGMA vive en `cita_repository_test.dart`.
      final claves = cita.toMap().keys.toSet();
      expect(
        claves,
        containsAll(<String>{
          'cliente',
          'vehiculo',
          'fecha_cita',
          'estado',
          'servicios',
          'total',
        }),
      );
    });

    test('los servicios sobreviven al viaje a JSON y vuelven', () {
      final conServicios = cita.copyWith(
        servicios: const ['Frenos', 'Alineación'],
      );
      final vuelta = Cita.fromMap(conServicios.toMap());
      expect(vuelta.servicios, ['Frenos', 'Alineación']);
    });

    // Regresion del error que salia en el dispositivo:
    // `[SyncService] Error procesando doc ...: type 'String' is not a subtype
    // of type 'List<dynamic>?' in type cast`. `toMap()` serializa los servicios
    // como JSON, asi que una cita que BAJA de Firestore llega como String y un
    // `as List?` revienta; con eso la cita entera se descartaba y nunca llegaba
    // a SQLite.
    test('leerServicios acepta el JSON que manda Firestore', () {
      expect(Cita.leerServicios('["Cambio de aceite y filtro","Frenos"]'), [
        'Cambio de aceite y filtro',
        'Frenos',
      ]);
    });

    test('leerServicios acepta una lista nativa', () {
      expect(Cita.leerServicios(['Frenos', 'Alineación']), [
        'Frenos',
        'Alineación',
      ]);
    });

    test('leerServicios devuelve vacío en vez de lanzar', () {
      expect(Cita.leerServicios(null), isEmpty);
      expect(Cita.leerServicios(''), isEmpty);
      expect(Cita.leerServicios('no es json'), isEmpty);
      expect(Cita.leerServicios('{"no":"es lista"}'), isEmpty);
    });
  });
}

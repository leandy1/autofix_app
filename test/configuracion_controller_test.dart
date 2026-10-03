import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/configuracion/presentation/configuracion_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Prueba la capa intermedia: el controller es lo unico que la vista conoce, asi
/// que es lo que hay que garantizar. En especial dos cosas que la vista no puede
/// resolver sola: traducir el error de SQLite a un mensaje legible, y no perder
/// datos cuando una escritura falla.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Base propia: este archivo corre en paralelo con los demas que usan SQLite.
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_configuracion_ctrl_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    await DatabaseHelper.resetParaPruebas();
  });

  ConfiguracionController nuevo() => ConfiguracionController();

  group('cargar', () {
    test('arranca con los catalogos de la semilla y sin error', () async {
      final c = nuevo();
      // `await cargar()` y no un `delayed(Duration.zero)`: la lectura de SQLite
      // son varias consultas encadenadas y no terminan en el proximo microtask.
      await c.cargar();

      expect(c.cargando, isFalse);
      expect(c.error, isNull);
      expect(c.tecnicos, isNotEmpty);
      expect(c.tiposServicio, isNotEmpty);
      expect(c.estados, isNotEmpty);
    });

    test('notifica a la vista para que se repinte', () async {
      final c = nuevo();
      var avisos = 0;
      c.addListener(() => avisos++);

      await c.cargar();

      // El primero es el `cargando = true`, el segundo el false con la data.
      expect(avisos, greaterThanOrEqualTo(2));
    });
  });

  group('guardar', () {
    test('un tecnico nuevo aparece en la lista', () async {
      final c = nuevo();
      await c.cargar();

      final antes = c.tecnicos.length;
      expect(await c.guardarTecnico('  Juan Pérez  '), isTrue);

      expect(c.tecnicos.length, antes + 1);
      // El `trim` es lo que hace que el UNIQUE detecte el duplicado de 'Tecnico 1'
      // cuando el admin escribe 'Tecnico 1 ' con el espacio de siempre pegado.
      expect(c.tecnicos.any((t) => t.nombre == 'Juan Pérez'), isTrue);
      expect(c.error, isNull);
    });

    test('un nombre vacio no se guarda y explica por que', () async {
      final c = nuevo();
      await c.cargar();

      expect(await c.guardarTecnico('   '), isFalse);
      expect(c.error, isNotNull);
      expect(c.error, contains('vacío'));
    });

    test('un nombre repetido NO se guarda y el mensaje es legible', () async {
      final c = nuevo();
      await c.cargar();
      await c.guardarTecnico('Repetido');
      final antes = c.tecnicos.length;

      expect(await c.guardarTecnico('repetido'), isFalse);

      // Lo importante: el mensaje NO es el 'UNIQUE constraint failed:
      // tecnicos.nombre' crudo de SQLite, que el admin no puede entender.
      expect(c.error, 'Ya existe un elemento con ese nombre.');
      expect(c.error, isNot(contains('UNIQUE')));
      expect(c.tecnicos.length, antes, reason: 'no debe haber una fila de mas');
    });

    test('un tipo de servicio guarda el precio como entero', () async {
      final c = nuevo();
      await c.cargar();

      // Un nombre que NO esta en la semilla: 'Cambio de gomas' ya viene creado y
      // el UNIQUE lo rechazaria, y el fallo seria del UNIQUE y no del precio.
      expect(
        await c.guardarTipoServicio('Cambio de bujes', r'RD$ 2,500'),
        isTrue,
      );

      final guardado = c.tiposServicio.firstWhere(
        (s) => s.nombre == 'Cambio de bujes',
      );
      expect(guardado.precio, 2500);
    });

    test(
      'un precio que no es numero se rechaza en vez de guardarse como 0',
      () async {
        final c = nuevo();
        await c.cargar();

        // Si se aceptara, el admin veria 'RD$ 0' en la tarjeta y recien en la
        // factura descubriria que el precio se perdio.
        expect(
          await c.guardarTipoServicio('Servicio raro', 'a definir'),
          isFalse,
        );
        expect(c.error, contains('precio'));
        expect(
          c.tiposServicio.any((s) => s.nombre == 'Servicio raro'),
          isFalse,
        );
      },
    );

    test('un estado nuevo aparece en la lista', () async {
      final c = nuevo();
      await c.cargar();
      final antes = c.estados.length;

      expect(await c.guardarEstado('En garantía'), isTrue);
      expect(c.estados.length, antes + 1);
    });
  });

  group('eliminar', () {
    test('eliminar saca la fila de la lista', () async {
      final c = nuevo();
      await c.cargar();
      await c.guardarTecnico('Temporal');
      final id = c.tecnicos.firstWhere((t) => t.nombre == 'Temporal').id!;

      expect(await c.eliminarTecnico(id), isTrue);

      expect(c.tecnicos.any((t) => t.nombre == 'Temporal'), isFalse);
      expect(c.error, isNull);
    });

    test('eliminar un tipo de servicio y un estado tambien los saca', () async {
      final c = nuevo();
      await c.cargar();
      await c.guardarTipoServicio('Temporal S', '100');
      await c.guardarEstado('Temporal E');

      final idServicio = c.tiposServicio
          .firstWhere((s) => s.nombre == 'Temporal S')
          .id!;
      final idEstado = c.estados
          .firstWhere((e) => e.nombre == 'Temporal E')
          .id!;

      expect(await c.eliminarTipoServicio(idServicio), isTrue);
      expect(await c.eliminarEstado(idEstado), isTrue);

      expect(c.tiposServicio.any((s) => s.nombre == 'Temporal S'), isFalse);
      expect(c.estados.any((e) => e.nombre == 'Temporal E'), isFalse);
    });

    test('eliminar un id que no existe avisa y no rompe la pantalla', () async {
      final c = nuevo();
      await c.cargar();
      final antes = c.tecnicos.length;

      expect(await c.eliminarTecnico(999999), isTrue);

      // Sin fila que borrar NO es un error: la vista no tiene por que mostrar un
      // Snackbar rojo por algo que el usuario no hizo mal.
      expect(c.error, isNull);
      expect(c.tecnicos.length, antes);
    });
  });

  group('formato de precio', () {
    test('muestra el separador de miles', () {
      expect(nuevo().formatearPrecio(1200), r'RD$ 1,200');
      expect(nuevo().formatearPrecio(850), r'RD$ 850');
    });

    test('un precio sin definir se muestra como el diseno, no como cero', () {
      // 'RD$ 0' diria que el trabajo es gratis. El diseno pedia 'RD$ -', que
      // significa "aun no se le puso precio".
      expect(nuevo().formatearPrecio(0), r'RD$ -');
    });

    test('lee lo que la persona escribe de verdad', () {
      expect(ConfiguracionController.leerPrecio('1200'), 1200);
      expect(ConfiguracionController.leerPrecio('1,200'), 1200);
      expect(ConfiguracionController.leerPrecio(r'RD$ 1,200'), 1200);
      expect(ConfiguracionController.leerPrecio(r'$1200'), 1200);
      expect(ConfiguracionController.leerPrecio(' 850 '), 850);
    });

    test('devuelve null cuando no hay ningun digito', () {
      expect(ConfiguracionController.leerPrecio(''), isNull);
      expect(ConfiguracionController.leerPrecio('   '), isNull);
      expect(ConfiguracionController.leerPrecio('a definir'), isNull);
      expect(ConfiguracionController.leerPrecio(null), isNull);
    });
  });
}

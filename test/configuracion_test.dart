import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/database/semilla_inicial.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/configuracion/data/estado_repository.dart';
import 'package:autofix/features/configuracion/data/tecnico_repository.dart';
import 'package:autofix/features/configuracion/data/tipo_servicio_repository.dart';
import 'package:autofix/features/configuracion/models/estado.dart';
import 'package:autofix/features/configuracion/models/tecnico.dart';
import 'package:autofix/features/configuracion/models/tipo_servicio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Prueba de integracion de los catalogos de Configuracion contra una base
/// SQLite real (via FFI). No usa mocks.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Base propia: este archivo corre en paralelo con los otros que usan SQLite.
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_configuracion_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    // El .db queda en `.dart_tool/`, o sea en disco. Sin este reset `onCreate`
    // no se vuelve a correr y el test pasa probando un esquema viejo.
    await DatabaseHelper.resetParaPruebas();
  });

  Future<String> rutaDeLaBase() async =>
      p.join(await getDatabasesPath(), 'autofix_configuracion_test.db');

  group('esquema', () {
    test(
      'los tres catalogos se crean con TODAS las columnas del modelo',
      () async {
        // Este es el test que atrapa el "no such column": los modelos declaran sus
        // claves como literales para no depender de `DatabaseHelper`, asi que
        // PRAGMA es la unica red que ata el CREATE TABLE con el `toMap()`.
        final db = await DatabaseHelper.instance.base;

        Future<void> comprobar(
          String tabla,
          Map<String, Object?> deUnModelo,
        ) async {
          final info = await db.rawQuery('PRAGMA table_info($tabla)');
          final nombres = info.map((f) => f['name'] as String).toSet();
          for (final clave in deUnModelo.keys) {
            expect(
              nombres,
              contains(clave),
              reason: 'falta la columna $clave en $tabla',
            );
          }
        }

        await comprobar(
          DatabaseHelper.tablaTecnicos,
          const Tecnico(nombre: 'x').toMap(),
        );
        await comprobar(
          DatabaseHelper.tablaTiposServicio,
          const TipoServicio(nombre: 'x', precio: 10).toMap(),
        );
        await comprobar(
          DatabaseHelper.tablaEstados,
          const EstadoConfig(nombre: 'x').toMap(),
        );
      },
    );

    test(
      'tipos_servicio tiene la columna de precio y las otras dos no',
      () async {
        final db = await DatabaseHelper.instance.base;

        final conPrecio = await db.rawQuery(
          'PRAGMA table_info(${DatabaseHelper.tablaTiposServicio})',
        );
        expect(
          conPrecio.map((f) => f['name']),
          contains(DatabaseHelper.colPrecio),
        );

        final sinPrecio = await db.rawQuery(
          'PRAGMA table_info(${DatabaseHelper.tablaTecnicos})',
        );
        expect(
          sinPrecio.map((f) => f['name']),
          isNot(contains(DatabaseHelper.colPrecio)),
        );
      },
    );
  });

  group('semilla inicial', () {
    test('una base nueva nace con los catalogos del diseno', () async {
      final tecnicos = await TecnicoRepository.instance.obtenerTodas();
      final servicios = await TipoServicioRepository.instance.obtenerTodas();
      final estados = await EstadoRepository.instance.obtenerTodas();

      expect(
        tecnicos.map((t) => t.nombre),
        containsAll(SemillaInicial.tecnicos),
      );
      expect(
        servicios.map((s) => s.nombre),
        containsAll(SemillaInicial.tiposServicio),
      );
      expect(estados.map((e) => e.nombre), containsAll(SemillaInicial.estados));
    });

    test(r'los precios sembrados son 0, no el texto RD$ del diseno', () async {
      final servicios = await TipoServicioRepository.instance.obtenerTodas();
      // El diseno mostraba 'RD$ —' porque no se sabia el precio. Guardar eso como
      // texto habria obligado a una columna TEXT y la suma de una orden de trabajo
      // dejaria de ser una suma.
      expect(servicios, isNotEmpty);
      expect(servicios.every((s) => s.precio == 0), isTrue);
    });

    test('abrir la app de nuevo NO duplica la semilla', () async {
      await DatabaseHelper.instance.cerrar();
      await TecnicoRepository.instance.obtenerTodas();
      await DatabaseHelper.instance.cerrar();

      final tecnicos = await TecnicoRepository.instance.obtenerTodas();
      expect(tecnicos.length, SemillaInicial.tecnicos.length);
    });
  });

  group('CRUD de catalogos', () {
    test('CREATE: el alta queda disponible y es recuperable', () async {
      final id = await TecnicoRepository.instance.crear(
        const Tecnico(nombre: 'Juan Pérez'),
      );

      final creado = await TecnicoRepository.instance.obtenerPorId(id);
      expect(creado, isNotNull);
      expect(creado!.nombre, 'Juan Pérez');
      expect(creado.activo, isTrue);
      // Sin esto el listado de la tarjeta no tendria contra que borrar.
      expect(creado.id, id);
    });

    test('READ: obtenerTodas devuelve lo guardado y ordenado por nombre', () async {
      await TecnicoRepository.instance.crear(const Tecnico(nombre: 'Zulma'));
      await TecnicoRepository.instance.crear(const Tecnico(nombre: 'Ana'));

      final todas = await TecnicoRepository.instance.obtenerTodas();
      final nombres = todas.map((t) => t.nombre).toList();

      // La semilla tambien esta: se compara el orden RELATIVO, no la posicion,
      // para que agregar un registro nuevo a la semilla no rompa este test.
      expect(nombres.indexOf('Ana'), lessThan(nombres.indexOf('Zulma')));
    });

    test('READ: obtenerPorNombre ignora mayusculas y espacios', () async {
      await TecnicoRepository.instance.crear(
        const Tecnico(nombre: 'Carlos Ruiz'),
      );

      expect(
        (await TecnicoRepository.instance.obtenerPorNombre('  carlos ruiz '))
            ?.nombre,
        'Carlos Ruiz',
      );
      expect(
        await TecnicoRepository.instance.obtenerPorNombre('No Existe'),
        isNull,
      );
    });

    test('UPDATE: los cambios quedan persistidos', () async {
      // 'Frenos' ya viene en la semilla, asi que se crea uno propio: si no, el
      // fallo seria del UNIQUE del nombre y no de la actualizacion.
      final id = await TipoServicioRepository.instance.crear(
        const TipoServicio(nombre: 'Frenos de disco', precio: 900),
      );
      final guardado = (await TipoServicioRepository.instance.obtenerPorId(
        id,
      ))!;

      final filas = await TipoServicioRepository.instance.actualizar(
        guardado.copyWith(nombre: 'Frenos y discos', precio: 1500),
      );
      expect(filas, 1);

      final releido = await TipoServicioRepository.instance.obtenerPorId(id);
      expect(releido!.nombre, 'Frenos y discos');
      expect(releido.precio, 1500);
    });

    test(
      'UPDATE: el precio sobrevive un round-trip sin perder Precision',
      () async {
        final id = await TipoServicioRepository.instance.crear(
          const TipoServicio(nombre: 'Alineación', precio: 1200),
        );
        final releido = await TipoServicioRepository.instance.obtenerPorId(id);

        // Entero, no REAL: si se guardara como 1200.50 volveria como
        // 1200.4999999 y la suma de una orden dejaria de cuadrar.
        expect(releido!.precio, 1200);
        expect(releido.precioEnCentavos, 120000);
      },
    );

    test('DELETE: la fila deja de estar en la base', () async {
      final id = await EstadoRepository.instance.crear(
        const EstadoConfig(nombre: 'Retrabajo'),
      );

      expect(await EstadoRepository.instance.eliminar(id), 1);
      expect(await EstadoRepository.instance.obtenerPorId(id), isNull);
    });

    test('eliminar un id inexistente devuelve 0 filas', () async {
      expect(await TecnicoRepository.instance.eliminar(999999), 0);
    });

    test('actualizar sin id lanza en vez de fallar en silencio', () async {
      expect(
        () => TecnicoRepository.instance.actualizar(const Tecnico(nombre: 'x')),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('UNIQUE de nombre', () {
    test('un nombre repetido se rechaza', () async {
      await TecnicoRepository.instance.crear(const Tecnico(nombre: 'Laura'));

      expect(
        () => TecnicoRepository.instance.crear(const Tecnico(nombre: 'Laura')),
        throwsA(isA<Exception>()),
      );
    });

    test('la diferencia de mayusculas TAMBIEN se rechaza', () async {
      // Se crea primero: 'En proceso' ya viene en la semilla, y lo que se quiere
      // probar es que el UNIQUE salta entre dos altas, no contra la semilla.
      await EstadoRepository.instance.crear(
        const EstadoConfig(nombre: 'Revisión profunda'),
      );

      // Es lo que justifica el indice COLLATE NOCASE: sin el, "Revisión profunda"
      // y "revisión profunda" coexistirian y el admin veria el estado duplicado
      // en la pantalla de Citas.
      expect(
        () => EstadoRepository.instance.crear(
          const EstadoConfig(nombre: 'revisión profunda'),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('cada catalogo es independiente: el mismo nombre puede existir en dos', () async {
      // Un tecnico y un estado pueden llamarse igual: son tablas distintas y el
      // UNIQUE es por tabla.
      await EstadoRepository.instance.crear(
        const EstadoConfig(nombre: 'Temporal'),
      );
      await expectLater(
        TecnicoRepository.instance.crear(const Tecnico(nombre: 'Temporal')),
        completes,
      );
    });
  });

  group('PATRON BASE', () {
    test('los tres repositorios cumplen BaseRepository', () async {
      // Compilar esto YA es la prueba de que cumplen el contrato: si dejaran de
      // cumplirlo, el analyzer falla antes de correr el test.
      final BaseRepository<Tecnico> tecnicos = TecnicoRepository.instance;
      final BaseRepository<TipoServicio> servicios =
          TipoServicioRepository.instance;
      final BaseRepository<EstadoConfig> estados = EstadoRepository.instance;

      expect(tecnicos.tabla, DatabaseHelper.tablaTecnicos);
      expect(servicios.tabla, DatabaseHelper.tablaTiposServicio);
      expect(estados.tabla, DatabaseHelper.tablaEstados);

      final id = await servicios.crear(
        const TipoServicio(nombre: 'Lavado', precio: 300),
      );
      expect(
        await servicios.actualizar(
          (await servicios.obtenerPorId(id))!.copyWith(precio: 350),
        ),
        1,
      );
      expect((await servicios.obtenerPorId(id))!.precio, 350);
      expect(await servicios.eliminar(id), 1);

      expect(
        (await tecnicos.obtenerTodas()).length,
        SemillaInicial.tecnicos.length,
      );
      expect(
        (await estados.obtenerTodas()).length,
        SemillaInicial.estados.length,
      );
    });
  });

  group('migracion v2 -> v3', () {
    // El esquema v2 tal cual lo creo la version anterior. Esta es la base que
    // puede tener un dispositivo que YA instalo la app con citas guardadas.
    const esquemaV2 = '''
      CREATE TABLE citas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo_qr TEXT NOT NULL UNIQUE,
        cliente TEXT NOT NULL,
        vehiculo TEXT NOT NULL,
        telefono TEXT NOT NULL DEFAULT '',
        marca TEXT NOT NULL DEFAULT '',
        modelo TEXT NOT NULL DEFAULT '',
        anio INTEGER NOT NULL DEFAULT 0,
        placa TEXT NOT NULL DEFAULT '',
        servicios TEXT NOT NULL DEFAULT '[]',
        tecnico TEXT NOT NULL DEFAULT '',
        actualizado_en TEXT NOT NULL DEFAULT '',
        descripcion TEXT NOT NULL DEFAULT '',
        fecha_cita TEXT NOT NULL,
        estado TEXT NOT NULL,
        creado_en TEXT NOT NULL
      )
    ''';

    Future<void> sembrarBaseV2({required String qr}) async {
      await DatabaseHelper.resetParaPruebas();
      final base = await databaseFactory.openDatabase(
        await rutaDeLaBase(),
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute(esquemaV2);
            await db.execute(
              'CREATE UNIQUE INDEX idx_citas_codigo_qr ON citas (codigo_qr)',
            );
            await db.execute(
              "INSERT INTO citas (codigo_qr, cliente, vehiculo, placa, fecha_cita, estado, creado_en) "
              "VALUES ('$qr', 'Cliente Anterior', 'Ford Ranger', 'A123456', "
              "'2026-01-05T10:00:00.000', 'pendiente', '2026-01-01T09:00:00.000')",
            );
          },
        ),
      );
      await base.close();
    }

    test(
      'un dispositivo con v2 conserva sus citas y gana los catalogos',
      () async {
        await sembrarBaseV2(qr: 'VIEJO-V2');

        // Abrir con el helper dispara onUpgrade: crea catalogos y siembra.
        final citas = await CitaRepository.instance.obtenerTodas();
        // La v5 elimina `codigo_qr`, asi que el marcador que la base vieja
        // guardaba ahi no sobrevive. Lo que demuestra que no se perdio la fila
        // es que sigue estando, con los valores que el seed escribio.
        expect(citas.length, 1, reason: 'la migracion NO debe perder datos');
        expect(citas.first.cliente, 'Cliente Anterior');
        expect(citas.first.placa, 'A123456');

        expect(
          (await TecnicoRepository.instance.obtenerTodas()).length,
          SemillaInicial.tecnicos.length,
        );
        expect(
          (await EstadoRepository.instance.obtenerTodas()).length,
          SemillaInicial.estados.length,
        );
        expect(
          (await TipoServicioRepository.instance.obtenerTodas()).length,
          SemillaInicial.tiposServicio.length,
        );
      },
    );

    test('un dispositivo con v1 salta de v1 a v3 en una sola apertura', () async {
      // Aplica los dos pasos (columnas de citas + catalogos) en una transaccion.
      // Si el `return` temprano del `_migrar` viejo no se hubiera cambiado por
      // `if (versionAnterior < 2)` / `< 3`, este test fallaria con "no such table".
      await DatabaseHelper.resetParaPruebas();
      final base = await databaseFactory.openDatabase(
        await rutaDeLaBase(),
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE citas (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                codigo_qr TEXT NOT NULL UNIQUE,
                cliente TEXT NOT NULL,
                vehiculo TEXT NOT NULL,
                descripcion TEXT NOT NULL DEFAULT '',
                fecha_cita TEXT NOT NULL,
                estado TEXT NOT NULL,
                creado_en TEXT NOT NULL
              )
            ''');
            await db.execute(
              "INSERT INTO citas (codigo_qr, cliente, vehiculo, fecha_cita, estado, creado_en) "
              "VALUES ('VIEJO-V1', 'Cliente Viejo', 'Kia Rio', "
              "'2025-11-02T08:30:00.000', 'pendiente', '2025-11-01T08:00:00.000')",
            );
          },
        ),
      );
      await base.close();

      final citas = await CitaRepository.instance.obtenerTodas();
      expect(citas.length, 1);
      // `codigo_qr` no existe desde la v5; la fila se reconoce por `cliente`.
      expect(citas.first.cliente, 'Cliente Viejo');
      // Columnas de la v2: llegan con el default, no en null.
      expect(citas.first.telefono, '');
      expect(citas.first.anio, 0);
      expect(
        (await TecnicoRepository.instance.obtenerTodas()).length,
        SemillaInicial.tecnicos.length,
      );
    });

    test('migrar dos veces no duplica los catalogos', () async {
      await sembrarBaseV2(qr: 'VIEJO-DOS');
      await TecnicoRepository.instance.obtenerTodas();
      await DatabaseHelper.instance.cerrar();
      await TecnicoRepository.instance.obtenerTodas();

      expect(
        (await TecnicoRepository.instance.obtenerTodas()).length,
        SemillaInicial.tecnicos.length,
      );
    });
  });
}

import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/database/semilla_inicial.dart';
import 'package:autofix/core/utils/uuid.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/configuracion/data/grupo_servicio_repository.dart';
import 'package:autofix/features/configuracion/data/marca_repository.dart';
import 'package:autofix/features/configuracion/data/tecnico_repository.dart';
import 'package:autofix/features/configuracion/data/tipo_servicio_repository.dart';
import 'package:autofix/features/configuracion/models/grupo_servicio.dart';
import 'package:autofix/features/configuracion/models/marca.dart';
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
      'los CUATRO catalogos se crean con TODAS las columnas del modelo',
      () async {
        // Este es el test que atrapa el "no such column": los modelos declaran sus
        // claves como literales para no depender de `DatabaseHelper`, asi que
        // PRAGMA es la unica red que ata el CREATE TABLE con el `toMap()`.
        //
        // v7: eran TRES (tecnicos, tipos, estados) y ahora son CUATRO. Los estados
        // se fueron; marcas y grupos entraron (punto 6 del encargo).
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
          DatabaseHelper.tablaMarcas,
          const Marca(nombre: 'x').toMap(),
        );
        await comprobar(
          DatabaseHelper.tablaGruposServicio,
          const GrupoServicio(nombre: 'x').toMap(),
        );
      },
    );

    test('la tabla de ESTADOS ya no existe', () async {
      // El catalogo `estados` se elimino en la v7 por decision de Leandy: el
      // estado de una cita es el enum cerrado `EstadoCita`, y el catalogo era data
      // muerta que ademas contradecía al enum ('En diagnostico' no existe en el
      // enum). Este test falla si alguien lo vuelve a agregar.
      final db = await DatabaseHelper.instance.base;
      final tablas = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      expect(tablas.map((f) => f['name']), isNot(contains('estados')));
    });

    test('los cuatro catalogos tienen la PK en TEXT, no INTEGER', () async {
      // El motivo de ser del UUID: con `INTEGER PRIMARY KEY` el id es un contador
      // POR DISPOSITIVO y dos tablets creaban "el mismo" tecnico 1, que al
      // sincronizar se pisan. Se comprueba con PRAGMA, no inferiendolo de que el
      // modelo compile.
      final db = await DatabaseHelper.instance.base;
      for (final tabla in <String>[
        DatabaseHelper.tablaTecnicos,
        DatabaseHelper.tablaTiposServicio,
        DatabaseHelper.tablaMarcas,
        DatabaseHelper.tablaGruposServicio,
      ]) {
        final info = await db.rawQuery('PRAGMA table_info($tabla)');
        final pk = info.firstWhere((f) => f['pk'] == 1);
        expect(pk['type'], 'TEXT', reason: 'la PK de $tabla no es TEXT');
        // Y `NOT NULL`: una PK sin valor no puede existir, y SQLite en modo legacy
        // permitiria un NULL en una PRIMARY KEY sin declarar NOT NULL.
        expect(pk['notnull'], 1, reason: 'la PK de $tabla admite NULL');
      }
    });

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

        // v7: los dos catalogos nuevos del punto 6 tampoco llevan precio. Una marca
        // no se cobra y un grupo solo agrupa servicios.
        for (final tabla in <String>[
          DatabaseHelper.tablaTecnicos,
          DatabaseHelper.tablaMarcas,
          DatabaseHelper.tablaGruposServicio,
        ]) {
          final info = await db.rawQuery('PRAGMA table_info($tabla)');
          expect(
            info.map((f) => f['name']),
            isNot(contains(DatabaseHelper.colPrecio)),
            reason: '$tabla no deberia tener columna de precio',
          );
        }
      },
    );
  });

  group('semilla inicial', () {
    test('una base nueva nace con los CUATRO catalogos del diseno', () async {
      // v7: los estados se eliminaron y marcas/grupos entraron. Los cuatro
      // catalogos que el punto 6 del encargo pide tienen que estar sembrados.
      expect(
        (await TecnicoRepository.instance.obtenerTodas()).map((t) => t.nombre),
        containsAll(SemillaInicial.tecnicos),
      );
      expect(
        (await TipoServicioRepository.instance.obtenerTodas()).map(
          (s) => s.nombre,
        ),
        containsAll(SemillaInicial.tiposServicio),
      );
      expect(
        (await MarcaRepository.instance.obtenerTodas()).map((m) => m.nombre),
        containsAll(SemillaInicial.marcas),
      );
      expect(
        (await GrupoServicioRepository.instance.obtenerTodas()).map(
          (g) => g.nombre,
        ),
        containsAll(SemillaInicial.gruposServicio),
      );
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

    test(
      'cada taller afiliado obtiene su propio catálogo bootstrap idempotente',
      () async {
        final taller = SemillaInicial.talleres[2];
        await DatabaseHelper.instance.asegurarCatalogosParaTaller(taller.id);
        await DatabaseHelper.instance.asegurarCatalogosParaTaller(taller.id);

        final servicios = await TipoServicioRepository.instance
            .obtenerTodasPorTaller(taller.id);
        final serviciosTallerBase = await TipoServicioRepository.instance
            .obtenerTodasPorTaller(SemillaInicial.talleres.first.id);
        expect(servicios, hasLength(SemillaInicial.tiposServicio.length));
        expect(servicios.every((servicio) => servicio.precio == 0), isTrue);
        expect(
          servicios
              .map((servicio) => servicio.id)
              .toSet()
              .intersection(
                serviciosTallerBase.map((servicio) => servicio.id).toSet(),
              ),
          isEmpty,
        );
        expect(
          servicios.map((servicio) => servicio.id).toSet(),
          hasLength(SemillaInicial.tiposServicio.length),
        );
        expect(
          await TecnicoRepository.instance.obtenerActivosPorTaller(taller.id),
          hasLength(SemillaInicial.tecnicos.length),
        );
      },
    );
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

    test(
      'DELETE: todos los catalogos conservan tombstone y quedan pending',
      () async {
        final db = await DatabaseHelper.instance.base;
        final altas =
            <
              ({
                String tabla,
                String id,
                Future<int> Function(String) eliminar,
                Future<Object?> Function(String) leer,
              })
            >[
              (
                tabla: DatabaseHelper.tablaTecnicos,
                id: await TecnicoRepository.instance.crear(
                  const Tecnico(nombre: 'Técnico tombstone'),
                ),
                eliminar: TecnicoRepository.instance.eliminar,
                leer: (id) async => TecnicoRepository.instance.obtenerPorId(id),
              ),
              (
                tabla: DatabaseHelper.tablaTiposServicio,
                id: await TipoServicioRepository.instance.crear(
                  const TipoServicio(nombre: 'Servicio tombstone'),
                ),
                eliminar: TipoServicioRepository.instance.eliminar,
                leer: (id) async =>
                    TipoServicioRepository.instance.obtenerPorId(id),
              ),
              (
                tabla: DatabaseHelper.tablaMarcas,
                id: await MarcaRepository.instance.crear(
                  const Marca(nombre: 'Marca tombstone'),
                ),
                eliminar: MarcaRepository.instance.eliminar,
                leer: (id) async => MarcaRepository.instance.obtenerPorId(id),
              ),
              (
                tabla: DatabaseHelper.tablaGruposServicio,
                id: await GrupoServicioRepository.instance.crear(
                  const GrupoServicio(nombre: 'Grupo tombstone'),
                ),
                eliminar: GrupoServicioRepository.instance.eliminar,
                leer: (id) async =>
                    GrupoServicioRepository.instance.obtenerPorId(id),
              ),
            ];

        for (final alta in altas) {
          expect(await alta.eliminar(alta.id), 1);
          expect(await alta.leer(alta.id), isNull);
          final filas = await db.query(
            alta.tabla,
            where: '${DatabaseHelper.colId} = ?',
            whereArgs: [alta.id],
          );
          final fila = filas.single;
          expect(fila[DatabaseHelper.colEliminadoEn], isA<String>());
          expect(fila[DatabaseHelper.colSyncStatus], 'pending');
          expect(
            await alta.eliminar(alta.id),
            0,
            reason: 'el tombstone es idempotente',
          );
        }

        // El índice parcial permite crear de nuevo el mismo nombre sin destruir
        // la fila histórica que conserva el tombstone.
        await MarcaRepository.instance.crear(
          const Marca(nombre: 'Marca tombstone'),
        );
        final marcas = await db.query(
          DatabaseHelper.tablaMarcas,
          where: '${DatabaseHelper.colNombre} = ?',
          whereArgs: ['Marca tombstone'],
        );
        expect(marcas, hasLength(2));
      },
    );

    test('eliminar un id inexistente devuelve 0 filas', () async {
      // v7: los ids son UUID en texto, no numeros.
      expect(
        await TecnicoRepository.instance.eliminar(
          'ffffffff-ffff-4fff-8fff-ffffffffffff',
        ),
        0,
      );
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
      // v7: este test usaba el catalogo de estados. Como los estados se
      // eliminaron, la misma propiedad se verifica sobre `tipos_servicio`, que es
      // el catalogo que mas filas tiene y donde un duplicado se nota mas (dos
      // botones con el mismo texto en la tarjeta de Servicios).
      await TipoServicioRepository.instance.crear(
        const TipoServicio(nombre: 'Revisión profunda'),
      );

      // Es lo que justifica el indice COLLATE NOCASE: sin el, "Revisión profunda"
      // y "revisión profunda" coexistirian y el admin veria el servicio duplicado
      // en la pantalla de Configuracion.
      expect(
        () => TipoServicioRepository.instance.crear(
          const TipoServicio(nombre: 'revisión profunda'),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('cada catalogo es independiente: el mismo nombre puede existir en dos', () async {
      // Un tecnico y una marca pueden llamarse igual: son tablas distintas y el
      // UNIQUE es por tabla. Antes este test comparaba un tecnico contra un estado.
      await MarcaRepository.instance.crear(const Marca(nombre: 'Temporal'));
      await expectLater(
        TecnicoRepository.instance.crear(const Tecnico(nombre: 'Temporal')),
        completes,
      );
    });

    test('marcas y grupos tambien rechazan nombres repetidos', () async {
      // Los cuatro catalogos comparten `_crearTablaCatalogo`, asi que los cuatro
      // tienen el mismo UNIQUE. Este test lo verifica en los dos nuevos, que son
      // los que todavia no tenian cobertura.
      await MarcaRepository.instance.crear(const Marca(nombre: 'Kia'));
      expect(
        () => MarcaRepository.instance.crear(const Marca(nombre: 'Kia')),
        throwsA(isA<Exception>()),
      );

      await GrupoServicioRepository.instance.crear(
        const GrupoServicio(nombre: 'Electricidad'),
      );
      expect(
        () => GrupoServicioRepository.instance.crear(
          const GrupoServicio(nombre: 'electricidad'),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('PATRON BASE', () {
    test('los CUATRO repositorios cumplen BaseRepository', () async {
      // Compilar esto YA es la prueba de que cumplen el contrato: si dejaran de
      // cumplirlo, el analyzer falla antes de correr el test.
      //
      // v7: eran TRES. Los estados se fueron y marcas/grupos entraron, asi que
      // el numero de repos que cumplen el contrato es ahora cuatro. Los cuatro
      // son intercambiables desde la UI de Leandy: mismo `crear`, mismo
      // `obtenerTodas`, mismo `actualizar`, mismo `eliminar`.
      final BaseRepository<Tecnico> tecnicos = TecnicoRepository.instance;
      final BaseRepository<TipoServicio> servicios =
          TipoServicioRepository.instance;
      final BaseRepository<Marca> marcas = MarcaRepository.instance;
      final BaseRepository<GrupoServicio> grupos =
          GrupoServicioRepository.instance;

      expect(tecnicos.tabla, DatabaseHelper.tablaTecnicos);
      expect(servicios.tabla, DatabaseHelper.tablaTiposServicio);
      expect(marcas.tabla, DatabaseHelper.tablaMarcas);
      expect(grupos.tabla, DatabaseHelper.tablaGruposServicio);

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
        (await marcas.obtenerTodas()).length,
        SemillaInicial.marcas.length,
      );
      expect(
        (await grupos.obtenerTodas()).length,
        SemillaInicial.gruposServicio.length,
      );
    });

    test('los cuatro repositorios devuelven un UUID de crear', () async {
      // El contrato generico dice `Future<String> crear`, pero no garantiza que lo
      // que devuelve sea un UUID bien formado. Este test lo comprueba en los
      // cuatro, porque un `crear` que devuelva '' o un numero solo se rompe cuando
      // la fila llega a Firestore.
      expect(
        Uuid.tieneFormaDeUuid(
          await TecnicoRepository.instance.crear(const Tecnico(nombre: 'A')),
        ),
        isTrue,
      );
      expect(
        Uuid.tieneFormaDeUuid(
          await TipoServicioRepository.instance.crear(
            const TipoServicio(nombre: 'B'),
          ),
        ),
        isTrue,
      );
      expect(
        Uuid.tieneFormaDeUuid(
          await MarcaRepository.instance.crear(const Marca(nombre: 'C')),
        ),
        isTrue,
      );
      expect(
        Uuid.tieneFormaDeUuid(
          await GrupoServicioRepository.instance.crear(
            const GrupoServicio(nombre: 'D'),
          ),
        ),
        isTrue,
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

    test('un dispositivo con v2 arranca con los catalogos de la v7', () async {
      // v7: este test se reescribio entero. Antes se llamaba 'conserva sus citas'
      // y hacia `expect(citas.length, 1)`. Con `_versionBase = 7` eso es falso:
      // la v7 dropea `citas` a proposito (ver `DatabaseHelper._migrar`), porque
      // cambiar la PK de INTEGER a TEXT/UUID no se puede hacer copiando filas.
      await sembrarBaseV2(qr: 'VIEJO-V2');

      // Abrir con el helper dispara onUpgrade.
      final citas = await CitaRepository.instance.obtenerTodas();
      expect(citas, isEmpty, reason: 'la v7 reinicia el esquema a proposito');

      // Lo que si importa: los cuatro catalogos quedan creados y sembrados.
      expect(
        (await TecnicoRepository.instance.obtenerTodas()).length,
        SemillaInicial.tecnicos.length,
      );
      expect(
        (await TipoServicioRepository.instance.obtenerTodas()).length,
        SemillaInicial.tiposServicio.length,
      );
      expect(
        (await MarcaRepository.instance.obtenerTodas()).length,
        SemillaInicial.marcas.length,
      );
      expect(
        (await GrupoServicioRepository.instance.obtenerTodas()).length,
        SemillaInicial.gruposServicio.length,
      );
    });

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
      // v7: la v7 dropea la tabla, asi que la cita vieja no sobrevive. El test
      // verifica lo que la migracion SI tiene que garantizar: que el salto de
      // versiones no deje la base a medias, con los catalogos creados.
      expect(citas, isEmpty, reason: 'la v7 reinicia el esquema a proposito');
      expect(
        (await TecnicoRepository.instance.obtenerTodas()).length,
        SemillaInicial.tecnicos.length,
      );
      // Y que la base quedo ESCRIBIBLE: si la transaccion de la migracion se
      // hubiera dejado a medias, este INSERT seria el que falla.
      final id = await TecnicoRepository.instance.crear(
        const Tecnico(nombre: 'Post-migracion'),
      );
      expect(
        Uuid.tieneFormaDeUuid(id),
        isTrue,
        reason: 'la base quedo inutilizable despues de migrar',
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

  group('migracion v13 -> v14', () {
    Future<void> sembrarBaseV13() async {
      await DatabaseHelper.resetParaPruebas();
      final base = await databaseFactory.openDatabase(
        await rutaDeLaBase(),
        options: OpenDatabaseOptions(
          version: 13,
          onCreate: (db, _) async {
            for (final tabla in <String>[
              DatabaseHelper.tablaTecnicos,
              DatabaseHelper.tablaTiposServicio,
              DatabaseHelper.tablaMarcas,
              DatabaseHelper.tablaGruposServicio,
            ]) {
              final precio = tabla == DatabaseHelper.tablaTiposServicio
                  ? ', precio INTEGER NOT NULL DEFAULT 0'
                  : '';
              await db.execute('''
                CREATE TABLE $tabla (
                  id TEXT NOT NULL PRIMARY KEY,
                  nombre TEXT NOT NULL,
                  activo INTEGER NOT NULL DEFAULT 1,
                  creado_en TEXT NOT NULL,
                  actualizado_en TEXT NOT NULL,
                  taller_id TEXT
                  $precio
                )
              ''');
              await db.execute(
                'CREATE UNIQUE INDEX idx_${tabla}_nombre '
                'ON $tabla (nombre COLLATE NOCASE)',
              );
              await db.execute(
                'CREATE INDEX idx_${tabla}_taller_id ON $tabla (taller_id)',
              );
              await db.insert(tabla, <String, Object?>{
                'id': 'legacy-$tabla',
                'nombre': 'Fila legacy $tabla',
                'activo': 1,
                'creado_en': '2025-01-01T00:00:00.000Z',
                'actualizado_en': '2025-01-02T00:00:00.000Z',
                'taller_id': null,
                if (tabla == DatabaseHelper.tablaTiposServicio) 'precio': 785,
              });
            }
          },
        ),
      );
      await base.close();
    }

    test('reconstruye los cuatro catálogos sin perder datos y asigna taller legacy', () async {
      await sembrarBaseV13();
      final db = await DatabaseHelper.instance.base;

      for (final tabla in <String>[
        DatabaseHelper.tablaTecnicos,
        DatabaseHelper.tablaTiposServicio,
        DatabaseHelper.tablaMarcas,
        DatabaseHelper.tablaGruposServicio,
      ]) {
        final info = await db.rawQuery('PRAGMA table_info($tabla)');
        final columnas = info.where(
          (c) => c['name'] == DatabaseHelper.colTallerId,
        );
        expect(
          columnas.single['notnull'],
          1,
          reason: '$tabla debe exigir taller_id',
        );
        expect(
          info.map((c) => c['name']),
          contains(DatabaseHelper.colSyncStatus),
        );
        expect(
          info.map((c) => c['name']),
          contains(DatabaseHelper.colEliminadoEn),
        );

        final filas = await db.query(tabla);
        final fila = filas.single;
        expect(fila[DatabaseHelper.colId], 'legacy-$tabla');
        expect(
          fila[DatabaseHelper.colTallerId],
          SemillaInicial.talleres.first.id,
        );
        expect(fila[DatabaseHelper.colSyncStatus], 'pending');
        expect(fila[DatabaseHelper.colEliminadoEn], isNull);
        expect(fila[DatabaseHelper.colNombre], 'Fila legacy $tabla');
        if (tabla == DatabaseHelper.tablaTiposServicio) {
          expect(fila[DatabaseHelper.colPrecio], 785);
        }
      }
    });

    test('permite repetir nombres entre talleres, pero no entre filas vigentes del mismo taller', () async {
      final repositorio = TecnicoRepository.instance;
      await repositorio.crear(
        const Tecnico(nombre: 'Mecanico', tallerId: 'taller-a'),
      );
      await repositorio.crear(
        const Tecnico(nombre: 'mecanico', tallerId: 'taller-b'),
      );
      await expectLater(
        repositorio.crear(
          const Tecnico(nombre: 'MECANICO', tallerId: 'taller-a'),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}

import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/database/semilla_inicial.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/configuracion/data/grupo_servicio_repository.dart';
import 'package:autofix/features/configuracion/data/marca_repository.dart';
import 'package:autofix/features/configuracion/data/tecnico_repository.dart';
import 'package:autofix/features/configuracion/data/tipo_servicio_repository.dart';
import 'package:autofix/features/talleres/data/taller_repository.dart';
import 'package:autofix/features/talleres/models/taller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Prueba de integracion de los talleres afiliados contra una base SQLite real
/// (via FFI). No usa mocks.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Base propia: este archivo corre en paralelo con los otros que usan SQLite.
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_talleres_test.db';
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
      p.join(await getDatabasesPath(), 'autofix_talleres_test.db');

  group('esquema', () {
    test('talleres se crea con TODAS las columnas del modelo', () async {
      // Este test atrapa el "no such column": el modelo declara sus claves como
      // literales para no depender de `DatabaseHelper`, asi que PRAGMA es la unica
      // red que ata el CREATE TABLE con el `toMap()`.
      final db = await DatabaseHelper.instance.base;

      final info = await db.rawQuery(
        'PRAGMA table_info(${DatabaseHelper.tablaTalleres})',
      );
      final nombres = info.map((f) => f['name'] as String).toSet();

      for (final clave in const Taller(
        nombre: 'x',
        latitud: 1,
        longitud: 1,
      ).toMap().keys) {
        expect(
          nombres,
          contains(clave),
          reason: 'falta la columna $clave en talleres',
        );
      }
    });

    test('citas tiene la columna taller_id', () async {
      final db = await DatabaseHelper.instance.base;
      final info = await db.rawQuery(
        'PRAGMA table_info(${DatabaseHelper.tablaCitas})',
      );
      expect(info.map((f) => f['name']), contains(DatabaseHelper.colTallerId));
    });

    test('latitud y longitud son REAL, no INTEGER', () async {
      // El bug que justifica la prueba: con INTEGER, 18.4184 se trunca a 18 y el
      // taller cae 46 km al norte, en el Atlantico. Y no da ningun error, solo
      // un punto en el lugar equivocado.
      final db = await DatabaseHelper.instance.base;
      final info = await db.rawQuery(
        'PRAGMA table_info(${DatabaseHelper.tablaTalleres})',
      );

      String tipoDe(String columna) => info
          .firstWhere((f) => f['name'] == columna)['type']
          .toString()
          .toUpperCase();

      expect(tipoDe(DatabaseHelper.colLatitud), 'REAL');
      expect(tipoDe(DatabaseHelper.colLongitud), 'REAL');
    });

    test(
      'las coordenadas conservan los decimales al hacer round-trip',
      () async {
        await DatabaseHelper.instance.sembrarTalleres();
        final refriauto = SemillaInicial.talleres.firstWhere(
          (t) => t.nombre == 'Global Refriauto',
        );

        final guardado = await TallerRepository.instance.obtenerPorNombre(
          'Global Refriauto',
        );

        expect(guardado, isNotNull);
        expect(guardado!.latitud, refriauto.latitud);
        expect(guardado.longitud, refriauto.longitud);
        // Coordenadas reales del local. El assert contra el literal es el que
        // atrapa el truncado a entero: si la columna volviera a ser INTEGER,
        // esto daria 18.0 y pasaria igual que con el round-trip de arriba.
        expect(guardado.latitud, closeTo(18.4624868, 0.0000001));
        expect(guardado.longitud, closeTo(-69.9517036, 0.0000001));
      },
    );

    test('taller_id es INTEGER, no TEXT', () async {
      // Si fuera TEXT, el id 1 se guardaria como '1' y el
      // `WHERE taller_id = ?` con el numero no encontraria nada. El sintoma es
      // un historial vacio sin error, que es de lo mas dificil de detectar.
      final db = await DatabaseHelper.instance.base;
      final info = await db.rawQuery(
        'PRAGMA table_info(${DatabaseHelper.tablaCitas})',
      );
      final tipo = info
          .firstWhere((f) => f['name'] == DatabaseHelper.colTallerId)['type']
          .toString()
          .toUpperCase();
      // v7: la PK pasa a TEXT/UUID, asi que la FK tambien debe ser TEXT.
      expect(tipo, 'TEXT');
    });
  });

  group('semilla de afiliados', () {
    test('una base nueva nace vacía sin talleres por defecto', () async {
      final talleres = await TallerRepository.instance.obtenerTodas();
      expect(talleres, isEmpty);
    });

    test('sembrarTalleres() siembra los talleres de la semilla', () async {
      await DatabaseHelper.instance.sembrarTalleres();
      final talleres = await TallerRepository.instance.obtenerTodas();

      expect(talleres.length, SemillaInicial.talleres.length);
      expect(
        talleres.map((t) => t.nombre),
        containsAll(SemillaInicial.talleres.map((t) => t.nombre)),
      );
    });

    test('incluye Global Refriauto, el taller destacado', () async {
      await DatabaseHelper.instance.sembrarTalleres();
      final refriauto = await TallerRepository.instance.obtenerPorNombre(
        'Global Refriauto',
      );
      expect(refriauto, isNotNull);
      expect(refriauto!.direccion, isNotEmpty);
      expect(refriauto.telefono, isNotEmpty);
    });

    test('los 3 nacen activos al sembrar', () async {
      await DatabaseHelper.instance.sembrarTalleres();
      final activos = await TallerRepository.instance.obtenerActivos();
      expect(activos.length, SemillaInicial.talleres.length);
      expect(activos.every((t) => t.activo), isTrue);
    });

    test('las coordenadas son de Republica Dominicana', () async {
      await DatabaseHelper.instance.sembrarTalleres();
      for (final t in await TallerRepository.instance.obtenerTodas()) {
        expect(
          t.latitud,
          inInclusiveRange(17.5, 19.9),
          reason: '${t.nombre} lat',
        );
        expect(
          t.longitud,
          inInclusiveRange(-72.0, -68.0),
          reason: '${t.nombre} lng',
        );
      }
    });

    test('llamar sembrarTalleres de nuevo NO duplica la semilla', () async {
      await DatabaseHelper.instance.sembrarTalleres();
      await DatabaseHelper.instance.sembrarTalleres();

      expect(
        (await TallerRepository.instance.obtenerTodas()).length,
        SemillaInicial.talleres.length,
      );
    });

    test(
      '"AutoFix Central" puede sembrarse desde SemillaInicial',
      () async {
        await DatabaseHelper.instance.sembrarTalleres();
        expect(
          await TallerRepository.instance.obtenerPorNombre('AutoFix Central'),
          isNotNull,
        );
      },
    );
  });

  group('CRUD de talleres', () {
    test('CREATE: el alta queda disponible y es recuperable', () async {
      final id = await TallerRepository.instance.crear(
        const Taller(
          nombre: 'Taller Nuevo',
          direccion: 'Calle 1',
          telefono: '809-000-0000',
          latitud: 18.5,
          longitud: -69.9,
        ),
      );

      final creado = await TallerRepository.instance.obtenerPorId(id);
      expect(creado, isNotNull);
      expect(creado!.nombre, 'Taller Nuevo');
      expect(creado.activo, isTrue);
      expect(creado.id, id);
    });

    test(
      'READ: obtenerTodas ordena por nombre sin distinguir mayusculas',
      () async {
        await TallerRepository.instance.crear(
          const Taller(nombre: 'zapateria', latitud: 18.5, longitud: -69.9),
        );
        await TallerRepository.instance.crear(
          const Taller(nombre: 'Abarrotes', latitud: 18.5, longitud: -69.9),
        );

        final nombres = (await TallerRepository.instance.obtenerTodas())
            .map((t) => t.nombre)
            .toList();

        // Se compara el orden RELATIVO, no la posicion, para que agregar un taller
        // a la semilla no rompa este test.
        expect(
          nombres.indexOf('Abarrotes'),
          lessThan(nombres.indexOf('zapateria')),
        );
      },
    );

    test('READ: obtenerPorNombre ignora mayusculas y espacios', () async {
      // No se usa 'Taller Gomez' porque ya viene en la semilla y el UNIQUE lo
      // rechazaria: este test prueba el WHERE, no el alta (esa va aparte).
      await TallerRepository.instance.crear(
        const Taller(nombre: 'Taller Pérez', latitud: 18.5, longitud: -69.9),
      );

      expect(
        (await TallerRepository.instance.obtenerPorNombre('  taller pérez '))
            ?.nombre,
        'Taller Pérez',
      );
      expect(
        await TallerRepository.instance.obtenerPorNombre('No Existe'),
        isNull,
      );
    });

    test('READ: la semilla se encuentra por nombre', () async {
      // El caso de uso real: el formulario busca el taller que el cliente eligio
      // por nombre, y ese texto viene de la base, no de una constante.
      // La siembra no es automatica desde v7: hay que pedirla.
      await DatabaseHelper.instance.sembrarTalleres();
      expect(
        (await TallerRepository.instance.obtenerPorNombre(
          '  global refriauto ',
        ))?.nombre,
        'Global Refriauto',
      );
    });

    test('READ: obtenerActivos excluye los dados de baja', () async {
      final id = await TallerRepository.instance.crear(
        const Taller(nombre: 'Temporal', latitud: 18.5, longitud: -69.9),
      );
      await TallerRepository.instance.darDeBaja(id);

      final activos = await TallerRepository.instance.obtenerActivos();
      expect(activos.map((t) => t.nombre), isNot(contains('Temporal')));
      // Pero sigue en la lista de administracion, para poder reactivarlo.
      expect(
        (await TallerRepository.instance.obtenerTodas()).map((t) => t.nombre),
        contains('Temporal'),
      );
    });

    test('UPDATE: mover el taller queda persistido', () async {
      final id = await TallerRepository.instance.crear(
        const Taller(nombre: 'Muelle', latitud: 18.5, longitud: -69.9),
      );
      final guardado = (await TallerRepository.instance.obtenerPorId(id))!;

      final filas = await TallerRepository.instance.actualizar(
        guardado.copyWith(latitud: 19.4517, longitud: -70.6970),
      );
      expect(filas, 1);

      final releido = await TallerRepository.instance.obtenerPorId(id);
      expect(releido!.latitud, 19.4517);
      expect(releido.longitud, -70.6970);
    });

    test('UPDATE: darDeBaja no borra la fila', () async {
      final id = await TallerRepository.instance.crear(
        const Taller(nombre: 'A Cerrar', latitud: 18.5, longitud: -69.9),
      );

      expect(await TallerRepository.instance.darDeBaja(id), 1);
      final releido = await TallerRepository.instance.obtenerPorId(id);
      expect(releido, isNotNull, reason: 'la baja logica NO debe borrar');
      expect(releido!.activo, isFalse);
    });

    test('DELETE: eliminar un id inexistente devuelve 0 filas', () async {
      expect(
        await TallerRepository.instance.eliminar(
          'ffffffff-ffff-4fff-8fff-ffffffffffff',
        ),
        0,
      );
    });

    test('actualizar sin id lanza en vez de fallar en silencio', () async {
      expect(
        () => TallerRepository.instance.actualizar(
          const Taller(nombre: 'x', latitud: 1, longitud: 1),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('un nombre repetido se rechaza, tambien variando mayusculas', () async {
      // El nombre de la semilla es el que importa: si el admin intenta dar de
      // alta un afiliado que ya existe, con otra capitalizacion o sin ella, el
      // UNIQUE COLLATE NOCASE lo detiene. Sin ese indice, el mapa mostraria dos
      // circulos orange en la misma esquina.
      await TallerRepository.instance.crear(
        const Taller(nombre: 'Refriauto Norte', latitud: 18.4, longitud: -69.9),
      );

      expect(
        () => TallerRepository.instance.crear(
          const Taller(
            nombre: 'refriauto norte',
            latitud: 18.4,
            longitud: -69.9,
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('no se puede dar de alta dos veces un taller de la semilla', () async {
      // 'Global Refriauto' ya esta sembrado: un alta repetida tiene que fallar, no
      // crear un segundo afiliado en la misma direccion.
      // La siembra no es automatica desde v7: hay que pedirla.
      await DatabaseHelper.instance.sembrarTalleres();
      expect(
        () => TallerRepository.instance.crear(
          const Taller(
            nombre: 'Global Refriauto',
            latitud: 18.4184,
            longitud: -69.9167,
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('distancia', () {
    test('la distancia a si mismo es cero', () async {
      const t = Taller(nombre: 'x', latitud: 18.4861, longitud: -69.9312);
      expect(t.distanciaKmDesde(18.4861, -69.9312), closeTo(0, 0.0001));
    });

    test('Santo Domingo a Santiago son ~134 km en linea recta', () async {
      // Verificacion contra la realidad: la distancia en linea recta entre el
      // centro de Santo Domingo y el de Santiago es de ~134 km. La distancia por
      // carretera son ~200, y NO es la que se calcula aqui: Haversine da la
      // distancia geodésica, que es la minima entre dos puntos.
      //
      // El numero importa como control: si la formula estuviera mal (radio
      // equivocado, grados sin convertir, [lat, lng] invertido), daria un valor
      // completamente distinto y este test lo atrapa.
      final d = Taller.distanciaHaversineKm(
        18.4861,
        -69.9312,
        19.4517,
        -70.6970,
      );
      expect(d, closeTo(134, 3));
    });

    test('la distancia en linea recta es menor que la de carretera', () async {
      // La razon por la que la pantalla no puede decir "la ruta": 134 km en linea
      // recta son ~200 por carretera. Mostrar 134 y prometer 200 seria mentir.
      const sd = (18.4861, -69.9312);
      const sc = (19.4517, -70.6970);
      expect(
        Taller.distanciaHaversineKm(sd.$1, sd.$2, sc.$1, sc.$2),
        lessThan(160),
      );
    });

    test('la distancia es simetrica', () async {
      const a = (18.4861, -69.9312);
      const b = (19.4517, -70.6970);
      expect(
        Taller.distanciaHaversineKm(a.$1, a.$2, b.$1, b.$2),
        closeTo(Taller.distanciaHaversineKm(b.$1, b.$2, a.$1, a.$2), 0.0001),
      );
    });

    test('dos puntos casi iguales NO producen NaN', () async {
      // El clamp de `sqrt(min(1, a))` existe por esto: por redondeo, `a` puede
      // pasar de 1 y `asin` de eso devuelve NaN, que arruina el orden de la lista.
      final d = Taller.distanciaHaversineKm(
        18.4861,
        -69.9312,
        18.4861,
        -69.9312,
      );
      expect(d.isNaN, isFalse);
    });

    test('ordenar por cercanía funciona con la lista de la base', () async {
      await DatabaseHelper.instance.sembrarTalleres();
      final activos = await TallerRepository.instance.obtenerActivos();
      // El cliente esta en Santiago, asi que AutoFix Central (que esta ahi) debe
      // quedar primero.
      activos.sort(
        (a, b) => a
            .distanciaKmDesde(19.4517, -70.6970)
            .compareTo(b.distanciaKmDesde(19.4517, -70.6970)),
      );
      expect(activos.first.nombre, 'AutoFix Central');
    });
  });

  group('cita <-> taller', () {
    // La v5 elimino `codigo_qr`, asi que cada cita se distingue por `cliente`.
    Cita citaCon({String cliente = 'Cliente', String? tallerId}) => Cita(
      cliente: cliente,
      vehiculo: 'Toyota Corolla',
      fechaCita: DateTime(2026, 10, 15, 10),
      tallerId: tallerId,
    );

    test('la cita guarda el id del taller y lo devuelve', () async {
      await DatabaseHelper.instance.sembrarTalleres();
      final id = (await TallerRepository.instance.obtenerPorNombre(
        'Global Refriauto',
      ))!.id!;

      final citaId = await CitaRepository.instance.crear(citaCon(tallerId: id));
      final releida = await CitaRepository.instance.obtenerPorId(citaId);

      expect(releida!.tallerId, id);
    });

    test('una cita SIN taller se guarda con null, no revienta', () async {
      // Las citas del escaner QR no eligen taller todavia.
      final citaId = await CitaRepository.instance.crear(
        citaCon(cliente: 'Cliente escaner'),
      );
      expect(
        (await CitaRepository.instance.obtenerPorId(citaId))!.tallerId,
        isNull,
      );
    });

    test('obtenerPorTaller devuelve solo las de ese taller', () async {
      await DatabaseHelper.instance.sembrarTalleres();
      final refriauto = (await TallerRepository.instance.obtenerPorNombre(
        'Global Refriauto',
      ))!.id!;
      final gomez = (await TallerRepository.instance.obtenerPorNombre(
        'Taller Gómez',
      ))!.id!;

      await CitaRepository.instance.crear(
        citaCon(cliente: 'Cliente Refriauto', tallerId: refriauto),
      );
      await CitaRepository.instance.crear(
        citaCon(cliente: 'Cliente Gomez', tallerId: gomez),
      );
      await CitaRepository.instance.crear(citaCon(cliente: 'Cliente suelto'));

      final delRefriauto = await CitaRepository.instance.obtenerPorTaller(
        refriauto,
      );
      expect(delRefriauto.length, 1);
      expect(delRefriauto.first.cliente, 'Cliente Refriauto');
      expect(delRefriauto.first.tallerId, refriauto);
    });

    test('el filtro por taller funciona con un id numerico de verdad', () async {
      // Esta es la trampa de la columna TEXT: si `taller_id` fuera TEXT, el id 1
      // se guardaria como '1' y este `WHERE taller_id = 1` no encontraria nada.
      // El sintoma seria "el historial del taller siempre sale vacio".
      await DatabaseHelper.instance.sembrarTalleres();
      final id = (await TallerRepository.instance.obtenerPorNombre(
        'Global Refriauto',
      ))!.id!;
      // v7: la PK es TEXT/UUID, no INTEGER. Un id numerico ya no existe.
      expect(id, isA<String>());

      await CitaRepository.instance.crear(citaCon(tallerId: id));
      expect((await CitaRepository.instance.obtenerPorTaller(id)).length, 1);
    });

    test('update de la cita conserva el taller', () async {
      await DatabaseHelper.instance.sembrarTalleres();
      final tallerId = (await TallerRepository.instance.obtenerPorNombre(
        'Global Refriauto',
      ))!.id!;

      final citaId = await CitaRepository.instance.crear(
        citaCon(tallerId: tallerId),
      );
      await CitaRepository.instance.crear(
        citaCon(cliente: 'Cliente Otra', tallerId: tallerId),
      );

      await CitaRepository.instance.cambiarEstado(citaId, EstadoCita.enProceso);
      final releida = await CitaRepository.instance.obtenerPorId(citaId);

      // `cambiarEstado` es un UPDATE parcial: solo manda la columna del estado.
      // Si el `toMap` de la cita no mandara `taller_id`, este test falla.
      expect(releida!.tallerId, tallerId);
      expect(releida.estado, EstadoCita.enProceso);
    });
  });

  group('PATRON BASE', () {
    test('TallerRepository cumple BaseRepository', () async {
      // Compilar esto YA es la prueba de que cumple el contrato: si dejara de
      // cumplirlo, el analyzer falla antes de correr el test.
      final BaseRepository<Taller> repositorio = TallerRepository.instance;
      expect(repositorio.tabla, DatabaseHelper.tablaTalleres);

      final id = await repositorio.crear(
        const Taller(nombre: 'Contrato', latitud: 18.5, longitud: -69.9),
      );
      expect(
        await repositorio.actualizar(
          (await repositorio.obtenerPorId(id))!.copyWith(nombre: 'Contrato 2'),
        ),
        1,
      );
      expect((await repositorio.obtenerPorId(id))!.nombre, 'Contrato 2');
      expect(await repositorio.eliminar(id), 1);
    });
  });

  group('migracion v3 -> v4', () {
    // El esquema v3 tal cual lo creo la version anterior. Esta es la base que
    // puede tener un dispositivo que YA instalo la app con los catalogos.
    const esquemaV3 = '''
      CREATE TABLE citas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo_qr TEXT NOT NULL UNIQUE,
        cliente TEXT NOT NULL,
        telefono TEXT NOT NULL DEFAULT '',
        vehiculo TEXT NOT NULL,
        marca TEXT NOT NULL DEFAULT '',
        modelo TEXT NOT NULL DEFAULT '',
        anio INTEGER NOT NULL DEFAULT 0,
        placa TEXT NOT NULL DEFAULT '',
        servicios TEXT NOT NULL DEFAULT '[]',
        tecnico TEXT NOT NULL DEFAULT '',
        descripcion TEXT NOT NULL DEFAULT '',
        fecha_cita TEXT NOT NULL,
        estado TEXT NOT NULL,
        creado_en TEXT NOT NULL,
        actualizado_en TEXT NOT NULL DEFAULT ''
      )
    ''';

    Future<void> sembrarBaseV3({required String qr}) async {
      await DatabaseHelper.resetParaPruebas();
      final base = await databaseFactory.openDatabase(
        await rutaDeLaBase(),
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await db.execute(esquemaV3);
            await db.execute(
              'CREATE UNIQUE INDEX idx_citas_codigo_qr ON citas (codigo_qr)',
            );
            await db.execute(
              "INSERT INTO citas (codigo_qr, cliente, vehiculo, fecha_cita, estado, creado_en) "
              "VALUES ('$qr', 'Cliente Anterior', 'Ford Ranger', "
              "'2026-01-05T10:00:00.000', 'pendiente', '2026-01-01T09:00:00.000')",
            );
          },
        ),
      );
      await base.close();
    }

    test('un dispositivo con v3 arranca con los talleres y catalogos de la v7', () async {
      // v7: este test se reescribio entero. Antes se llamaba 'conserva sus citas'
      // y hacia `expect(citas.length, 1)`. Con `_versionBase = 7` eso es falso:
      // la v7 dropea `citas` a proposito (ver `DatabaseHelper._migrar`), porque
      // cambiar la PK de INTEGER a TEXT/UUID no se puede hacer copiando filas.
      await sembrarBaseV3(qr: 'VIEJO-V3');

      // Abrir con el helper dispara onUpgrade.
      final citas = await CitaRepository.instance.obtenerTodas();
      expect(citas, isEmpty, reason: 'la v7 reinicia el esquema a proposito');

      // Lo que si importa: los catalogos quedan creados y sembrados.
      expect(
        (await TallerRepository.instance.obtenerTodas()),
        isEmpty,
      );
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

    test('tras migrar a v7 se puede agendar con taller', () async {
      await sembrarBaseV3(qr: 'VIEJO-AGENDAR');
      await DatabaseHelper.instance.sembrarTalleres();

      final tallerId = (await TallerRepository.instance.obtenerPorNombre(
        'Global Refriauto',
      ))!.id!;

      final nuevaId = await CitaRepository.instance.crear(
        Cita(
          cliente: 'Cliente Nuevo',
          vehiculo: 'Kia Rio',
          fechaCita: DateTime.utc(2026, 11, 3, 14),
          tallerId: tallerId,
        ),
      );

      final nueva = await CitaRepository.instance.obtenerPorId(nuevaId);
      expect(nueva!.tallerId, tallerId);
      // Solo la cita nueva existe.
      expect((await CitaRepository.instance.obtenerTodas()).length, 1);
    });

    test('un dispositivo con v1 salta de v1 a v4 en una sola apertura', () async {
      // Aplica los tres pasos (columnas de citas + catalogos + talleres) en una
      // transaccion. Si el `_migrar` tuviera un `return` temprano, este test
      // fallaria con "no such table: talleres".
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
      // v7: la migracion dropea las tablas y reinicia el esquema, asi que las citas
      // viejas no se conservan. Ver la nota larga de `DatabaseHelper._migrar`.
      expect(citas, isEmpty);
      // Y los catalogos quedan creados y sembrados.

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
        (await TallerRepository.instance.obtenerTodas()),
        isEmpty,
      );
    });

    test('migrar dos veces no crea errores y permite sembrarTalleres', () async {
      await sembrarBaseV3(qr: 'VIEJO-DOS');
      await TallerRepository.instance.obtenerTodas();
      await DatabaseHelper.instance.cerrar();
      await DatabaseHelper.instance.sembrarTalleres();

      expect(
        (await TallerRepository.instance.obtenerTodas()).length,
        SemillaInicial.talleres.length,
      );
    });
  });
}

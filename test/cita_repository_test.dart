import 'package:autofix/core/data/base_repository.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/utils/borrado_logico.dart';
import 'package:autofix/core/utils/uuid.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/citas/models/codigo_de_cita.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Prueba de integracion contra una base SQLite real (via FFI).
/// No usa mocks: crea la tabla, inserta, lee, actualiza y elimina de verdad.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Base propia: este archivo corre en paralelo con los otros que usan SQLite.
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_citas_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    // CRITICO: se borra el .db antes de cada prueba. `sqflite_common_ffi` lo
    // guarda en `.dart_tool/`, o sea EN DISCO, no en memoria. Sin este reset,
    // `onCreate` no se vuelve a correr y los tests dan verde probando un
    // esquema viejo. Asi cada test arranca de una base recien creada de verdad.
    await DatabaseHelper.resetParaPruebas();
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
  });

  Cita nueva({String cliente = 'Ana Torres'}) => Cita(
    cliente: cliente,
    vehiculo: 'Toyota Hilux',
    descripcion: 'Cambio de aceite',
    fechaCita: DateTime(2026, 10, 1, 9, 30),
  );

  test('CREATE: el id generado es un UUID y la fila es recuperable', () async {
    final id = await CitaRepository.instance.crear(nueva());

    // v7: el id NO es un numero. Es un UUID v4 de 36 caracteres, y se comprueba
    // con `Uuid.tieneFormaDeUuid` y no con una regexp escrita aca: asi el test usa
    // la mismadefinicion de "UUID bien formado" que usa la nube, y si un dia la
    // regla cambia el test cambia solo.
    expect(Uuid.tieneFormaDeUuid(id), isTrue, reason: 'no es un UUID: $id');

    final creada = await CitaRepository.instance.obtenerPorId(id);
    expect(creada, isNotNull);
    expect(creada!.cliente, 'Ana Torres');
  });

  test('CREATE: dos citas seguidas reciben UUID DISTINTOS', () async {
    // El motivo de ser del UUID: con el autoincremento de la v6 el id era un
    // contador POR DISPOSITIVO, asi que "el celular A" y "el celular B" creaban
    // la cita 1 y al sincronizar una pisaba a la otra.
    final a = await CitaRepository.instance.crear(nueva());
    final b = await CitaRepository.instance.crear(nueva(cliente: 'Luis Paz'));
    expect(a, isNot(b));
  });

  test('CREATE: la cita nace con codigo PENDIENTE, no con un numero inventado', () async {
    // El numero definitivo lo da la nube (contador transaccional de Firestore).
    // Fabricar uno en el cliente es justamente lo que hace que dos tablets.agenden
    // el mismo 'CITA-0004'.
    final id = await CitaRepository.instance.crear(nueva());
    final creada = await CitaRepository.instance.obtenerPorId(id);

    expect(creada!.codigoVisible, codigoCitaTemporal);
    expect(creada.codigoVisible, 'PENDIENTE');
    expect(creada.tieneCodigoDefinitivo, isFalse);
  });

  test('READ: obtenerTodas devuelve lo que se guardo', () async {
    await CitaRepository.instance.crear(nueva());
    await CitaRepository.instance.crear(nueva(cliente: 'Luis Paz'));

    final todas = await CitaRepository.instance.obtenerTodas();
    expect(todas.length, 2);
    expect(
      todas.map((c) => c.cliente),
      containsAll(['Ana Torres', 'Luis Paz']),
    );
  });

  test('UPDATE: los cambios quedan persistidos', () async {
    final id = await CitaRepository.instance.crear(nueva());
    final editada = (await CitaRepository.instance.obtenerPorId(id))!
        .copyWith(estado: EstadoCita.completado, cliente: 'Ana T. Updated');

    final filasAfectadas = await CitaRepository.instance.actualizar(editada);
    expect(filasAfectadas, 1);

    final releida = await CitaRepository.instance.obtenerPorId(id);
    expect(releida!.estado, EstadoCita.completado);
    expect(releida.cliente, 'Ana T. Updated');
  });

  test('UPDATE parcial: cambiarEstado no pisa el resto de la fila', () async {
    final id = await CitaRepository.instance.crear(
      nueva().copyWith(tecnico: 'Tecnico 2', placa: 'A123456'),
    );

    await CitaRepository.instance.cambiarEstado(id, EstadoCita.enProceso);

    final releida = await CitaRepository.instance.obtenerPorId(id);
    expect(releida!.estado, EstadoCita.enProceso);
    expect(releida.tecnico, 'Tecnico 2');
    expect(releida.placa, 'A123456');
  });

  test('un error de push queda visible y sigue siendo reintentable', () async {
    final id = await CitaRepository.instance.crear(nueva());

    expect(await CitaRepository.instance.marcarErrorSync(id), 1);
    var releida = await CitaRepository.instance.obtenerPorId(id);
    expect(releida!.syncStatus, 'error');
    expect(
      (await CitaRepository.instance.obtenerFallidasDeSync()).map((c) => c.id),
      contains(id),
    );
    expect(await CitaRepository.instance.obtenerPendientesDeSync(), isEmpty);

    expect(await CitaRepository.instance.marcarPendienteSync(id), 1);
    releida = await CitaRepository.instance.obtenerPorId(id);
    expect(releida!.syncStatus, 'pending');
  });

  test(
    'Aceptar y rechazar quedan en SQLite pendientes de sincronización',
    () async {
      for (final estado in [EstadoCita.aceptada, EstadoCita.rechazada]) {
        final id = await CitaRepository.instance.crear(
          nueva().copyWith(syncStatus: 'synced'),
        );

        expect(await CitaRepository.instance.cambiarEstado(id, estado), 1);
        final releida = await CitaRepository.instance.obtenerPorId(id);

        expect(releida!.estado, estado);
        expect(releida.syncStatus, 'pending');
      }
    },
  );

  test('rechazar con motivo guarda el motivo en la base', () async {
    final id = await CitaRepository.instance.crear(
      nueva().copyWith(syncStatus: 'synced'),
    );

    await CitaRepository.instance.cambiarEstado(
      id,
      EstadoCita.rechazada,
      motivoRechazo: 'Cliente no se presentó',
    );
    final releida = await CitaRepository.instance.obtenerPorId(id);

    expect(releida!.estado, EstadoCita.rechazada);
    expect(releida.motivoRechazo, 'Cliente no se presentó');
  });

  // -------------------------------------------------------------------
  // BORRADO LOGICO (v7)
  //
  // Antes esto era un `test('DELETE: la cita deja de estar en la base')` que
  // comprobaba `obtenerPorId(id) == null`. Ese test era CORRECTO para la v6 y es
  // incorrecto para la v7, y no por poco: el `DELETE` fisico hacia que la cita
  // reapareciera en cuanto otro dispositivo la rebia de la nube, porque para la
  // nube nunca habia existido el borrado. Los tests de abajo fijan el
  // comportamiento nuevo.
  // -------------------------------------------------------------------

  group('borrado logico', () {
    test('eliminar MARCA la cita: la fila sigue en la base', () async {
      final id = await CitaRepository.instance.crear(nueva());

      expect(await CitaRepository.instance.eliminar(id), 1);

      // `obtenerPorId` es la excepcion documentada: trae la fila aunque este
      // borrada, porque es la que usa la sincronizacion y la Papelera.
      final borrada = await CitaRepository.instance.obtenerPorId(id);
      expect(
        borrada,
        isNotNull,
        reason: 'el DELETE fisico es justo lo que se prohibio',
      );
      expect(borrada!.estaBorrada, isTrue);
      expect(borrada.trazabilidad.eliminadoEn, isNotNull);
    });

    test('una cita borrada desaparece de obtenerTodas', () async {
      final id = await CitaRepository.instance.crear(nueva());
      final otraId = await CitaRepository.instance.crear(
        nueva(cliente: 'Luis Paz'),
      );

      await CitaRepository.instance.eliminar(id);

      final todas = await CitaRepository.instance.obtenerTodas();
      expect(todas.length, 1);
      expect(todas.first.id, otraId);
    });

    test('borrar se registra con quien lo hizo', () async {
      final id = await CitaRepository.instance.crear(nueva());

      await CitaRepository.instance.borrar(
        id,
        eliminadaPor: 'tablet-de-leandy',
      );

      final borrada = await CitaRepository.instance.obtenerPorId(id);
      expect(borrada!.trazabilidad.eliminadoPor, 'tablet-de-leandy');
    });

    test('borrar dos veces la misma cita no vuelve a sellar el borrado', () async {
      final id = await CitaRepository.instance.crear(nueva());
      expect(await CitaRepository.instance.eliminar(id), 1);

      // El segundo devuelve 0: el WHERE filtra por `eliminado_en IS NULL`. Con
      // esto el repositorio puede distinguir "no existe" de "ya estaba borrada"
      // sin tener que leer la fila antes.
      expect(await CitaRepository.instance.eliminar(id), 0);
    });

    test('restaurar devuelve la cita a las consultas normales', () async {
      final id = await CitaRepository.instance.crear(nueva());
      await CitaRepository.instance.eliminar(id);

      expect(await CitaRepository.instance.restaurar(id), 1);

      final restaurada = await CitaRepository.instance.obtenerPorId(id);
      expect(restaurada!.estaBorrada, isFalse);
      expect(restaurada.trazabilidad.eliminadoEn, isNull);
      // La huella de que estuvo fuera NO se pierde: eso es lo que distingue una
      // restauracion de una cita que nunca se borro.
      expect(restaurada.trazabilidad.restauradoEn, isNotNull);
      expect((await CitaRepository.instance.obtenerTodas()).length, 1);
    });

    test(
      'restaurar una cita viva devuelve 0 en vez de inventar una fecha',
      () async {
        final id = await CitaRepository.instance.crear(nueva());
        expect(await CitaRepository.instance.restaurar(id), 0);
        expect(
          (await CitaRepository.instance.obtenerPorId(id))!
              .trazabilidad
              .restauradoEn,
          isNull,
        );
      },
    );

    test('la Papelera lista las borradas y las normales no', () async {
      final borradaId = await CitaRepository.instance.crear(nueva());
      await CitaRepository.instance.crear(nueva(cliente: 'Luis Paz'));
      await CitaRepository.instance.eliminar(borradaId);

      final papelera = await CitaRepository.instance.obtenerBorradas();
      expect(papelera.length, 1);
      expect(papelera.first.id, borradaId);
    });

    test('asignarCodigoVisible sella el numero SIN pisar el resto', () async {
      // El caso que justifica el metodo: la nube confirma 'CITA-0004' y hay que
      // escribir solo ese campo. Si se hiciera con `actualizar` + `toMap()`, el
      // mapa traeria `creado_en` y `actualizado_en` del objeto de la UI, que no
      // son los de la base, y se perderian.
      final id = await CitaRepository.instance.crear(
        nueva().copyWith(tecnico: 'Tecnico 2', placa: 'A123456'),
      );
      final original = (await CitaRepository.instance.obtenerPorId(id))!;

      expect(
        await CitaRepository.instance.asignarCodigoVisible(id, 'CITA-0004'),
        1,
      );

      final conCodigo = (await CitaRepository.instance.obtenerPorId(id))!;
      expect(conCodigo.codigoVisible, 'CITA-0004');
      expect(conCodigo.tieneCodigoDefinitivo, isTrue);
      // Lo demas intacto:
      expect(conCodigo.tecnico, 'Tecnico 2');
      expect(conCodigo.placa, 'A123456');
      expect(conCodigo.creadoEn, original.creadoEn);
    });
  });

  test(
    'el esquema recien creado tiene TODAS las columnas que usa el modelo',
    () async {
      // Este test es el que atrapo el bug de `vehiculo`: si el CREATE TABLE se
      // desincroniza del modelo, el INSERT revienta con "no such column". Ahora es
      // todavia mas importante: el modelo declara las claves como literales para no
      // depender de `DatabaseHelper`, y esta es la unica red que los une.
      final db = await DatabaseHelper.instance.base;
      final columnas = await db.rawQuery(
        'PRAGMA table_info(${DatabaseHelper.tablaCitas})',
      );
      final nombres = columnas.map((f) => f['name'] as String).toSet();

      for (final c in nueva().toMap().keys) {
        expect(
          nombres,
          contains(c),
          reason: 'falta la columna $c en la tabla citas',
        );
      }
    },
  );

  test('PATRON BASE: el repositorio se puede usar como BaseRepository<Cita>', () async {
    // Compilar esto YA es la prueba: si `CitaRepository` dejara de cumplir el
    // contrato, el analyzer falla antes de correr el test. Lo que se verifica en
    // runtime es que la API generica funciona contra la base real.
    final BaseRepository<Cita> repo = CitaRepository.instance;

    final id = await repo.crear(nueva());
    expect(Uuid.tieneFormaDeUuid(id), isTrue);
    expect(repo.tabla, DatabaseHelper.tablaCitas);

    final guardada = await repo.obtenerPorId(id);
    expect(guardada!.cliente, 'Ana Torres');
    expect((await repo.obtenerTodas()).length, 1);

    expect(await repo.actualizar(guardada.copyWith(cliente: 'Ana T.')), 1);
    expect((await repo.obtenerPorId(id))!.cliente, 'Ana T.');

    // v7: por el contrato, `eliminar` es el BORRADO LOGICO. Lo que se comprueba
    // aca es que el metodo generico despacha bien, no que la fila desaparezca.
    expect(await repo.eliminar(id), 1);
    expect((await repo.obtenerTodas()).length, 0);
  });

  test('actualizar sin id lanza en vez de fallar en silencio', () async {
    expect(
      () => CitaRepository.instance.actualizar(nueva()),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('eliminar un id inexistente devuelve 0 filas', () async {
    // Un UUID con la forma correcta pero que no esta en la base: el `UPDATE` con
    // `WHERE` no encuentra nada y devuelve 0. No se pasa un numero, porque en la
    // v7 `eliminar` espera texto.
    expect(await CitaRepository.instance.eliminar(Uuid.instancia.generar()), 0);
  });

  // -------------------------------------------------------------------
  // MIGRACION A LA v7
  //
  // Este grupo CAMBIO de opinion en la v7 y hay que entender por que antes de
  // tocarlo.
  //
  // Antes se llamaba `migracion v1 -> v2` y su asercion central era
  // `expect(citas.length, 1, reason: 'la migracion NO debe perder datos')`. Con
  // `_versionBase = 7` ese test miente, y no por un detalle del test: la v7
  // DROPEA las cuatro tablas a proposito, porque una PK que pasa de
  // `INTEGER PRIMARY KEY AUTOINCREMENT` a `TEXT` con UUID no se puede migrar sin
  // inventar una tabla de mapeo de ids. Ver la nota larga de `DatabaseHelper._migrar`.
  //
  // O sea: la migracion de la v1 a la v2 SI conservaba datos, y ese test era
  // correcto para su epoca. Lo que cambio es que ahora abrir una base vieja la
  // lleva a la v7, y la v7 reinicia el esquema.
  //
  // Los tests de abajo fijan el comportamiento REAL de la v7: la base vieja se
  // reemplaza, las tablas quedan con el esquema nuevo, y el catalogo de estados
  // desaparece.
  // -------------------------------------------------------------------
  group('migracion a la v7', () {
    // El esquema v1 tal cual lo creo la primera version. Esta es la base que
    // puede tener un dispositivo que ya instalo la app antes de la v2.
    const esquemaV1 = '''
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
    ''';

    test('una base vieja se REINICIA: el esquema pasa a ser el de la v7', () async {
      await DatabaseHelper.resetParaPruebas();
      final ruta = p.join(await getDatabasesPath(), 'autofix.db');

      // Se siembra una base v1 a mano, como si el dispositivo ya la tuviera.
      final baseV1 = await databaseFactory.openDatabase(
        ruta,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(esquemaV1);
            await db.execute(
              "INSERT INTO citas (codigo_qr, cliente, vehiculo, fecha_cita, estado, creado_en) "
              "VALUES ('OLD-1', 'Cliente Anterior', 'Ford Ranger', '2026-01-05T10:00:00.000', 'pendiente', '2026-01-01T09:00:00.000')",
            );
          },
        ),
      );
      await baseV1.close();

      // Se abre con el helper de la app: version 7 dispara onUpgrade.
      final citas = await CitaRepository.instance.obtenerTodas();

      // A diferencia de la v6, aqui la v7 SI borra los datos de la v6. Es la
      // decision documentada en `DatabaseHelper._migrar`: cambiar la PK a UUID no
      // se puede hacer copiando.
      expect(citas, isEmpty, reason: 'la v7 reinicia el esquema a proposito');

      // Lo que no se negocia: el esquema con el que queda.
      final db = await DatabaseHelper.instance.base;
      final info = await db.rawQuery(
        'PRAGMA table_info(${DatabaseHelper.tablaCitas})',
      );
      final columnas = info.map((f) => f['name'] as String).toSet();

      expect(columnas, contains(DatabaseHelper.colCodigoVisible));
      expect(columnas, contains(DatabaseHelper.colEliminadoEn));
      expect(columnas, contains(DatabaseHelper.colEliminadoPor));
      expect(columnas, contains(DatabaseHelper.colRestauradoEn));
      // La v5 elimino el codigo QR: si volviera a aparecer, es que el paso 5 no
      // corrio.
      expect(columnas, isNot(contains(DatabaseHelper.colCodigoQr)));

      // La PK es TEXT, y esto se comprueba leyendo `PRAGMA`, no inferiendolo de
      // que el modelo compile.
      final pk = info.firstWhere((f) => f['pk'] == 1);
      expect(pk['type'], 'TEXT');
    });

    test('la tabla de estados desaparece en la v7', () async {
      // El catalogo `estados` se elimino por decision de Leandy. Este test existe
      // para que, si alguien lo vuelve a agregar a `_crearEsquema` "porque total
      // hace falta", falle en vez de dejar data muerta que contradice al enum.
      final db = await DatabaseHelper.instance.base;
      final tablas = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final nombres = tablas.map((f) => f['name'] as String).toSet();

      expect(nombres, isNot(contains('estados')));
      // Y los catalogos del punto 6 SI existen.
      expect(nombres, contains(DatabaseHelper.tablaMarcas));
      expect(nombres, contains(DatabaseHelper.tablaGruposServicio));
    });

    test('los catalogos del punto 6 quedan sembrados tras migrar', () async {
      await DatabaseHelper.resetParaPruebas();
      final ruta = p.join(await getDatabasesPath(), 'autofix.db');

      final baseV1 = await databaseFactory.openDatabase(
        ruta,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => db.execute(esquemaV1),
        ),
      );
      await baseV1.close();

      final db = await DatabaseHelper.instance.base;
      for (final tabla in <String>[
        DatabaseHelper.tablaTecnicos,
        DatabaseHelper.tablaTiposServicio,
        DatabaseHelper.tablaMarcas,
        DatabaseHelper.tablaGruposServicio,
      ]) {
        final filas = await db.query(tabla);
        expect(
          filas,
          isNotEmpty,
          reason: 'el catalogo $tabla quedo vacio tras migrar',
        );
      }
    });

    test(
      'la migracion es idempotente: abrir dos veces no rompe nada',
      () async {
        await DatabaseHelper.resetParaPruebas();
        final ruta = p.join(await getDatabasesPath(), 'autofix.db');

        final baseV1 = await databaseFactory.openDatabase(
          ruta,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) => db.execute(esquemaV1),
          ),
        );
        await baseV1.close();

        // Primera apertura: migra. Segunda: onUpgrade ya no debe correr.
        await CitaRepository.instance.obtenerTodas();
        await DatabaseHelper.instance.cerrar();
        expect(await CitaRepository.instance.obtenerTodas(), isEmpty);

        final id = await CitaRepository.instance.crear(nueva());
        expect(Uuid.tieneFormaDeUuid(id), isTrue);
      },
    );
  });

  group('FUSION DESDE NUBE (sincronizacion entre dispositivos)', () {
    test(
      'un cambio de estado de OTRO dispositivo baja a la base local',
      () async {
        final id = await CitaRepository.instance.crear(nueva());
        final local = await CitaRepository.instance.obtenerPorId(id);
        expect(local!.estado, EstadoCita.pendiente);

        // Lo que llegaria del onSnapshot: misma cita, estado nuevo y
        // actualizado_en mas reciente (lo escribe el otro dispositivo).
        final remota = local.copyWith(
          estado: EstadoCita.completado,
          actualizadoEn: local.actualizadoEn!
              .add(const Duration(hours: 1)),
        );
        await CitaRepository.instance.fusionarDesdeNube(remota);

        final fusionada = await CitaRepository.instance.obtenerPorId(id);
        expect(fusionada!.estado, EstadoCita.completado);
      },
    );

    test(
      'una version remota MAS VIEJA no pisa la local',
      () async {
        final id = await CitaRepository.instance.crear(nueva());
        final local = await CitaRepository.instance.obtenerPorId(id);

        final remotaVieja = local!.copyWith(
          estado: EstadoCita.completado,
          actualizadoEn: local.actualizadoEn!
              .subtract(const Duration(hours: 1)),
        );
        await CitaRepository.instance.fusionarDesdeNube(remotaVieja);

        final sinCambios = await CitaRepository.instance.obtenerPorId(id);
        expect(sinCambios!.estado, EstadoCita.pendiente);
      },
    );

    test(
      'el tombstone remoto (borrado en otro dispositivo) gana',
      () async {
        final id = await CitaRepository.instance.crear(nueva());
        final local = await CitaRepository.instance.obtenerPorId(id);

        final borradaEnLaNube = local!.marcarBorrada(
          cuando: local.actualizadoEn!
              .add(const Duration(hours: 1)),
          por: 'otro-dispositivo',
        );
        await CitaRepository.instance.fusionarDesdeNube(borradaEnLaNube);

        final fusionada = await CitaRepository.instance.obtenerPorId(id);
        expect(fusionada!.estaBorrada, isTrue);
        expect(await CitaRepository.instance.obtenerTodas(), isEmpty);
      },
    );
  });
}

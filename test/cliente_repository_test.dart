import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/features/cliente/data/cliente_repository.dart';
import 'package:autofix/features/cliente/presentation/perfil_cliente_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// La columna local del perfil cliente (v12): se guarda sin red, queda
/// `pending` y la sube `SyncService`. No usa mocks: SQLite real via FFI.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_clientes_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    // El .db vive en disco. Sin este reset `onCreate` no se vuelve a correr y
    // el test pasaria probando un esquema viejo.
    await DatabaseHelper.resetParaPruebas();
    SharedPreferences.setMockInitialValues({});
    await SesionCliente.instance.olvidarTodo();
  });

  tearDown(() async {
    await SesionCliente.instance.olvidarTodo();
  });

  Future<String> rutaDeLaBase() async =>
      p.join(await getDatabasesPath(), 'autofix_clientes_test.db');

  Future<int> contarFilas() async {
    final db = await DatabaseHelper.instance.base;
    final filas = await db.query(DatabaseHelper.tablaClientes);
    return filas.length;
  }

  group('perfil y migración local', () {
    test('una base creada de cero trae la tabla clientes', () async {
      final db = await DatabaseHelper.instance.base;
      final info = await db.rawQuery(
        'PRAGMA table_info(${DatabaseHelper.tablaClientes})',
      );
      final nombres = info.map((f) => f['name'] as String).toSet();

      expect(
        nombres,
        containsAll(<String>[
          DatabaseHelper.colId,
          DatabaseHelper.colUid,
          DatabaseHelper.colCorreo,
          DatabaseHelper.colNombre,
          DatabaseHelper.colTelefono,
          DatabaseHelper.colActualizadoEn,
          DatabaseHelper.colSyncStatus,
        ]),
      );
      // Nace `pending`: es lo que hace que SyncService la suba. Una fila que
      // naciera `synced` nunca subiria y el guardado sin red quedaria local
      // para siempre.
      final sync = info.firstWhere(
        (f) => f['name'] == DatabaseHelper.colSyncStatus,
      );
      expect(sync['dflt_value'], contains('pending'));
    });

    test(
      'solo puede haber UNA fila por correo, sin importar mayusculas',
      () async {
        final repo = ClienteRepository();
        expect(
          await repo.guardarLocal(
            nombre: 'Ana',
            correo: 'Ana@Ejemplo.com',
            telefono: '8090000000',
          ),
          isTrue,
        );
        // La unica forma de fallar aca es un segundo INSERT: si no hubiera
        // indice unico, la fila de arriba y la de abajo convivirian.
        final db = await DatabaseHelper.instance.base;
        final duplicado = await db.query(
          DatabaseHelper.tablaClientes,
          where: '${DatabaseHelper.colCorreo} = ? COLLATE NOCASE',
          whereArgs: ['ana@ejemplo.com'],
        );
        expect(duplicado, hasLength(1));

        final indices = await db.rawQuery(
          'PRAGMA index_list(${DatabaseHelper.tablaClientes})',
        );
        expect(
          indices.map((i) => i['name']),
          contains('idx_clientes_correo'),
          reason:
              'sin el indice unico no hay garantia de "una persona, una fila"',
        );
      },
    );

    test('una base v11 sube a v15 con clientes y vehículos locales', () async {
      await DatabaseHelper.resetParaPruebas();
      final ruta = await rutaDeLaBase();

      // Un archivo que dice "soy la version 11". No hace falta replicar el
      // esquema v11 entero: los pasos posteriores solo agregan tablas nuevas, asi
      // que basta con que `user_version` sea 11 para que `onUpgrade` corra.
      final vieja = await databaseFactory.openDatabase(
        ruta,
        options: OpenDatabaseOptions(
          version: 11,
          onCreate: (db, _) => db.execute('CREATE TABLE marcador (id TEXT)'),
        ),
      );
      await vieja.close();

      // Abrir con el helper dispara onUpgrade hasta la versión actual.
      final db = await DatabaseHelper.instance.base;
      final info = await db.rawQuery(
        'PRAGMA table_info(${DatabaseHelper.tablaClientes})',
      );
      expect(
        info.map((f) => f['name']),
        contains(DatabaseHelper.colCorreo),
        reason: 'la migracion 11 -> 12 no creo la tabla',
      );
      final vehiculos = await db.rawQuery(
        'PRAGMA table_info(${DatabaseHelper.tablaVehiculos})',
      );
      expect(
        vehiculos.map((f) => f['name']),
        contains(DatabaseHelper.colClienteIdVehiculo),
      );
      final version = await db.rawQuery('PRAGMA user_version');
      expect(version.first.values.first, 15);
    });
  });

  group('guardarLocal', () {
    late ClienteRepository repo;

    setUp(() => repo = ClienteRepository());

    test('deja la fila pendiente de subir', () async {
      expect(
        await repo.guardarLocal(
          nombre: 'Ana Perez',
          correo: 'ana@ejemplo.com',
          telefono: '8091111111',
        ),
        isTrue,
      );

      final fila = await repo.local(correo: 'ana@ejemplo.com');
      expect(fila, isNotNull);
      expect(fila!.nombre, 'Ana Perez');
      expect(fila.telefono, '8091111111');
      expect(fila.pendienteDeSync, isTrue);
      // Sin sesion de Auth no hay uid: la identidad local es el correo.
      expect(fila.uid, isEmpty);
      expect(fila.id, 'ana@ejemplo.com');
    });

    test('editar de nuevo ACTUALIZA la fila, no crea una segunda', () async {
      await repo.guardarLocal(
        nombre: 'Ana',
        correo: 'ana@ejemplo.com',
        telefono: '8091111111',
      );
      final primera = await repo.local(correo: 'ana@ejemplo.com');

      // Mismo correo de sesion, distinto telefono: es una edicion.
      await repo.guardarLocal(
        correoIdentidad: 'ana@ejemplo.com',
        nombre: 'Ana',
        correo: 'ana@ejemplo.com',
        telefono: '8092222222',
      );
      expect(await contarFilas(), 1);
      final fila = await repo.local(correo: 'ana@ejemplo.com');
      expect(fila!.telefono, '8092222222');
      expect(fila.id, primera!.id);
    });

    test('cambiar el correo mueve la MISMA fila a la cuenta nueva', () async {
      await repo.guardarLocal(
        nombre: 'Ana',
        correo: 'ana@ejemplo.com',
        telefono: '8091111111',
      );

      // Este es el caso que sin `correoIdentidad` dejaria una fila huerfana:
      // el id de la fila vieja es su correo, y escribir con el correo nuevo
      // crearia una segunda persona.
      await repo.guardarLocal(
        correoIdentidad: 'ana@ejemplo.com',
        nombre: 'Ana',
        correo: 'ana@nuevo.com',
        telefono: '8091111111',
      );

      expect(await contarFilas(), 1);
      expect(await repo.local(correo: 'ana@nuevo.com'), isNotNull);
      expect(await repo.local(correo: 'ana@ejemplo.com'), isNull);
    });

    test('un correo vacio no guarda', () async {
      expect(
        await repo.guardarLocal(
          nombre: 'Ana',
          correo: '   ',
          telefono: '8091111111',
        ),
        isFalse,
      );
      expect(await contarFilas(), 0);
    });
  });

  group('push', () {
    late ClienteRepository repo;

    setUp(() => repo = ClienteRepository());

    test('marcarSincronizada sella la fila con el uid de Auth', () async {
      await repo.guardarLocal(
        nombre: 'Ana',
        correo: 'ana@ejemplo.com',
        telefono: '8091111111',
      );
      final fila = await repo.local(correo: 'ana@ejemplo.com');

      final marcada = await repo.marcarSincronizada(
        id: fila!.id,
        uid: 'UID-1',
        actualizadoEn: fila.actualizadoEn,
      );
      expect(marcada, isTrue);

      final despues = await repo.local(uid: 'UID-1');
      expect(despues, isNotNull);
      expect(despues!.pendienteDeSync, isFalse);
      expect(despues.uid, 'UID-1');
    });

    test(
      'si el usuario edito mientras el push volvia, la fila sigue pendiente',
      () async {
        await repo.guardarLocal(
          nombre: 'Ana',
          correo: 'ana@ejemplo.com',
          telefono: '8091111111',
        );
        final fila = await repo.local(correo: 'ana@ejemplo.com');

        // Timestamp de una edicion que ya no es la vigente: la UPDATE no debe
        // tocar nada, o el cambio nuevo se marcaria como subido sin subirse.
        final tocada = await repo.marcarSincronizada(
          id: fila!.id,
          uid: 'UID-1',
          actualizadoEn: '1999-01-01T00:00:00.000Z',
        );
        expect(tocada, isFalse);

        final despues = await repo.local(correo: 'ana@ejemplo.com');
        expect(despues!.pendienteDeSync, isTrue);
        expect(despues.uid, isEmpty);
      },
    );
  });

  group('pull', () {
    late ClienteRepository repo;

    setUp(() => repo = ClienteRepository());

    test('un perfil local pending NO lo pisa la nube', () async {
      await repo.guardarLocal(
        nombre: 'Ana Local',
        correo: 'ana@ejemplo.com',
        telefono: '8091111111',
      );

      final aplicado = await repo.aplicarDesdeNube(
        uid: 'UID-1',
        nombre: 'Ana Nube',
        correo: 'ana@ejemplo.com',
        telefono: '8099999999',
        eliminado: false,
      );
      expect(aplicado, isFalse);
      expect(
        (await repo.local(correo: 'ana@ejemplo.com'))!.nombre,
        'Ana Local',
        reason: 'el cambio hecho sin red se pierde si la nube lo pisa',
      );
    });

    test('un perfil ya subido si acepta la nube', () async {
      await repo.guardarLocal(
        nombre: 'Ana Local',
        correo: 'ana@ejemplo.com',
        telefono: '8091111111',
      );
      final fila = await repo.local(correo: 'ana@ejemplo.com');
      await repo.marcarSincronizada(
        id: fila!.id,
        uid: 'UID-1',
        actualizadoEn: fila.actualizadoEn,
      );

      final aplicado = await repo.aplicarDesdeNube(
        uid: 'UID-1',
        nombre: 'Ana Nube',
        correo: 'ana@ejemplo.com',
        telefono: '8099999999',
        eliminado: false,
      );
      expect(aplicado, isTrue);

      final despues = await repo.local(uid: 'UID-1');
      expect(despues!.nombre, 'Ana Nube');
      expect(despues.telefono, '8099999999');
      // Bajado de la nube: no hay nada que volver a subir.
      expect(despues.pendienteDeSync, isFalse);
    });

    test('la nube rellena el uid de una fila que se creo sin sesion', () async {
      await repo.guardarLocal(
        nombre: 'Ana Local',
        correo: 'ana@ejemplo.com',
        telefono: '8091111111',
      );
      final fila = await repo.local(correo: 'ana@ejemplo.com');
      await repo.marcarSincronizada(
        id: fila!.id,
        uid: 'UID-1',
        actualizadoEn: fila.actualizadoEn,
      );

      // El documento de la nube se llama por UID; si el buscador no
      // cayera al correo, este upsert dejaria DOS filas para la misma persona
      // y el indice unico reventaria el INSERT.
      expect(
        await repo.aplicarDesdeNube(
          uid: 'UID-1',
          nombre: 'Ana Local',
          correo: 'ana@ejemplo.com',
          telefono: '8091111111',
          eliminado: false,
        ),
        isTrue,
      );
      expect(await contarFilas(), 1);
    });

    test('un documento sin uid no se aplica', () async {
      expect(
        await repo.aplicarDesdeNube(
          uid: '   ',
          nombre: 'Nadie',
          correo: 'x@y.com',
          telefono: '',
          eliminado: false,
        ),
        isFalse,
      );
      expect(await contarFilas(), 0);
    });
  });

  group('PerfilClienteController.guardarDatos', () {
    test('escribe en SQLite (pending) y en la sesión', () async {
      await SesionCliente.instance.iniciar(
        nombre: 'Ana',
        correo: 'ana@ejemplo.com',
        telefono: '8091111111',
      );

      final controller = PerfilClienteController();
      final mensaje = await controller.guardarDatos(
        nombre: 'Ana Perez',
        correo: 'ana@ejemplo.com',
        telefono: '8092222222',
      );
      controller.dispose();

      expect(mensaje, 'Información guardada');

      // La lectura rapida (AppBar, prellenado) ve el cambio ya...
      expect(SesionCliente.instance.nombre, 'Ana Perez');
      expect(SesionCliente.instance.telefono, '8092222222');

      // ...y la fuente que se sincroniza tambien, marcada para subir.
      final fila = await ClienteRepository().local(correo: 'ana@ejemplo.com');
      expect(fila, isNotNull);
      expect(fila!.nombre, 'Ana Perez');
      expect(fila.pendienteDeSync, isTrue);
    });

    test('un dato invalido no escribe en ninguna de las dos', () async {
      await SesionCliente.instance.iniciar(
        nombre: 'Ana',
        correo: 'ana@ejemplo.com',
        telefono: '8091111111',
      );

      final controller = PerfilClienteController();
      final mensaje = await controller.guardarDatos(
        nombre: 'Ana',
        correo: 'no-es-correo',
        telefono: '8092222222',
      );
      controller.dispose();

      expect(mensaje, contains('correo'));
      expect(SesionCliente.instance.correo, 'ana@ejemplo.com');
      expect(await contarFilas(), 0);
    });
  });
}

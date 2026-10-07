import 'package:autofix/core/auth/credenciales_seguras.dart';
import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/core/data/limpieza_local.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/cliente/data/cliente_repository.dart';
import 'package:autofix/features/cliente/data/vehiculo_repository.dart';
import 'package:autofix/features/cliente/models/vehiculo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Las tres reglas del ciclo de vida local de [LimpiezaLocal], con SQLite real
/// via FFI: un purge que pasa contra un mock de base no prueba nada.
///
/// Los datos de "usuario" (citas y perfil) se purgan; los de plataforma
/// (talleres y admins) no. Esa linea es la que evita que un logout deje al
/// dispositivo sin mapa ni cuentas hasta la proxima sincronizacion.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_limpieza_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
    CredencialesSeguras.usarAlmacenParaPruebas(null);
  });

  setUp(() async {
    // Sin el reset `onCreate` no vuelve a correr y el test pasaria contra un
    // esquema viejo o contra datos del test anterior.
    await DatabaseHelper.resetParaPruebas();
    SharedPreferences.setMockInitialValues({});
    await SesionCliente.instance.olvidarTodo();
    // El keystore del sistema no existe en pruebas: con el almacen en memoria
    // "Recuerdame" se puede encender y apagar de verdad.
    CredencialesSeguras.usarAlmacenParaPruebas(AlmacenSeguroEnMemoria());
  });

  tearDown(() async {
    await SesionCliente.instance.olvidarTodo();
    CredencialesSeguras.usarAlmacenParaPruebas(null);
  });

  Future<int> contar(String tabla) async {
    final db = await DatabaseHelper.instance.base;
    final filas = await db.rawQuery('SELECT COUNT(*) AS n FROM $tabla');
    return filas.first['n'] as int;
  }

  /// Deja el dispositivo como si un cliente hubiera usado la app: red de
  /// talleres, un admin de la nube, una cita, un vehículo y el perfil local.
  Future<void> dejarDatosDeUsuario() async {
    await DatabaseHelper.instance.sembrarTalleres();

    final db = await DatabaseHelper.instance.base;
    final ahora = DateTime.now().toUtc().toIso8601String();
    await db.insert(DatabaseHelper.tablaAdmins, <String, Object?>{
      DatabaseHelper.colId: 'admin-de-prueba',
      DatabaseHelper.colAdminEmail: 'dueno@autofix.test',
      DatabaseHelper.colCreadoEn: ahora,
      DatabaseHelper.colActualizadoEn: ahora,
    });

    await CitaRepository.instance.crear(
      Cita(
        cliente: 'Ana Perez',
        vehiculo: 'Honda Civic',
        fechaCita: DateTime(2026, 10, 10, 9),
        tallerId: 'taller-de-prueba',
      ),
    );

    await ClienteRepository().guardarLocal(
      nombre: 'Ana Perez',
      correo: 'ana@autofix.test',
      telefono: '8090000000',
    );
    await VehiculoRepository.instance.crear(
      const Vehiculo(
        clienteId: 'ana@autofix.test',
        marca: 'Honda',
        modelo: 'Civic',
        anio: 2020,
      ),
    );
  }

  /// Cantidad de filas de DATOS DE USUARIO (lo que tiene que desaparecer).
  Future<int> datosDeUsuario() async =>
      (await contar(DatabaseHelper.tablaCitas)) +
      (await contar(DatabaseHelper.tablaClientes)) +
      (await contar(DatabaseHelper.tablaVehiculos));

  group('purgar()', () {
    test('borra citas y perfil pero deja talleres y admins', () async {
      await dejarDatosDeUsuario();
      final talleres = await contar(DatabaseHelper.tablaTalleres);
      await SesionCliente.instance.iniciar(
        nombre: 'Ana Perez',
        correo: 'ana@autofix.test',
        telefono: '8090000000',
      );
      expect(await datosDeUsuario(), 3);

      await LimpiezaLocal.purgar(motivo: 'prueba directa');

      expect(await contar(DatabaseHelper.tablaCitas), 0);
      expect(await contar(DatabaseHelper.tablaClientes), 0);
      expect(await contar(DatabaseHelper.tablaVehiculos), 0);
      // La plataforma no es dato de nadie: vaciarla dejaria al proximo
      // usuario sin mapa ni cuentas hasta la proxima sincronizacion.
      expect(await contar(DatabaseHelper.tablaTalleres), talleres);
      expect(talleres, greaterThan(0));
      expect(await contar(DatabaseHelper.tablaAdmins), 1);
      // La sesion de perfil tambien es dato local del usuario.
      expect(SesionCliente.instance.activa, isFalse);
    });

    test('no se cae aunque las citas sigan pendientes de subir', () async {
      // Este es el caso real de un logout: las filas nacieron `pending` y el
      // ultimo push puede tocar la conectividad. El purge tiene que completar
      // igual, con la plataforma de red disponible o no.
      await dejarDatosDeUsuario();
      final db = await DatabaseHelper.instance.base;
      final pendientes = await db.query(
        DatabaseHelper.tablaCitas,
        where: '${DatabaseHelper.colSyncStatus} = ?',
        whereArgs: const ['pending'],
      );
      expect(pendientes, isNotEmpty);

      await LimpiezaLocal.purgar(motivo: 'logout con cola pendiente');

      expect(await datosDeUsuario(), 0);
    });
  });

  group('alArrancar()', () {
    test('con sesion restaurada conserva los datos', () async {
      await dejarDatosDeUsuario();

      await LimpiezaLocal.alArrancar(haySesion: true);

      expect(await datosDeUsuario(), 3);
    });

    test('sin sesion purga', () async {
      await dejarDatosDeUsuario();

      await LimpiezaLocal.alArrancar(haySesion: false);

      expect(await datosDeUsuario(), 0);
      expect(await contar(DatabaseHelper.tablaTalleres), greaterThan(0));
    });
  });

  group('alCerrarSesion()', () {
    test('con Recuerdame activo conserva los datos', () async {
      await CredencialesSeguras.guardar(
        usuario: 'ana@autofix.test',
        contrasena: 'secreta',
      );
      await dejarDatosDeUsuario();

      await LimpiezaLocal.alCerrarSesion();

      expect(await datosDeUsuario(), 3);
    });

    test('sin Recuerdame purga', () async {
      await dejarDatosDeUsuario();

      await LimpiezaLocal.alCerrarSesion();

      expect(await datosDeUsuario(), 0);
    });
  });

  group('alIniciarSesion()', () {
    test('la primera cuenta del dispositivo no purga', () async {
      await dejarDatosDeUsuario();

      await LimpiezaLocal.alIniciarSesion(uid: 'uid-1');

      expect(await datosDeUsuario(), 3);
    });

    test('la misma cuenta no purga', () async {
      await LimpiezaLocal.alIniciarSesion(uid: 'uid-1');
      await dejarDatosDeUsuario();

      await LimpiezaLocal.alIniciarSesion(uid: 'uid-1');

      expect(await datosDeUsuario(), 3);
    });

    test('una cuenta distinta purga, pero deja los catalogos', () async {
      await LimpiezaLocal.alIniciarSesion(uid: 'uid-1');
      await dejarDatosDeUsuario();

      await LimpiezaLocal.alIniciarSesion(uid: 'uid-2');

      expect(await datosDeUsuario(), 0);
      expect(await contar(DatabaseHelper.tablaTalleres), greaterThan(0));
      expect(await contar(DatabaseHelper.tablaAdmins), 1);
    });

    test('uid nulo (login sin red) no purga', () async {
      await dejarDatosDeUsuario();

      await LimpiezaLocal.alIniciarSesion(uid: null);
      await LimpiezaLocal.alIniciarSesion(uid: '   ');

      expect(await datosDeUsuario(), 3);
    });
  });
}

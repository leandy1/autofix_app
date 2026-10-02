import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Punto unico de acceso a SQLite (Singleton).
///
/// Singleton de SQLite: UNA sola conexion abierta para todo el proceso, clave
/// para que el CRUD no se trabe. Si cada pantalla abriera su propia base, dos
/// escrituras simultaneas se pelean por el lock del archivo y SQLite tira
/// "database is locked". Ademas `openDatabase` se paga una vez, no por pantalla.
class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  static const String _nombreBase = 'autofix.db';

  /// Nombre alternativo del archivo .db, solo para tests.
  ///
  /// `flutter test` corre cada archivo en su propio isolate y EN PARALELO, pero
  /// `sqflite_common_ffi` deja la base en un unico lugar de `.dart_tool/`. Sin
  /// esto, dos archivos que insertan el mismo QR se pisan y el UNIQUE revienta
  /// con un error que no tiene nada que ver con lo que se esta probando.
  @visibleForTesting
  static String? nombreBaseParaPruebas;

  static String get _nombre => nombreBaseParaPruebas ?? _nombreBase;

  /// v1 = esquema base de la unidad de almacenamiento.
  /// v2 = se agregan telefono, marca, modelo, anio, placa, servicios y tecnico.
  /// v3 = se elimina codigo_qr y se persiste el total de la cita.
  /// OJO: subir la version NO borra la base, dispara `onUpgrade`, que es lo
  /// que permite a un dispositivo que ya instalo la v1 seguir funcionando.
  static const int _versionBase = 3;

  static const String tablaCitas = 'citas';
  static const String colId = 'id';
  static const String colCliente = 'cliente';
  static const String colTelefono = 'telefono';
  static const String colVehiculo = 'vehiculo';
  static const String colMarca = 'marca';
  static const String colModelo = 'modelo';
  static const String colAnio = 'anio';
  static const String colPlaca = 'placa';
  static const String colServicios = 'servicios';
  static const String colTecnico = 'tecnico';
  static const String colDescripcion = 'descripcion';
  static const String colFechaCita = 'fecha_cita';
  static const String colEstado = 'estado';
  static const String colCreadoEn = 'creado_en';
  static const String colActualizadoEn = 'actualizado_en';
  static const String colTotal = 'total';

  /// Columnas que se agregan en v2, con su tipo y default.
  /// Estar en una constante evita duplicar los nombres entre `_crearEsquema`
  /// y `_migrarAV2`, que es como seroductionen bugs de migracion.
  static const Map<String, String> _columnasV2 = {
    colTelefono: 'TEXT NOT NULL DEFAULT \'\'',
    colMarca: 'TEXT NOT NULL DEFAULT \'\'',
    colModelo: 'TEXT NOT NULL DEFAULT \'\'',
    colAnio: 'INTEGER NOT NULL DEFAULT 0',
    colPlaca: 'TEXT NOT NULL DEFAULT \'\'',
    colServicios: 'TEXT NOT NULL DEFAULT \'[]\'',
    colTecnico: 'TEXT NOT NULL DEFAULT \'\'',
    colActualizadoEn: 'TEXT NOT NULL DEFAULT \'\'',
  };

  Database? _base;

  Future<Database> get base async => _base ??= await _abrir();

  Future<Database> _abrir() async {
    // El archivo vive en el almacenamiento INTERNO de la app, no en externo:
    // por eso sobrevive al cierre total y solo se va al desinstalar.
    final ruta = p.join(await getDatabasesPath(), _nombre);

    return openDatabase(
      ruta,
      version: _versionBase,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) => _crearEsquema(db),
      onUpgrade: _migrar,
    );
  }

  /// `onCreate` crea directamente el esquema actual; las migraciones conservan
  /// los datos de instalaciones que todavia tengan una version anterior.
  ///
  /// El SQL se arma en un solo string porque `execute` manda UNA sentencia
  /// completa: partir el CREATE TABLE en varias llamadas es SQL invalido.
  Future<void> _crearEsquema(Database db) async {
    final definiciones = <String>[
      '$colId INTEGER PRIMARY KEY AUTOINCREMENT',
      '$colCliente TEXT NOT NULL',
      '$colVehiculo TEXT NOT NULL',
      ..._columnasV2.entries.map((e) => '${e.key} ${e.value}'),
      '$colDescripcion TEXT NOT NULL DEFAULT \'\'',
      '$colFechaCita TEXT NOT NULL',
      '$colEstado TEXT NOT NULL',
      '$colCreadoEn TEXT NOT NULL',
      '$colTotal REAL NOT NULL DEFAULT 0',
    ];

    await db.execute('CREATE TABLE $tablaCitas (${definiciones.join(', ')})');
  }

  Future<void> _migrar(
    Database db,
    int versionAnterior,
    int versionNueva,
  ) async {
    if (versionAnterior < 2) await _migrarAV2(db);
    if (versionAnterior < 3) await _migrarAV3(db);
  }

  /// Migracion 1 -> 2. Un ALTER TABLE por columna dentro de una transaccion.
  Future<void> _migrarAV2(Database db) async {
    await db.transaction((txn) async {
      for (final entrada in _columnasV2.entries) {
        await txn.execute('ALTER TABLE $tablaCitas ADD COLUMN ${entrada.key} ${entrada.value}');
      }
    });
  }

  /// Migracion 2 -> 3. Reconstruye la tabla para retirar codigo_qr, que era
  /// NOT NULL, y conservar todos los datos mientras agrega el total.
  Future<void> _migrarAV3(Database db) async {
    await db.transaction((txn) async {
      const tablaNueva = 'citas_v3';
      final definiciones = <String>[
        '$colId INTEGER PRIMARY KEY AUTOINCREMENT',
        '$colCliente TEXT NOT NULL',
        '$colVehiculo TEXT NOT NULL',
        ..._columnasV2.entries.map((e) => '${e.key} ${e.value}'),
        '$colDescripcion TEXT NOT NULL DEFAULT \'\'',
        '$colFechaCita TEXT NOT NULL',
        '$colEstado TEXT NOT NULL',
        '$colCreadoEn TEXT NOT NULL',
        '$colTotal REAL NOT NULL DEFAULT 0',
      ];
      const columnasExistentes = [
        colId,
        colCliente,
        colTelefono,
        colVehiculo,
        colMarca,
        colModelo,
        colAnio,
        colPlaca,
        colServicios,
        colTecnico,
        colDescripcion,
        colFechaCita,
        colEstado,
        colCreadoEn,
        colActualizadoEn,
      ];

      await txn.execute(
        'CREATE TABLE $tablaNueva (${definiciones.join(', ')})',
      );
      await txn.execute(
        'INSERT INTO $tablaNueva (${columnasExistentes.join(', ')}, $colTotal) '
        'SELECT ${columnasExistentes.join(', ')}, 0 FROM $tablaCitas',
      );
      await txn.execute('DROP TABLE $tablaCitas');
      await txn.execute('ALTER TABLE $tablaNueva RENAME TO $tablaCitas');
    });
  }

  Future<void> cerrar() async {
    await _base?.close();
    _base = null;
  }

  /// Borra el archivo .db y reabre desde cero. SOLO para pruebas.
  ///
  /// Esto es indispensable, no un lujo: `sqflite_common_ffi` deja la base en
  /// `.dart_tool/sqflite_common_ffi/`, o sea en disco, NO en memoria. Sin este
  /// reset, la segunda corrida de los tests se encuentra con el archivo que
  /// dejo la primera, `onCreate` NO se vuelve a ejecutar, y los tests pasan
  /// verdes probando una base vieja. Ya me paso: un `CREATE TABLE` al que le
  /// faltaba la columna `vehiculo` daba verde porque la base en disco era de la
  /// version anterior. Por eso el `setUp` de las pruebas SIEMPRE resetea.
  @visibleForTesting
  static Future<void> resetParaPruebas() async {
    await instance.cerrar();
    await deleteDatabase(p.join(await getDatabasesPath(), _nombre));
  }
}

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'semilla_inicial.dart';

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
  /// v2 = se agregan los campos que el formulario de Leandy ya captura
  ///      (telefono, marca, modelo, anio, placa, servicios, tecnico).
  /// v3 = los catalogos de Configuracion (tecnicos, tipos de servicio, estados).
  /// OJO: subir la version NO borra la base, dispara `onUpgrade`, que es lo
  /// que permite a un dispositivo que ya instalo la v1 seguir funcionando.
  static const int _versionBase = 3;

  static const String tablaCitas = 'citas';
  static const String colId = 'id';
  static const String colCodigoQr = 'codigo_qr';
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

  // ------------------------------------------------------------------
  // Catalogos de Configuracion (v3)
  //
  // Tecnicos, Tipos de Servicio y Estados son el mismo molde: una lista de
  // nombres que el administrador mantiene. Por eso comparten las mismas
  // columnas y el mismo constructor de tabla.
  // ------------------------------------------------------------------

  static const String tablaTecnicos = 'tecnicos';
  static const String tablaTiposServicio = 'tipos_servicio';
  static const String tablaEstados = 'estados';

  static const String colNombre = 'nombre';
  static const String colActivo = 'activo';
  static const String colPrecio = 'precio';

  /// Columnas comunes a los tres catalogos, en el orden en que se declaran.
  ///
  /// Tenerlas en una constante evita duplicar los nombres entre la creacion y la
  /// migracion, que es justamente como se producen los bugs de esquema: uno
  /// escribe 'nombre' y el otro 'nombres', y el INSERT revienta con
  /// "no such column" solo en produccion.
  static const Map<String, String> _columnasCatalogo = <String, String>{
    colNombre: 'TEXT NOT NULL',
    colActivo: 'INTEGER NOT NULL DEFAULT 1',
    colCreadoEn: 'TEXT NOT NULL',
    colActualizadoEn: 'TEXT NOT NULL',
  };

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

  /// `onCreate` solo corre la PRIMERA vez que se crea el archivo. Si armara el
  /// `CREATE TABLE` con la version vieja y despues subiera la version, los
  /// dispositivos que ya tenian la v1 se quedarian sin las columnas nuevas y
  /// la app truena con "no such column". Por eso todas las versiones arman el
  /// MISMO esquema completo y la migracion solo sirve para bases ya creadas.
  ///
  /// El SQL se arma en un solo string porque `execute` manda UNA sentencia
  /// completa: partir el CREATE TABLE en varias llamadas es SQL invalido.
  Future<void> _crearEsquema(Database db) async {
    final definiciones = <String>[
      '$colId INTEGER PRIMARY KEY AUTOINCREMENT',
      '$colCodigoQr TEXT NOT NULL UNIQUE',
      '$colCliente TEXT NOT NULL',
      '$colVehiculo TEXT NOT NULL',
      ..._columnasV2.entries.map((e) => '${e.key} ${e.value}'),
      '$colDescripcion TEXT NOT NULL DEFAULT \'\'',
      '$colFechaCita TEXT NOT NULL',
      '$colEstado TEXT NOT NULL',
      '$colCreadoEn TEXT NOT NULL',
    ];

    await db.execute('CREATE TABLE $tablaCitas (${definiciones.join(', ')})');

    // Indice unico: tu escaner QR consulta por codigo. Con el indice la busqueda
    // es O(log n) en vez de un recorrido secuencial de toda la tabla, y de yapa
    // SQLite impide dos citas con el mismo QR (integridad a nivel motor).
    await db.execute(
      'CREATE UNIQUE INDEX idx_citas_codigo_qr ON $tablaCitas ($colCodigoQr)',
    );

    await _crearCatalogos(db);
    await _sembrarCatalogos(db);
  }

  /// Crea los tres catalogos de Configuracion con el mismo molde.
  ///
  /// `CREATE TABLE IF NOT EXISTS` y no `CREATE TABLE` porque esta misma funcion
  /// la usan los dos caminos: el de una base nueva y el de la migracion. Con el
  /// `IF NOT EXISTS` no importa cual de los dos llegue primero.
  ///
  /// Recibe un [DatabaseExecutor] y no un `Database` porque la creacion inicial
  /// lo llama por fuera de la transaccion y la migracion por dentro: `Database` y
  /// `Transaction` implementan las dos interfaces y asi el codigo se escribe una
  /// sola vez.
  Future<void> _crearCatalogos(DatabaseExecutor db) async {
    await _crearTablaCatalogo(db, tablaTecnicos);
    await _crearTablaCatalogo(
      db,
      tablaTiposServicio,
      columnasExtra: <String>['$colPrecio INTEGER NOT NULL DEFAULT 0'],
    );
    await _crearTablaCatalogo(db, tablaEstados);
  }

  Future<void> _crearTablaCatalogo(
    DatabaseExecutor db,
    String tabla, {
    List<String> columnasExtra = const <String>[],
  }) async {
    final definiciones = <String>[
      '$colId INTEGER PRIMARY KEY AUTOINCREMENT',
      ..._columnasCatalogo.entries.map((e) => '${e.key} ${e.value}'),
      ...columnasExtra,
    ];

    await db.execute('CREATE TABLE IF NOT EXISTS $tabla (${definiciones.join(', ')})');

    // `COLLATE NOCASE` compara sin distinguir mayusculas, asi que el indice
    // IMPIDE que existan "Nissan" y "nissan" a la vez. Sin esto, el admin
    // escribia "Toyota" y tres semanas despues "toyota" y le aparecian dos
    // filas identicas en el desplegable de Marcas.
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_${tabla}_nombre '
      'ON $tabla ($colNombre COLLATE NOCASE)',
    );
  }

  /// Inserta el catalogo inicial del diseno en los tres catalogos.
  ///
  /// El chequeo de vacio por tabla NO es paranoia: la siembran los dos caminos
  /// (creacion y migracion) y nada impide que ambos corran, por ejemplo si un
  /// dispositivo se reinstala sin desinstalar del todo. Sin el `isEmpty`, esos
  /// casos duplicarian los 14 registros iniciales.
  Future<void> _sembrarCatalogos(DatabaseExecutor db) async {
    final ahora = DateTime.now().toIso8601String();

    // `extra` y no un `String? columnaPrecio`: los catalogos son el mismo molde y
    // cada uno aporta sus columnas, asi que el parametro es un mapa y no una
    // lista de casos. Agregar una columna nueva despues no obliga a tocar esto.
    Future<void> sembrar(
      String tabla,
      List<String> nombres, {
      Map<String, Object?> extra = const <String, Object?>{},
    }) async {
      final existentes = await db.query(tabla, columns: <String>[colId], limit: 1);
      if (existentes.isNotEmpty) return;

      for (final nombre in nombres) {
        await db.insert(tabla, <String, Object?>{
          colNombre: nombre,
          colActivo: 1,
          ...extra,
          colCreadoEn: ahora,
          colActualizadoEn: ahora,
        });
      }
    }

    await sembrar(tablaTecnicos, SemillaInicial.tecnicos);
    await sembrar(
      tablaTiposServicio,
      SemillaInicial.tiposServicio,
      extra: <String, Object?>{colPrecio: SemillaInicial.precioInicial},
    );
    await sembrar(tablaEstados, SemillaInicial.estados);
  }

  /// Migracion por pasos: 1 -> 2 agrega columnas a `citas`, 2 -> 3 agrega los
  /// catalogos de Configuracion.
  ///
  /// Antes esto era `if (versionAnterior >= 2) return;`, que con una v3 nueva
  /// impidia hacer exactamente lo mismo que hacia: al agregar pasos hay que
  /// dejar de cortar el flujo y pasar a preguntar por cada version. Un `return`
  /// temprano aqui es el bug clasico de las migraciones encadenadas.
  ///
  /// Todo dentro de UNA transaccion: si algo falla, SQLite revierte el paquete
  /// entero y la base queda como estaba. Migrar a medias es peor que no migrar.
  Future<void> _migrar(Database db, int versionAnterior, int versionNueva) async {
    if (versionAnterior >= _versionBase) return;

    await db.transaction((txn) async {
      if (versionAnterior < 2) {
        for (final entrada in _columnasV2.entries) {
          await txn.execute(
            'ALTER TABLE $tablaCitas ADD COLUMN ${entrada.key} ${entrada.value}',
          );
        }
      }

      if (versionAnterior < 3) {
        await _crearCatalogos(txn);
        // Un dispositivo que ya tenia citas entra por aca y recibe el catalogo
        // inicial: si no, el admin veria sus citas pero las tres tarjetas de
        // Configuracion vacias en un taller que ya venia funcionando.
        await _sembrarCatalogos(txn);
      }
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

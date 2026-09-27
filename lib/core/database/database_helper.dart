import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Punto unico de acceso a SQLite (Singleton).
///
/// Se usa un Singleton porque SQLite administra un unico pool de conexiones por
/// proceso. Si cada pantalla abriera su propia base, varias escrituras simultaneas
/// podrian provocar un bloqueo, y `openDatabase` tambien duplicaria trabajo.
class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  static const String _nombreBase = 'autofix.db';
  static const int _versionBase = 1;

  static const String tablaCitas = 'citas';
  static const String colId = 'id';
  static const String colCodigoQr = 'codigo_qr';
  static const String colCliente = 'cliente';
  static const String colVehiculo = 'vehiculo';
  static const String colDescripcion = 'descripcion';
  static const String colFechaCita = 'fecha_cita';
  static const String colEstado = 'estado';
  static const String colCreadoEn = 'creado_en';

  Database? _base;

  Future<Database> get base async => _base ??= await _abrir();

  Future<Database> _abrir() async {
    final ruta = p.join(await getDatabasesPath(), _nombreBase);

    return openDatabase(
      ruta,
      version: _versionBase,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _crearEsquema,
    );
  }

  /// El archivo .db vive en el almacenamiento interno de la app, por eso los
  /// datos sobreviven al cierre completo: solo se borran al desinstalar.
  Future<void> _crearEsquema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tablaCitas (
        $colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colCodigoQr TEXT NOT NULL UNIQUE,
        $colCliente TEXT NOT NULL,
        $colVehiculo TEXT NOT NULL,
        $colDescripcion TEXT NOT NULL DEFAULT '',
        $colFechaCita TEXT NOT NULL,
        $colEstado TEXT NOT NULL,
        $colCreadoEn TEXT NOT NULL
      )
    ''');

    // Indice unico: el escaner QR del companero consulta por codigo, y el
    // indice evita un recorrido secuencial de toda la tabla.
    await db.execute(
      'CREATE UNIQUE INDEX idx_citas_codigo_qr ON $tablaCitas ($colCodigoQr)',
    );
  }

  Future<void> cerrar() async {
    await _base?.close();
    _base = null;
  }
}

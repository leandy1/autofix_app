import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'semilla_citas_demo.dart';
import 'semilla_inicial.dart';

/// Punto unico de acceso a SQLite (Singleton).
///
/// Singleton de SQLite: UNA sola conexion abierta para todo el proceso, clave
/// para que el CRUD no se trabe. Si cada pantalla abriera su propia base, dos
/// escrituras simultaneas se pelean por el lock del archivo y SQLite tira
/// "database is locked". Ademas `openDatabase` se paga una vez, no por pantalla.
///
/// -----------------------------------------------------------------
/// LO QUE CAMBIO EN LA v7 (leer esto antes de tocar el esquema)
/// -----------------------------------------------------------------
///
/// Tres cambios estructurales, todos con la misma razon de fondo: la base local
/// paso a ser la fuente de verdad de la UI pero ya NO es la unica fuente de
/// verdad. Hay una nube al lado, y las dos tienen que poder coexistir.
///
/// 1. Las PRIMARY KEY pasaron de `INTEGER PRIMARY KEY AUTOINCREMENT` a
///    `TEXT PRIMARY KEY`, y el valor es un UUID v4 generado por la app.
///
///    Un autoincremento es un contador LOCAL. Dos dispositivos numeran sus filas
///    desde 1 por separado, asi que "la cita 7" significa una cosa en cada
///    celular. En la nube eso es una colision guaranteed: un `set` con docId
///    sobreescribe al otro y una orden se pierde. Un UUID se genera en el cliente
///    sin pedir nada al servidor y es el mismo en todas partes.
///
///    El precio es que el id ya no es un numero, asi que `citas` gana una columna
///    `codigo_visible` con el 'CITA-0004' que el humano lee.
///
/// 2. Tres columnas de trazabilidad en `citas`: `eliminado_en`, `eliminado_por` y
///    `restaurado_en`. El `DELETE` fisico quedo eliminado: con dos dispositivos, un
///    borrado local no se propaga y la cita reaparece cuando el otro la rebia de
///    la nube. Ver `lib/core/utils/borrado_logico.dart`.
///
/// 3. Se DROPEARON las tablas. No es una migracion de datos: es una purga
///    deliberada, y la seccion [_migrar] explica por que en un proyecto de
///    coursework es la decision correcta y en produccion no lo seria.
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
  /// v4 = la red de talleres AFILIADOS y el vinculo de la cita con el taller.
  /// v5 = se elimina codigo_qr de citas y se agrega total (histórico inmutable).
  /// v6 = indice en `citas.fecha_cita`, que es por donde filtran el Dashboard y
  ///      la lista de Citas.
  /// v7 = IDENTIDAD FEDERADA: la PK pasa a TEXT/UUID en las cuatro tablas, se
  ///      agrega `citas.codigo_visible` (numero que ve el humano) y las tres
  ///      columnas de borrado logico, se eliminan los estados de configuracion, y
  ///      se agregan los catalogos `marcas` y `grupos_servicio` que Leandy esta
  ///      construyendo en su UI de Configuracion (punto 6 del encargo).
  ///
  /// v8 = SINCRONIZACION (Fase 2): agrega columna `sync_status` a `citas`
  ///      para rastrear el estado de sincronizacion con Firestore ('pending' /
  ///      'synced'). No dropea tablas: solo `ALTER TABLE ADD COLUMN`.
  /// v9 = AISLAMIENTO POR TALLER: agrega columna `taller_id` a los 4 catalogos
  ///      (tecnicos, tipos_servicio, marcas, grupos_servicio) para filtrar
  ///      por taller. Usa `ALTER TABLE ADD COLUMN` para conservar datos.
  ///
  /// v9 = DEVMODE SYNC: agrega tabla `admins` para reflejar cuentas de admin
  ///      creadas desde Firestore y permitir baja logica local.
  /// v10/v11 = cola de cambios de contraseña (ver arriba).
  /// v12 = PERFIL OFFLINE-FIRST: agrega la tabla `clientes`, que es la copia
  ///      local del perfil que Editar Perfil guarda con `sync_status='pending'`
  ///      para que suba sola cuando vuelva la red. Antes de la v12 ese perfil
  ///      solo existia en SharedPreferences, que es un almacenamiento de
  ///      preferencias: no tiene forma de encolarse, ni de compararse con la
  ///      nube, ni siquiera de decir "esto cambio despues de la ultima sync".
  /// v13 = VEHÍCULOS DEL CLIENTE: agrega la lista local, que sigue disponible
  ///      al agendar sin depender de la API de catálogo.
  /// v14 = CATALOGOS OFFLINE-FIRST: los cuatro catalogos reciben `sync_status`
  ///      y el tombstone `eliminado_en`; `taller_id` se vuelve obligatorio y la
  ///      unicidad del nombre queda limitada al taller y a filas vigentes.
  ///
  /// OJO: subir la version NO borra la base por si sola, dispara `onUpgrade`, que
  /// es lo que permite a un dispositivo que ya instalo la v1 seguir funcionando.
  /// En la v7 el `onUpgrade` hace `DROP TABLE`, asi que en ESTE caso si borra los
  /// datos, y es intencional (ver [_migrar]).
  static const int _versionBase = 14;

  /// Nombre del indice de [tablaCitas] por fecha.
  ///
  /// Publico y no privado a proposito: las pruebas de migracion lo consultan con
  /// `PRAGMA index_list` para atar el `CREATE INDEX` con la version del esquema.
  /// Un `PRAGMA` escrito a mano en el test con el nombre puesto de cabeza no
  /// comprueba nada, porque pasa igual si el nombre cambia.
  static const String idxCitasFecha = 'idx_citas_fecha';

  static const String tablaCitas = 'citas';
  static const String tablaVehiculos = 'vehiculos';
  static const String colId = 'id';
  static const String colCodigoQr = 'codigo_qr';

  /// Columna nueva en la v7: el 'CITA-0004' que se muestra, separado del UUID.
  static const String colCodigoVisible = 'codigo_visible';

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

  /// Correo del contacto que agendo la cita (v10).
  ///
  /// Va en la cita y no solo en el perfil del cliente porque la cita es el
  /// documento que el taller recibe: `telefono` ya estaba, y sin el correo el
  /// admin no tiene como escribirle a un cliente que solo dejo su direccion.
  ///
  /// `TEXT NOT NULL DEFAULT ''` igual que `telefono`: las citas que ya existen
  /// no tienen correo y no deben romper un SELECT.
  static const String colCorreoCliente = 'correo_cliente';

  static const String colClienteIdVehiculo = 'cliente_id';
  static const String colMarcaVehiculo = 'marca';
  static const String colModeloVehiculo = 'modelo';
  static const String colAnioVehiculo = 'anio';
  static const String colPlacaVehiculo = 'placa';
  static const String colActivoVehiculo = 'activo';

  // ------------------------------------------------------------------
  // SINCRONIZACION (Fase 2)
  //
  // Columna para rastrear el estado de sincronizacion con Firestore.
  // Valores: 'pending' (local creada/modificada, pendiente de subir),
  // 'synced' (coincide con la nube). Se usa en SyncService para saber
  // que filas subir y marcar como subidas tras push exitoso.
  // ------------------------------------------------------------------
  static const String colSyncStatus = 'sync_status';

  // ------------------------------------------------------------------
  // BORRADO LOGICO (v7)
  //
  // Las tres columnas viajan en el mapa de toda escritura de `citas` y los
  // repositorios las filtran. Ver `lib/core/utils/borrado_logico.dart`.
  //
  // `eliminado_por` es TEXT y no INTEGER porque guarda el id del USUARIO que
  // borro, no una fila de una tabla: el usuario de Firebase Auth vive en la nube
  // y no tiene tabla local.
  // ------------------------------------------------------------------

  static const String colEliminadoEn = 'eliminado_en';
  static const String colEliminadoPor = 'eliminado_por';
  static const String colRestauradoEn = 'restaurado_en';

  // ------------------------------------------------------------------
  // Catalogos de Configuracion (v3, con `estados` eliminado en la v7)
  //
  // Los cuatro catalogos que Leandy necesita son el MISMO molde: una lista de
  // nombres que el administrador mantiene. `estados` se elimino por decision de
  // Leandy: los estados de `citas` los define el enum `EstadoCita` y el catalogo
  // era data muerta que ademas contradecía al enum ('En diagnostico' no existe en
  // el enum, 'Esperando pieza' va en minuscula y el mapa de colores matchea por
  // texto EXACTO).
  //
  // `marcas` y `grupos_servicio` son NUEVOS en la v7. Antes eran listas `const`
  // de demostracion en `lib/shared/models/demo_admin_data.dart`: cinco marcas y
  // un grupo, escritos en el codigo, que nadie podia editar y que se perdian en
  // cada rebuild. El punto 6 del encargo define que la fuente es esta base, asi
  // que pasaron a ser filas de verdad con la misma PK UUID que el resto.
  // ------------------------------------------------------------------

  static const String tablaTecnicos = 'tecnicos';
  static const String tablaTiposServicio = 'tipos_servicio';

  /// Marcas de vehiculo. Alta en la v7. Ver `lib/features/configuracion/models/marca.dart`.
  static const String tablaMarcas = 'marcas';

  /// Grupos de servicios ("Carroceria", "Mecanica general"). Alta en la v7.
  /// Ver `lib/features/configuracion/models/grupo_servicio.dart`.
  static const String tablaGruposServicio = 'grupos_servicio';

  // ------------------------------------------------------------------
  // COLA DE CAMBIOS DE CONTRASEÑA (v10)
  //
  // Cuando el cliente pide cambiar su contraseña sin internet, el cambio queda
  // en esta tabla con `sync_status = 'pending'` y lo drena `SyncService` cuando
  // vuelve la conexion, igual que con las citas.
  //
  // OJO con lo que NO esta aca: la contraseña. El secreto vive en
  // `flutter_secure_storage` (ver `CambiosPasswordRepository`) y la fila es
  // solo el indice de "queda un cambio por aplicar". Guardar una contraseña en
  // SQLite en claro -- o peor, subirla a Firestore -- seria regalar la cuenta
  // de alguien, por eso la cola guarda metadata y el secreto va al keystore.
  // ------------------------------------------------------------------
  static const String tablaCambiosPassword = 'cambios_password';
  static const String colCorreoCambioPassword = 'correo_cliente';

  /// Prefijo de la clave de `flutter_secure_storage` bajo la cual se guarda el
  /// secreto de cada fila de la cola: `cambiosPassword.<id>`.
  ///
  /// Esta en `DatabaseHelper` y no adentro del repositorio porque es parte del
  /// contrato entre los dos archivos: si uno cambia el prefijo y el otro no,
  /// la cola queda con filas cuyo secreto nadie puede leer.
  static const String prefijoSeguroCambiosPassword = 'cambiosPassword.';

  static const String colNombre = 'nombre';
  static const String colActivo = 'activo';
  static const String colPrecio = 'precio';

  // ------------------------------------------------------------------
  // Talleres afiliados (v4)
  //
  // Directriz de Leandy: el mapa NO busca talleres libres en el mundo. Solo
  // muestra los que estan en esta tabla, que es la red de afiliados de la
  // empresa. Por eso `talleres` se siembra y se administra, y no se consulta
  // a ningun servicio externo.
  //
  // `citas.taller_id` es lo que ata una cita al taller donde se agenda. Sin
  // esa columna no hay forma de responder "dame las citas del Taller Gomez":
  // el nombre del taller no sirve, porque dos filas con el mismo nombre
  // Serian la misma cita a los ojos del sistema.
  //
  // `taller_id` es TEXT en la v7 (UUID) y NO lleva `REFERENCES`. Ver
  // `_crearTalleres` para por que la FK tampoco va en el indice.
  // ------------------------------------------------------------------

  static const String tablaTalleres = 'talleres';

  static const String colDireccion = 'direccion';
  static const String colLatitud = 'latitud';
  static const String colLongitud = 'longitud';
  static const String colTallerId = 'taller_id';

  // ------------------------------------------------------------------
  // Admins de Modo Desarrollador (v9)
  // ------------------------------------------------------------------
  static const String tablaAdmins = 'admins';
  static const String colAdminUid = 'uid';
  static const String colAdminEmail = 'email';
  static const String colAdminTallerId = 'tallerId';
  static const String colAdminTallerNombre = 'tallerNombre';
  static const String colAdminEliminado = 'eliminado';

  static const Map<String, String> _columnasAdmins = <String, String>{
    colAdminEmail: 'TEXT NOT NULL',
    colAdminTallerId: 'TEXT NOT NULL DEFAULT \'\'',
    colAdminTallerNombre: 'TEXT',
    colCreadoEn: 'TEXT NOT NULL',
    colActualizadoEn: 'TEXT NOT NULL',
    colAdminEliminado: 'INTEGER NOT NULL DEFAULT 0',
  };

  // ------------------------------------------------------------------
  // PERFIL DEL CLIENTE (v12)
  //
  // La tabla que le faltaba a la Fase 3. `Editar Perfil` escribia nombre,
  // correo y telefono en SharedPreferences y ahi terminaba: una preferencia no
  // se puede encolar, no se puede comparar con la nube y no puede decir
  // "esto cambio despues de la ultima sincronizacion". Con `clientes` el
  // perfil pasa a tener el mismo tratamiento que las citas: escritura local
  // inmediata con `sync_status = 'pending'`, y `SyncService` lo sube.
  //
  // OJO con la PK: es el uid de Firebase Auth cuando lo hay, y el CORREO
  // normalizado cuando no (login sin red, contra las credenciales del
  // keystore). Ese segundo caso es exactamente el que la v12 existe para
  // cubrir: el cliente edita su perfil sin internet y todavia no tiene
  // identidad en la nube, pero igual tiene que poder guardarse. La columna
  // `uid` se rellena cuando el push consigue la sesion.
  // ------------------------------------------------------------------
  static const String tablaClientes = 'clientes';
  static const String colUid = 'uid';

  /// Baja logica del perfil, mismo nombre y significado que `admins.eliminado`.
  ///
  /// Se declara aparte de [colAdminEliminado] aunque el texto SQL sea el
  /// mismo: son columnas de tablas distintas y el dia que una de las dos cambie,
  /// que hoy se compartan una constante seria el bug.
  static const String colEliminado = 'eliminado';

  /// Correo del perfil cliente.
  ///
  /// Distinta de [colCorreoCliente] ('correo_cliente'), que es la de
  /// `citas` y de `cambios_password`: alla el correo es METADATO de una cita
  /// que puede pertenecer a cualquiera, aca es la IDENTIDAD del registro.
  /// Mantener los dos nombres separados evita que un dia alguien "unifique
  /// las constantes" y pase a escribir la identidad del cliente en una cita.
  static const String colCorreo = 'correo';

  static const Map<String, String> _columnasClientes = <String, String>{
    colUid: 'TEXT NOT NULL DEFAULT \'\'',
    colCorreo: 'TEXT NOT NULL DEFAULT \'\'',
    colNombre: 'TEXT NOT NULL DEFAULT \'\'',
    colTelefono: 'TEXT NOT NULL DEFAULT \'\'',
    colEliminado: 'INTEGER NOT NULL DEFAULT 0',
    colCreadoEn: 'TEXT NOT NULL DEFAULT \'\'',
    colActualizadoEn: 'TEXT NOT NULL DEFAULT \'\'',
    colSyncStatus: "TEXT NOT NULL DEFAULT 'pending'",
  };

  // `colTelefono` NO se redeclara aca: ya existe arriba para `citas.telefono`, y
  // el mismo nombre de columna significa lo mismo en las dos tablas (el telefono
  // de un contacto, en texto, con guiones). Reutilizar la constante es lo que
  // evita que un dia alguien escriba 'telefono' de una forma y 'fono' otra.

  /// Columnas de `talleres`, en el orden en que se declaran.
  ///
  /// `latitud`/`longitud` son REAL y no INTEGER a proposito: son grados
  /// decimales. Con INTEGER, `18.4184` se trunca a 18 y el taller cae 46 km al
  /// norte, en el Atlantico.
  ///
  /// `telefono` es TEXT y no INTEGER: en Republica Dominicana se escribe con
  /// guiones ('809-555-0101').
  static const Map<String, String> _columnasTalleres = <String, String>{
    colNombre: 'TEXT NOT NULL',
    colDireccion: 'TEXT NOT NULL DEFAULT \'\'',
    colTelefono: 'TEXT NOT NULL DEFAULT \'\'',
    colLatitud: 'REAL NOT NULL DEFAULT 0',
    colLongitud: 'REAL NOT NULL DEFAULT 0',
    colActivo: 'INTEGER NOT NULL DEFAULT 1',
    colCreadoEn: 'TEXT NOT NULL',
    colActualizadoEn: 'TEXT NOT NULL',
  };

  /// Columnas comunes a los catalogos, en el orden en que se declaran.
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
  /// y `_migrarAV2`, que es como se producen los bugs de migracion.
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

  /// Columna que se agrega a `citas` en la v4.
  ///
  /// NULL y no NOT NULL: las citas que ya existen (v1 a v3) no tienen taller, y
  /// las que crea el modulo del escaner QR todavia no lo_eligen. La columna
  /// acepta null hasta que el formulario de David la empiece a mandar.
  ///
  /// OJO: no lleva `REFERENCES talleres(id)`. Ver la nota de `_crearTalleres`
  /// para por que la FK va en el indice y no en la declaracion de la columna.
  ///
  /// En la v7 pasa de INTEGER a TEXT: el id del taller es un UUID, no un
  /// autoincremento local. La nota larga de por que esta columna no puede
  /// seguir siendo un numero esta arriba, en el doc del modelo `Cita`.
  static const String _columnaTallerIdV4 = '$colTallerId TEXT';

  /// Definicion de la PK federada.
  ///
  /// En una constante y no repetida en los tres `CREATE TABLE` porque el error
  /// grave aca es que una tabla quede con la PK vieja: SQLite NO avisa, la tabla
  /// se crea con `INTEGER PRIMARY KEY`, el primer INSERT sin id genera un 1, y
  /// la fila tiene un id "1" que no es un UUID. La app funciona en ese
  /// dispositivo y falla al sincronizar.
  ///
  /// `TEXT NOT NULL` y no solo `TEXT`: una PK sin valor no puede existir, y SQLite
  /// en su modo legacy (el de `PRAGMA legacy_alter_table`) permitiria un `NULL`
  /// en una `PRIMARY KEY` sin declarar `NOT NULL`, que es un hole negro de datos.
  static const String _pkUuid = '$colId TEXT NOT NULL PRIMARY KEY';

  /// Las tres columnas de borrado logico, en el orden en que se declaran.
  ///
  /// Las tres van en `_crearEsquema` y en el `_migrar` desde la v7. No hay que
  /// hacerlas nullable con `ALTER TABLE` porque la tabla se reconstruye entera:
  /// es una de las dos razones por las que la v7 dropea en vez de alterar.
  static const List<String> _columnasTrazabilidad = <String>[
    '$colEliminadoEn TEXT',
    '$colEliminadoPor TEXT',
    '$colRestauradoEn TEXT',
  ];

  /// La carrera de la PRIMERA apertura, no la conexion resuelta.
  ///
  /// Con la version vieja (`_base ??= await _abrir()`) dos primeras lecturas
  /// simultaneas evaluaban la expresion a la vez, ambas veian `_base == null` y
  /// las dos llamaban `_abrir()`: el archivo se abria dos veces, quedaban dos
  /// conexiones compitiendo (riesgo de "database is locked") y una referencia
  /// huérfana que nadie cerraba. Memoizar la Future de la apertura garantiza
  /// una sola apertura compartida por todos los llamadores.
  ///
  /// OJO: la futura memoizada solo se expone mientras esta EN VUELO. Ya
  /// resuelta, [base] devuelve `Future.value(_base)` creada en la zona del
  /// llamador, igual que el getter viejo. Devolver la futura cacheada (creada
  /// en la zona de quien abrio, p. ej. el `setUp` raiz) rompe los tests de
  /// widgets: esperarla desde el `FakeAsync` de `testWidgets` deja la zona
  /// invalida y el siguiente `tester.pump()` se cuelga para siempre.
  Future<Database>? _aperturaEnCurso;

  Future<Database> get base async {
    final resuelta = _base;
    if (resuelta != null) return resuelta;
    return _aperturaEnCurso ??= _abrir().then(
      (db) {
        _aperturaEnCurso = null;
        _base = db;
        return db;
      },
      onError: (Object e, StackTrace s) {
        // Una apertura fallida no se cachea: si se guardara el error, todos los
        // accesos siguientes reutilizarian esa Future muerta y la app quedaria
        // sin base hasta reiniciar. Se descarta y el proximo reintenta.
        _aperturaEnCurso = null;
        Error.throwWithStackTrace(e, s);
      },
    );
  }

  Database? _base;

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
  ///
  /// El parametro es `DatabaseExecutor` y no `Database` a proposito. `onCreate`
  /// recibe un `Database`, que implements `DatabaseExecutor`, asi que el mismo
  /// cuerpo sirve para los dos caminos. Con `Database` el parametro, [_migrarAV7]
  /// no podria llamar a esta funcion: en `onUpgrade` lo que se recibe es el
  /// `DatabaseExecutor` de la transaccion, que es mas estrecho, y Dart no
  /// permite degradarlo a `Database`. La firma aceptaria en `onCreate` y
  /// rechazaria en `onUpgrade`, que es justo el bug que hace que la migracion se
  /// pruebe en un camino que nunca se ejecuta.
  Future<void> _crearEsquema(DatabaseExecutor db) async {
    final definiciones = <String>[
      _pkUuid,
      // codigo_qr ELIMINADO (v5)
      // `codigo_visible` es lo que ve el humano ('CITA-0004'). Nace como
      // 'PENDIENTE' y la nube lo reemplaza por el definitivo.
      //
      // `NOT NULL DEFAULT 'PENDIENTE'` y no nullable: una cita sin numero sigue
      // teniendo ALGO que mostrar, y el default pone ese "algo" en el lugar sin
      // que cada repositorio tenga que acordarse.
      "$colCodigoVisible TEXT NOT NULL DEFAULT 'PENDIENTE'",
      '$colCliente TEXT NOT NULL',
      '$colVehiculo TEXT NOT NULL',
      ..._columnasV2.entries.map((e) => '${e.key} ${e.value}'),
      '$colDescripcion TEXT NOT NULL DEFAULT \'\'',
      '$colFechaCita TEXT NOT NULL',
      '$colEstado TEXT NOT NULL',
      '$colCreadoEn TEXT NOT NULL',
      _columnaTallerIdV4,
      '$colTotal INTEGER NOT NULL DEFAULT 0', // v5
      ..._columnasTrazabilidad, // v7
      // v8 (Fase 2): estado de sincronizacion con Firestore.
      // 'pending' = recien creada/modificada localmente, falta subir.
      // 'synced' = coincide con la nube.
      // Default 'pending' porque toda cita nueva nace local y hay que subirla.
      "$colSyncStatus TEXT NOT NULL DEFAULT 'pending'",
      // v10: correo del contacto. Igual que `telefono`, texto y con default
      // vacio para que las citas viejas no revienten un SELECT.
      "$colCorreoCliente TEXT NOT NULL DEFAULT ''",
    ];

    await db.execute('CREATE TABLE $tablaCitas (${definiciones.join(', ')})');
    // Índice de QR ELIMINADO (v5)

    // `talleres` ANTES que el indice de `citas.taller_id`: una FK necesita que
    // la tabla que referencia exista.
    await _crearTalleres(db);
    await _crearAdmins(db);
    await _crearClientes(db);
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_citas_taller_id '
      'ON $tablaCitas ($colTallerId)',
    );
    // v6. Toda consulta del Dashboard y de la pantalla de Citas filtra por dia
    // con `fecha_cita LIKE 'AAAA-MM-DD%'`, que sin indice es un escaneo
    // secuencial de la tabla completa. Con el volumen de un taller real eso se
    // nota al cambiar de fecha en el calendario.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS $idxCitasFecha '
      'ON $tablaCitas ($colFechaCita)',
    );

    // v7. Indice compuesto para el filtro de papelera. `eliminado_en IS NULL` es
    // la condicion de TODA consulta de la UI (ver `CitaRepository`), y sin indice
    // es un escaneo secuencial. El orden es (eliminado_en, fecha_cita) y no al
    // reves porque el primero es la igualdad y el segundo el rango: SQLite solo
    // puede usar el segundo si el primero ya esta resuelto.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_citas_vigentes '
      'ON $tablaCitas ($colEliminadoEn, $colFechaCita)',
    );

    await _crearCambiosPassword(db);
    await _crearCatalogos(db);
    await _crearVehiculos(db);
    await _sembrarCatalogos(db);
  }

  /// Registro local de vehículos del cliente. Los vehículos son seleccionables
  /// al agendar incluso si la API pública no está disponible.
  Future<void> _crearVehiculos(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tablaVehiculos (
        $colId TEXT NOT NULL PRIMARY KEY,
        $colClienteIdVehiculo TEXT NOT NULL,
        $colMarcaVehiculo TEXT NOT NULL,
        $colModeloVehiculo TEXT NOT NULL,
        $colAnioVehiculo INTEGER NOT NULL,
        $colPlacaVehiculo TEXT NOT NULL DEFAULT '',
        $colActivoVehiculo INTEGER NOT NULL DEFAULT 1,
        $colCreadoEn TEXT NOT NULL,
        $colActualizadoEn TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_vehiculos_cliente_activo '
      'ON $tablaVehiculos ($colClienteIdVehiculo, $colActivoVehiculo)',
    );
  }

  /// Crea la cola de cambios de contraseña pendientes (v10).
  ///
  /// `IF NOT EXISTS` por la misma razon que los catalogos y los talleres: esta
  /// funcion la llaman los dos caminos (creacion nueva y migracion) y no
  /// importa cual llegue primero.
  ///
  /// Sin indice de `sync_status`: la cola tiene como maximo un puñado de filas
  /// (un cambio por cliente) y `WHERE sync_status = 'pending'` sobre eso no
  /// gana nada. El indice de `citas` existe porque esa tabla crece; este no.
  Future<void> _crearCambiosPassword(DatabaseExecutor db) async {
    final definiciones = <String>[
      _pkUuid,
      // Metadatos, no el secreto: la contraseña va en el keystore. Ver el doc
      // de `tablaCambiosPassword`.
      "$colSyncStatus TEXT NOT NULL DEFAULT 'pending'",
      "$colCorreoCambioPassword TEXT NOT NULL DEFAULT ''",
      '$colCreadoEn TEXT NOT NULL',
      '$colActualizadoEn TEXT NOT NULL DEFAULT \'\'',
    ];

    await db.execute(
      'CREATE TABLE IF NOT EXISTS $tablaCambiosPassword '
      '(${definiciones.join(', ')})',
    );
  }

  /// Crea la tabla de talleres afiliados.
  ///
  /// `IF NOT EXISTS` por la misma razon que los catalogos: esta funcion la
  /// llaman los dos caminos (creacion nueva y migracion) y no importa cual
  /// llegue primero.
  ///
  /// Sobre la FK de `citas.taller_id` a `talleres.id`: NO va declarada como
  /// `REFERENCES` en la columna, a proposito. SQLite no permite agregar una
  /// columna con `REFERENCES` usando `ALTER TABLE` si la tabla ya tiene filas, y
  /// mas importante: con `PRAGMA foreign_keys = ON` (que esta activo en
  /// `onConfigure`), una FK restrictiva hace que borrar un taller con historial
  /// falle, y el admin no tiene forma de dar de baja un taller. Por eso la
  /// relacion se garantiza en la aplicacion, no en el motor: el
  /// `TallerRepository` filtra por `activo` y nunca borra fisicamente un taller
  /// que tenga citas. Es la baja logica la que evita perder el historial.
  ///
  /// Y desde la v7 hay una razon mas: la cita puede traer un `taller_id` que
  /// todavia no existe en ESTE dispositivo, porque la cita llego de la nube antes
  /// que el taller. Con FK restrictiva, ese INSERT revienta. Sin FK, la cita se
  /// guarda y el taller aparece cuando llega.
  Future<void> _crearTalleres(DatabaseExecutor db) async {
    final definiciones = <String>[
      _pkUuid,
      ..._columnasTalleres.entries.map((e) => '${e.key} ${e.value}'),
    ];

    await db.execute(
      'CREATE TABLE IF NOT EXISTS $tablaTalleres (${definiciones.join(', ')})',
    );

    // `COLLATE NOCASE` para que el admin no pueda dar de alta "Global Refriauto"
    // y "global refriauto" como dos afiliados distintos. Sin esto, el mapa
    // muestra dos circulos orange en la misma esquina.
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_${tablaTalleres}_nombre '
      'ON $tablaTalleres ($colNombre COLLATE NOCASE)',
    );
  }

  Future<void> _crearAdmins(DatabaseExecutor db) async {
    final definiciones = <String>[
      _pkUuid,
      ..._columnasAdmins.entries.map((e) => '${e.key} ${e.value}'),
    ];

    await db.execute(
      'CREATE TABLE IF NOT EXISTS $tablaAdmins (${definiciones.join(', ')})',
    );

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_${tablaAdmins}_email '
      'ON $tablaAdmins ($colAdminEmail COLLATE NOCASE)',
    );
  }

  /// Crea la tabla de perfil cliente (v12).
  ///
  /// `IF NOT EXISTS` por la misma razon que talleres, admins y catalogos: esta
  /// funcion la llaman los dos caminos (creacion nueva y migracion) y no
  /// importa cual llegue primero.
  ///
  /// El indice UNICO sobre `correo COLLATE NOCASE` es lo que garantiza "una
  /// fila por persona". Hace falta por un camino concreto: el cliente que
  /// edita su perfil SIN red obtiene una fila cuya PK es el correo; si despues
  /// entra CON red y la nube manda el mismo perfil con su uid, un `INSERT` a
  /// ciegas dejaria dos filas para la misma persona. El indice convierte ese
  /// error en un conflicto que el repositorio sabe resolver (primero busca por
  /// `uid`, luego por `correo`). Mismo molde que `idx_talleres_nombre`.
  ///
  /// Sin indice de `sync_status`, por el mismo motivo que en
  /// [_crearCambiosPassword]: es una tabla de una o dos filas.
  Future<void> _crearClientes(DatabaseExecutor db) async {
    final definiciones = <String>[
      _pkUuid,
      ..._columnasClientes.entries.map((e) => '${e.key} ${e.value}'),
    ];

    await db.execute(
      'CREATE TABLE IF NOT EXISTS $tablaClientes (${definiciones.join(', ')})',
    );

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_${tablaClientes}_correo '
      'ON $tablaClientes ($colCorreo COLLATE NOCASE)',
    );
  }

  /// Siembra la red de talleres afiliados.
  ///
  /// El chequeo de vacio por tabla NO es paranoia, es el mismo motivo que en
  /// `_sembrarCatalogos`: los dos caminos pueden correr, y sin el chequeo los
  /// tres talleres se duplican.
  ///
  /// Cada taller recibe un UUID POR FILA, generado aca. No puede ser un
  /// autoincremento (ver la nota del `DatabaseHelper`) y no puede ser una
  /// constante en [SemillaInicial] por una razon concreta: si el id fuera fijo,
  /// dos dispositivos que instalan la app tendrian el "taller 1" con el MISMO id,
  /// lo cual pareceria correcto pero hace que cualquier edicion de un taller se
  /// pise entre dispositivos. Y si fuera aleatorio pero distinto en cada
  /// instalacion, la red de afiliados se multiplicaria por el numero de
  /// instalaciones. La unica forma de tener las dos cosas es un UUID por fila,
  /// generado en la instalacion: unico en el mundo, y replicado desde la nube al
  /// Siembra los talleres iniciales definidos en [SemillaInicial.talleres].
  /// No se ejecuta automáticamente para permitir que los talleres se gestionen dinámicamente.
  Future<void> sembrarTalleres([DatabaseExecutor? db]) async {
    final executor = db ?? await base;
    final existentes = await executor.query(
      tablaTalleres,
      columns: <String>[colId],
      limit: 1,
    );
    if (existentes.isNotEmpty) return;

    final ahora = DateTime.now().toUtc().toIso8601String();

    for (int i = 0; i < SemillaInicial.talleres.length; i++) {
      final t = SemillaInicial.talleres[i];
      await executor.insert(tablaTalleres, <String, Object?>{
        colId: t.id,
        colNombre: t.nombre,
        colDireccion: t.direccion,
        colTelefono: t.telefono,
        colLatitud: t.latitud,
        colLongitud: t.longitud,
        colActivo: 1,
        colCreadoEn: ahora,
        colActualizadoEn: ahora,
      });
    }
  }

  /// Crea los catalogos de Configuracion con el mismo molde.
  ///
  /// `CREATE TABLE IF NOT EXISTS` y no `CREATE TABLE` porque esta misma funcion
  /// la usan los dos caminos: el de una base nueva y el de la migracion. Con el
  /// `IF NOT EXISTS` no importa cual de los dos llegue primero.
  ///
  /// Recibe un [DatabaseExecutor] y no un `Database` porque la creacion inicial
  /// lo llama por fuera de la transaccion y la migracion por dentro: `Database` y
  /// `Transaction` implementan las dos interfaces y asi el codigo se escribe una
  /// sola vez.
  ///
  /// La v7 elimino la llamada a `tablaEstados` de aca. Ver [_migrar].
  ///
  /// Las cuatro tablas del punto 6 se crean con [_crearTablaCatalogo], la misma
  /// funcion que las otras dos. Eso es lo que las mantiene en el mismo molde: si
  /// `marcas` tuviera su propio `CREATE TABLE` a mano, el dia que se le agregue una
  /// columna habria que acordarse de cambiarla en dos lugares, y el que se
  /// olvide produce "no such column" solo en el dispositivo que instalo primero.
  Future<void> _crearCatalogos(DatabaseExecutor db) async {
    await _crearTablaCatalogo(db, tablaTecnicos);
    await _crearTablaCatalogo(
      db,
      tablaTiposServicio,
      columnasExtra: <String>['$colPrecio INTEGER NOT NULL DEFAULT 0'],
    );

    // `marcas` y `grupos_servicio` NO llevan `columnasExtra`: el requisito es
    // 'nombre' y nada mas. Ver `Marca` y `GrupoServicio` para por que no se
    // anticipan columnas que la UI todavia no muestra.
    await _crearTablaCatalogo(db, tablaMarcas);
    await _crearTablaCatalogo(db, tablaGruposServicio);
  }

  Future<void> _crearTablaCatalogo(
    DatabaseExecutor db,
    String tabla, {
    List<String> columnasExtra = const <String>[],
  }) async {
    final definiciones = <String>[
      _pkUuid,
      ..._columnasCatalogo.entries.map((e) => '${e.key} ${e.value}'),
      ...columnasExtra,
      // v9/v14: catalogos aislados por taller. Desde v14 es obligatorio.
      '$colTallerId TEXT NOT NULL',
      "$colSyncStatus TEXT NOT NULL DEFAULT 'pending'",
      '$colEliminadoEn TEXT',
    ];

    await db.execute(
      'CREATE TABLE IF NOT EXISTS $tabla (${definiciones.join(', ')})',
    );

    // `COLLATE NOCASE` compara sin distinguir mayusculas, asi que el indice
    // IMPIDE que existan "Nissan" y "nissan" a la vez. Sin esto, el admin
    // escribia "Toyota" y tres semanas despues "toyota" y le aparecian dos
    // filas identicas en el desplegable de Marcas.
    // Un catalogo puede repetir el mismo nombre en talleres distintos. Las bajas
    // conservan el nombre historico, pero no deben impedir un alta posterior.
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_${tabla}_taller_nombre_vigente '
      'ON $tabla ($colTallerId, $colNombre COLLATE NOCASE) '
      'WHERE $colEliminadoEn IS NULL',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${tabla}_taller_id '
      'ON $tabla ($colTallerId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${tabla}_sync_status '
      'ON $tabla ($colSyncStatus)',
    );
  }

  /// Inserta el catalogo inicial del diseno en los cuatro catalogos.
  ///
  /// El chequeo de vacio por tabla NO es paranoia: la siembran los dos caminos
  /// (creacion y migracion) y nada impide que ambos corran, por ejemplo si un
  /// dispositivo se reinstala sin desinstalar del todo. Sin el `isEmpty`, esos
  /// casos duplicarian los registros iniciales.
  ///
  /// La v7 elimino la siembra de `estados`.
  Future<void> _sembrarCatalogos(DatabaseExecutor db) async {
    final ahora = DateTime.now().toUtc().toIso8601String();

    // `extra` y no un `String? columnaPrecio`: los catalogos son el mismo molde y
    // cada uno aporta sus columnas, asi que el parametro es un mapa y no una
    // lista de casos. Agregar una columna nueva despues no obliga a tocar esto.
    Future<void> sembrar(
      String tabla,
      List<String> nombres,
      List<String> ids, {
      Map<String, Object?> extra = const <String, Object?>{},
    }) async {
      final existentes = await db.query(
        tabla,
        columns: <String>[colId],
        limit: 1,
      );
      if (existentes.isNotEmpty) return;

      for (int i = 0; i < nombres.length; i++) {
        await db.insert(tabla, <String, Object?>{
          colId: ids[i],
          colNombre: nombres[i],
          colActivo: 1,
          ...extra,
          // Las filas bootstrap son idénticas en todas las instalaciones; no
          // son cambios del usuario que deban subir por separado.
          colSyncStatus: 'synced',
          colCreadoEn: ahora,
          colActualizadoEn: ahora,
        });
      }
    }

    // v9: asignar taller_id a las semillas (asignar al primer taller por defecto para demo)
    final tallerIdSemilla = SemillaInicial.talleres.isNotEmpty
        ? SemillaInicial.talleres.first.id
        : null;
    await sembrar(
      tablaTecnicos,
      SemillaInicial.tecnicos,
      SemillaInicial.tecnicosIds,
      extra: <String, Object?>{colTallerId: ?tallerIdSemilla},
    );
    await sembrar(
      tablaTiposServicio,
      SemillaInicial.tiposServicio,
      SemillaInicial.tiposServicioIds,
      extra: <String, Object?>{
        colPrecio: SemillaInicial.precioInicial,
        colTallerId: ?tallerIdSemilla,
      },
    );

    // v7. Las marcas y los grupos que antes eran `const` de demostracion ahora son
    // filas. Se siembran por la misma razon que los otros catalogos: un
    // dispositivo nuevo abre Configuracion y tiene que ver algo, y una lista
    // vacia es indistinguible de "el catalogo esta roto".
    //
    // Y se siembran con el MISMO texto que tenian las listas de demo, para que la
    // pantalla no cambie de aspecto al pasar de `demoMarcasVehiculo` a la tabla.
    await sembrar(
      tablaMarcas,
      SemillaInicial.marcas,
      SemillaInicial.marcasIds,
      extra: <String, Object?>{colTallerId: ?tallerIdSemilla},
    );
    await sembrar(
      tablaGruposServicio,
      SemillaInicial.gruposServicio,
      SemillaInicial.gruposServicioIds,
      extra: <String, Object?>{colTallerId: ?tallerIdSemilla},
    );
  }

  // ------------------------------------------------------------------
  // Semilla de CITAS: la unica que es data de prueba de verdad
  // ------------------------------------------------------------------

  /// Inyecta un lote de citas de demostracion y devuelve cuantas se guardaron.
  ///
  /// A diferencia de `_sembrarCatalogos` y `_sembrarTalleres`, esta NO se llama
  /// desde `_crearEsquema` ni desde `_migrar`, y eso es deliberado:
  ///
  /// - En una instalacion real, el administrador abriria el Dashboard con ~100
  ///   clientes que no existen y una linea de ingresos que no es de nadie, sin
  ///   forma de distinguirla de su negocio real.
  /// - En los tests, `cita_repository_test.dart` asume que una base recien
  ///   creada no tiene citas (`obtenerTodas()` vacio, `length == 2` despues de
  ///   crear dos). Sembrarlas aqui rompe esas tres aserciones.
  ///
  /// Se activa a mano desde `main.dart`, y solo en modo debug. Ver la nota de
  /// `SemillaCitasDemo`.
  ///
  /// El chequeo de vacio es la misma proteccion de las otras semillas: es una
  /// operacion de desarrollo y la segunda llamada no debe duplicar el lote.
  /// Si el taller ya tiene citas propias, no se inyecta nada y se devuelve 0,
  /// porque un `INSERT` encima de data real es indistinguible de un bug.
  static Future<int> sembrarCitasDemo({DateTime? referencia}) async {
    final db = await instance.base;

    final existentes = await db.query(
      tablaCitas,
      columns: <String>[colId],
      limit: 1,
    );
    if (existentes.isNotEmpty) return 0;

    // Los ids de `talleres` se LEEN de la base y no se suponen. Con tres
    // talleres tiene toda la pinta de que el id es 1, 2, 3, y lo es, pero
    // escribirlo a mano ata la semilla a un estado de la base que no depende de
    // ella: el dia que se siembre un cuarto taller o se borre uno, las citas
    // de demostracion apuntan a un taller equivocado sin que nada avise.
    //
    // El `ORDER BY id` que se usaba antes ya no tiene sentido: los ids son
    // UUID, y ordenarlos por texto es ordenarlos al azar. Se ordena por nombre
    // para que el reparto de citas entre talleres sea SIEMPRE el mismo y el test
    // de la semilla pueda afirmar cual es cual.
    final filasTalleres = await db.query(
      tablaTalleres,
      columns: <String>[colId],
      orderBy: '$colNombre COLLATE NOCASE ASC',
    );
    final tallerIds = filasTalleres
        .map((f) => (f[colId] as String))
        .toList(growable: false);

    final citas = SemillaCitasDemo.generar(
      referencia: referencia ?? DateTime.now(),
      tallerIds: tallerIds,
    );

    // En UNA transaccion: ~100 INSERT sueltos abren y cierran el statement uno por
    // uno y se nota el arranque. Ademas, si algo falla a la mitad, la tabla
    // queda con 60 citas y no con un lote coherente.
    await db.transaction((txn) async {
      for (final cita in citas) {
        // El id va en el mapa porque la semilla genera ids deterministas (los
        // necesita el test) y con una PK de TEXT SQLite no los genera solo.
        await txn.insert(tablaCitas, cita.toMap());
      }
    });

    return citas.length;
  }

  /// Borra las citas de demostracion y deja el taller como estaba.
  ///
  /// El reverso de [sembrarCitasDemo], para cuando ya se vio suficiente grafico
  /// de mentira y hay que probar el Dashboard con la data real. Borra TODO lo
  /// que hay en `citas`, no solo el lote demo: no hay forma de distinguir una
  /// fila sembrada de una creada por el admin, y un WHERE que adivinase seria
  /// peor que un borrado honesto.
  ///
  /// Por eso lleva una advertencia en el nombre y no se llama desde ningun
  /// lugar de la app. Y es un `DELETE` fisico a proposito: es una herramienta de
  /// DESARROLLO para limpiar la base local antes de que la sincronizacion suba
  /// cualquier cosa. La app nunca borra fisico; ver `borrado_logico.dart`.
  @visibleForTesting
  static Future<void> limpiarCitasParaPruebas() async {
    final db = await instance.base;
    await db.delete(tablaCitas);
  }

  /// Migracion por pasos: 1 -> 2 agrega columnas a `citas`, 2 -> 3 agrega los
  /// catalogos de Configuracion, 3 -> 4 agrega los talleres afiliados y el
  /// vinculo `citas.taller_id`, 4 -> 5 reconstruye `citas` sin `codigo_qr` y con
  /// `total`, 5 -> 6 agrega el indice de `fecha_cita`, 6 -> 7 reconstruye el
  /// esquema con identidad federada.
  ///
  /// -----------------------------------------------------------------
  /// POR QUE LA v7 DROPEA EN VEZ DE MIGRAR LOS DATOS
  /// -----------------------------------------------------------------
  ///
  /// Esto NO es lo que se hace en una app con usuarios reales, y es importante
  /// que quede escrito por que la decision es correcta AQUI y seria un error en
  /// produccion.
  ///
  /// Una migracion que conserva datos de la v6 a la v7 es imposible de hacer
  /// bien, por tres razones concretas:
  ///
  /// 1. LA PK CAMBIA DE TIPO. La v6 tiene `INTEGER PRIMARY KEY AUTOINCREMENT` con
  ///    valores 1, 2, 3... La v7 quiere TEXT con UUID. SQLite puede copiar un
  ///    entero a TEXT (queda '1'), pero '1' NO es un UUID: si esa cita sube a
  ///    Firestore con docId '1', colisiona con la cita '1' de cualquier otro
  ///    dispositivo. Habria que GENERAR un UUID por fila y reescribir el
  ///    `taller_id` de cada cita para apuntar al UUID nuevo de su taller, y eso es
  ///    una tabla de mapeo que ademas se desincroniza con la nube en cuanto otro
  ///    dispositivo sincroniza sus propias citas viejas.
  ///
  /// 2. LOS ESTADOS DE CONFIGURACION SE ELIMINAN. El catalogo `estados` tiene
  ///    datos que el modulo de Citas nunca leyo (el enum `EstadoCita` manda) y que
  ///    ademas contradicen al enum. No hay nada que conservar.
  ///
  /// 3. LOS DISPOSITIVOS DE PRUEBA TIENEN BASES SUCIAS. Un dispositivo que lleva
  ///    semanas instalaindo la app tiene citas de hace tres semanas, con ids que
  ///    colisionarian entre si al primer `onSnapshot`, y una `codigo_visible` que
  ///    no existe todavia en ninguna parte. Esas filas no aportan nada al
  ///    desarrollo y si estorban: el Dashboard muestra numeros que no son del
  ///    taller.
  ///
  /// El costo de dropear es que un dispositivo con datos REALES pierde el
  /// historial. Por eso la app tiene [limpiarCitasParaPruebas] y por eso, si
  /// algun dia esto se pone en manos de un taller de verdad, lo que corresponde es
  /// una v8 CON migracion de datos (reconstruir la tabla copiando fila por fila y
  /// generando un UUID por fila) mas un export previo. Ese camino esta
  /// preparado: [_crearEsquema] ya es el esquema v7 completo, asi que una v8
  /// seria "crear la tabla nueva con los datos convertidos, copiar, tirar la
  /// vieja", exactamente como hace el paso 5.
  ///
  /// Todo dentro de UNA transaccion: si algo falla, SQLite revierte el paquete
  /// entero y la base queda como estaba. Migrar a medias es peor que no migrar.
  Future<void> _migrar(
    Database db,
    int versionAnterior,
    int versionNueva,
  ) async {
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
        // inicial: si no, el admin veria sus citas pero las dos tarjetas de
        // Configuracion vacias en un taller que ya venia funcionando.
        await _sembrarCatalogos(txn);
      }

      if (versionAnterior < 4) {
        // Orden obligatorio: primero el `ALTER TABLE` de `citas`, despues la
        // tabla `talleres`. Al reves, el indice de `taller_id` no tendria tabla
        // a la que apuntar y el `CREATE INDEX` falla.
        //
        // `taller_id` se agrega con `ALTER TABLE` y NO va en `_crearEsquema` de
        // las versiones viejas: por eso el paso es explicito aqui, en vez de
        // meterse en el bucle de `_columnasV2`.
        await txn.execute(
          'ALTER TABLE $tablaCitas ADD COLUMN $_columnaTallerIdV4',
        );
        await _crearTalleres(txn);
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_citas_taller_id '
          'ON $tablaCitas ($colTallerId)',
        );
      }

      if (versionAnterior < 5) {
        // Eliminar índice de codigo_qr si existe y reconstruir tabla sin codigo_qr + total
        await txn.execute('DROP INDEX IF EXISTS idx_citas_codigo_qr');

        await txn.execute('''
          CREATE TABLE citas_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
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
            actualizado_en TEXT NOT NULL DEFAULT '',
            taller_id INTEGER,
            total INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await txn.execute('''
          INSERT INTO citas_new (
            id, cliente, telefono, vehiculo, marca, modelo, anio, placa,
            servicios, tecnico, descripcion, fecha_cita, estado,
            creado_en, actualizado_en, taller_id, total
          )
          SELECT
            id,
            cliente,
            COALESCE(telefono, '') AS telefono,
            vehiculo,
            COALESCE(marca, '') AS marca,
            COALESCE(modelo, '') AS modelo,
            COALESCE(anio, 0) AS anio,
            COALESCE(placa, '') AS placa,
            COALESCE(servicios, '[]') AS servicios,
            COALESCE(tecnico, '') AS tecnico,
            COALESCE(descripcion, '') AS descripcion,
            fecha_cita,
            estado,
            creado_en,
            COALESCE(actualizado_en, '') AS actualizado_en,
            taller_id,
            0 AS total
          FROM citas
        ''');

        await txn.execute('DROP TABLE citas');
        await txn.execute('ALTER TABLE citas_new RENAME TO citas');
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_citas_taller_id ON citas (taller_id)',
        );
      }

      if (versionAnterior < 6) {
        // DESPUES del paso 5, y esto no es un detalle de orden sin importancia:
        // el paso 5 reconstruye la tabla (DROP TABLE citas + RENAME) para
        // quitar `codigo_qr`. Los indices pertenecen a la tabla, asi que un
        // `CREATE INDEX` puesto antes del paso 5 se va con la tabla vieja y el
        // dispositivo queda migrado a la v6 SIN indice. Un `IF NOT EXISTS` no
        // salva: el nombre del indice desaparecio junto con el, asi que el
        // `IF NOT EXISTS` lo crearia sin problema y nadie veria que el paso
        // corrio en el momento equivocado. Solo el orden lo evita.
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS $idxCitasFecha '
          'ON $tablaCitas ($colFechaCita)',
        );
      }

      if (versionAnterior < 7) {
        await _migrarAV7(txn);
      }

      if (versionAnterior < 8) {
        await _migrarAV8(txn);
      }

      if (versionAnterior < 9) {
        await _migrarAV9(txn);
      }

      if (versionAnterior < 10) {
        await _migrarAV10(txn);
      }
      if (versionAnterior < 11) {
        await _migrarAV11(txn);
      }
      if (versionAnterior < 12) {
        await _migrarAV12(txn);
      }

      if (versionAnterior < 13) {
        await _migrarAV13(txn);
      }

      if (versionAnterior < 14) {
        await _migrarAV14(txn);
      }
    });
  }

  /// Paso 13 -> 14: convierte los catalogos existentes en tablas offline-first.
  ///
  /// Se reconstruyen para poder declarar `taller_id NOT NULL` en SQLite y se
  /// copian los datos de cada fila (incluyendo sus UUID y precios). Una fila
  /// legacy sin taller se asigna al primer taller estable de la semilla. Las
  /// filas preexistentes nacen `pending` para que el primer login admin las
  /// publique en Firestore.
  Future<void> _migrarAV14(DatabaseExecutor txn) async {
    for (final tabla in <String>[
      tablaTecnicos,
      tablaTiposServicio,
      tablaMarcas,
      tablaGruposServicio,
    ]) {
      await _migrarTablaCatalogoAV14(
        txn,
        tabla,
        tienePrecio: tabla == tablaTiposServicio,
      );
    }
  }

  Future<void> _migrarTablaCatalogoAV14(
    DatabaseExecutor txn,
    String tabla, {
    required bool tienePrecio,
  }) async {
    final info = await txn.rawQuery('PRAGMA table_info($tabla)');
    final columnas = info.map((fila) => fila['name'] as String).toSet();
    String valor(String columna, String alternativo) =>
        columnas.contains(columna) ? columna : alternativo;

    final temporal = '${tabla}_v14';
    final precioDef = tienePrecio
        ? ', $colPrecio INTEGER NOT NULL DEFAULT 0'
        : '';
    await txn.execute('DROP INDEX IF EXISTS idx_${tabla}_nombre');
    await txn.execute(
      'DROP INDEX IF EXISTS idx_${tabla}_taller_nombre_vigente',
    );
    await txn.execute('DROP INDEX IF EXISTS idx_${tabla}_taller_id');
    await txn.execute('DROP INDEX IF EXISTS idx_${tabla}_sync_status');
    await txn.execute('DROP TABLE IF EXISTS $temporal');
    await txn.execute('''
      CREATE TABLE $temporal (
        $_pkUuid,
        $colNombre TEXT NOT NULL,
        $colActivo INTEGER NOT NULL DEFAULT 1,
        $colCreadoEn TEXT NOT NULL,
        $colActualizadoEn TEXT NOT NULL,
        $colTallerId TEXT NOT NULL
        $precioDef,
        $colSyncStatus TEXT NOT NULL DEFAULT 'pending',
        $colEliminadoEn TEXT
      )
    ''');

    final columnasDestino = <String>[
      colId,
      colNombre,
      colActivo,
      colCreadoEn,
      colActualizadoEn,
      colTallerId,
      if (tienePrecio) colPrecio,
      colSyncStatus,
      colEliminadoEn,
    ];
    final tallerFallback = "'${SemillaInicial.talleres.first.id}'";
    final valores = <String>[
      valor(colId, "''"),
      valor(colNombre, "''"),
      'COALESCE(${valor(colActivo, '1')}, 1)',
      "COALESCE(${valor(colCreadoEn, "''")}, '')",
      "COALESCE(${valor(colActualizadoEn, "''")}, '')",
      'COALESCE(NULLIF(${valor(colTallerId, 'NULL')}, \'\'), $tallerFallback)',
      if (tienePrecio) 'COALESCE(${valor(colPrecio, '0')}, 0)',
      "COALESCE(${valor(colSyncStatus, "'pending'")}, 'pending')",
      valor(colEliminadoEn, 'NULL'),
    ];
    await txn.execute(
      'INSERT INTO $temporal (${columnasDestino.join(', ')}) '
      'SELECT ${valores.join(', ')} FROM $tabla',
    );
    await txn.execute('DROP TABLE $tabla');
    await txn.execute('ALTER TABLE $temporal RENAME TO $tabla');

    await txn.execute(
      'CREATE UNIQUE INDEX idx_${tabla}_taller_nombre_vigente '
      'ON $tabla ($colTallerId, $colNombre COLLATE NOCASE) '
      'WHERE $colEliminadoEn IS NULL',
    );
    await txn.execute(
      'CREATE INDEX idx_${tabla}_taller_id ON $tabla ($colTallerId)',
    );
    await txn.execute(
      'CREATE INDEX idx_${tabla}_sync_status ON $tabla ($colSyncStatus)',
    );
  }

  /// Paso 6 -> 7: identidad federada (UUID), codigo visible, borrado logico y
  /// purga de los estados de configuracion.
  ///
  /// Se hace `DROP TABLE` y no `ALTER TABLE`, por la razon larga del doc de
  /// [_migrar]: cambiar el tipo de la PK conservando los datos deja ids enteros
  /// disfrazados de texto, que colisionan al subir a Firestore.
  ///
  /// Los `DROP` van con `IF EXISTS` aunque se sepa que las tablas estan: el
  /// recorrido de versiones de la v3 creaba `estados`, y un dispositivo que
  /// nunca instalo la v3 no la tiene. Un `DROP TABLE estados` sin `IF EXISTS`
  /// revienta la transaccion entera y deja el dispositivo en la v6 para siempre.
  ///
  /// Y el orden importa: primero se borran las tablas viejas, despues se
  /// recrean TODAS con `_crearEsquema`, y al final se siembran. Recrear y sembrar
  /// en el mismo paso es lo que garantiza que un dispositivo migrado quede igual
  /// que uno recien instalado, que es lo que evita el bug de "a mi telefono le
  /// faltan los talleres y al otro no".
  Future<void> _migrarAV7(DatabaseExecutor txn) async {
    // 1. Purga de la tabla que Leandy elimino de la app. Va PRIMERO para que
    //    una falla en cualquiera de los pasos siguientes no deje `estados` viva:
    //    una base a medio migrada con la tabla vieja es mas dificil de
    //    diagnosticar que una base intacta.
    await txn.execute('DROP TABLE IF EXISTS estados');

    // 2. Las tablas que cambian de identidad. El orden entre ellas es
    //    irrelevante (no hay FK declarada) pero se hace citas -> talleres ->
    //    catalogos para que se lea en el mismo orden que `_crearEsquema`.
    await txn.execute('DROP TABLE IF EXISTS $tablaCitas');
    await txn.execute('DROP TABLE IF EXISTS $tablaTalleres');
    await txn.execute('DROP TABLE IF EXISTS $tablaTecnicos');
    await txn.execute('DROP TABLE IF EXISTS $tablaTiposServicio');

    // `marcas` y `grupos_servicio` son NUEVAS en la v7, asi que en theory no hay
    // nada que dropear. El `IF EXISTS` va igual, y por el mismo motivo que en
    // `estados`: este mismo archivo pudo correr una version de la v7 a medio
    // desarrollar que ya las habia creado, y un `DROP TABLE marcas` sin `IF
    // EXISTS` revienta la transaccion entera y deja ese dispositivo con la base a
    // medio migrar, que es mas dificil de diagnosticar que una base intacta.
    await txn.execute('DROP TABLE IF EXISTS $tablaMarcas');
    await txn.execute('DROP TABLE IF EXISTS $tablaGruposServicio');

    // Los indices cuelgan de las tablas, asi que `DROP TABLE` ya los borro. El
    // `IF EXISTS` de los indices de todas formas es lo que permite correr este
    // paso sobre una base donde la tabla NO existia pero el indice si (una
    // creacion a medias anterior).
    await txn.execute('DROP INDEX IF EXISTS $idxCitasFecha');
    await txn.execute('DROP INDEX IF EXISTS idx_citas_taller_id');
    await txn.execute('DROP INDEX IF EXISTS idx_citas_vigentes');

    // 3. Recrear con el esquema v7 completo. `_crearEsquema` es la MISMA funcion
    //    que usa `onCreate`, y esa es la garantia de que las dos rutas producen
    //    el mismo esquema. Si `_crearEsquema` tuviera una version propia para
    //    migrar, serian dos esquemas que se desincronizan.
    await _crearEsquema(txn);

    // 4. Las semillas ya corrieron dentro de `_crearEsquema`. `_sembrarTalleres`
    //    y `_sembrarCatalogos` hacen su propio chequeo de vacio, asi que el
    //    doble chequeo es inofensivo y hace que este paso se lea solo.
  }

  /// Paso 7 -> 8: Sincronizacion (Fase 2).
  ///
  /// Agrega la columna `sync_status` a la tabla `citas` SOLO si no existe.
  /// La v7 ya la crea en `_crearEsquema`, asi que esta migracion solo es
  /// necesaria para dispositivos que actualicen desde v6 o anterior sin pasar
  /// por v7 (saltan directo a v8). Usa `PRAGMA table_info` para verificar.
  Future<void> _migrarAV8(DatabaseExecutor txn) async {
    final info = await txn.rawQuery('PRAGMA table_info($tablaCitas)');
    final tieneSyncStatus = info.any((c) => c['name'] == colSyncStatus);

    if (!tieneSyncStatus) {
      await txn.execute(
        'ALTER TABLE $tablaCitas ADD COLUMN $colSyncStatus TEXT NOT NULL DEFAULT \'pending\'',
      );
    }

    // Indice para filtrar rapidamente las citas pendientes de subir.
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_citas_sync_status '
      'ON $tablaCitas ($colSyncStatus)',
    );
  }

  /// Paso 8 -> 9: Aislamiento por taller (v9) + tabla local de admins para devmode sync.
  ///
  /// Agrega columna `taller_id` a las 4 tablas de catalogo SOLO si no existe.
  /// Usa `ALTER TABLE ADD COLUMN` como se solicito (Opcion A).
  /// También crea la tabla local de admins para devmode sync.
  Future<void> _migrarAV9(DatabaseExecutor txn) async {
    // tecnicos
    final infoTecnicos = await txn.rawQuery(
      'PRAGMA table_info($tablaTecnicos)',
    );
    if (!infoTecnicos.any((c) => c['name'] == colTallerId)) {
      await txn.execute(
        'ALTER TABLE $tablaTecnicos ADD COLUMN $colTallerId TEXT',
      );
    }
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_${tablaTecnicos}_taller_id ON $tablaTecnicos ($colTallerId)',
    );

    // tipos_servicio
    final infoTipos = await txn.rawQuery(
      'PRAGMA table_info($tablaTiposServicio)',
    );
    if (!infoTipos.any((c) => c['name'] == colTallerId)) {
      await txn.execute(
        'ALTER TABLE $tablaTiposServicio ADD COLUMN $colTallerId TEXT',
      );
    }
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_${tablaTiposServicio}_taller_id ON $tablaTiposServicio ($colTallerId)',
    );

    // marcas
    final infoMarcas = await txn.rawQuery('PRAGMA table_info($tablaMarcas)');
    if (!infoMarcas.any((c) => c['name'] == colTallerId)) {
      await txn.execute(
        'ALTER TABLE $tablaMarcas ADD COLUMN $colTallerId TEXT',
      );
    }
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_${tablaMarcas}_taller_id ON $tablaMarcas ($colTallerId)',
    );

    // grupos_servicio
    final infoGrupos = await txn.rawQuery(
      'PRAGMA table_info($tablaGruposServicio)',
    );
    if (!infoGrupos.any((c) => c['name'] == colTallerId)) {
      await txn.execute(
        'ALTER TABLE $tablaGruposServicio ADD COLUMN $colTallerId TEXT',
      );
    }
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_${tablaGruposServicio}_taller_id ON $tablaGruposServicio ($colTallerId)',
    );

    await _crearAdmins(txn);
  }

  /// Paso 9 -> 10: perfil del cliente y cola de contraseñas (v10).
  ///
  /// Dos cosas aditivas y ninguna destructiva:
  ///
  /// 1. `citas.correo_cliente` con `ALTER TABLE ADD COLUMN` (mismo patron que
  ///    la v8 y la v9), protegido por `PRAGMA table_info` para que correr dos
  ///    veces -- o una v9 que ya la trajo -- no revierta la transaccion.
  /// 2. La tabla `cambios_password`, nueva, con `CREATE TABLE IF NOT EXISTS`;
  ///    si se creó antes de asociar cada secreto a un correo, se añade esa
  ///    columna para no aplicar por accidente el cambio a otra cuenta.
  ///
  /// A diferencia de la v7, NO se dropea nada: el correo entra como columna
  /// nueva con default vacio y las citas viejas quedan igual que antes.
  Future<void> _migrarAV10(DatabaseExecutor txn) async {
    final info = await txn.rawQuery('PRAGMA table_info($tablaCitas)');
    if (!info.any((c) => c['name'] == colCorreoCliente)) {
      await txn.execute(
        "ALTER TABLE $tablaCitas ADD COLUMN $colCorreoCliente TEXT NOT NULL DEFAULT ''",
      );
    }

    await _crearCambiosPassword(txn);
  }

  /// Paso 10 -> 11: asocia cada cambio en cola a la cuenta cliente correcta.
  ///
  /// El secreto sigue fuera de SQLite; solo se añade el correo como metadata
  /// para impedir que SyncService aplique una contraseña pendiente a la cuenta
  /// Firebase de otro usuario que haya iniciado sesión en este dispositivo.
  Future<void> _migrarAV11(DatabaseExecutor txn) async {
    final infoCambios = await txn.rawQuery(
      'PRAGMA table_info($tablaCambiosPassword)',
    );
    if (!infoCambios.any((c) => c['name'] == colCorreoCambioPassword)) {
      await txn.execute(
        "ALTER TABLE $tablaCambiosPassword "
        "ADD COLUMN $colCorreoCambioPassword TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  /// Paso 11 -> 12: tabla `clientes`, el perfil del cliente offline-first.
  ///
  /// Solo crea tablas nuevas, igual que la v10 y a diferencia de la v7: no hay
  /// nada que transformar porque antes no existia una copia local del perfil.
  /// Lo que SI existia (SharedPreferences) queda intacto: es la lectura rapida
  /// que usan el saludo del AppBar y el prellenado del formulario, y seguir
  /// funcionando sin tocarla es lo que hace que esta migracion sea inocua.
  ///
  /// `_crearClientes` trae el `IF NOT EXISTS` y el indice unico por correo, de
  /// modo que un dispositivo que ya tuviera la tabla por una corrida previa de
  /// una v12 en desarrollo no revienta la transaccion.
  Future<void> _migrarAV12(DatabaseExecutor txn) async {
    await _crearClientes(txn);
  }

  /// Paso 12 -> 13: lista local de vehículos por cliente.
  ///
  /// Solo agrega una tabla, sin alterar las citas ni descartar datos existentes.
  Future<void> _migrarAV13(DatabaseExecutor txn) async {
    await _crearVehiculos(txn);
  }

  Future<void> cerrar() async {
    final apertura = _aperturaEnCurso;
    _aperturaEnCurso = null;
    try {
      if (apertura != null) {
        // Habia una apertura en vuelo: esperarla y cerrar la conexion que
        // llegue, para que no quede un archivo abierto huérfano.
        final db = await apertura;
        await db.close();
      } else if (_base != null) {
        await _base!.close();
      }
    } catch (_) {
      // Si la apertura fallo (o nunca llego a completarse) no hay conexion
      // que cerrar; el cache ya quedo limpio arriba.
    }
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

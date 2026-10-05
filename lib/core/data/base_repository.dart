/// Contrato minimo de una entidad persistible.
///
/// Existe para poder escribir `BaseRepository<T>` generico. Le piden solo dos
/// cosas: un id (para leer y borrar) y `actualizadoEn` (la sincronizacion va a
/// comparar por ese campo). No se hereda de nada ni importa sqflite, asi que
/// cumplirlo no arrastra la capa de datos adentro del dominio.
///
/// CAMBIO v7: `id` paso de `int?` a `String?`.
///
/// El cambio no es cosmetico. Con `int?`, cada dispositivo numeraba sus filas
/// desde 1 por su cuenta, asi que el mismo taller, la misma cita y el mismo
/// tecnico tenian tres identidades distintas segun en que celular se crearan. En
/// una app sin nube eso no se notaba; al sincronizar, "la cita 7" del dispositivo
/// A pisaba "la cita 7" del dispositivo B y un taller aparecia con el historial
/// de otro.
///
/// Con un UUID el id se genera en el cliente, sin pedir nada al servidor, y es
/// el mismo en todas partes. La consecuencia es que ya NO se puede usar el id como
/// numero visible, y por eso `Cita` tiene ademas `codigoVisible`. Ver
/// `lib/core/utils/uuid.dart`.
abstract class EntidadPersistida {
  /// UUID v4 de la fila, o `null` si todavia no se guardo.
  String? get id;

  /// Ultima escritura, en UTC.
  ///
  /// La sincronizacion compara por este campo para decidir que version gana cuando
  /// dos dispositivos tocaron la misma fila. Por eso no puede quedar jamas null en
  /// una fila guardada: [toMap] lo sella con [Reloj] en cada escritura.
  DateTime? get actualizadoEn;
}

/// Esqueleto del patron Repositorio base.
///
/// Cada modulo funcional extiende esto y recibe la misma API, de modo que un
/// controlador no distingue si sus datos salen de SQLite o de la nube.
///
/// `actualizar` y `eliminar` devuelven cuantas filas tocaron: 0 significa "el id
/// no existia", y un update que no hace nada hay que reportarlo, no tragarlo.
abstract class BaseRepository<T extends EntidadPersistida> {
  /// Nombre de la tabla. La capa de sincronizacion la necesita para resolver
  /// los nombres de tabla contra la base de la nube.
  String get tabla;

  /// Guarda la entidad y devuelve el id con el que quedo.
  ///
  /// CAMBIO v7: devuelve `String`, no `int`, y el id lo genera el REPOSITORIO.
  ///
  /// Que lo genere el repositorio y no el controller es lo que hace que ningun
  /// call site pueda olvidarse: hay un solo lugar que sabe que hay que pedir un
  /// UUID. Ademas el repositorio es el unico que puede devolver algo distinto de
  /// lo que recibio (un id que la base asigno, o una colision que se resolvio
  /// reintentando), y si el id lo eligiera el caller, esa correccion no tendria
  /// por donde volver.
  ///
  /// Recibe la entidad SIN id, la completa y la persiste. Si la entidad ya trae
  /// id (una cita que se edita, un documento que baja de Firestore), se respeta
  /// el que trae.
  Future<String> crear(T entidad);

  /// Lanza `ArgumentError` si la entidad no tiene id, en vez de fallar en
  /// silencio contra una fila que no existe.
  Future<int> actualizar(T entidad);

  Future<List<T>> obtenerTodas();

  /// Una entidad por id, o `null` si no existe.
  ///
  /// Vive en el contrato y no en cada repositorio porque el formulario de
  /// edicion la necesita SIEMPRE: abrir "editar cita 3" tiene que poder leer la
  /// cita por id. Si el metodo quedara solo en `CitaRepository`, el controller
  /// tendria que hacer `is` para poder compilar contra el tipo generico, y cada
  /// repositorio nuevo seria una excepcion que alguien tiene que acordarse.
  ///
  /// CAMBIO v7: el parametro paso de `int` a `String` por la misma razon que
  /// [EntidadPersistida.id].
  ///
  /// Que devuelva `null` y no lance es lo que permite tratar "no existe" como un
  /// caso normal: el `id` de una pantalla viene de una sesion vieja, o de un
  /// documento que se borro en otro dispositivo, y eso no es un error de
  /// programacion sino de la vida real.
  Future<T?> obtenerPorId(String id);

  /// 0 filas = el id no existia.
  Future<int> eliminar(String id);
}

/// Contrato minimo de una entidad persistible.
///
/// Existe para poder escribir `BaseRepository<T>` generico. Le piden solo dos
/// cosas: un id (para leer y borrar) y `actualizadoEn` (la sincronizacion va a
/// comparar por ese campo). No se hereda de nada ni importa sqflite, asi que
/// cumplirlo no arrastra la capa de datos adentro del dominio.
abstract class EntidadPersistida {
  int? get id;
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

  /// Devuelve el id autogenerado y no la entidad: recien insertada todavia no
  /// existe como objeto con id.
  Future<int> crear(T entidad);

  /// Lanza `ArgumentError` si la entidad no tiene id, en vez de fallar en
  /// silencio contra una fila que no existe.
  Future<int> actualizar(T entidad);

  Future<List<T>> obtenerTodas();

  Future<T?> obtenerPorId(int id);

  /// 0 filas = el id no existia.
  Future<int> eliminar(int id);
}

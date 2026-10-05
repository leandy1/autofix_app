import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;

import 'package:autofix/features/configuracion/data/grupo_servicio_repository.dart';
import 'package:autofix/features/configuracion/data/marca_repository.dart';
import 'package:autofix/features/configuracion/data/tecnico_repository.dart';
import 'package:autofix/features/configuracion/data/tipo_servicio_repository.dart';
import 'package:autofix/features/configuracion/models/grupo_servicio.dart';
import 'package:autofix/features/configuracion/models/marca.dart';
import 'package:autofix/features/configuracion/models/tecnico.dart';
import 'package:autofix/features/configuracion/models/tipo_servicio.dart';

/// Estado y logica de la pantalla de Configuracion.
///
/// Es la unica capa que la vista conoce. Leandy engancha su diseño a este
/// `ChangeNotifier` sin tocar la vista actual ni los repositorios.
///
/// -----------------------------------------------------------------
/// LA API QUE NECESITA LEANDY (punto 6 del encargo)
/// -----------------------------------------------------------------
///
/// Los cuatro catalogos que pide, con el estado de cada uno:
///
/// | Catalogo        | Tipo             | Repo                     | Estado            |
/// |-----------------|------------------|--------------------------|-------------------|
/// | Tipos de servicio | `TipoServicio` | `TipoServicioRepository` | completo, con precio |
/// | Tecnicos        | `Tecnico`        | `TecnicoRepository`      | completo           |
/// | Marcas          | `Marca`          | `MarcaRepository`        | NUEVO en la v7     |
/// | Grupos de servicio | `GrupoServicio` | `GrupoServicioRepository` | NUEVO en la v7    |
///
/// Para los cuatro hay los mismos tres getters (`marcas`, `tecnicos`,
/// `tiposServicio`, `gruposServicio`), los mismos tres metodos de escritura
/// (`guardarX`, `eliminarX`) y el mismo manejo de errores en [error]. Cuando
/// Leandy conecte su UI no tiene que preguntar nada: todos devuelven `bool` y
/// dejan el motivo en [error].
///
/// Lo que NO esta es la relacion grupo -> servicios. Necesita una tabla puente y
/// la decision de si un servicio puede estar en varios grupos. Ver el doc de
/// [GrupoServicio].
///
/// -----------------------------------------------------------------
/// UN CONTROLLER PARA LOS CUATRO
/// -----------------------------------------------------------------
///
/// Uno solo y no cuatro porque la pantalla es UNA pagina con una sola
/// `initState`: cuatro controllers obligarian a la vista a escuchar cuatro
/// `ListenableBuilder` y a coordinar cuatro estados de carga para, al final,
/// pintar cuatro listas en la misma pantalla.
///
/// ESTADOS: antes manejaba tres catalogos y el tercero era `EstadoConfig`, el
/// estado configurable de una orden. Ese catalogo se elimino (commit `5f5e676` ya
/// habia quitado su seccion de la UI) porque un taller autoFixed no puede estar
/// "en espera" de que otro lo mueva: o entra hoy o no entra. El estado de una
/// cita es un `enum` cerrado en `Cita.estado`, no una fila de tabla, y por eso no
/// se puede administers, ni sincronizar, ni dejar en un estado invalido escrito a
/// mano en la base. Ver `lib/features/citas/models/cita.dart`.
///
/// No expone `Color` ni `Widget`: devuelve entidades y texto ya formateado. El
/// mapeo a color es del diseño, no del dominio.
class ConfiguracionController extends ChangeNotifier {
  /// Los cuatro repositorios son inyectables para que un test pueda pasar un
  /// doble sin tocar la base. Todos son opcionales y por defecto caen al
  /// singleton, asi que la vista hace `ConfiguracionController()` y listo.
  ConfiguracionController({
    TecnicoRepository? tecnicos,
    TipoServicioRepository? servicios,
    MarcaRepository? marcas,
    GrupoServicioRepository? grupos,
  }) : _repoTecnicos = tecnicos ?? TecnicoRepository.instance,
       _repoServicios = servicios ?? TipoServicioRepository.instance,
       _repoMarcas = marcas ?? MarcaRepository.instance,
       _repoGrupos = grupos ?? GrupoServicioRepository.instance;

  final TecnicoRepository _repoTecnicos;
  final TipoServicioRepository _repoServicios;
  final MarcaRepository _repoMarcas;
  final GrupoServicioRepository _repoGrupos;

  /// Formateador de miles. Sin locale explicito a proposito: el separador de
  /// miles por defecto de `intl` ya sale con coma ('1,200') sin pedirle que
  /// cargue locale data para un idioma que la app no usa.
  late final NumberFormat _dinero = NumberFormat('#,##0');

  List<Tecnico> _tecnicos = const <Tecnico>[];
  List<TipoServicio> _tiposServicio = const <TipoServicio>[];
  List<Marca> _marcas = const <Marca>[];
  List<GrupoServicio> _gruposServicio = const <GrupoServicio>[];

  bool _cargando = true;
  String? _error;

  /// Los cuatro getters devuelven listas NO modificables a proposito: son
  /// `List.unmodifiable`, no la lista interna. La UI puede ordenar o filtrar para
  /// pintar, pero no puede `sort()` la lista del controller, que dejaria las
  /// cuatro listas en un orden que la base no tiene y que el proximo `cargar()`
  /// revertsira.
  List<Tecnico> get tecnicos => List.unmodifiable(_tecnicos);
  List<TipoServicio> get tiposServicio => List.unmodifiable(_tiposServicio);
  List<Marca> get marcas => List.unmodifiable(_marcas);
  List<GrupoServicio> get gruposServicio => List.unmodifiable(_gruposServicio);

  bool get cargando => _cargando;

  /// Ultimo error, en texto que se puede mostrar tal cual en un SnackBar.
  /// `null` cuando la ultima operacion salio bien.
  String? get error => _error;

  // ---------------------------------------------------------------------
  // Formato
  // ---------------------------------------------------------------------

  /// 'RD\$ 1,200'. Vive en el controller y no en la vista para que el formato no
  /// se repita por cada tarjeta, y para que un cambio de moneda o de separador
  /// se cambie en un solo lugar.
  ///
  /// Sin decimales a proposito: los precios se guardan enteros y el diseno los
  /// muestra sin centavos.
  ///
  /// El 0 se muestra como 'RD$ -' y no como 'RD$ 0' porque significan cosas
  /// distintas: 0 es "el admin todavia no le puso precio" (asi nace la semilla,
  /// igual que en el diseno) y no "este trabajo sale gratis". Ponerlo en cero de
  /// verdad dejaria al admin cobrando RD$ 0 sin querer.
  String formatearPrecio(int precio) =>
      precio == 0 ? 'RD\$ -' : 'RD\$ ${_dinero.format(precio)}';

  /// Convierte lo que escribio el usuario en el campo de precio a un entero.
  ///
  /// El campo del diseno es libre y la gente escribe '1200', '1,200', 'RD$ 1200'
  /// o '$1200'. Se descarta todo lo que no sea digito. Si no queda nada, `null`:
  /// es preferible que el controller diga "precio invalido" a guardar 0 en
  /// silencio y que el admin descubra el error cuando le cuadre la factura.
  static int? leerPrecio(String? texto) {
    if (texto == null) return null;
    final digitos = texto.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.isEmpty) return null;
    return int.tryParse(digitos);
  }

  // ---------------------------------------------------------------------
  // Lectura
  // ---------------------------------------------------------------------

  Future<void> cargar() async {
    _cargando = true;
    _error = null;
    notifyListeners();

    try {
      // Las cuatro se piden juntas: son de la misma base y del mismo tamano de
      // dato. Pedirlas en paralelo evita los cuatro viajes de ida y vuelta, y con
      // `sqflite` el viaje no es gratis: cada uno reabre el statement.
      //
      // El orden de los resultados es el orden de esta lista, y por eso se
      // castean por posicion y NO por nombre. Con cuatro castings a `List<...>`
      // un desordene aca asigna la lista de marcas a la de grupos y no da ningun
      // error: los dos son `List<dynamic>` en la firma de `Future.wait` y el
      // casteo pasa igual. Ver el doc de [Future.wait] sobre el tipo de la lista.
      final resultados = await Future.wait(<Future<Object?>>[
        _repoTecnicos.obtenerTodas(),
        _repoServicios.obtenerTodas(),
        _repoMarcas.obtenerTodas(),
        _repoGrupos.obtenerTodas(),
      ]);

      _tecnicos = resultados[0] as List<Tecnico>;
      _tiposServicio = resultados[1] as List<TipoServicio>;
      _marcas = resultados[2] as List<Marca>;
      _gruposServicio = resultados[3] as List<GrupoServicio>;
      _error = null;
    } on Exception catch (e) {
      _error = _mensajeDe(e);
    }

    _cargando = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Escritura
  // ---------------------------------------------------------------------

  /// CREATE si no tiene id, UPDATE si lo tiene: el mismo metodo para los dos
  /// casos, que es como decide el formulario.
  ///
  /// Aplica `trim` a [nombre]: el admin escribe 'Nissan ' con el espacio de
  /// siempre pegado, y sin trim eso crea una fila que el UNIQUE no detecta como
  /// duplicada de 'Nissan'.
  Future<bool> guardarTecnico(String nombre) async {
    final limpio = _validarNombre(nombre);
    if (limpio == null) return false;
    // `Future<String>` y no `Future<int>`: desde la v7 `crear` devuelve el UUID
    // generado. `_escribir` no usa el valor devuelto (despues relee la lista
    // entera), asi que el tipo solo tiene que ser compatible.
    return _escribir(
      () => _repoTecnicos.crear(Tecnico(nombre: limpio)),
      () async {
        _tecnicos = await _repoTecnicos.obtenerTodas();
      },
    );
  }

  Future<bool> guardarTipoServicio(String nombre, String? precioTexto) async {
    final limpio = _validarNombre(nombre);
    if (limpio == null) return false;

    final precio = leerPrecio(precioTexto);
    if (precio == null) {
      _error = 'Escribe un precio válido, por ejemplo 1200.';
      notifyListeners();
      return false;
    }

    return _escribir(
      () => _repoServicios.crear(TipoServicio(nombre: limpio, precio: precio)),
      () async => _tiposServicio = await _repoServicios.obtenerTodas(),
    );
  }

  /// Alta de marca. El mismo contrato que [guardarTecnico]: nombre limpio,
  /// error en [_error] y `bool` de salida.
  Future<bool> guardarMarca(String nombre) async {
    final limpio = _validarNombre(nombre);
    if (limpio == null) return false;
    return _escribir(
      () => _repoMarcas.crear(Marca(nombre: limpio)),
      () async => _marcas = await _repoMarcas.obtenerTodas(),
    );
  }

  /// Alta de grupo de servicios. Sin precio: un grupo no se cobra, agrupa.
  Future<bool> guardarGrupoServicio(String nombre) async {
    final limpio = _validarNombre(nombre);
    if (limpio == null) return false;
    return _escribir(
      () => _repoGrupos.crear(GrupoServicio(nombre: limpio)),
      () async => _gruposServicio = await _repoGrupos.obtenerTodas(),
    );
  }

  Future<bool> eliminarTecnico(String id) => _escribir(
    () => _repoTecnicos.eliminar(id),
    () async => _tecnicos = await _repoTecnicos.obtenerTodas(),
  );

  Future<bool> eliminarTipoServicio(String id) => _escribir(
    () => _repoServicios.eliminar(id),
    () async => _tiposServicio = await _repoServicios.obtenerTodas(),
  );

  /// Borrado fisico de la marca. Para una baja que deba conservar el historial
  /// existe `MarcaRepository.darDeBaja`, que marca `activo = 0`; la UI decide
  /// cual de los dos usar y el controller no lo esconde.
  Future<bool> eliminarMarca(String id) => _escribir(
    () => _repoMarcas.eliminar(id),
    () async => _marcas = await _repoMarcas.obtenerTodas(),
  );

  Future<bool> eliminarGrupoServicio(String id) => _escribir(
    () => _repoGrupos.eliminar(id),
    () async => _gruposServicio = await _repoGrupos.obtenerTodas(),
  );

  // ---------------------------------------------------------------------
  // Internos
  // ---------------------------------------------------------------------

  /// Devuelve el nombre limpio, o `null` si no se puede guardar (dejando el
  /// motivo en [_error]).
  String? _validarNombre(String nombre) {
    final limpio = nombre.trim();
    if (limpio.isEmpty) {
      _error = 'El nombre no puede quedar vacío.';
      notifyListeners();
      return null;
    }
    return limpio;
  }

  /// Ejecuta la escritura y despues relee la lista completa.
  ///
  /// Releer y no parchear el array en memoria: el orden de `obtenerTodas` es
  /// alfabetico, y un alta o un borrado dejarian el array desordenado hasta que
  /// se recargara la pantalla.
  ///
  /// [accion] es `Future<Object?>` y no `Future<int>` porque desde la v7 no todos
  /// los repositorios devuelven la misma cosa: `crear` devuelve el UUID
  /// (`String`) y `eliminar` devuelve las filas tocadas (`int`). Se tipa lo mas
  /// amplio posible porque a este helper no le interesa el resultado, solo que la
  /// escritura no reventara. Cuando se vuelva a necesitar el valor, se tipa.
  Future<bool> _escribir(
    Future<Object?> Function() accion,
    Future<void> Function() releer,
  ) async {
    try {
      await accion();
      await releer();
      _error = null;
      notifyListeners();
      return true;
    } on Exception catch (e) {
      _error = _mensajeDe(e);
      notifyListeners();
      return false;
    }
  }

  /// Traduce la excepcion de SQLite a algo que un administrador entienda.
  ///
  /// `e.toString()` de un `DatabaseException` es una parrafada de SQL que dice
  /// 'UNIQUE constraint failed: tecnicos.nombre'. Alguien del taller no puede
  /// leer eso, y si el mensaje no sirve, la app parece rota.
  String _mensajeDe(Exception e) {
    if (e is DatabaseException && e.isUniqueConstraintError()) {
      return 'Ya existe un elemento con ese nombre.';
    }
    return 'No se pudo completar la operacion. Intenta de nuevo.';
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;

import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/features/configuracion/data/grupo_servicio_repository.dart';
import 'package:autofix/features/configuracion/data/marca_repository.dart';
import 'package:autofix/features/configuracion/data/tecnico_repository.dart';
import 'package:autofix/features/configuracion/data/tipo_servicio_repository.dart';
import 'package:autofix/features/configuracion/models/grupo_servicio.dart';
import 'package:autofix/features/configuracion/models/marca.dart';
import 'package:autofix/features/configuracion/models/tecnico.dart';
import 'package:autofix/features/configuracion/models/tipo_servicio.dart';
import 'package:autofix/features/sync/sync_service.dart';

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
  /// singleton.
  ///
  /// [tallerId] es obligatorio: el controlador filtra todos los catalogos por
  /// este ID. Se inyecta desde la vista (ej. LoginController -> AdminProfile).
  ConfiguracionController({
    required this.tallerId,
    TecnicoRepository? tecnicos,
    TipoServicioRepository? servicios,
    MarcaRepository? marcas,
    GrupoServicioRepository? grupos,
  }) : _repoTecnicos = tecnicos ?? TecnicoRepository.instance,
       _repoServicios = servicios ?? TipoServicioRepository.instance,
       _repoMarcas = marcas ?? MarcaRepository.instance,
       _repoGrupos = grupos ?? GrupoServicioRepository.instance;

  final String tallerId;

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
  bool _disposed = false;

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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notificarSiActivo() {
    if (!_disposed) notifyListeners();
  }

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
    var limpio = texto.trim();
    limpio = limpio.replaceFirst(
      RegExp(r'^(?:RD\$|\$)\s*', caseSensitive: false),
      '',
    );
    limpio = limpio.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)$').hasMatch(limpio)) {
      return null;
    }
    return int.tryParse(limpio.replaceAll(',', ''));
  }

  // ---------------------------------------------------------------------
  // Lectura
  // ---------------------------------------------------------------------

  Future<void> cargar({bool mostrarCarga = true}) async {
    if (mostrarCarga) _cargando = true;
    _error = null;
    if (mostrarCarga) _notificarSiActivo();

    try {
      // Las cuatro se piden juntas filtradas por tallerId
      final resultados = await Future.wait(<Future<Object?>>[
        _repoTecnicos.obtenerTodasPorTaller(tallerId),
        _repoServicios.obtenerTodasPorTaller(tallerId),
        _repoMarcas.obtenerTodasPorTaller(tallerId),
        _repoGrupos.obtenerTodasPorTaller(tallerId),
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
    _notificarSiActivo();
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
    return _escribir(
      () => _repoTecnicos.crear(Tecnico(nombre: limpio, tallerId: tallerId)),
      () async {
        _tecnicos = await _repoTecnicos.obtenerTodasPorTaller(tallerId);
      },
    );
  }

  Future<bool> editarTecnico(String id, String nombre) async {
    final limpio = _validarNombre(nombre);
    if (limpio == null) return false;
    final existente = _tecnicos.where((tecnico) => tecnico.id == id);
    if (existente.isEmpty) return _noEncontrado();
    return _escribir(
      () => _repoTecnicos.actualizar(existente.first.copyWith(nombre: limpio)),
      () async =>
          _tecnicos = await _repoTecnicos.obtenerTodasPorTaller(tallerId),
    );
  }

  Future<bool> guardarTipoServicio(String nombre, String? precioTexto) async {
    final limpio = _validarNombre(nombre);
    if (limpio == null) return false;

    final precio = leerPrecio(precioTexto);
    if (precio == null) {
      _error = 'Escribe un precio válido, por ejemplo 1200.';
      _notificarSiActivo();
      return false;
    }

    return _escribir(
      () => _repoServicios.crear(
        TipoServicio(nombre: limpio, precio: precio, tallerId: tallerId),
      ),
      () async =>
          _tiposServicio = await _repoServicios.obtenerTodasPorTaller(tallerId),
    );
  }

  Future<bool> editarTipoServicio(
    String id,
    String nombre,
    String? precioTexto,
  ) async {
    final limpio = _validarNombre(nombre);
    if (limpio == null) return false;
    final precio = leerPrecio(precioTexto);
    if (precio == null) {
      _error = 'Escribe un precio válido y no negativo, por ejemplo 1200.';
      _notificarSiActivo();
      return false;
    }
    final existente = _tiposServicio.where((servicio) => servicio.id == id);
    if (existente.isEmpty) return _noEncontrado();
    return _escribir(
      () => _repoServicios.actualizar(
        existente.first.copyWith(nombre: limpio, precio: precio),
      ),
      () async =>
          _tiposServicio = await _repoServicios.obtenerTodasPorTaller(tallerId),
    );
  }

  /// Alta de marca. El mismo contrato que [guardarTecnico]: nombre limpio,
  /// error en [_error] y `bool` de salida.
  Future<bool> guardarMarca(String nombre) async {
    final limpio = _validarNombre(nombre);
    if (limpio == null) return false;
    return _escribir(
      () => _repoMarcas.crear(Marca(nombre: limpio, tallerId: tallerId)),
      () async => _marcas = await _repoMarcas.obtenerTodasPorTaller(tallerId),
    );
  }

  Future<bool> editarMarca(String id, String nombre) async {
    final limpio = _validarNombre(nombre);
    if (limpio == null) return false;
    final existente = _marcas.where((marca) => marca.id == id);
    if (existente.isEmpty) return _noEncontrado();
    return _escribir(
      () => _repoMarcas.actualizar(existente.first.copyWith(nombre: limpio)),
      () async => _marcas = await _repoMarcas.obtenerTodasPorTaller(tallerId),
    );
  }

  /// Alta de grupo de servicios. Sin precio: un grupo no se cobra, agrupa.
  Future<bool> guardarGrupoServicio(String nombre) async {
    final limpio = _validarNombre(nombre);
    if (limpio == null) return false;
    return _escribir(
      () =>
          _repoGrupos.crear(GrupoServicio(nombre: limpio, tallerId: tallerId)),
      () async =>
          _gruposServicio = await _repoGrupos.obtenerTodasPorTaller(tallerId),
    );
  }

  Future<bool> editarGrupoServicio(String id, String nombre) async {
    final limpio = _validarNombre(nombre);
    if (limpio == null) return false;
    final existente = _gruposServicio.where((grupo) => grupo.id == id);
    if (existente.isEmpty) return _noEncontrado();
    return _escribir(
      () => _repoGrupos.actualizar(existente.first.copyWith(nombre: limpio)),
      () async =>
          _gruposServicio = await _repoGrupos.obtenerTodasPorTaller(tallerId),
    );
  }

  // Los cuatro `eliminar*` releen con `obtenerTodasPorTaller(tallerId)`, igual
  // que los `guardar*`. Releer con `obtenerTodas()` (sin filtro) dejaba en la
  // lista en memoria los catalogos de OTROS talleres: al borrar un tecnico, el
  // admin de un taller veia en pantalla los tecnicos de todos los talleres
  // guardados en el dispositivo (fuga de multitenencia en la UI).
  Future<bool> eliminarTecnico(String id) => _escribir(
    () => _repoTecnicos.eliminar(id),
    () async => _tecnicos = await _repoTecnicos.obtenerTodasPorTaller(tallerId),
  );

  Future<bool> eliminarTipoServicio(String id) => _escribir(
    () => _repoServicios.eliminar(id),
    () async =>
        _tiposServicio = await _repoServicios.obtenerTodasPorTaller(tallerId),
  );

  /// Baja lógica sincronizable de la marca. `MarcaRepository.darDeBaja` conserva
  /// además la marca visible en el historial usando `activo = 0`.
  Future<bool> eliminarMarca(String id) => _escribir(
    () => _repoMarcas.eliminar(id),
    () async => _marcas = await _repoMarcas.obtenerTodasPorTaller(tallerId),
  );

  Future<bool> eliminarGrupoServicio(String id) => _escribir(
    () => _repoGrupos.eliminar(id),
    () async =>
        _gruposServicio = await _repoGrupos.obtenerTodasPorTaller(tallerId),
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
      _notificarSiActivo();
      return null;
    }
    return limpio;
  }

  bool _noEncontrado() {
    _error = 'El registro ya no está disponible. Actualiza la lista e inténtalo de nuevo.';
    _notificarSiActivo();
    return false;
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
      _notificarSiActivo();
      if (SesionAdmin.instance.tallerId == tallerId) {
        // La escritura local ya terminó. El push queda en segundo plano y, si
        // no hay conexión o Firebase rechaza algo, `pending` se conserva para
        // el siguiente ciclo de sincronización.
        unawaited(SyncService.instance.pushPending());
      }
      return true;
    } on Exception catch (e) {
      _error = _mensajeDe(e);
      _notificarSiActivo();
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

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;

import 'package:autofix/features/configuracion/data/estado_repository.dart';
import 'package:autofix/features/configuracion/data/tecnico_repository.dart';
import 'package:autofix/features/configuracion/data/tipo_servicio_repository.dart';
import 'package:autofix/features/configuracion/models/estado.dart';
import 'package:autofix/features/configuracion/models/tecnico.dart';
import 'package:autofix/features/configuracion/models/tipo_servicio.dart';

/// Estado y logica de la pantalla de Configuracion.
///
/// Es la unica capa que la vista conoce. Leandy engancha su diseño a este
/// `ChangeNotifier` sin tocar la vista actual ni los repositorios.
///
/// UN controller para los tres catalogos y no tres por separado, porque la
/// pantalla es UNA pagina con una sola `initState`: tres controllers obligarian a
/// la vista a escuchar tres `ListenableBuilder` y a coordinating tres estados de
/// carga para, al final, pintar tres listas en la misma pantalla. Cuando entren
/// Grupos de Servicios (y Marcas, cuando se defina su dueno) y esto crezca, se
/// parte en `CatalogosController` + `GruposController`.
///
/// No expone `Color` ni `Widget`: devuelve entidades y texto ya formateado. El
/// mapeo a color es del diseño, no del dominio.
class ConfiguracionController extends ChangeNotifier {
  ConfiguracionController({
    TecnicoRepository? tecnicos,
    TipoServicioRepository? servicios,
    EstadoRepository? estados,
  }) : _repoTecnicos = tecnicos ?? TecnicoRepository.instance,
       _repoServicios = servicios ?? TipoServicioRepository.instance,
       _repoEstados = estados ?? EstadoRepository.instance;

  final TecnicoRepository _repoTecnicos;
  final TipoServicioRepository _repoServicios;
  final EstadoRepository _repoEstados;

  /// Formateador de miles. Sin locale explicito a proposito: el separador de
  /// miles por defecto de `intl` ya sale con coma ('1,200') sin pedirle que
  /// cargue locale data para un idioma que la app no usa.
  late final NumberFormat _dinero = NumberFormat('#,##0');

  List<Tecnico> _tecnicos = const <Tecnico>[];
  List<TipoServicio> _tiposServicio = const <TipoServicio>[];
  List<EstadoConfig> _estados = const <EstadoConfig>[];

  bool _cargando = true;
  String? _error;

  List<Tecnico> get tecnicos => List.unmodifiable(_tecnicos);
  List<TipoServicio> get tiposServicio => List.unmodifiable(_tiposServicio);
  List<EstadoConfig> get estados => List.unmodifiable(_estados);

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
      // Las tres se piden juntas: son de la misma base y del mismo tamano de
      // dato. Pedirlas en paralelo evita los tres viajes de ida y vuelta.
      final resultados = await Future.wait(<Future<Object?>>[
        _repoTecnicos.obtenerTodas(),
        _repoServicios.obtenerTodas(),
        _repoEstados.obtenerTodas(),
      ]);

      _tecnicos = resultados[0] as List<Tecnico>;
      _tiposServicio = resultados[1] as List<TipoServicio>;
      _estados = resultados[2] as List<EstadoConfig>;
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

  Future<bool> guardarEstado(String nombre) async {
    final limpio = _validarNombre(nombre);
    if (limpio == null) return false;
    return _escribir(
      () => _repoEstados.crear(EstadoConfig(nombre: limpio)),
      () async {
        _estados = await _repoEstados.obtenerTodas();
      },
    );
  }

  Future<bool> eliminarTecnico(int id) => _escribir(
    () => _repoTecnicos.eliminar(id),
    () async => _tecnicos = await _repoTecnicos.obtenerTodas(),
  );

  Future<bool> eliminarTipoServicio(int id) => _escribir(
    () => _repoServicios.eliminar(id),
    () async => _tiposServicio = await _repoServicios.obtenerTodas(),
  );

  Future<bool> eliminarEstado(int id) => _escribir(
    () => _repoEstados.eliminar(id),
    () async => _estados = await _repoEstados.obtenerTodas(),
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
  Future<bool> _escribir(
    Future<int> Function() accion,
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

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/core/connectivity/connectivity_scope.dart';
import 'package:autofix/core/connectivity/connectivity_service.dart';
import 'package:autofix/core/mapa/etiqueta_distancia.dart';
import 'package:autofix/core/ubicacion/ubicacion_service.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/configuracion/data/tipo_servicio_repository.dart';
import 'package:autofix/features/configuracion/models/tipo_servicio.dart';
import 'package:autofix/features/sync/sync_service.dart';
import 'package:autofix/features/talleres/data/taller_repository.dart';
import 'package:autofix/features/talleres/models/taller.dart';
import 'package:autofix/shared/theme/app_colors.dart';
import 'package:autofix/features/cliente/widgets/agenda_cliente_widgets.dart';
import 'package:autofix/features/cliente/widgets/cliente_section_widgets.dart';
import 'package:autofix/features/cliente/data/catalogo_vehiculos_api.dart';
import 'package:autofix/features/cliente/data/vehiculo_repository.dart';
import 'package:autofix/features/cliente/models/vehiculo.dart';

/// "RD$ 1,250" -- pesos dominicanos con separador de miles.
///
/// Top-level y no metodo del widget para que el test la verifique, por la misma
/// razon que `aCss` vive fuera del `State`: un separador mal puesto no rompe
/// la app, imprime "RD$ 12500" y queda como si el taller cobrara 125 mil.
///
/// El separador de miles se pone con un `replaceAllMapped` sobre el string y no
/// con `intl`: `NumberFormat` con locale `es_DO` depende de los datos de locale
/// que trae el paquete, y si no estan cargados revienta en runtime con un error
/// de locale, no con uno de formato. Un patron regular no puede fallar asi.
///
/// Decimales a proposito ausentes: [TipoServicio.precio] es un entero y la
/// semilla los siembra en 0. El día que haga falta centavos, se suman enteros
/// de centavos y se divide acá.
String formatearPesosDR(int monto) {
  final conSeparadores = monto.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

  return 'RD\$ $conSeparadores';
}

/// Fila de precio de un servicio en el selector.
///
/// Un precio en 0 NO es un servicio gratis: es un servicio cuyo precio nadie ha
/// cargado todavía. Decir "RD$ 0" es una afirmación sobre el taller, y si esta
/// mal es una de las que hacen perder plata. Por eso sale "Por definir".
///
/// No lo confunde con el `total = 0` que se guarda en la cita: ese es un dato
/// honesto de que la aritmética dio cero, este es un dato de que falta
/// configuracion.
String etiquetaPrecio(int precio) =>
    precio > 0 ? formatearPesosDR(precio) : 'Precio por definir';

class AgendarCitaClienteSection extends StatefulWidget {
  const AgendarCitaClienteSection({
    required this.tallerSeleccionado,
    required this.onTallerSelected,
    this.tallerSeleccionadoId,
    super.key,
  });

  /// Nombre del taller, solo para mostrarlo en pantalla.
  final String tallerSeleccionado;

  /// Identificador del taller. Es el dato que se guarda en `citas.taller_id`;
  /// el nombre es una etiqueta y puede repetirse o cambiar.
  ///
  /// `String?` desde la v7: es el UUID del taller, no un numero. Antes era `int?`
  /// y por eso `==` comparaba autoincrementos que solo tenían sentido dentro de
  /// ESTE dispositivo.
  final String? tallerSeleccionadoId;

  final ValueChanged<Taller> onTallerSelected;

  @override
  State<AgendarCitaClienteSection> createState() =>
      _AgendarCitaClienteSectionState();
}

class _AgendarCitaClienteSectionState extends State<AgendarCitaClienteSection> {
  static const List<String> _marcasComunesOffline = [
    'Toyota',
    'Honda',
    'Hyundai',
    'Kia',
    'Nissan',
    'Mazda',
    'Mitsubishi',
    'Suzuki',
    'Ford',
    'Chevrolet',
    'BMW',
    'Mercedes-Benz',
    'Lexus',
    'Jeep',
    'Isuzu',
    'Subaru',
    'Volkswagen',
    'Audi',
    'Volvo',
    'Acura',
  ];

  final CatalogoVehiculosApi _catalogoVehiculos = CatalogoVehiculosApi();
  List<String> _marcasDisponibles = _marcasComunesOffline;
  List<String> _modelosDisponibles = const [];
  bool _cargandoMarcas = false;
  bool _cargandoModelos = false;
  bool _inicializoCatalogo = false;
  bool _ultimaConexion = false;
  String? _avisoCatalogo;
  ConnectivityService? _servicioConectividad;
  int _solicitudModelos = 0;

  List<String> get _aniosDisponibles => List<String>.generate(
    DateTime.now().year - 1980 + 2,
    (indice) => (DateTime.now().year + 1 - indice).toString(),
  );

  /// Catálogo de servicios REAL de la base, no una lista fija del widget.
  ///
  /// Antes eran cuatro literales y el admin no podía cambiar nada: los servicios
  /// "Alineación y balanceo" y "Cambio de gomas" que él sí tenía cargados en
  /// Configuración no se podían marcar en la cita. La fuente de verdad de qué
  /// ofrece el taller es `tipos_servicio`, y el precio de cada uno sale de ahí
  /// para el total.
  List<TipoServicio> _serviciosDisponibles = const <TipoServicio>[];
  bool _cargandoServicios = true;

  final TextEditingController _clienteController = TextEditingController();
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();
  final TextEditingController _descripcionController = TextEditingController();
  final TextEditingController _marcaController = TextEditingController();
  final TextEditingController _modeloController = TextEditingController();
  final TextEditingController _anioController = TextEditingController();
  final TextEditingController _placaController = TextEditingController();

  /// Nombres de los servicios marcados. Se guardan por NOMBRE y no por id
  /// porque es lo que viaja en `Cita.servicios` (JSON de texto). El precio se
  /// cruza contra el catálogo al enviar; ver [TipoServicio.totalDe].
  final Set<String> _serviciosSeleccionados = {};
  DateTime _fechaSeleccionada = DateTime.now();
  TimeOfDay _horaSeleccionada = const TimeOfDay(hour: 9, minute: 0);
  bool _vehiculoFormularioVisible = false;
  bool _vehiculoSeleccionado = false;
  String? _vehiculoSeleccionadoId;
  List<Vehiculo> _vehiculosRegistrados = const [];

  /// Talleres afiliados reales, leídos de la base local.
  List<Taller> _talleres = const <Taller>[];
  bool _cargandoTalleres = true;

  /// Donde esta el cliente, SOLO si ya dio permiso de ubicacion.
  ///
  /// Son dos `double?` y no una `Position` porque aca no se necesita precision,
  /// timestamp ni nada mas: lo unico que sale de aca es la distancia, y eso son
  /// dos coordenadas. Ademas, serian dos valoresnullables que se mueven juntos,
  /// y una `Position` nullable es un estado mas que puede quedar a medias.
  double? _latitudUsuario;
  double? _longitudUsuario;

  @override
  void initState() {
    super.initState();
    _prellenarDesdeElPerfil();
    _cargarTalleres();
    _cargarServicios();
    SyncService.instance.addListener(_alCambiarSync);
    unawaited(_cargarVehiculosRegistrados());
    unawaited(_cargarPosicionSiHayPermiso());
    // Igual que el mapa: el pull del arranque puede bajar los talleres
    // DESPUES de que ya se pinto la lista de este formulario.
    TallerRepository.instance.addListener(_alCambiarElCatalogo);
  }

  @override
  void didUpdateWidget(covariant AgendarCitaClienteSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tallerSeleccionadoId != widget.tallerSeleccionadoId) {
      _serviciosSeleccionados.clear();
      unawaited(_cargarServicios());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      final servicio = ConnectivityScope.read(context);
      if (!identical(servicio, _servicioConectividad)) {
        _servicioConectividad?.removeListener(_alCambiarConectividad);
        _servicioConectividad = servicio;
        _ultimaConexion = servicio.hayConexion;
        servicio.addListener(_alCambiarConectividad);
      }
    } on Object {
      // Tests o previews pueden montar el formulario sin el scope de la app;
      // en ese caso se usan las opciones locales y el ingreso manual.
    }
    if (!_inicializoCatalogo) {
      _inicializoCatalogo = true;
      unawaited(_cargarMarcas());
    }
  }

  bool get _hayConexion => _servicioConectividad?.hayConexion ?? false;

  String? get _clienteIdVehiculos =>
      SesionCliente.instance.correo?.trim().toLowerCase();

  Future<void> _cargarVehiculosRegistrados() async {
    final clienteId = _clienteIdVehiculos;
    if (clienteId == null || clienteId.isEmpty) return;
    try {
      final vehiculos = await VehiculoRepository.instance.obtenerPorCliente(
        clienteId,
      );
      if (mounted) setState(() => _vehiculosRegistrados = vehiculos);
    } on Object {
      if (mounted) {
        _mostrarAviso('No se pudieron leer los vehículos guardados.');
      }
    }
  }

  void _seleccionarVehiculoRegistrado(Vehiculo? vehiculo) {
    if (vehiculo == null) return;
    setState(() {
      _vehiculoSeleccionadoId = vehiculo.id;
      _marcaController.text = vehiculo.marca;
      _modeloController.text = vehiculo.modelo;
      _anioController.text = vehiculo.anio.toString();
      _placaController.text = vehiculo.placa;
      _vehiculoSeleccionado = true;
      _vehiculoFormularioVisible = false;
    });
    final anio = vehiculo.anio;
    unawaited(_cargarModelos(marca: vehiculo.marca, anio: anio));
  }

  void _agregarOtroVehiculo() {
    setState(() {
      _vehiculoSeleccionadoId = null;
      _vehiculoSeleccionado = false;
      _vehiculoFormularioVisible = true;
      _marcaController.clear();
      _modeloController.clear();
      _anioController.clear();
      _placaController.clear();
      _modelosDisponibles = const [];
    });
  }

  Future<void> _guardarVehiculo() async {
    final clienteId = _clienteIdVehiculos;
    final marca = _marcaController.text.trim();
    final modelo = _modeloController.text.trim();
    final anio = int.tryParse(_anioController.text.trim());
    if (clienteId == null || clienteId.isEmpty) {
      _mostrarAviso('Inicia sesión con tu correo para registrar el vehículo.');
      return;
    }
    if (marca.isEmpty || modelo.isEmpty || anio == null || anio < 1886) {
      _mostrarAviso('Completa marca, modelo y año del vehículo.');
      return;
    }

    final existente = _vehiculoSeleccionadoId == null
        ? null
        : _vehiculosRegistrados
              .where((vehiculo) => vehiculo.id == _vehiculoSeleccionadoId)
              .firstOrNull;
    final vehiculo = Vehiculo(
      id: existente?.id,
      clienteId: clienteId,
      marca: marca,
      modelo: modelo,
      anio: anio,
      placa: _placaController.text.trim().toUpperCase(),
      creadoEn: existente?.creadoEn,
    );

    try {
      final id = existente == null
          ? await VehiculoRepository.instance.crear(vehiculo)
          : (await VehiculoRepository.instance.actualizar(vehiculo) > 0
                ? existente.id!
                : null);
      if (id == null) throw StateError('No se encontró el vehículo a editar.');
      final actualizados = await VehiculoRepository.instance.obtenerPorCliente(
        clienteId,
      );
      final guardado = actualizados.firstWhere((item) => item.id == id);
      if (!mounted) return;
      setState(() {
        _vehiculosRegistrados = actualizados;
        _vehiculoSeleccionadoId = guardado.id;
        _vehiculoSeleccionado = true;
        _vehiculoFormularioVisible = false;
      });
      _mostrarAviso('Vehículo guardado en este dispositivo.');
    } on Object {
      if (mounted) {
        _mostrarAviso('No se pudo guardar el vehículo. Intenta otra vez.');
      }
    }
  }

  void _alCambiarConectividad() {
    final conectado = _hayConexion;
    if (conectado && !_ultimaConexion) {
      unawaited(_cargarMarcas());
      final marca = _marcaController.text.trim();
      final anio = int.tryParse(_anioController.text.trim());
      if (marca.isNotEmpty && anio != null) {
        unawaited(_cargarModelos(marca: marca, anio: anio));
      }
    } else if (!conectado && _ultimaConexion && mounted) {
      setState(() {
        _avisoCatalogo = 'Sin conexión: usa las marcas guardadas o escribe los datos manualmente.';
      });
    }
    _ultimaConexion = conectado;
  }

  Future<void> _cargarMarcas() async {
    final online = _hayConexion;
    if (mounted && online) setState(() => _cargandoMarcas = true);
    try {
      final recibidas = await _catalogoVehiculos.obtenerMarcas(enLinea: online);
      if (!mounted) return;
      final normalizadas = <String, String>{
        for (final marca in _marcasComunesOffline) marca.toLowerCase(): marca,
        for (final marca in recibidas)
          if (marca.trim().isNotEmpty) marca.toLowerCase(): marca.trim(),
      };
      final comunes = _marcasComunesOffline
          .map((marca) => normalizadas.remove(marca.toLowerCase()) ?? marca)
          .toList();
      final resto = normalizadas.values.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      setState(() {
        _marcasDisponibles = [...comunes, ...resto];
        _cargandoMarcas = false;
        _avisoCatalogo = online ? null : 'Sin conexión: catálogo local listo; puedes ingresar una marca manualmente.';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _marcasDisponibles = _marcasComunesOffline;
        _cargandoMarcas = false;
        _avisoCatalogo = online
            ? 'No se pudo actualizar el catálogo. Puedes ingresar la marca manualmente.'
            : 'Sin conexión: usa las marcas comunes o ingresa una manualmente.';
      });
    }
  }

  void _seleccionarMarca(String? marca) {
    if (marca == null) {
      setState(() {
        _marcaController.clear();
        _anioController.clear();
        _modeloController.clear();
        _modelosDisponibles = const [];
      });
      return;
    }
    setState(() {
      _marcaController.text = marca;
      _anioController.clear();
      _modeloController.clear();
      _modelosDisponibles = const [];
      _avisoCatalogo = null;
    });
  }

  void _seleccionarAnio(String? anio) {
    if (anio == null) {
      setState(() {
        _anioController.clear();
        _modeloController.clear();
        _modelosDisponibles = const [];
      });
      return;
    }
    setState(() {
      _anioController.text = anio;
      _modeloController.clear();
      _modelosDisponibles = const [];
      _avisoCatalogo = null;
    });
    final marca = _marcaController.text.trim();
    final anioNumero = int.tryParse(anio);
    if (marca.isNotEmpty && anioNumero != null) {
      unawaited(_cargarModelos(marca: marca, anio: anioNumero));
    }
  }

  void _seleccionarModelo(String? modelo) {
    if (modelo == null) {
      setState(() => _modeloController.clear());
      return;
    }
    setState(() {
      _modeloController.text = modelo;
      _avisoCatalogo = null;
    });
  }

  Future<void> _cargarModelos({
    required String marca,
    required int anio,
  }) async {
    final token = ++_solicitudModelos;
    final online = _hayConexion;
    if (online && mounted) setState(() => _cargandoModelos = true);
    try {
      final modelos = await _catalogoVehiculos.obtenerModelos(
        marca: marca,
        anio: anio,
        enLinea: online,
      );
      if (!mounted || token != _solicitudModelos) return;
      setState(() {
        _modelosDisponibles = modelos;
        _cargandoModelos = false;
        _avisoCatalogo = modelos.isEmpty
            ? online
                  ? 'No hay modelos para esa selección. Puedes escribir el modelo manualmente.'
                  : 'Sin conexión: escribe el modelo manualmente.'
            : online
            ? null
            : 'Modelos disponibles desde la caché local.';
      });
    } on Object {
      if (!mounted || token != _solicitudModelos) return;
      setState(() {
        _modelosDisponibles = const [];
        _cargandoModelos = false;
        _avisoCatalogo = 'No se pudieron cargar los modelos. Puedes ingresarlos manualmente.';
      });
    }
  }

  /// Rellena nombre, correo y teléfono con lo que sabe la sesion del cliente.
  ///
  /// El requisito es que esos tres campos NO arranquen vacios, y la fuente es
  /// el perfil local (`SesionCliente`): no hay llamada a la nube ni a
  /// Firebase, asi que funciona igual sin internet.
  ///
  /// Es EDITABLE: se escriben los valores iniciales y despues el campo es del
  /// usuario, que puede corregir su telefono antes de mandar.
  void _prellenarDesdeElPerfil() {
    final sesion = SesionCliente.instance;
    _clienteController.text =
        sesion.nombre ?? (sesion.correo == null ? '' : sesion.nombreVisible);
    _correoController.text = sesion.correo ?? '';
    _telefonoController.text = sesion.telefono ?? '';
  }

  /// Lee la ubicacion para poder escribir "a 2.5 km" en el selector.
  ///
  /// NO pide permiso: usa [UbicacionService.obtenerPosicionSiEstaPermitido], que
  /// devuelve `null` si el cliente todavia no lo concedio. Preguntar desde aca
  /// seria Interruptir el formulario con un dialogo del sistema a un usuario que
  /// solo quiere dejar su cita; el mapa ya se encargo de preguntar, y cuando lo
  /// hizo esta llamada encuentra el permiso dado y escribe la distancia sola.
  ///
  /// Si no hay posicion, no se muestra ninguna. Un "Distancia no disponible" en
  /// el selector se leeria como que al taller le falta un dato, cuando lo que
  /// falta es el nuestro.
  Future<void> _cargarPosicionSiHayPermiso() async {
    final posicion = await const UbicacionService()
        .obtenerPosicionSiEstaPermitido();
    if (posicion == null || !mounted) return;

    setState(() {
      _latitudUsuario = posicion.latitude;
      _longitudUsuario = posicion.longitude;
    });
  }

  /// El catalogo local cambio y este formulario ya estaba armado.
  ///
  /// Vuelve a leer los activos y repinta la lista de seleccion, por el mismo
  /// camino con el que la arma al construirse.
  void _alCambiarElCatalogo() {
    if (!mounted) return;
    unawaited(_cargarTalleres());
  }

  Future<void> _cargarTalleres() async {
    final talleres = await TallerRepository.instance.obtenerActivos();
    if (!mounted) return;
    setState(() {
      _talleres = talleres;
      _cargandoTalleres = false;
    });
  }

  /// Lee el catálogo de servicios.
  ///
  /// `activo = 1` solamente: un servicio dado de baja sigue existiendo en la
  /// tabla para las citas viejas que lo nombran, igual que los talleres, pero no
  /// se ofrece a un cliente nuevo.
  Future<void> _cargarServicios() async {
    final tallerId = widget.tallerSeleccionadoId;
    if (tallerId == null || tallerId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _serviciosDisponibles = const <TipoServicio>[];
        _cargandoServicios = false;
      });
      return;
    }
    final todos = await TipoServicioRepository.instance.obtenerTodasPorTaller(
      tallerId,
    );
    if (!mounted) return;
    if (widget.tallerSeleccionadoId != tallerId) return;
    setState(() {
      _serviciosDisponibles = todos
          .where((s) => s.activo)
          .toList(growable: false);
      _cargandoServicios = false;
    });
  }

  void _alCambiarSync() {
    if (mounted && widget.tallerSeleccionadoId != null) {
      unawaited(_cargarServicios());
    }
  }

  /// Total estimado de la cita, con los precios que el admin tiene cargados.
  int get _totalEstimado =>
      TipoServicio.totalDe(_serviciosDisponibles, _serviciosSeleccionados);

  @override
  void dispose() {
    TallerRepository.instance.removeListener(_alCambiarElCatalogo);
    SyncService.instance.removeListener(_alCambiarSync);
    _servicioConectividad?.removeListener(_alCambiarConectividad);
    _catalogoVehiculos.close();
    _clienteController.dispose();
    _correoController.dispose();
    _telefonoController.dispose();
    _descripcionController.dispose();
    _marcaController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _placaController.dispose();
    super.dispose();
  }

  /// Resuelve el taller seleccionado por `id`, que es la clave fiable.
  /// Devuelve `null` en vez de lanzar si aún no hay nada seleccionado o si el
  /// taller ya no está activo: antes esto era un `firstWhere` sin `orElse` que
  /// reventaba la pantalla cuando el nombre no coincidía con la lista.
  Taller? get _tallerActual {
    for (final taller in _talleres) {
      if (taller.id == widget.tallerSeleccionadoId) return taller;
    }
    for (final taller in _talleres) {
      if (taller.nombre == widget.tallerSeleccionado) return taller;
    }
    return null;
  }

  /// "a 2.5 km de ti", o `null` si todavia no sabemos donde esta el cliente.
  String? _distanciaDe(Taller taller) =>
      etiquetaDistanciaSiHayGps(taller, _latitudUsuario, _longitudUsuario);

  /// Direccion del taller, con la distancia cuando la hay.
  ///
  /// La distancia se joins al final con un punto y coma, no con un guion: "Av.
  /// Las Americas; a 2.5 km de ti" se lee como dos datos del mismo lugar, en
  /// cambio "Av. Las Americas - 2.5 km" parece un rango de direcciones.
  String _subtituloDe(Taller taller) {
    final distancia = _distanciaDe(taller);
    final direccion = taller.direccion;

    return distancia == null ? direccion : '$direccion; $distancia';
  }

  Future<void> _seleccionarTaller() async {
    if (_talleres.isEmpty) {
      _mostrarAviso('No hay talleres afiliados disponibles.');
      return;
    }

    final taller = await showModalBottomSheet<Taller>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Material(
              color: Colors.transparent,
              child: ListTile(
                title: Text(
                  'Selecciona un taller',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            for (final taller in _talleres)
              Material(
                color: AppColors.cardWhite,
                child: ListTile(
                  leading: const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.orangePrimary,
                  ),
                  title: Text(taller.nombre),
                  subtitle: Text(_subtituloDe(taller)),
                  trailing: taller.id == widget.tallerSeleccionadoId
                      ? const Icon(
                          Icons.check_circle,
                          color: AppColors.greenAccent,
                        )
                      : null,
                  onTap: () => Navigator.pop(context, taller),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (taller == null || !mounted) return;
    widget.onTallerSelected(taller);
  }

  Future<void> _seleccionarFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada.isBefore(DateTime.now())
          ? DateTime.now()
          : _fechaSeleccionada,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (fecha == null || !mounted) return;
    setState(() => _fechaSeleccionada = fecha);
  }

  Future<void> _seleccionarHora() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: _horaSeleccionada,
    );
    if (hora == null || !mounted) return;
    setState(() => _horaSeleccionada = hora);
  }

  /// Junta la fecha y la hora en un solo `DateTime` para `citas.fecha_cita`.
  DateTime get _fechaCita => DateTime(
    _fechaSeleccionada.year,
    _fechaSeleccionada.month,
    _fechaSeleccionada.day,
    _horaSeleccionada.hour,
    _horaSeleccionada.minute,
  );

  String get _vehiculoResumen {
    final partes = [
      _marcaController.text.trim(),
      _modeloController.text.trim(),
      _anioController.text.trim(),
    ].where((p) => p.isNotEmpty).toList();
    return partes.isEmpty ? 'Por definir' : partes.join(' ');
  }

  Future<void> _enviarSolicitud() async {
    final cliente = _clienteController.text.trim();
    if (cliente.isEmpty) {
      _mostrarAviso('Escribe tu nombre completo.');
      return;
    }

    if (!_vehiculoSeleccionado) {
      _mostrarAviso('Selecciona o registra un vehículo para la cita.');
      return;
    }

    // Sin `taller_id` la cita quedaría huérfana y el taller no podría verla.
    final tallerId = widget.tallerSeleccionadoId;
    if (tallerId == null) {
      _mostrarAviso('Selecciona un taller para tu cita.');
      return;
    }

    final cita = Cita(
      cliente: cliente,
      correoCliente: _correoController.text.trim().toLowerCase(),
      telefono: _telefonoController.text.trim(),
      vehiculo: _vehiculoResumen,
      marca: _marcaController.text.trim(),
      modelo: _modeloController.text.trim(),
      anio: int.tryParse(_anioController.text.trim()) ?? 0,
      placa: _placaController.text.trim().toUpperCase(),
      servicios: _serviciosSeleccionados.toList(),
      descripcion: _descripcionController.text.trim(),
      fechaCita: _fechaCita,
      tallerId: tallerId,
      // Suma de los precios del catálogo (`tipos_servicio.precio`) de los
      // servicios marcados. Es el mismo valor que muestra el resumen de abajo
      // del formulario: el cliente ve lo que se guarda, no otra cuenta.
      //
      // Da 0 mientras el admin no cargue precios -- la semilla los siembra en 0
      // a proposito, porque en el diseño original no se sabian todavía. No es
      // un total inventado: es el total real de un catálogo que hoy vale 0.
      // Cuando `Configuración` tenga los precios, este numero cambia solo.
      total: _totalEstimado,
    );

    try {
      await CitaRepository.instance.crear(cita);
    } catch (_) {
      _mostrarAviso('No pudimos guardar tu cita. Intenta de nuevo.');
      return;
    }

    // Sube a Firebase en segundo plano. Sin este llamado la cita se quedaria en
    // `sync_status = 'pending'` hasta el proximo arranque de la app: la cola la
    // drena [SyncService], nadie la drena solo. Si no hay red no pasa nada --
    // `pushPending` traga su propio error -- y la cita sale en "Mis citas" con
    // el badge de "en cola" hasta que vuelva la conexion.
    unawaited(SyncService.instance.pushPending());

    if (!mounted) return;
    _resetearFormulario();
    _mostrarAviso('Cita guardada con éxito.');
  }

  /// Limpia lo ya enviado para que un doble toque no duplique la cita.
  void _resetearFormulario() {
    // Mantiene los datos de contacto para que una segunda cita también pueda
    // usar el perfil guardado; solo se limpian los datos de esta solicitud.
    _prellenarDesdeElPerfil();
    _descripcionController.clear();
    final vehiculo = _vehiculosRegistrados
        .where((item) => item.id == _vehiculoSeleccionadoId)
        .firstOrNull;
    if (vehiculo != null) {
      _marcaController.text = vehiculo.marca;
      _modeloController.text = vehiculo.modelo;
      _anioController.text = vehiculo.anio.toString();
      _placaController.text = vehiculo.placa;
    } else {
      _marcaController.clear();
      _modeloController.clear();
      _anioController.clear();
      _placaController.clear();
    }
    setState(() {
      _serviciosSeleccionados.clear();
      _vehiculoFormularioVisible = false;
      _vehiculoSeleccionado = vehiculo != null;
    });
  }

  void _mostrarAviso(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tallerActual = _tallerActual;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const TituloSeccionCliente(
          eyebrow: 'RESERVA TU VISITA',
          title: 'Agenda tu cita',
          subtitle: 'Cuéntanos qué necesita tu vehículo',
        ),
        const SizedBox(height: 20),
        etiquetaFormularioCliente('Datos de contacto'),
        const SizedBox(height: 8),
        TextField(
          controller: _clienteController,
          textCapitalization: TextCapitalization.words,
          decoration: clienteInputDecoration(
            'Nombre completo',
            hintText: 'Ej: María Pérez',
            prefixIcon: Icons.person_outline,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _correoController,
          keyboardType: TextInputType.emailAddress,
          decoration: clienteInputDecoration(
            'Correo electrónico',
            hintText: 'nombre@ejemplo.com',
            prefixIcon: Icons.email_outlined,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _telefonoController,
          keyboardType: TextInputType.phone,
          decoration: clienteInputDecoration(
            'Teléfono',
            hintText: '809-000-0000',
            prefixIcon: Icons.phone_outlined,
          ),
        ),
        const SizedBox(height: 18),
        etiquetaFormularioCliente('Taller'),
        const SizedBox(height: 8),

        // Sin campo de búsqueda. La directriz de Leandy es que no hay búsqueda
        // libre de talleres: lo que existe son los afiliados, y se eligen de una
        // lista. El filtro por texto que estaba acá se leía como "buscá donde
        // quieras" y llevaba a un mensaje de "no encontramos talleres" cuando lo
        // que pasó fue que el taller no está en nuestra red.
        //
        // La distancia va en el mismo subtitulo que la direccion, y solo si hay
        // GPS: es el mismo dato que el mapa muestra, y el cliente no tiene por
        // que saltarse al mapa para saber si le queda cerca.
        TallerSeleccionTile(
          icon: Icons.location_on_outlined,
          title:
              tallerActual?.nombre ??
              (_cargandoTalleres ? 'Cargando talleres...' : 'Sin seleccionar'),
          subtitle: tallerActual == null
              ? 'Toca para ver los afiliados'
              : _subtituloDe(tallerActual),
          onTap: _seleccionarTaller,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.info_outline, size: 13, color: AppColors.textGray),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Solo agenda en talleres afiliados de AutoFix.',
                style: TextStyle(color: AppColors.textGray, fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        etiquetaFormularioCliente('Vehículo'),
        const SizedBox(height: 8),
        VehiculoPlaceholderCliente(
          formularioVisible: _vehiculoFormularioVisible,
          seleccionado: _vehiculoSeleccionado,
          resumenVehiculo: _vehiculoSeleccionado ? _vehiculoResumen : null,
          marcaController: _marcaController,
          modeloController: _modeloController,
          anioController: _anioController,
          placaController: _placaController,
          errorFormulario: null,
          marcasDisponibles: _marcasDisponibles,
          modelosDisponibles: _modelosDisponibles,
          aniosDisponibles: _aniosDisponibles,
          cargandoMarcas: _cargandoMarcas,
          cargandoModelos: _cargandoModelos,
          mensajeCatalogo: _avisoCatalogo,
          onMarcaSelected: _seleccionarMarca,
          onAnioSelected: _seleccionarAnio,
          onModeloSelected: _seleccionarModelo,
          onRecargarCatalogo: () => unawaited(_cargarMarcas()),
          vehiculosRegistrados: _vehiculosRegistrados,
          vehiculoSeleccionadoId: _vehiculoSeleccionadoId,
          onVehiculoRegistradoSelected: _seleccionarVehiculoRegistrado,
          onAgregarVehiculo: _agregarOtroVehiculo,
          onPressed: () => setState(() => _vehiculoFormularioVisible = true),
          onCancel: () => setState(() => _vehiculoFormularioVisible = false),
          onSave: () => unawaited(_guardarVehiculo()),
        ),
        const SizedBox(height: 18),
        etiquetaFormularioCliente('Servicio'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardWhite,
            border: Border.all(color: AppColors.inputBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
                ),
                child: const Text(
                  'TIPOS DE SERVICIO',
                  style: TextStyle(
                    color: AppColors.textGray,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (_cargandoServicios)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_serviciosDisponibles.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Text(
                    'Todavía no hay servicios configurados.',
                    style: TextStyle(color: AppColors.textGray, fontSize: 12),
                  ),
                )
              else
                for (final servicio in _serviciosDisponibles)
                  Material(
                    color: AppColors.cardWhite,
                    child: CheckboxListTile(
                      dense: true,
                      activeColor: AppColors.orangePrimary,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _serviciosSeleccionados.contains(servicio.nombre),
                      title: Text(
                        servicio.nombre,
                        style: const TextStyle(fontSize: 13),
                      ),
                      // El precio va en la fila y no solo en el total de abajo:
                      // el cliente tiene que ver por qué sube el número antes de
                      // marcar la casilla, no después.
                      subtitle: Text(
                        etiquetaPrecio(servicio.precio),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: servicio.precio > 0
                              ? AppColors.labelDark
                              : AppColors.textGray,
                        ),
                      ),
                      onChanged: (seleccionado) {
                        setState(() {
                          if (seleccionado == true) {
                            _serviciosSeleccionados.add(servicio.nombre);
                          } else {
                            _serviciosSeleccionados.remove(servicio.nombre);
                          }
                        });
                      },
                    ),
                  ),
            ],
          ),
        ),

        // Solo cuando hay algo marcado: un "Total estimado: RD$ 0" debajo de
        // una lista sin nada elegido le dice al cliente que su cita vale cero,
        // que es un mensaje distinto del que dice la verdad ("todavía no
        // elegiste nada").
        if (_serviciosSeleccionados.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ResumenTotal(total: _totalEstimado),
        ],
        const SizedBox(height: 20),
        etiquetaFormularioCliente('Fecha y hora preferidas'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: BotonFechaHoraCliente(
                label: 'Fecha',
                value: formatearFechaCortaCliente(_fechaSeleccionada),
                icon: Icons.calendar_today_outlined,
                onTap: _seleccionarFecha,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: BotonFechaHoraCliente(
                label: 'Hora',
                value: _horaSeleccionada.format(context),
                icon: Icons.access_time,
                onTap: _seleccionarHora,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _descripcionController,
          minLines: 3,
          maxLines: 4,
          decoration: clienteInputDecoration(
            'Descripción',
            hintText: 'Notas adicionales sobre la cita...',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 20),
        botonAccionCliente(
          'Enviar solicitud de cita',
          onPressed: _enviarSolicitud,
        ),
        const SizedBox(height: 10),
        Text(
          'Guardamos tu cita en el dispositivo. El taller la confirma y le '
          'llega el detalle de lo que necesitas.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textGray, fontSize: 12),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Total estimado de los servicios marcados.
///
/// Dice "estimado" y no "total" a proposito: estos son los precios de catálogo,
/// no una cotización. El técnico puede encontrar otra cosa al abrir el carro y
/// el precio final lo acuerda el taller con el cliente. Prometer un total firme
/// acá es una promesa que la app no puede cumplir.
///
/// Cuando el total da 0 porque el catálogo todavía no tiene precios cargados,
/// el texto lo aclara en vez de mostrar "RD$ 0" pelado.
class _ResumenTotal extends StatelessWidget {
  const _ResumenTotal({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final sinPrecios = total == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.orangePrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.orangePrimary.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 18,
            color: AppColors.orangePrimary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total estimado',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.labelDark,
                  ),
                ),
                if (sinPrecios)
                  const Text(
                    'Sin precios cargados todavía',
                    style: TextStyle(fontSize: 10, color: AppColors.textGray),
                  ),
              ],
            ),
          ),
          Text(
            formatearPesosDR(total),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.orangePrimary,
            ),
          ),
        ],
      ),
    );
  }
}

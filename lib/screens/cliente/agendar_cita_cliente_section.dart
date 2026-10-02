import 'package:flutter/material.dart';

import '../../features/citas/data/cita_repository.dart';
import '../../features/citas/models/cita.dart';
import '../../features/talleres/data/taller_repository.dart';
import '../../features/talleres/models/taller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/cliente/agenda_cliente_widgets.dart';
import '../../widgets/cliente/cliente_section_widgets.dart';

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
  final int? tallerSeleccionadoId;

  final ValueChanged<Taller> onTallerSelected;

  @override
  State<AgendarCitaClienteSection> createState() =>
      _AgendarCitaClienteSectionState();
}

class _AgendarCitaClienteSectionState extends State<AgendarCitaClienteSection> {
  /// Catálogo de servicios que el cliente puede marcar. La base no tiene tabla
  /// de servicios (ni precios), así que por ahora son las opciones fijas de la
  /// pantalla; cuando exista, esto pasa a leerse del repositorio.
  static const _serviciosDisponibles = [
    'Cambio de aceite y filtro',
    'Frenos',
    'Suspensión y dirección',
    'Transmisión y caja',
  ];

  final TextEditingController _busquedaTallerController =
      TextEditingController();
  final TextEditingController _clienteController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();
  final TextEditingController _descripcionController = TextEditingController();
  final TextEditingController _marcaController = TextEditingController();
  final TextEditingController _modeloController = TextEditingController();
  final TextEditingController _anioController = TextEditingController();
  final TextEditingController _placaController = TextEditingController();
  final Set<String> _serviciosSeleccionados = {};
  DateTime _fechaSeleccionada = DateTime.now();
  TimeOfDay _horaSeleccionada = const TimeOfDay(hour: 9, minute: 0);
  bool _vehiculoFormularioVisible = false;
  bool _vehiculoSeleccionado = false;

  /// Talleres afiliados reales, leídos de la base local.
  List<Taller> _talleres = const <Taller>[];
  bool _cargandoTalleres = true;

  @override
  void initState() {
    super.initState();
    _cargarTalleres();
  }

  Future<void> _cargarTalleres() async {
    final talleres = await TallerRepository.instance.obtenerActivos();
    if (!mounted) return;
    setState(() {
      _talleres = talleres;
      _cargandoTalleres = false;
    });
  }

  @override
  void dispose() {
    _busquedaTallerController.dispose();
    _clienteController.dispose();
    _telefonoController.dispose();
    _descripcionController.dispose();
    _marcaController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _placaController.dispose();
    super.dispose();
  }

  List<Taller> get _talleresFiltrados {
    final query = _busquedaTallerController.text.trim().toLowerCase();
    if (query.isEmpty) return const <Taller>[];
    return _talleres
        .where(
          (taller) =>
              taller.nombre.toLowerCase().contains(query) ||
              taller.direccion.toLowerCase().contains(query),
        )
        .toList();
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
                  subtitle: Text(taller.direccion),
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

  void _seleccionarTallerDesdeBusqueda(Taller taller) {
    widget.onTallerSelected(taller);
    _busquedaTallerController.clear();
    FocusScope.of(context).unfocus();
    setState(() {});
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

    // Sin `taller_id` la cita quedaría huérfana y el taller no podría verla.
    final tallerId = widget.tallerSeleccionadoId;
    if (tallerId == null) {
      _mostrarAviso('Selecciona un taller para tu cita.');
      return;
    }

    final cita = Cita(
      cliente: cliente,
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
      // No hay catálogo de servicios con precios en la base, así que el cliente
      // no puede calcular un total real. Queda en 0 hasta que administración lo
      // registre.
      total: 0,
    );

    try {
      await CitaRepository.instance.crear(cita);
    } catch (_) {
      _mostrarAviso('No pudimos guardar tu cita. Intenta de nuevo.');
      return;
    }

    if (!mounted) return;
    _resetearFormulario();
    _mostrarAviso('Cita guardada con éxito.');
  }

  /// Limpia lo ya enviado para que un doble toque no duplique la cita.
  void _resetearFormulario() {
    _clienteController.clear();
    _telefonoController.clear();
    _descripcionController.clear();
    _marcaController.clear();
    _modeloController.clear();
    _anioController.clear();
    _placaController.clear();
    setState(() {
      _serviciosSeleccionados.clear();
      _vehiculoFormularioVisible = false;
      _vehiculoSeleccionado = false;
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
        TextField(
          controller: _busquedaTallerController,
          onChanged: (_) => setState(() {}),
          decoration:
              clienteInputDecoration(
                'Buscar taller',
                hintText: 'Nombre del taller o sector',
                prefixIcon: Icons.search,
              ).copyWith(
                suffixIcon: _busquedaTallerController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () {
                          _busquedaTallerController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
        ),
        if (_busquedaTallerController.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          if (_talleresFiltrados.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'No encontramos talleres con esa búsqueda.',
                style: TextStyle(color: AppColors.textGray, fontSize: 12),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardWhite,
                border: Border.all(color: AppColors.inputBorder),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < _talleresFiltrados.length;
                    index++
                  ) ...[
                    if (index > 0)
                      const Divider(height: 1, color: AppColors.inputBorder),
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.location_on_outlined,
                          color: AppColors.orangePrimary,
                        ),
                        title: Text(
                          _talleresFiltrados[index].nombre,
                          style: const TextStyle(
                            color: AppColors.labelDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          _talleresFiltrados[index].direccion,
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing:
                            _talleresFiltrados[index].id ==
                                widget.tallerSeleccionadoId
                            ? const Icon(
                                Icons.check_circle,
                                color: AppColors.greenAccent,
                                size: 19,
                              )
                            : null,
                        onTap: () => _seleccionarTallerDesdeBusqueda(
                          _talleresFiltrados[index],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
        const SizedBox(height: 10),
        TallerSeleccionTile(
          icon: Icons.location_on_outlined,
          title:
              tallerActual?.nombre ??
              (_cargandoTalleres ? 'Cargando talleres...' : 'Sin seleccionar'),
          subtitle: tallerActual?.direccion ?? 'Toca para elegir un taller',
          onTap: _seleccionarTaller,
        ),
        const SizedBox(height: 18),
        etiquetaFormularioCliente('Vehículo'),
        const SizedBox(height: 8),
        VehiculoPlaceholderCliente(
          formularioVisible: _vehiculoFormularioVisible,
          seleccionado: _vehiculoSeleccionado,
          resumenVehiculo: null,
          marcaController: _marcaController,
          modeloController: _modeloController,
          anioController: _anioController,
          placaController: _placaController,
          errorFormulario: null,
          onPressed: () => setState(() => _vehiculoFormularioVisible = true),
          onCancel: () => setState(() => _vehiculoFormularioVisible = false),
          onSave: () => setState(() {
            _vehiculoFormularioVisible = false;
            _vehiculoSeleccionado = true;
          }),
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
              for (final servicio in _serviciosDisponibles)
                Material(
                  color: AppColors.cardWhite,
                  child: CheckboxListTile(
                    dense: true,
                    activeColor: AppColors.orangePrimary,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _serviciosSeleccionados.contains(servicio),
                    title: Text(servicio, style: const TextStyle(fontSize: 13)),
                    onChanged: (seleccionado) {
                      setState(() {
                        if (seleccionado == true) {
                          _serviciosSeleccionados.add(servicio);
                        } else {
                          _serviciosSeleccionados.remove(servicio);
                        }
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
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

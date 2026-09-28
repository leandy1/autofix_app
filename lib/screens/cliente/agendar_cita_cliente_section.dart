import 'package:flutter/material.dart';

import '../../controllers/cliente/vehiculo_cliente_controller.dart';
import '../../models/cliente_dashboard_data.dart';
import '../../theme/app_colors.dart';
import '../../widgets/cliente/agenda_cliente_widgets.dart';
import '../../widgets/cliente/cliente_section_widgets.dart';

class AgendarCitaClienteSection extends StatefulWidget {
  const AgendarCitaClienteSection({
    required this.tallerSeleccionado,
    required this.onTallerSelected,
    super.key,
  });

  final String tallerSeleccionado;
  final ValueChanged<String> onTallerSelected;

  @override
  State<AgendarCitaClienteSection> createState() =>
      _AgendarCitaClienteSectionState();
}

class _AgendarCitaClienteSectionState extends State<AgendarCitaClienteSection> {
  final TextEditingController _busquedaTallerController =
      TextEditingController();
  final VehiculoClienteController _vehiculoController =
      VehiculoClienteController();
  final Set<String> _serviciosSeleccionados = {};
  DateTime _fechaSeleccionada = DateTime.now();
  TimeOfDay _horaSeleccionada = const TimeOfDay(hour: 9, minute: 0);
  bool _solicitudSeleccionada = false;

  @override
  void dispose() {
    _busquedaTallerController.dispose();
    _vehiculoController.dispose();
    super.dispose();
  }

  List<TallerCliente> get _talleresFiltrados {
    final query = _busquedaTallerController.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return talleresCliente
        .where(
          (taller) =>
              taller.nombre.toLowerCase().contains(query) ||
              taller.direccion.toLowerCase().contains(query),
        )
        .toList();
  }

  Future<void> _seleccionarTaller() async {
    final taller = await showModalBottomSheet<String>(
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
            for (final taller in talleresCliente)
              Material(
                color: AppColors.cardWhite,
                child: ListTile(
                  leading: const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.orangePrimary,
                  ),
                  title: Text(taller.nombre),
                  subtitle: Text('${taller.distancia} · ${taller.direccion}'),
                  trailing: widget.tallerSeleccionado == taller.nombre
                      ? const Icon(
                          Icons.check_circle,
                          color: AppColors.greenAccent,
                        )
                      : null,
                  onTap: () => Navigator.pop(context, taller.nombre),
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

  void _seleccionarTallerDesdeBusqueda(TallerCliente taller) {
    widget.onTallerSelected(taller.nombre);
    _busquedaTallerController.clear();
    FocusScope.of(context).unfocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tallerActual = talleresCliente.firstWhere(
      (taller) => taller.nombre == widget.tallerSeleccionado,
    );

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
          textCapitalization: TextCapitalization.words,
          decoration: clienteInputDecoration(
            'Nombre completo',
            hintText: 'Ej: María Pérez',
            prefixIcon: Icons.person_outline,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
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
                          '${_talleresFiltrados[index].direccion} · ${_talleresFiltrados[index].distancia}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing:
                            widget.tallerSeleccionado ==
                                _talleresFiltrados[index].nombre
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
          title: tallerActual.nombre,
          subtitle: '${tallerActual.direccion} · ${tallerActual.distancia}',
          onTap: _seleccionarTaller,
        ),
        const SizedBox(height: 18),
        etiquetaFormularioCliente('Vehículo'),
        const SizedBox(height: 8),
        ListenableBuilder(
          listenable: _vehiculoController,
          builder: (context, _) => VehiculoPlaceholderCliente(
            formularioVisible: _vehiculoController.formularioVisible,
            seleccionado: _vehiculoController.seleccionado,
            resumenVehiculo: _vehiculoController.resumenVehiculo,
            marcaController: _vehiculoController.marcaController,
            modeloController: _vehiculoController.modeloController,
            anioController: _vehiculoController.anioController,
            placaController: _vehiculoController.placaController,
            errorFormulario: _vehiculoController.errorFormulario,
            onPressed: _vehiculoController.abrirFormulario,
            onCancel: _vehiculoController.cancelarFormulario,
            onSave: _vehiculoController.guardarVehiculo,
          ),
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
              for (final servicio in serviciosCliente)
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
          _solicitudSeleccionada ? 'Solicitud seleccionada' : 'Solicitar cita',
          selected: _solicitudSeleccionada,
          onPressed: () =>
              setState(() => _solicitudSeleccionada = !_solicitudSeleccionada),
        ),
        const SizedBox(height: 10),
        const Text(
          'La integración para registrar solicitudes se agregará después.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textGray, fontSize: 12),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

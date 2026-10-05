import 'package:flutter/material.dart';

import 'package:autofix/features/admin/widgets/solicitudes_citas_admin_section.dart';
import 'package:autofix/features/auth/screens/login_screen.dart';
import 'package:autofix/features/citas/models/cita.dart' as cita_data;
import 'package:autofix/features/citas/presentation/citas_controller.dart';
import 'package:autofix/shared/models/cita_admin.dart';
import 'package:autofix/shared/models/demo_admin_data.dart';
import 'package:autofix/shared/theme/app_colors.dart';

import 'dashboard_admin_screen.dart';
import 'configuracion_admin_screen.dart';

const Map<String, Color> kColorPorEstado = {
  'ATRASADAS': AppColors.atrasadas,
  'Pendiente': AppColors.pendientes,
  'Esperando Pieza': AppColors.esperandoPieza,
  'En proceso': AppColors.enProceso,
  'Completado': AppColors.completado,
};

class CitaAdminCard extends StatelessWidget {
  const CitaAdminCard({
    required this.cita,
    this.onEdited,
    this.onDeleted,
    super.key,
  });

  final CitaAdmin cita;
  final ValueChanged<CitaAdmin>? onEdited;
  final ValueChanged<int>? onDeleted;

  static String _estadoTexto(EstadoCitaAdmin estado) {
    switch (estado) {
      case EstadoCitaAdmin.atrasada:
        return 'Atrasadas';
      case EstadoCitaAdmin.pendiente:
        return 'Pendiente';
      case EstadoCitaAdmin.esperandoPieza:
        return 'Esperando Pieza';
      case EstadoCitaAdmin.enProceso:
        return 'En proceso';
      case EstadoCitaAdmin.completada:
        return 'Completado';
    }
  }

  static Color _estadoColor(EstadoCitaAdmin estado) {
    switch (estado) {
      case EstadoCitaAdmin.atrasada:
        return AppColors.atrasadas;
      case EstadoCitaAdmin.pendiente:
        return AppColors.pendientes;
      case EstadoCitaAdmin.esperandoPieza:
        return AppColors.esperandoPieza;
      case EstadoCitaAdmin.enProceso:
        return AppColors.enProceso;
      case EstadoCitaAdmin.completada:
        return AppColors.completado;
    }
  }

  String _fechaFormateada() =>
      '${cita.fecha.day.toString().padLeft(2, '0')}/${cita.fecha.month.toString().padLeft(2, '0')}/${cita.fecha.year}';

  Future<void> _editarCita(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _EditarCitaDialog(
        cita: cita,
        onSaved: (citaActualizada) {
          onEdited?.call(citaActualizada);
        },
      ),
    );
  }

  void _mostrarDetalle(BuildContext context) {
    final partesNombre = cita.cliente.trim().split(RegExp(r'\s+'));
    final nombre = partesNombre.isEmpty || partesNombre.first.isEmpty
        ? ''
        : partesNombre.first;
    final apellido = partesNombre.length > 1
        ? partesNombre.skip(1).join(' ')
        : '—';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                child: Column(
                  children: [
                    const Text(
                      'INFORMACIÓN DE LA CITA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.headerNavy,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE7EAF0)),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle('CLIENTE'),
                      _DetailGrid(
                        fields: [
                          ('Nombre', nombre),
                          ('Apellido', apellido),
                          ('Teléfono', cita.telefono),
                        ],
                      ),
                      const Divider(height: 32, color: Color(0xFFE7EAF0)),
                      const _SectionTitle('CITA'),
                      _DetailGrid(
                        fields: [
                          ('Fecha', _fechaFormateada()),
                          ('Hora', cita.hora.format(context)),
                        ],
                      ),
                      const Divider(height: 32, color: Color(0xFFE7EAF0)),
                      const _SectionTitle('VEHÍCULO'),
                      _DetailGrid(
                        fields: [
                          ('Marca', cita.marca.toUpperCase()),
                          ('Modelo', cita.modelo.toUpperCase()),
                          ('Año', cita.anio),
                          ('Placa', cita.placa.toUpperCase()),
                          ('Técnico', cita.tecnico ?? 'Sin asignar'),
                        ],
                      ),
                      const Divider(height: 32, color: Color(0xFFE7EAF0)),
                      const _SectionTitle('SERVICIOS'),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: cita.servicios.isEmpty
                            ? [const _Chip(label: 'Sin servicios')]
                            : [
                                for (final servicio in cita.servicios)
                                  _Chip(label: servicio),
                              ],
                      ),
                      const Divider(height: 32, color: Color(0xFFE7EAF0)),
                      const _SectionTitle('DESCRIPCIÓN'),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F3F7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          cita.descripcion.isEmpty
                              ? 'Sin descripción'
                              : cita.descripcion,
                          style: const TextStyle(
                            color: AppColors.labelDark,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE7EAF0)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 420;
                    final buttonPadding = EdgeInsets.symmetric(
                      horizontal: compact ? 8 : 16,
                      vertical: 8,
                    );
                    final deleteButton = OutlinedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        if (onDeleted != null) onDeleted!(cita.id);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFFECACA)),
                        padding: buttonPadding,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Eliminar'),
                    );
                    final editButton = OutlinedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _editarCita(context);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.headerNavy,
                        side: const BorderSide(color: AppColors.inputBorder),
                        padding: buttonPadding,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Editar'),
                    );
                    final closeButton = OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.headerNavy,
                        side: const BorderSide(color: AppColors.inputBorder),
                        padding: buttonPadding,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Cerrar'),
                    );

                    if (compact) {
                      return Row(
                        children: [
                          Expanded(child: deleteButton),
                          const SizedBox(width: 6),
                          Expanded(child: editButton),
                          const SizedBox(width: 6),
                          Expanded(child: closeButton),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        deleteButton,
                        const Spacer(),
                        editButton,
                        const SizedBox(width: 10),
                        closeButton,
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _estadoColor(cita.estado);
    final statusLabel = _estadoTexto(cita.estado);
    final statusOptions = [...demoEstadosAdmin];
    if (statusLabel == 'Atrasadas') statusOptions.insert(0, statusLabel);
    final fields = [
      _Field(label: 'CLIENTE', value: cita.cliente),
      _Field(label: 'TELÉFONO', value: cita.telefono),
      _Field(
        label: 'VEHÍCULO',
        value: '${cita.marca} ${cita.modelo} ${cita.anio}',
      ),
      _Field(label: 'PLACA', value: cita.placa),
      _Field(label: 'TÉCNICO', value: cita.tecnico ?? 'Sin asignar'),
      _Field(label: 'FECHA', value: _fechaFormateada()),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EBF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                Text(
                  '#${cita.id}',
                  style: const TextStyle(
                    color: AppColors.headerNavy,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.20),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: statusLabel,
                      isDense: true,
                      alignment: Alignment.center,
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: AppColors.headerNavy,
                      ),
                      dropdownColor: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                      items: statusOptions.map((label) {
                        return DropdownMenuItem<String>(
                          value: label,
                          enabled: label != 'Atrasadas',
                          child: Text(label),
                        );
                      }).toList(),
                      onChanged: (nuevoEstado) {
                        if (nuevoEstado == null) return;
                        final nuevoEstadoEnum = switch (nuevoEstado) {
                          'Pendiente' => EstadoCitaAdmin.pendiente,
                          'Esperando Pieza' => EstadoCitaAdmin.esperandoPieza,
                          'En proceso' => EstadoCitaAdmin.enProceso,
                          'Completado' => EstadoCitaAdmin.completada,
                          _ => cita.estado,
                        };

                        onEdited?.call(
                          CitaAdmin(
                            id: cita.id,
                            cliente: cita.cliente,
                            telefono: cita.telefono,
                            marca: cita.marca,
                            modelo: cita.modelo,
                            anio: cita.anio,
                            placa: cita.placa,
                            servicios: cita.servicios,
                            fecha: cita.fecha,
                            hora: cita.hora,
                            estado: nuevoEstadoEnum,
                            descripcion: cita.descripcion,
                            tecnico: cita.tecnico,
                            total: cita.total,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE7EAF0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 500 ? 2 : 1;
                final fieldWidth =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;

                return Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    for (final field in fields)
                      SizedBox(
                        width: fieldWidth,
                        child: _FieldWidget(
                          label: field.label,
                          value: field.value,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SERVICIOS',
                  style: TextStyle(
                    color: AppColors.placeholderGray,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: cita.servicios.isEmpty
                      ? const [SizedBox.shrink()]
                      : [
                          for (final servicio in cita.servicios)
                            _Chip(label: servicio),
                        ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE7EAF0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'RD\$ ${cita.total.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: AppColors.completado,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => _mostrarDetalle(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.headerNavy,
                    side: const BorderSide(color: AppColors.inputBorder),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Ver detalle'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditarCitaDialog extends StatefulWidget {
  const _EditarCitaDialog({required this.cita, required this.onSaved});

  final CitaAdmin cita;
  final ValueChanged<CitaAdmin> onSaved;

  @override
  State<_EditarCitaDialog> createState() => _EditarCitaDialogState();
}

class _EditarCitaDialogState extends State<_EditarCitaDialog> {
  late final TextEditingController _clienteController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _modeloController;
  late final TextEditingController _anioController;
  late final TextEditingController _placaController;
  late final TextEditingController _descripcionController;
  late DateTime _fecha;
  late TimeOfDay _hora;
  late String? _marcaSeleccionada;
  late String? _tecnicoSeleccionado;
  late String _estadoSeleccionado;
  final Set<String> _serviciosMarcados = {};

  @override
  void initState() {
    super.initState();
    _clienteController = TextEditingController(text: widget.cita.cliente);
    _telefonoController = TextEditingController(text: widget.cita.telefono);
    _modeloController = TextEditingController(text: widget.cita.modelo);
    _anioController = TextEditingController(text: widget.cita.anio);
    _placaController = TextEditingController(text: widget.cita.placa);
    _descripcionController = TextEditingController(
      text: widget.cita.descripcion,
    );
    _fecha = widget.cita.fecha;
    _hora = widget.cita.hora;
    _marcaSeleccionada = demoMarcasVehiculo.contains(widget.cita.marca)
        ? widget.cita.marca
        : demoMarcasVehiculo.first;
    _tecnicoSeleccionado = demoTecnicosAdmin.contains(widget.cita.tecnico)
        ? widget.cita.tecnico
        : null;
    _estadoSeleccionado = switch (widget.cita.estado) {
      EstadoCitaAdmin.atrasada => 'Pendiente',
      EstadoCitaAdmin.pendiente => 'Pendiente',
      EstadoCitaAdmin.esperandoPieza => 'Esperando Pieza',
      EstadoCitaAdmin.enProceso => 'En proceso',
      EstadoCitaAdmin.completada => 'Completado',
    };
    _serviciosMarcados.addAll(widget.cita.servicios);
  }

  @override
  void dispose() {
    _clienteController.dispose();
    _telefonoController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _placaController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  InputDecoration _decoracionCampo(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.textGray),
      hintStyle: const TextStyle(
        color: AppColors.placeholderGray,
        fontSize: 13,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: AppColors.orangePrimary,
          width: 1.5,
        ),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  String _formatearFechaCorta(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: AppColors.headerNavy,
                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Editar Cita',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Material(
                color: AppColors.background,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DATOS DEL CLIENTE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textGray,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _clienteController,
                        decoration: _decoracionCampo('Nombre completo'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _telefonoController,
                        decoration: _decoracionCampo('Teléfono'),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'DATOS DEL VEHÍCULO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textGray,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _marcaSeleccionada,
                              decoration: _decoracionCampo('Marca'),
                              items: demoMarcasVehiculo
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(
                                        m,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (valor) =>
                                  setState(() => _marcaSeleccionada = valor),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _modeloController,
                              decoration: _decoracionCampo('Modelo'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _anioController,
                              keyboardType: TextInputType.number,
                              decoration: _decoracionCampo('Año'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _placaController,
                              decoration: _decoracionCampo('Placa'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'SERVICIOS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textGray,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.inputBorder),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              color: const Color(0xFFF3F5F8),
                              child: const Text(
                                'TIPOS DE SERVICIO',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textGray,
                                ),
                              ),
                            ),
                            ...demoServiciosAdmin.map(
                              (servicio) => CheckboxListTile(
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: _serviciosMarcados.contains(
                                  servicio.nombre,
                                ),
                                onChanged: (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _serviciosMarcados.add(servicio.nombre);
                                    } else {
                                      _serviciosMarcados.remove(
                                        servicio.nombre,
                                      );
                                    }
                                  });
                                },
                                title: Text(
                                  '${servicio.nombre} · ${servicio.precio}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'ASIGNACIÓN',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textGray,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _tecnicoSeleccionado,
                        decoration: _decoracionCampo('Técnico'),
                        items: demoTecnicosAdmin
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(
                                  t,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (valor) =>
                            setState(() => _tecnicoSeleccionado = valor),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final nuevaFecha = await showDatePicker(
                                  context: context,
                                  initialDate: _fecha,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (nuevaFecha != null) {
                                  setState(() => _fecha = nuevaFecha);
                                }
                              },
                              child: InputDecorator(
                                decoration: _decoracionCampo('Fecha'),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatearFechaCorta(_fecha),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 16,
                                      color: AppColors.textGray,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final nuevaHora = await showTimePicker(
                                  context: context,
                                  initialTime: _hora,
                                );
                                if (nuevaHora != null) {
                                  setState(() => _hora = nuevaHora);
                                }
                              },
                              child: InputDecorator(
                                decoration: _decoracionCampo('Hora'),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _hora.format(context),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const Icon(
                                      Icons.access_time,
                                      size: 16,
                                      color: AppColors.textGray,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _estadoSeleccionado,
                        decoration: _decoracionCampo('Estado'),
                        items: demoEstadosAdmin
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text(
                                  e,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (valor) => setState(
                          () => _estadoSeleccionado =
                              valor ?? _estadoSeleccionado,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _descripcionController,
                        maxLines: 3,
                        decoration: _decoracionCampo('Descripción'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(18),
              child: ElevatedButton(
                onPressed: () {
                  final citaActualizada = CitaAdmin(
                    id: widget.cita.id,
                    cliente: _clienteController.text.trim(),
                    telefono: _telefonoController.text.trim(),
                    marca: _marcaSeleccionada ?? widget.cita.marca,
                    modelo: _modeloController.text.trim(),
                    anio: _anioController.text.trim(),
                    placa: _placaController.text.trim(),
                    servicios: _serviciosMarcados.toList(),
                    fecha: _fecha,
                    hora: _hora,
                    estado: switch (_estadoSeleccionado) {
                      'Atrasadas' => EstadoCitaAdmin.atrasada,
                      'Pendiente' => EstadoCitaAdmin.pendiente,
                      'Esperando Pieza' => EstadoCitaAdmin.esperandoPieza,
                      'En proceso' => EstadoCitaAdmin.enProceso,
                      'Completado' => EstadoCitaAdmin.completada,
                      _ => EstadoCitaAdmin.pendiente,
                    },
                    descripcion: _descripcionController.text.trim(),
                    tecnico: _tecnicoSeleccionado,
                    total: widget.cita.total,
                  );
                  widget.onSaved(citaActualizada);
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orangePrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Guardar cambios',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;
}

class _FieldWidget extends StatelessWidget {
  const _FieldWidget({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.placeholderGray,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFEDEFF3)),
          ),
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.fields});

  final List<(String, String)> fields;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 420 ? 2 : 1;
        final fieldWidth =
            (constraints.maxWidth - (columns - 1) * 12) / columns;

        return Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (final field in fields)
              SizedBox(
                width: fieldWidth,
                child: _FieldWidget(label: field.$1, value: field.$2),
              ),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textGray,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F7EF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCFEAD9)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.headerNavy,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class CitasScreen extends StatefulWidget {
  const CitasScreen({super.key});

  @override
  State<CitasScreen> createState() => _CitasScreenState();
}

class _CitasScreenState extends State<CitasScreen> {
  DateTime _fechaSeleccionada = DateTime.now();
  bool _filtrosExpandido = false;
  String? _categoriaExpandida = 'En proceso';
  final CitasController _citasController = CitasController();

  @override
  void initState() {
    super.initState();
    _citasController.cargar();
  }

  @override
  void dispose() {
    _citasController.dispose();
    super.dispose();
  }

  cita_data.Cita _aCitaPersistida(CitaAdmin cita) {
    final estado = switch (cita.estado) {
      EstadoCitaAdmin.atrasada => cita_data.EstadoCita.pendiente,
      EstadoCitaAdmin.pendiente => cita_data.EstadoCita.pendiente,
      EstadoCitaAdmin.esperandoPieza => cita_data.EstadoCita.esperandoPieza,
      EstadoCitaAdmin.enProceso => cita_data.EstadoCita.enProceso,
      EstadoCitaAdmin.completada => cita_data.EstadoCita.completado,
    };
    final fechaCita = DateTime(
      cita.fecha.year,
      cita.fecha.month,
      cita.fecha.day,
      cita.hora.hour,
      cita.hora.minute,
    );
    return cita_data.Cita(
      id: cita.id,
      cliente: cita.cliente,
      telefono: cita.telefono,
      vehiculo: _vehiculoPersistible(
        marca: cita.marca,
        modelo: cita.modelo,
        anio: cita.anio,
        placa: cita.placa,
      ),
      marca: cita.marca,
      modelo: cita.modelo,
      anio: int.tryParse(cita.anio) ?? 0,
      placa: cita.placa,
      servicios: cita.servicios,
      tecnico: cita.tecnico ?? '',
      descripcion: cita.descripcion,
      fechaCita: fechaCita,
      estado: estado,
      total: cita.total,
    );
  }

  String _vehiculoPersistible({
    required String marca,
    required String modelo,
    required String anio,
    required String placa,
  }) {
    final detalleAnio = anio.trim().isEmpty ? '' : ' (${anio.trim()})';
    final detallePlaca = placa.trim().isEmpty ? '' : ' · ${placa.trim()}';
    return '${marca.trim()} ${modelo.trim()}$detalleAnio$detallePlaca'.trim();
  }

  CitaAdmin _citaParaTarjeta(cita_data.Cita cita) {
    final estado = cita.esAtrasada(DateTime.now())
        ? EstadoCitaAdmin.atrasada
        : switch (cita.estado) {
            cita_data.EstadoCita.pendiente => EstadoCitaAdmin.pendiente,
            cita_data.EstadoCita.esperandoPieza =>
              EstadoCitaAdmin.esperandoPieza,
            cita_data.EstadoCita.enProceso => EstadoCitaAdmin.enProceso,
            cita_data.EstadoCita.completado => EstadoCitaAdmin.completada,
          };

    return CitaAdmin(
      id: cita.id!,
      cliente: cita.cliente,
      telefono: cita.telefono,
      marca: cita.marca,
      modelo: cita.modelo,
      anio: cita.anio.toString(),
      placa: cita.placa,
      servicios: cita.servicios,
      fecha: cita.fechaCita,
      hora: TimeOfDay.fromDateTime(cita.fechaCita),
      estado: estado,
      descripcion: cita.descripcion,
      tecnico: cita.tecnico,
      total: cita.total,
    );
  }

  Future<void> _guardarEdicion(CitaAdmin cita) async {
    final guardada = await _citasController.guardar(_aCitaPersistida(cita));
    if (!guardada && mounted) _mostrarErrorPersistencia();
  }

  Future<void> _eliminarCita(int id) async {
    final eliminada = await _citasController.eliminar(id);
    if (!eliminada && mounted) _mostrarErrorPersistencia();
  }

  void _mostrarErrorPersistencia() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_citasController.error ?? 'No se pudo guardar la cita.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      drawer: _buildDrawer(context),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroCard(),
            const SizedBox(height: 16),
            const SolicitudesCitasAdminSection(),
            const SizedBox(height: 16),
            _buildFiltrosAvanzados(),
            const SizedBox(height: 16),
            for (final categoria in kColorPorEstado.keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListenableBuilder(
                  listenable: _citasController,
                  builder: (context, _) => _buildEstadoAccordion(
                    nombre: categoria,
                    color: kColorPorEstado[categoria]!,
                    expanded: _categoriaExpandida == categoria,
                    onTap: () => setState(() {
                      _categoriaExpandida = _categoriaExpandida == categoria
                          ? null
                          : categoria;
                    }),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.headerNavy,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: 0,
      title: const Padding(
        padding: EdgeInsets.only(left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'AutoFix',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'SISTEMA DE GESTIÓN',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: CircleAvatar(
            backgroundColor: AppColors.orangePrimary,
            radius: 18,
            child: const Text(
              'L',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.headerNavy,
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AutoFix',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'SISTEMA DE GESTIÓN',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            _drawerItem(
              icon: Icons.grid_view_rounded,
              label: 'Dashboard',
              selected: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DashboardScreen()),
              ),
            ),
            _drawerItem(
              icon: Icons.calendar_today_outlined,
              label: 'Citas',
              selected: true,
            ),
            _drawerItem(
              icon: Icons.settings_outlined,
              label: 'Configuración',
              selected: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConfiguracionScreen()),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
                icon: const Icon(
                  Icons.logout,
                  size: 18,
                  color: Colors.redAccent,
                ),
                label: const Text(
                  'Cerrar Sesión',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    return Material(
      color: selected
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color: selected ? AppColors.orangePrimary : Colors.white70,
          size: 20,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.orangePrimary : Colors.white70,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        shape: selected
            ? const Border(
                left: BorderSide(color: AppColors.orangePrimary, width: 3),
              )
            : null,
      ),
    );
  }

  Widget _buildHeroCard() {
    final bool esHoy = _esMismoDia(_fechaSeleccionada, DateTime.now());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.headerNavy,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CITAS DE',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            esHoy ? 'Hoy' : _formatearFechaLarga(_fechaSeleccionada),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _navCircleButton(
                Icons.chevron_left,
                onTap: () {
                  setState(
                    () => _fechaSeleccionada = _fechaSeleccionada.subtract(
                      const Duration(days: 1),
                    ),
                  );
                },
              ),
              _buildCampoFechaHero(),
              _navCircleButton(
                Icons.chevron_right,
                onTap: () {
                  setState(
                    () => _fechaSeleccionada = _fechaSeleccionada.add(
                      const Duration(days: 1),
                    ),
                  );
                },
              ),
              ElevatedButton.icon(
                onPressed: _abrirFormularioNuevaCita,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nueva'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orangePrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCampoFechaHero() {
    return InkWell(
      onTap: () async {
        final nuevaFecha = await showDatePicker(
          context: context,
          initialDate: _fechaSeleccionada,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (nuevaFecha != null) setState(() => _fechaSeleccionada = nuevaFecha);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 40,
        constraints: const BoxConstraints(minWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatearFechaCorta(_fechaSeleccionada),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.calendar_today_outlined,
              color: Colors.white54,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navCircleButton(IconData icon, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white38),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
    );
  }

  Widget _buildFiltrosAvanzados() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _filtrosExpandido = !_filtrosExpandido),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_alt_outlined,
                    size: 18,
                    color: AppColors.textGray,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Filtros avanzados',
                      style: TextStyle(color: AppColors.textGray, fontSize: 14),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _filtrosExpandido ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _filtrosExpandido
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Buscar por cliente, vehículo o placa...',
                  hintStyle: const TextStyle(
                    color: AppColors.placeholderGray,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 18,
                    color: AppColors.textGray,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.inputBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppColors.orangePrimary,
                      width: 1.5,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            secondChild: const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoAccordion({
    required String nombre,
    required Color color,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    final citas =
        _citasController.agruparPorEstado(_fechaSeleccionada)[nombre] ??
        const <cita_data.Cita>[];
    final cantidadVisible = citas.length;
    return Column(
      children: [
        Material(
          color: color,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      nombre.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    child: Text(
                      '$cantidadVisible',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: _citasController.cargando
                ? const Center(child: CircularProgressIndicator())
                : _citasController.error != null
                ? Text(
                    'No se pudieron cargar las citas: ${_citasController.error}',
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 13,
                    ),
                  )
                : citas.isEmpty
                ? const Text(
                    'No hay citas en este estado.',
                    style: TextStyle(color: AppColors.textGray, fontSize: 13),
                  )
                : Column(
                    children: [
                      for (final cita in citas)
                        CitaAdminCard(
                          cita: _citaParaTarjeta(cita),
                          onEdited: (citaActualizada) {
                            _guardarEdicion(citaActualizada);
                          },
                          onDeleted: (id) {
                            _eliminarCita(id);
                          },
                        ),
                    ],
                  ),
          ),
          secondChild: const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }

  Widget _tituloSeccionModal(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textGray,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Future<void> _abrirFormularioNuevaCita() async {
    final clienteController = TextEditingController();
    final telefonoController = TextEditingController();
    final modeloController = TextEditingController();
    final anioController = TextEditingController();
    final placaController = TextEditingController();
    final descripcionController = TextEditingController();
    String? marcaSeleccionada;
    String? tecnicoSeleccionado;
    String estadoSeleccionado = 'Pendiente';
    DateTime fecha = DateTime.now();
    TimeOfDay? hora;
    final Set<String> serviciosMarcados = {};
    final formKey = GlobalKey<FormState>();
    bool guardando = false;
    bool intentoGuardar = false;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final hoy = DateTime.now();
            final fechaCita = DateTime(
              fecha.year,
              fecha.month,
              fecha.day,
              hora?.hour ?? 0,
              hora?.minute ?? 0,
            );
            final fechaAnterior = DateTime(
              fecha.year,
              fecha.month,
              fecha.day,
            ).isBefore(DateTime(hoy.year, hoy.month, hoy.day));
            final horaAnterior =
                hora != null && fechaCita.isBefore(hoy) && !fechaAnterior;
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 460,
                  maxHeight: 680,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: const BoxDecoration(
                        color: AppColors.headerNavy,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Nueva Cita',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              FocusScope.of(context).unfocus();
                              Navigator.of(context).pop();
                            },
                            child: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: Material(
                        color: AppColors.background,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(18),

                          child: Form(
                            key: formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _tituloSeccionModal('DATOS DEL CLIENTE'),
                                TextFormField(
                                  controller: clienteController,
                                  onTapOutside: (_) =>
                                      FocusScope.of(context).unfocus(),
                                  textCapitalization: TextCapitalization.words,
                                  decoration: _decoracionCampo(
                                    'Nombre completo',
                                  ).copyWith(hintText: 'Nombre del cliente'),
                                  validator: (valor) {
                                    final nombre = valor?.trim() ?? '';
                                    if (nombre.isEmpty) {
                                      return 'Ingresa el nombre del cliente.';
                                    }
                                    if (nombre.length < 3) {
                                      return 'El nombre debe tener al menos 3 caracteres.';
                                    }
                                    if (RegExp(r'\d').hasMatch(nombre)) {
                                      return 'El nombre no puede contener números.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: telefonoController,
                                  onTapOutside: (_) =>
                                      FocusScope.of(context).unfocus(),
                                  keyboardType: TextInputType.phone,
                                  decoration: _decoracionCampo('Teléfono')
                                      .copyWith(hintText: '809-000-0000'),
                                  validator: (valor) {
                                    final telefono = valor?.trim() ?? '';
                                    if (telefono.isEmpty) {
                                      return 'Ingresa el teléfono del cliente.';
                                    }
                                    if (!RegExp(r'^[+\d\s().-]+$')
                                        .hasMatch(telefono)) {
                                      return 'El teléfono contiene caracteres no válidos.';
                                    }
                                    final digitos = telefono.replaceAll(
                                      RegExp(r'\D'),
                                      '',
                                    );
                                    if (digitos.length < 10 ||
                                        digitos.length > 15) {
                                      return 'Ingresa un teléfono válido (10 a 15 dígitos).';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                _tituloSeccionModal('DATOS DEL VEHÍCULO'),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: marcaSeleccionada,
                                        decoration: _decoracionCampo('Marca'),
                                        validator: (valor) => valor == null
                                            ? 'Selecciona la marca.'
                                            : null,
                                        hint: const Text(
                                          'Seleccionar',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                        items: demoMarcasVehiculo
                                            .map(
                                              (m) => DropdownMenuItem(
                                                value: m,
                                                child: Text(
                                                  m,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (valor) => setDialogState(
                                          () => marcaSeleccionada = valor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextFormField(
                                        controller: modeloController,
                                        onTapOutside: (_) =>
                                            FocusScope.of(context).unfocus(),
                                        textCapitalization:
                                            TextCapitalization.words,
                                        decoration: _decoracionCampo('Modelo')
                                            .copyWith(hintText: 'Ej: Corolla'),
                                        validator: (valor) {
                                          if (valor?.trim().isEmpty ?? true) {
                                            return 'Ingresa el modelo.';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: anioController,
                                        onTapOutside: (_) =>
                                            FocusScope.of(context).unfocus(),
                                        keyboardType: TextInputType.number,
                                        decoration: _decoracionCampo('Año')
                                            .copyWith(hintText: '2020'),
                                        validator: (valor) {
                                          final anio = int.tryParse(
                                            valor?.trim() ?? '',
                                          );
                                          final anioActual =
                                              DateTime.now().year;
                                          if (anio == null) {
                                            return 'Ingresa un año válido.';
                                          }
                                          if (anio < 1900 ||
                                              anio > anioActual + 1) {
                                            return 'El año debe estar entre 1900 y ${anioActual + 1}.';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextFormField(
                                        controller: placaController,
                                        onTapOutside: (_) =>
                                            FocusScope.of(context).unfocus(),
                                        decoration: _decoracionCampo('Placa')
                                            .copyWith(hintText: 'A123456'),
                                        textCapitalization:
                                            TextCapitalization.characters,
                                        validator: (valor) {
                                          final placa = valor?.trim() ?? '';
                                          if (placa.isEmpty) {
                                            return 'Ingresa la placa.';
                                          }
                                          if (!RegExp(r'^[A-Za-z0-9-]{4,10}$')
                                              .hasMatch(placa)) {
                                            return 'Usa de 4 a 10 letras, números o guiones.';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _tituloSeccionModal('SERVICIOS'),
                                const Text(
                                  'Seleccionar servicios',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textGray,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  key: const ValueKey('servicios-cita'),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: AppColors.inputBorder,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        color: const Color(0xFFF3F5F8),
                                        child: const Text(
                                          'TIPOS DE SERVICIO',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textGray,
                                          ),
                                        ),
                                      ),
                                      ...demoServiciosAdmin.map(
                                        (servicio) => CheckboxListTile(
                                          dense: true,
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                          value: serviciosMarcados.contains(
                                            servicio.nombre,
                                          ),
                                          onChanged: (checked) {
                                            setDialogState(() {
                                              if (checked == true) {
                                                serviciosMarcados.add(
                                                  servicio.nombre,
                                                );
                                              } else {
                                                serviciosMarcados.remove(
                                                  servicio.nombre,
                                                );
                                              }
                                            });
                                          },
                                          title: Text(
                                            '${servicio.nombre} · ${servicio.precio}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (intentoGuardar &&
                                    serviciosMarcados.isEmpty) ...[
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Selecciona al menos un servicio.',
                                    style: TextStyle(
                                      color: Color(0xFFB3261E),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                _tituloSeccionModal('ASIGNACIÓN'),
                                DropdownButtonFormField<String>(
                                  initialValue: tecnicoSeleccionado,
                                  decoration: _decoracionCampo('Técnico'),
                                  validator: (valor) => valor == null
                                      ? 'Selecciona un técnico.'
                                      : null,
                                  hint: const Text(
                                    'Seleccionar técnico',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  items: demoTecnicosAdmin
                                      .map(
                                        (t) => DropdownMenuItem(
                                          value: t,
                                          child: Text(
                                            t,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (valor) => setDialogState(
                                    () => tecnicoSeleccionado = valor,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () async {
                                          final nuevaFecha =
                                              await showDatePicker(
                                                context: context,
                                                initialDate: fecha,
                                                firstDate: DateTime(
                                                  hoy.year,
                                                  hoy.month,
                                                  hoy.day,
                                                ),
                                                lastDate: DateTime(2100),
                                              );
                                          if (nuevaFecha != null) {
                                            setDialogState(
                                              () => fecha = nuevaFecha,
                                            );
                                          }
                                        },
                                        child: InputDecorator(
                                          decoration: _decoracionCampo('Fecha')
                                              .copyWith(
                                                errorText:
                                                    intentoGuardar &&
                                                        fechaAnterior
                                                    ? 'La fecha no puede ser anterior a hoy.'
                                                    : null,
                                              ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _formatearFechaCorta(fecha),
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const Icon(
                                                Icons.calendar_today_outlined,
                                                size: 16,
                                                color: AppColors.textGray,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () async {
                                          final nuevaHora =
                                              await showTimePicker(
                                                context: context,
                                                initialTime:
                                                    hora ?? TimeOfDay.now(),
                                              );
                                          if (nuevaHora != null) {
                                            setDialogState(
                                              () => hora = nuevaHora,
                                            );
                                          }
                                        },
                                        child: InputDecorator(
                                          decoration: _decoracionCampo('Hora')
                                              .copyWith(
                                                errorText: intentoGuardar
                                                    ? hora == null
                                                          ? 'Selecciona la hora.'
                                                          : horaAnterior
                                                          ? 'La hora debe ser futura.'
                                                          : null
                                                    : null,
                                              ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                hora == null
                                                    ? '--:--'
                                                    : hora!.format(context),
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const Icon(
                                                Icons.access_time,
                                                size: 16,
                                                color: AppColors.textGray,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String>(
                                  initialValue: estadoSeleccionado,
                                  decoration: _decoracionCampo('Estado'),
                                  items: demoEstadosAdmin
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(
                                            e,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (valor) => setDialogState(
                                    () => estadoSeleccionado =
                                        valor ?? estadoSeleccionado,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: descripcionController,
                                  onTapOutside: (_) =>
                                      FocusScope.of(context).unfocus(),
                                  maxLines: 3,
                                  decoration: _decoracionCampo('Descripción')
                                      .copyWith(
                                        hintText: 'Notas adicionales sobre la cita...',
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      color: AppColors.headerNavy,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: guardando
                                ? null
                                : () async {
                                    setDialogState(() => intentoGuardar = true);
                                    final formularioValido =
                                        formKey.currentState?.validate() ??
                                        false;
                                    final fechaValida =
                                        !fechaAnterior &&
                                        hora != null &&
                                        !horaAnterior;
                                    final serviciosValidos =
                                        serviciosMarcados.isNotEmpty;
                                    if (!formularioValido ||
                                        !fechaValida ||
                                        !serviciosValidos) {
                                      return;
                                    }

                                    final estado = switch (estadoSeleccionado) {
                                      'Esperando Pieza' =>
                                        cita_data.EstadoCita.esperandoPieza,
                                      'En proceso' =>
                                        cita_data.EstadoCita.enProceso,
                                      'Completado' =>
                                        cita_data.EstadoCita.completado,
                                      _ => cita_data.EstadoCita.pendiente,
                                    };
                                    final anio = anioController.text.trim();
                                    final cita = cita_data.Cita(
                                      cliente: clienteController.text.trim(),
                                      telefono: telefonoController.text.trim(),
                                      vehiculo: _vehiculoPersistible(
                                        marca: marcaSeleccionada!,
                                        modelo: modeloController.text,
                                        anio: anio,
                                        placa: placaController.text,
                                      ),
                                      marca: marcaSeleccionada!,
                                      modelo: modeloController.text.trim(),
                                      anio: int.tryParse(anio) ?? 0,
                                      placa: placaController.text.trim(),
                                      servicios: serviciosMarcados.toList(),
                                      fechaCita: DateTime(
                                        fecha.year,
                                        fecha.month,
                                        fecha.day,
                                        hora!.hour,
                                        hora!.minute,
                                      ),
                                      estado: estado,
                                      descripcion: descripcionController.text
                                          .trim(),
                                      tecnico: tecnicoSeleccionado ?? '',
                                      total: 0,
                                    );

                                    setDialogState(() => guardando = true);
                                    final guardada = await _citasController
                                        .guardar(cita);
                                    if (!context.mounted) return;
                                    if (!guardada) {
                                      setDialogState(() => guardando = false);
                                      _mostrarErrorPersistencia();
                                      return;
                                    }
                                    FocusScope.of(context).unfocus();
                                    Navigator.of(context).pop();
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.orangePrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: guardando
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Guardar Cita',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    clienteController.dispose();
    telefonoController.dispose();
    modeloController.dispose();
    anioController.dispose();
    placaController.dispose();
    descripcionController.dispose();
  }

  InputDecoration _decoracionCampo(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.textGray),
      hintStyle: const TextStyle(
        color: AppColors.placeholderGray,
        fontSize: 13,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: AppColors.orangePrimary,
          width: 1.5,
        ),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  bool _esMismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatearFechaCorta(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  String _formatearFechaLarga(DateTime fecha) {
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return '${fecha.day} de ${meses[fecha.month - 1]}';
  }
}

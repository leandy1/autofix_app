import 'package:flutter/material.dart';

import 'package:autofix/shared/theme/app_colors.dart';
import 'package:autofix/features/cliente/models/vehiculo.dart';

class TallerSeleccionTile extends StatelessWidget {
  const TallerSeleccionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardWhite,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.inputBorder),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.orangePrimary, size: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.labelDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textGray,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.expand_more,
                color: AppColors.textGray,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VehiculoPlaceholderCliente extends StatelessWidget {
  const VehiculoPlaceholderCliente({
    required this.formularioVisible,
    required this.seleccionado,
    required this.resumenVehiculo,
    required this.marcaController,
    required this.modeloController,
    required this.anioController,
    required this.placaController,
    required this.errorFormulario,
    required this.marcasDisponibles,
    required this.modelosDisponibles,
    required this.aniosDisponibles,
    required this.cargandoMarcas,
    required this.cargandoModelos,
    required this.mensajeCatalogo,
    required this.onMarcaSelected,
    required this.onAnioSelected,
    required this.onModeloSelected,
    required this.onRecargarCatalogo,
    required this.vehiculosRegistrados,
    required this.vehiculoSeleccionadoId,
    required this.onVehiculoRegistradoSelected,
    required this.onAgregarVehiculo,
    required this.onPressed,
    required this.onCancel,
    required this.onSave,
    super.key,
  });

  final bool formularioVisible;
  final bool seleccionado;
  final String? resumenVehiculo;
  final TextEditingController marcaController;
  final TextEditingController modeloController;
  final TextEditingController anioController;
  final TextEditingController placaController;
  final String? errorFormulario;
  final List<String> marcasDisponibles;
  final List<String> modelosDisponibles;
  final List<String> aniosDisponibles;
  final bool cargandoMarcas;
  final bool cargandoModelos;
  final String? mensajeCatalogo;
  final ValueChanged<String?> onMarcaSelected;
  final ValueChanged<String?> onAnioSelected;
  final ValueChanged<String?> onModeloSelected;
  final VoidCallback onRecargarCatalogo;
  final List<Vehiculo> vehiculosRegistrados;
  final String? vehiculoSeleccionadoId;
  final ValueChanged<Vehiculo?> onVehiculoRegistradoSelected;
  final VoidCallback onAgregarVehiculo;
  final VoidCallback onPressed;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: seleccionado ? AppColors.orangePrimary : AppColors.inputBorder,
        ),
      ),
      child: Column(
        children: [
          if (formularioVisible)
            _VehiculoFormulario(
              marcaController: marcaController,
              modeloController: modeloController,
              anioController: anioController,
              placaController: placaController,
              errorFormulario: errorFormulario,
              marcasDisponibles: marcasDisponibles,
              modelosDisponibles: modelosDisponibles,
              aniosDisponibles: aniosDisponibles,
              cargandoMarcas: cargandoMarcas,
              cargandoModelos: cargandoModelos,
              mensajeCatalogo: mensajeCatalogo,
              onMarcaSelected: onMarcaSelected,
              onAnioSelected: onAnioSelected,
              onModeloSelected: onModeloSelected,
              onRecargarCatalogo: onRecargarCatalogo,
              onCancel: onCancel,
              onSave: onSave,
            )
          else ...[
            if (vehiculosRegistrados.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('vehiculo-$vehiculoSeleccionadoId'),
                initialValue:
                    vehiculosRegistrados.any(
                      (vehiculo) => vehiculo.id == vehiculoSeleccionadoId,
                    )
                    ? vehiculoSeleccionadoId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Mis vehículos registrados',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                hint: const Text('Selecciona un vehículo'),
                isExpanded: true,
                items: [
                  for (final vehiculo in vehiculosRegistrados)
                    DropdownMenuItem(
                      value: vehiculo.id,
                      child: Text(
                        vehiculo.resumen,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => onVehiculoRegistradoSelected(
                  id == null
                      ? null
                      : vehiculosRegistrados.firstWhere(
                          (vehiculo) => vehiculo.id == id,
                        ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Icon(
              seleccionado
                  ? Icons.directions_car_filled_outlined
                  : Icons.directions_car_outlined,
              size: 30,
              color: seleccionado
                  ? AppColors.orangePrimary
                  : AppColors.placeholderGray,
            ),
            const SizedBox(height: 8),
            Text(
              resumenVehiculo ??
                  (seleccionado
                      ? 'Vehículo seleccionado'
                      : vehiculosRegistrados.isEmpty
                      ? 'Aún no tienes vehículos registrados'
                      : 'Selecciona uno de tus vehículos'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.labelDark,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (resumenVehiculo == null) ...[
              const SizedBox(height: 4),
              const Text(
                'Selecciona un vehículo o registra uno para continuar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textGray, fontSize: 11),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onPressed,
              icon: Icon(
                resumenVehiculo == null ? Icons.add : Icons.edit_outlined,
                size: 18,
              ),
              label: Text(
                resumenVehiculo == null
                    ? 'Registrar vehículo'
                    : 'Editar vehículo',
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.orangePrimary,
              ),
            ),
            if (seleccionado) ...[
              TextButton.icon(
                onPressed: onAgregarVehiculo,
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Registrar otro vehículo'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.headerNavy,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _VehiculoFormulario extends StatefulWidget {
  const _VehiculoFormulario({
    required this.marcaController,
    required this.modeloController,
    required this.anioController,
    required this.placaController,
    required this.errorFormulario,
    required this.marcasDisponibles,
    required this.modelosDisponibles,
    required this.aniosDisponibles,
    required this.cargandoMarcas,
    required this.cargandoModelos,
    required this.mensajeCatalogo,
    required this.onMarcaSelected,
    required this.onAnioSelected,
    required this.onModeloSelected,
    required this.onRecargarCatalogo,
    required this.onCancel,
    required this.onSave,
  });

  final TextEditingController marcaController;
  final TextEditingController modeloController;
  final TextEditingController anioController;
  final TextEditingController placaController;
  final String? errorFormulario;
  final List<String> marcasDisponibles;
  final List<String> modelosDisponibles;
  final List<String> aniosDisponibles;
  final bool cargandoMarcas;
  final bool cargandoModelos;
  final String? mensajeCatalogo;
  final ValueChanged<String?> onMarcaSelected;
  final ValueChanged<String?> onAnioSelected;
  final ValueChanged<String?> onModeloSelected;
  final VoidCallback onRecargarCatalogo;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  State<_VehiculoFormulario> createState() => _VehiculoFormularioState();
}

class _VehiculoFormularioState extends State<_VehiculoFormulario> {
  static const String _manual = '__ingreso_manual__';
  bool _marcaManual = false;
  bool _modeloManual = false;
  bool _anioManual = false;

  @override
  void initState() {
    super.initState();
    _marcaManual =
        widget.marcaController.text.isNotEmpty &&
        !widget.marcasDisponibles.contains(widget.marcaController.text.trim());
    _modeloManual =
        widget.modeloController.text.isNotEmpty &&
        !widget.modelosDisponibles.contains(
          widget.modeloController.text.trim(),
        );
    _anioManual =
        widget.anioController.text.isNotEmpty &&
        !widget.aniosDisponibles.contains(widget.anioController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final marca = widget.marcaController.text.trim();
    final anio = widget.anioController.text.trim();
    final modeloHabilitado = marca.isNotEmpty && anio.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Agregar vehículo',
            style: TextStyle(
              color: AppColors.labelDark,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('marca-${_marcaManual ? _manual : marca}'),
          initialValue: _marcaManual
              ? _manual
              : widget.marcasDisponibles.contains(marca)
              ? marca
              : null,
          decoration: _decoracionSelector(
            'Marca',
            widget.cargandoMarcas ? 'Cargando marcas…' : 'Selecciona una marca',
          ),
          isExpanded: true,
          items: [
            for (final opcion in widget.marcasDisponibles)
              DropdownMenuItem(value: opcion, child: Text(opcion)),
            const DropdownMenuItem(
              value: _manual,
              child: Text('Ingresar marca manualmente…'),
            ),
          ],
          onChanged: (valor) {
            if (valor == _manual) {
              widget.onMarcaSelected(null);
              setState(() => _marcaManual = true);
            } else if (valor != null) {
              setState(() => _marcaManual = false);
              widget.onMarcaSelected(valor);
            }
          },
        ),
        if (_marcaManual) ...[
          const SizedBox(height: 10),
          _campoVehiculo(
            controller: widget.marcaController,
            label: 'Marca (manual)',
            hint: 'Ej. Toyota',
            textCapitalization: TextCapitalization.words,
          ),
        ],
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: ValueKey(
            'modelo-${_modeloManual ? _manual : widget.modeloController.text}-'
            '${widget.modelosDisponibles.length}',
          ),
          initialValue: _modeloManual
              ? _manual
              : widget.modelosDisponibles.contains(
                  widget.modeloController.text.trim(),
                )
              ? widget.modeloController.text.trim()
              : null,
          decoration: _decoracionSelector(
            'Modelo',
            !modeloHabilitado
                ? 'Selecciona primero marca y año'
                : widget.cargandoModelos
                ? 'Consultando modelos…'
                : 'Selecciona un modelo',
          ),
          isExpanded: true,
          items: [
            for (final opcion in widget.modelosDisponibles)
              DropdownMenuItem(value: opcion, child: Text(opcion)),
            const DropdownMenuItem(
              value: _manual,
              child: Text('Ingresar modelo manualmente…'),
            ),
          ],
          onChanged: !modeloHabilitado
              ? null
              : (valor) {
                  if (valor == _manual) {
                    widget.onModeloSelected(null);
                    setState(() => _modeloManual = true);
                  } else if (valor != null) {
                    setState(() => _modeloManual = false);
                    widget.onModeloSelected(valor);
                  }
                },
        ),
        if (_modeloManual) ...[
          const SizedBox(height: 10),
          _campoVehiculo(
            controller: widget.modeloController,
            label: 'Modelo (manual)',
            hint: 'Ej. Corolla',
            textCapitalization: TextCapitalization.words,
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('anio-${_anioManual ? _manual : anio}'),
                initialValue: _anioManual
                    ? _manual
                    : widget.aniosDisponibles.contains(anio)
                    ? anio
                    : null,
                decoration: _decoracionSelector('Año', 'Selecciona el año'),
                isExpanded: true,
                items: [
                  for (final opcion in widget.aniosDisponibles)
                    DropdownMenuItem(value: opcion, child: Text(opcion)),
                  const DropdownMenuItem(value: _manual, child: Text('Otro…')),
                ],
                onChanged: (valor) {
                  if (valor == _manual) {
                    widget.onAnioSelected(null);
                    setState(() => _anioManual = true);
                  } else if (valor != null) {
                    setState(() => _anioManual = false);
                    widget.onAnioSelected(valor);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _campoVehiculo(
                controller: widget.placaController,
                label: 'Placa',
                hint: 'A123456',
                textCapitalization: TextCapitalization.characters,
              ),
            ),
          ],
        ),
        if (_anioManual) ...[
          const SizedBox(height: 10),
          _campoVehiculo(
            controller: widget.anioController,
            label: 'Año (manual)',
            hint: '2022',
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
        ],
        if (widget.mensajeCatalogo != null) ...[
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline,
                size: 15,
                color: AppColors.textGray,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.mensajeCatalogo!,
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 11,
                  ),
                ),
              ),
              if (widget.mensajeCatalogo!.contains('No se pudo') ||
                  widget.mensajeCatalogo!.contains('Sin conexión'))
                TextButton(
                  onPressed: widget.onRecargarCatalogo,
                  child: const Text('Reintentar'),
                ),
            ],
          ),
        ],
        if (widget.errorFormulario != null) ...[
          const SizedBox(height: 10),
          Text(
            widget.errorFormulario!,
            style: const TextStyle(color: AppColors.atrasadas, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onCancel,
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: widget.onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orangePrimary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Guardar'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _decoracionSelector(
    String label,
    String hint,
  ) => InputDecoration(
    labelText: label,
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    labelStyle: const TextStyle(color: AppColors.textGray, fontSize: 12),
    hintStyle: const TextStyle(color: AppColors.placeholderGray, fontSize: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: AppColors.inputBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: AppColors.orangePrimary, width: 1.4),
    ),
  );

  Widget _campoVehiculo({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        labelStyle: const TextStyle(color: AppColors.textGray, fontSize: 12),
        hintStyle: const TextStyle(
          color: AppColors.placeholderGray,
          fontSize: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(
            color: AppColors.orangePrimary,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

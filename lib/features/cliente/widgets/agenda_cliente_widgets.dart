import 'package:flutter/material.dart';

import 'package:autofix/shared/theme/app_colors.dart';

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
              onCancel: onCancel,
              onSave: onSave,
            )
          else ...[
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
                      ? 'Selección visual activa'
                      : 'Aún no tienes un vehículo seleccionado'),
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
                'Agrega los datos de tu vehículo para continuar.',
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
                    ? 'Agregar vehículo'
                    : 'Editar vehículo',
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.orangePrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VehiculoFormulario extends StatelessWidget {
  const _VehiculoFormulario({
    required this.marcaController,
    required this.modeloController,
    required this.anioController,
    required this.placaController,
    required this.errorFormulario,
    required this.onCancel,
    required this.onSave,
  });

  final TextEditingController marcaController;
  final TextEditingController modeloController;
  final TextEditingController anioController;
  final TextEditingController placaController;
  final String? errorFormulario;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
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
        _campoVehiculo(
          controller: marcaController,
          label: 'Marca',
          hint: 'Ej. Toyota',
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 10),
        _campoVehiculo(
          controller: modeloController,
          label: 'Modelo',
          hint: 'Ej. Corolla',
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _campoVehiculo(
                controller: anioController,
                label: 'Año',
                hint: '2022',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _campoVehiculo(
                controller: placaController,
                label: 'Placa',
                hint: 'A123456',
                textCapitalization: TextCapitalization.characters,
              ),
            ),
          ],
        ),
        if (errorFormulario != null) ...[
          const SizedBox(height: 10),
          Text(
            errorFormulario!,
            style: const TextStyle(color: AppColors.atrasadas, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onCancel,
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: onSave,
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

  Widget _campoVehiculo({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
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

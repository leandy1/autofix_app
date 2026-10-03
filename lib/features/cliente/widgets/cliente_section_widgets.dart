import 'package:flutter/material.dart';

import 'package:autofix/shared/theme/app_colors.dart';

const clienteCardShadow = [
  BoxShadow(color: Color(0x100B1E3F), blurRadius: 14, offset: Offset(0, 5)),
];

class TituloSeccionCliente extends StatelessWidget {
  const TituloSeccionCliente({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: AppColors.orangePrimary,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.labelDark,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
      ],
    );
  }
}

InputDecoration clienteInputDecoration(
  String label, {
  String? hintText,
  IconData? prefixIcon,
  bool alignLabelWithHint = false,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    alignLabelWithHint: alignLabelWithHint,
    prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 19),
    filled: true,
    fillColor: AppColors.cardWhite,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    labelStyle: const TextStyle(color: AppColors.textGray, fontSize: 13),
    hintStyle: const TextStyle(color: AppColors.placeholderGray, fontSize: 13),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.inputBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(
        color: AppColors.orangePrimary,
        width: 1.5,
      ),
    ),
  );
}

Widget etiquetaFormularioCliente(String label) {
  return Text(
    label,
    style: const TextStyle(
      color: AppColors.labelDark,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    ),
  );
}

class BotonFechaHoraCliente extends StatelessWidget {
  const BotonFechaHoraCliente({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardWhite,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          decoration: clienteInputDecoration(label),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.labelDark,
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(icon, size: 16, color: AppColors.textGray),
            ],
          ),
        ),
      ),
    );
  }
}

Widget botonAccionCliente(
  String label, {
  required VoidCallback onPressed,
  bool selected = false,
}) {
  return SizedBox(
    width: double.infinity,
    height: 50,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor:
            selected ? AppColors.headerNavy : AppColors.orangePrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

String formatearFechaCliente(DateTime date) {
  const weekdays = [
    'LUNES',
    'MARTES',
    'MIÉRCOLES',
    'JUEVES',
    'VIERNES',
    'SÁBADO',
    'DOMINGO',
  ];
  const months = [
    'ENERO',
    'FEBRERO',
    'MARZO',
    'ABRIL',
    'MAYO',
    'JUNIO',
    'JULIO',
    'AGOSTO',
    'SEPTIEMBRE',
    'OCTUBRE',
    'NOVIEMBRE',
    'DICIEMBRE',
  ];
  return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
}

String formatearFechaCortaCliente(DateTime date) {
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  return '${date.day} ${months[date.month - 1]}';
}

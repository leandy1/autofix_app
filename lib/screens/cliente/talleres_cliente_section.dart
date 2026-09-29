import 'package:flutter/material.dart';

import '../../models/cliente_dashboard_data.dart';
import '../../models/demo_cliente_data.dart';
import '../../theme/app_colors.dart';
import '../../widgets/cliente/cliente_section_widgets.dart';
import '../../widgets/cliente/taller_cliente_widgets.dart';

class TalleresClienteSection extends StatefulWidget {
  const TalleresClienteSection({
    required this.tallerSeleccionado,
    required this.onTallerSelected,
    super.key,
  });

  final String tallerSeleccionado;
  final ValueChanged<String> onTallerSelected;

  @override
  State<TalleresClienteSection> createState() => _TalleresClienteSectionState();
}

class _TalleresClienteSectionState extends State<TalleresClienteSection> {
  void _seleccionarTaller(TallerCliente taller) {
    widget.onTallerSelected(taller.nombre);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${taller.nombre} seleccionado para tu cita'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const TituloSeccionCliente(
          eyebrow: 'ENCUENTRA TU TALLER',
          title: 'Talleres cercanos',
          subtitle: 'Opciones disponibles cerca de tu ubicación',
        ),
        const SizedBox(height: 16),
        Container(
          height: 220,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFE7EDF0),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.inputBorder),
          ),
          child: Stack(
            children: [
              const Positioned.fill(
                child: CustomPaint(painter: MapaTalleresPainter()),
              ),
              Positioned.fill(
                child: Stack(
                  children: [
                    Align(
                      alignment: const Alignment(-0.5, -0.35),
                      child: TallerMapaPin(
                        taller: talleresCliente[0],
                        seleccionado:
                            widget.tallerSeleccionado ==
                            talleresCliente[0].nombre,
                        onTap: () => _seleccionarTaller(talleresCliente[0]),
                      ),
                    ),
                    Align(
                      alignment: const Alignment(0.35, 0.45),
                      child: TallerMapaPin(
                        taller: talleresCliente[1],
                        seleccionado:
                            widget.tallerSeleccionado ==
                            talleresCliente[1].nombre,
                        onTap: () => _seleccionarTaller(talleresCliente[1]),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 16,
                top: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.my_location,
                        size: 16,
                        color: AppColors.orangePrimary,
                      ),
                      SizedBox(width: 7),
                      Text(
                        'Santo Domingo',
                        style: TextStyle(
                          color: AppColors.labelDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Centrar mapa',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Mostrando talleres en Santo Domingo'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.near_me_outlined,
                      size: 20,
                      color: AppColors.headerNavy,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Talleres disponibles',
                style: TextStyle(
                  color: AppColors.labelDark,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${talleresCliente.length} cerca de ti',
              style: const TextStyle(
                color: AppColors.textGray,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < talleresCliente.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          TallerClienteCard(
            taller: talleresCliente[index],
            seleccionado:
                widget.tallerSeleccionado == talleresCliente[index].nombre,
            onTap: () => _seleccionarTaller(talleresCliente[index]),
          ),
        ],
      ],
    );
  }
}

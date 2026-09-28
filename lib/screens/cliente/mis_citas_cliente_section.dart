import 'package:flutter/material.dart';

import '../../models/cliente_dashboard_data.dart';
import '../../theme/app_colors.dart';
import '../../widgets/cliente/cliente_section_widgets.dart';

class MisCitasClienteSection extends StatelessWidget {
  const MisCitasClienteSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const TituloSeccionCliente(
          eyebrow: 'TUS VISITAS',
          title: 'Mis citas',
          subtitle: 'Presenta el código QR al llegar al taller',
        ),
        const SizedBox(height: 18),
        for (var index = 0; index < citasClienteDemo.length; index++) ...[
          if (index > 0) const SizedBox(height: 14),
          _AppointmentCard(cita: citasClienteDemo[index]),
        ],
      ],
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.cita});

  final CitaClienteDemo cita;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(15),
        boxShadow: clienteCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatearFechaCliente(cita.fecha),
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.55,
                  ),
                ),
              ),
              _StatusBadge(label: cita.estado, color: cita.colorEstado),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.orangePrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.build_outlined,
                  color: AppColors.orangePrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cita.taller,
                      style: const TextStyle(
                        color: AppColors.labelDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cita.servicio,
                      style: const TextStyle(
                        color: AppColors.textGray,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      cita.vehiculo,
                      style: const TextStyle(
                        color: AppColors.labelDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Divider(height: 1, color: AppColors.inputBorder),
          ),
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 16,
                color: AppColors.headerNavy.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Text(
                cita.hora,
                style: const TextStyle(
                  color: AppColors.labelDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Código ${cita.codigo}',
                style: const TextStyle(color: AppColors.textGray, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Material(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showQrPreview(context, cita),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const _MockQrCode(size: 68),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Código de tu cita',
                            style: TextStyle(
                              color: AppColors.labelDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Toca para ampliar la vista previa del QR.',
                            style: TextStyle(
                              color: AppColors.textGray,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.open_in_full,
                      color: AppColors.textGray,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showQrPreview(BuildContext context, CitaClienteDemo cita) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Código QR de la cita',
              style: TextStyle(
                color: AppColors.labelDark,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              cita.codigo,
              style: const TextStyle(
                color: AppColors.orangePrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            const _MockQrCode(size: 180),
            const SizedBox(height: 14),
            const Text(
              'Vista previa ilustrativa',
              style: TextStyle(color: AppColors.textGray, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cerrar',
              style: TextStyle(color: AppColors.orangePrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MockQrCode extends StatelessWidget {
  const _MockQrCode({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const _QrPatternPainter(),
    );
  }
}

class _QrPatternPainter extends CustomPainter {
  const _QrPatternPainter();

  static const _modules = 17;

  @override
  void paint(Canvas canvas, Size size) {
    final module = size.width / _modules;
    final fill = Paint()..color = AppColors.headerNavy;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    for (var y = 0; y < _modules; y++) {
      for (var x = 0; x < _modules; x++) {
        if (_isFinder(x, y)) {
          if (_finderModuleIsFilled(x, y)) {
            canvas.drawRect(
              Rect.fromLTWH(x * module, y * module, module, module),
              fill,
            );
          }
        } else if ((x * 7 + y * 11 + x * y) % 5 < 2) {
          canvas.drawRect(
            Rect.fromLTWH(x * module, y * module, module, module),
            fill,
          );
        }
      }
    }
  }

  bool _isFinder(int x, int y) =>
      (x < 5 && y < 5) ||
      (x >= _modules - 5 && y < 5) ||
      (x < 5 && y >= _modules - 5);

  bool _finderModuleIsFilled(int x, int y) {
    final localX = x >= _modules - 5 ? x - (_modules - 5) : x;
    final localY = y >= _modules - 5 ? y - (_modules - 5) : y;
    return localX == 0 ||
        localX == 4 ||
        localY == 0 ||
        localY == 4 ||
        (localX == 2 && localY == 2);
  }

  @override
  bool shouldRepaint(covariant _QrPatternPainter oldDelegate) => false;
}

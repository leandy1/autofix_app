import 'package:flutter/material.dart';

import 'package:autofix/shared/models/cliente_dashboard_data.dart';
import 'package:autofix/shared/theme/app_colors.dart';

import 'cliente_section_widgets.dart';

class TallerMapaPin extends StatelessWidget {
  const TallerMapaPin({
    required this.taller,
    required this.seleccionado,
    required this.onTap,
    super.key,
  });

  final TallerCliente taller;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: seleccionado
                      ? AppColors.orangePrimary
                      : AppColors.headerNavy,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  taller.nombre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.location_on,
                color: seleccionado
                    ? AppColors.headerNavy
                    : AppColors.orangePrimary,
                size: seleccionado ? 33 : 29,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TallerClienteCard extends StatelessWidget {
  const TallerClienteCard({
    required this.taller,
    required this.seleccionado,
    required this.onTap,
    super.key,
  });

  final TallerCliente taller;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: seleccionado
                  ? AppColors.orangePrimary
                  : Colors.transparent,
              width: 1.2,
            ),
            boxShadow: clienteCardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.headerNavy,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.car_repair,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            taller.nombre,
                            style: const TextStyle(
                              color: AppColors.labelDark,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.star,
                          color: Color(0xFFF4B740),
                          size: 15,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          taller.calificacion,
                          style: const TextStyle(
                            color: AppColors.labelDark,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      taller.direccion,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textGray,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      taller.horario,
                      style: const TextStyle(
                        color: AppColors.greenAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  const Icon(
                    Icons.near_me_outlined,
                    color: AppColors.orangePrimary,
                    size: 18,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    taller.distancia,
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MapaTalleresPainter extends CustomPainter {
  const MapaTalleresPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final parkPaint = Paint()..color = const Color(0xFFD4E7D6);
    final blockPaint = Paint()..color = const Color(0xFFDCE3E6);
    final roadPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 17
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final smallRoadPaint = Paint()
      ..color = const Color(0xFFF8FAFB)
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE9EFF0),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.7, 10, size.width * 0.26, 46),
        const Radius.circular(10),
      ),
      parkPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(12, size.height * 0.68, size.width * 0.29, 56),
        const Radius.circular(10),
      ),
      parkPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.42, size.height * 0.1, 52, 48),
        const Radius.circular(8),
      ),
      blockPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.73, size.height * 0.7, 60, 44),
        const Radius.circular(8),
      ),
      blockPaint,
    );
    final mainRoad = Path()
      ..moveTo(-10, size.height * 0.78)
      ..cubicTo(
        size.width * 0.24,
        size.height * 0.72,
        size.width * 0.5,
        size.height * 0.49,
        size.width + 15,
        size.height * 0.43,
      );
    final crossRoad = Path()
      ..moveTo(size.width * 0.43, -10)
      ..cubicTo(
        size.width * 0.47,
        size.height * 0.34,
        size.width * 0.32,
        size.height * 0.68,
        size.width * 0.38,
        size.height + 10,
      );
    canvas.drawPath(mainRoad, roadPaint);
    canvas.drawPath(crossRoad, roadPaint);
    for (var index = 0; index < 3; index++) {
      final street = Path()
        ..moveTo(size.width * (0.12 + index * 0.3), -5)
        ..lineTo(size.width * (0.27 + index * 0.22), size.height + 5);
      canvas.drawPath(street, smallRoadPaint);
    }
  }

  @override
  bool shouldRepaint(covariant MapaTalleresPainter oldDelegate) => false;
}

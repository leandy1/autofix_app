import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:autofix/shared/theme/app_colors.dart';

/// Renderiza localmente el QR de una cita. El único dato codificado es el
/// [codigoVisible]; no realiza solicitudes ni requiere conectividad.
class CodigoQrCita extends StatelessWidget {
  const CodigoQrCita({required this.codigoVisible, this.size = 220, super.key});

  final String codigoVisible;
  final double size;

  @override
  Widget build(BuildContext context) => QrImageView(
    data: codigoVisible,
    version: QrVersions.auto,
    size: size,
    backgroundColor: Colors.white,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: AppColors.headerNavy,
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: AppColors.headerNavy,
    ),
  );
}

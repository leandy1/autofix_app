import 'package:flutter/material.dart';

import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/cliente/widgets/codigo_qr_cita.dart';
import 'package:autofix/shared/theme/app_colors.dart';

/// Acción y modal de QR. No aparece hasta que el Admin acepta la cita.
class AccionQrCitaCliente extends StatelessWidget {
  const AccionQrCitaCliente({required this.cita, super.key});

  final Cita cita;

  @override
  Widget build(BuildContext context) {
    if (cita.estado != EstadoCita.aceptada) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _mostrarQr(context),
        icon: const Icon(Icons.qr_code_2),
        label: const Text('Ver Código QR'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.orangePrimary,
          side: const BorderSide(color: AppColors.orangePrimary),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  void _mostrarQr(BuildContext context) {
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
              cita.identificadorParaPantalla,
              style: const TextStyle(
                color: AppColors.orangePrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            CodigoQrCita(codigoVisible: cita.codigoVisible),
            const SizedBox(height: 14),
            Text(
              cita.tieneCodigoDefinitivo
                  ? 'Este código identifica tu cita en el taller.'
                  : 'Código temporal: se confirmará al sincronizar. La cita '
                        'sigue guardada en este dispositivo.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textGray, fontSize: 12),
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

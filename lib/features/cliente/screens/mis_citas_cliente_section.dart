import 'package:flutter/material.dart';

import 'package:autofix/features/cliente/widgets/cliente_section_widgets.dart';
import 'package:autofix/shared/models/cliente_dashboard_data.dart';
import 'package:autofix/shared/models/demo_cliente_data.dart';
import 'package:autofix/shared/models/solicitud_cita_cliente.dart';
import 'package:autofix/shared/theme/app_colors.dart';

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
        const SizedBox(height: 18),
        const TituloSeccionCliente(
          eyebrow: 'SOLICITUDES ENVIADAS',
          title: 'Seguimiento de citas',
          subtitle: 'Datos de demostración; las respuestas no se guardan.',
        ),
        const SizedBox(height: 12),
        _SolicitudCitaClienteCard(solicitud: demoSeguimientoCitaCliente),
      ],
    );
  }
}

class _SolicitudCitaClienteCard extends StatelessWidget {
  const _SolicitudCitaClienteCard({required this.solicitud});

  final SolicitudCitaCliente solicitud;

  @override
  Widget build(BuildContext context) {
    final propuesta = solicitud.estado == EstadoSolicitudCita.fechaPropuesta;
    final aceptada = solicitud.estado == EstadoSolicitudCita.aceptada;
    final rechazada = solicitud.estado == EstadoSolicitudCita.rechazada;
    final estado = propuesta
        ? 'Nueva fecha propuesta'
        : aceptada
        ? 'Cita aceptada'
        : rechazada
        ? 'Cita rechazada'
        : 'Esperando respuesta del taller';
    final colorEstado = propuesta
        ? AppColors.blueAccent
        : aceptada
        ? AppColors.greenAccent
        : rechazada
        ? AppColors.atrasadas
        : AppColors.pendientes;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: propuesta ? AppColors.blueAccent : AppColors.inputBorder,
        ),
        boxShadow: clienteCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Solicitud enviada al taller',
                  style: TextStyle(
                    color: AppColors.labelDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StatusBadge(label: estado, color: colorEstado),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            solicitud.taller,
            style: const TextStyle(
              color: AppColors.labelDark,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            solicitud.servicios.join(', '),
            style: const TextStyle(color: AppColors.textGray, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.directions_car_outlined,
                size: 16,
                color: AppColors.textGray,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  solicitud.vehiculo,
                  style: const TextStyle(
                    color: AppColors.labelDark,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.calendar_month_outlined,
                size: 16,
                color: AppColors.textGray,
              ),
              const SizedBox(width: 6),
              Text(
                '${formatearFechaCortaCliente(solicitud.fecha)} · ${solicitud.hora.format(context)}',
                style: const TextStyle(
                  color: AppColors.labelDark,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (propuesta) ...[
            const SizedBox(height: 12),
            const Text(
              'El taller propone este nuevo horario. ¿Te funciona?',
              style: TextStyle(
                color: AppColors.blueAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _mostrarAvisoDemo(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.atrasadas,
                    side: BorderSide(
                      color: AppColors.atrasadas.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text('No me funciona'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _mostrarAvisoDemo(context),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Aceptar horario'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.greenAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _mostrarAvisoDemo(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Vista de demostración: la respuesta no se guarda.'),
        behavior: SnackBarBehavior.floating,
      ),
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

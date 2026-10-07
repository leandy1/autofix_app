import 'package:flutter/material.dart';

import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/shared/theme/app_colors.dart';

/// Solicitudes persistidas en SQLite. Las decisiones del admin viajan al
/// repositorio mediante [onCambiarEstado], que deja la cita pendiente de sync.
class SolicitudesCitasAdminSection extends StatelessWidget {
  const SolicitudesCitasAdminSection({
    required this.citas,
    required this.onCambiarEstado,
    this.cargando = false,
    super.key,
  });

  final List<Cita> citas;
  final Future<void> Function(Cita cita, EstadoCita estado) onCambiarEstado;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    final pendientes = citas
        .where((cita) => cita.estado == EstadoCita.pendiente)
        .toList(growable: false);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.orangePrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.mark_email_unread_outlined,
                  color: AppColors.orangePrimary,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Solicitudes de citas',
                      style: TextStyle(
                        color: AppColors.headerNavy,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Revisa y responde las citas pendientes.',
                      style: TextStyle(color: AppColors.textGray, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.orangePrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${pendientes.length} pendientes',
                  style: const TextStyle(
                    color: AppColors.orangePrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (cargando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (pendientes.isEmpty)
            const _SolicitudesVacias()
          else
            for (final cita in pendientes) ...[
              _SolicitudPendienteCard(
                cita: cita,
                onCambiarEstado: onCambiarEstado,
              ),
              if (cita != pendientes.last) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _SolicitudesVacias extends StatelessWidget {
  const _SolicitudesVacias();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Column(
      children: [
        Icon(Icons.inbox_outlined, color: AppColors.textGray, size: 28),
        SizedBox(height: 7),
        Text(
          'No hay solicitudes pendientes.',
          style: TextStyle(
            color: AppColors.headerNavy,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _SolicitudPendienteCard extends StatefulWidget {
  const _SolicitudPendienteCard({
    required this.cita,
    required this.onCambiarEstado,
  });

  final Cita cita;
  final Future<void> Function(Cita cita, EstadoCita estado) onCambiarEstado;

  @override
  State<_SolicitudPendienteCard> createState() =>
      _SolicitudPendienteCardState();
}

class _SolicitudPendienteCardState extends State<_SolicitudPendienteCard> {
  bool _guardando = false;

  Future<void> _responder(EstadoCita estado) async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      await widget.onCambiarEstado(widget.cita, estado);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cita = widget.cita;
    final fecha = cita.fechaCita.toLocal();
    final fechaHora =
        '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/${fecha.year} · '
        '${fecha.hour.toString().padLeft(2, '0')}:'
        '${fecha.minute.toString().padLeft(2, '0')}';
    final vehiculo = '${cita.marca} ${cita.modelo} ${cita.anio}'.trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cita.identificadorParaPantalla,
                  style: const TextStyle(
                    color: AppColors.headerNavy,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const _EstadoPendienteBadge(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            cita.cliente,
            style: const TextStyle(
              color: AppColors.headerNavy,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          _DatoSolicitud(icon: Icons.phone_outlined, texto: cita.telefono),
          _DatoSolicitud(
            icon: Icons.directions_car_outlined,
            texto: vehiculo.isEmpty ? cita.vehiculo : vehiculo,
          ),
          _DatoSolicitud(icon: Icons.calendar_month_outlined, texto: fechaHora),
          if (cita.servicios.isNotEmpty)
            _DatoSolicitud(
              icon: Icons.build_outlined,
              texto: cita.servicios.join(', '),
            ),
          if (cita.descripcion.trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              cita.descripcion,
              style: const TextStyle(color: AppColors.textGray, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _guardando
                      ? null
                      : () => _responder(EstadoCita.rechazada),
                  icon: const Icon(Icons.close, size: 17),
                  label: const Text('Rechazar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.atrasadas,
                    side: const BorderSide(color: AppColors.atrasadas),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _guardando
                      ? null
                      : () => _responder(EstadoCita.aceptada),
                  icon: _guardando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 17),
                  label: Text(_guardando ? 'Guardando' : 'Aceptar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.greenAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EstadoPendienteBadge extends StatelessWidget {
  const _EstadoPendienteBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.pendientes.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Text(
      'Pendiente',
      style: TextStyle(
        color: AppColors.pendientes,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _DatoSolicitud extends StatelessWidget {
  const _DatoSolicitud({required this.icon, required this.texto});

  final IconData icon;
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppColors.textGray),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(color: AppColors.textGray, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';

import '../../models/solicitud_admin.dart';
import '../../services/solicitudes_admin_service.dart';
import '../../theme/app_colors.dart';

class SolicitudesAdminSection extends StatefulWidget {
  const SolicitudesAdminSection({
    super.key,
    required this.service,
  });

  final SolicitudesAdminService service;

  @override
  State<SolicitudesAdminSection> createState() =>
      _SolicitudesAdminSectionState();
}

class _SolicitudesAdminSectionState
    extends State<SolicitudesAdminSection> {
  @override
  Widget build(BuildContext context) {
    final solicitudes = widget.service.nuevas;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(solicitudes.length),
        const SizedBox(height: 12),
        if (solicitudes.isEmpty)
          _buildEmptyState()
        else
          for (final solicitud in solicitudes)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SolicitudAdminCard(
                solicitud: solicitud,
                onAceptar: () => _aceptar(solicitud.id),
                onRechazar: () => _rechazar(solicitud.id),
                onGestionar: () => _gestionar(solicitud),
              ),
            ),
      ],
    );
  }

  Widget _buildHeader(int cantidad) {
    return Row(
      children: [
        const Icon(
          Icons.assignment_outlined,
          color: AppColors.headerNavy,
          size: 22,
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Solicitudes de clientes',
            style: TextStyle(
              color: AppColors.headerNavy,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: AppColors.pendientes.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$cantidad nuevas',
            style: const TextStyle(
              color: AppColors.pendientes,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            color: AppColors.textGray,
            size: 40,
          ),
          SizedBox(height: 10),
          Text(
            'No hay solicitudes pendientes',
            style: TextStyle(
              color: AppColors.labelDark,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Las nuevas solicitudes aparecerán aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textGray,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _aceptar(int id) {
    final resultado = widget.service.aceptarSolicitud(id);

    if (!mounted) {
      return;
    }

    if (resultado) {
      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solicitud aceptada correctamente.'),
        ),
      );
    }
  }

  void _rechazar(int id) {
    final resultado = widget.service.rechazarSolicitud(id);

    if (!mounted) {
      return;
    }

    if (resultado) {
      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solicitud rechazada.'),
        ),
      );
    }
  }

  Future<void> _gestionar(SolicitudAdmin solicitud) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: solicitud.fecha,
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );

    if (fecha == null || !mounted) {
      return;
    }

    final hora = await showTimePicker(
      context: context,
      initialTime: solicitud.hora,
    );

    if (hora == null || !mounted) {
      return;
    }

    final resultado = widget.service.proponerFechaHora(
      solicitud.id,
      fecha: fecha,
      hora: hora,
    );

    if (!mounted) {
      return;
    }

    if (resultado) {
      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nueva fecha y hora propuestas.'),
        ),
      );
    }
  }
}

class _SolicitudAdminCard extends StatelessWidget {
  const _SolicitudAdminCard({
    required this.solicitud,
    required this.onAceptar,
    required this.onRechazar,
    required this.onGestionar,
  });

  final SolicitudAdmin solicitud;
  final VoidCallback onAceptar;
  final VoidCallback onRechazar;
  final VoidCallback onGestionar;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inputBorder),
        boxShadow: const [
          BoxShadow(
            blurRadius: 8,
            offset: Offset(0, 2),
            color: Color(0x12000000),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCliente(),
          const SizedBox(height: 14),
          _buildVehiculo(),
          const SizedBox(height: 12),
          _buildServicios(),
          const SizedBox(height: 12),
          _buildFecha(),
          if (solicitud.descripcion.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              solicitud.descripcion,
              style: const TextStyle(
                color: AppColors.textGray,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildCliente() {
    return Row(
      children: [
        const CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.background,
          child: Icon(
            Icons.person_outline,
            color: AppColors.headerNavy,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                solicitud.cliente,
                style: const TextStyle(
                  color: AppColors.labelDark,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                solicitud.telefono,
                style: const TextStyle(
                  color: AppColors.textGray,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVehiculo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.directions_car_outlined,
            color: AppColors.headerNavy,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${solicitud.marcaVehiculo} ${solicitud.modeloVehiculo}',
                  style: const TextStyle(
                    color: AppColors.labelDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Año: ${solicitud.anioVehiculo} · Placa: ${solicitud.placa}',
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicios() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: solicitud.servicios
          .map(
            (servicio) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: AppColors.blueAccent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                servicio,
                style: const TextStyle(
                  color: AppColors.blueAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildFecha() {
    final fecha =
        '${solicitud.fecha.day.toString().padLeft(2, '0')}/'
        '${solicitud.fecha.month.toString().padLeft(2, '0')}/'
        '${solicitud.fecha.year}';

    final hora =
        '${solicitud.hora.hour.toString().padLeft(2, '0')}:'
        '${solicitud.hora.minute.toString().padLeft(2, '0')}';

    return Row(
      children: [
        const Icon(
          Icons.calendar_today_outlined,
          color: AppColors.textGray,
          size: 17,
        ),
        const SizedBox(width: 7),
        Text(
          '$fecha · $hora',
          style: const TextStyle(
            color: AppColors.textGray,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: onGestionar,
          icon: const Icon(Icons.edit_calendar_outlined, size: 17),
          label: const Text('Gestionar'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.headerNavy,
          ),
        ),
        OutlinedButton.icon(
          onPressed: onRechazar,
          icon: const Icon(Icons.close, size: 17),
          label: const Text('Rechazar'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.atrasadas,
          ),
        ),
        ElevatedButton.icon(
          onPressed: onAceptar,
          icon: const Icon(Icons.check, size: 17),
          label: const Text('Aceptar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.greenAccent,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

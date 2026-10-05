import 'package:flutter/material.dart';

import 'package:autofix/shared/models/demo_admin_data.dart';
import 'package:autofix/shared/models/solicitud_cita_cliente.dart';
import 'package:autofix/shared/theme/app_colors.dart';

class SolicitudesCitasAdminSection extends StatelessWidget {
  const SolicitudesCitasAdminSection({super.key});

  @override
  Widget build(BuildContext context) {
    final solicitudes = demoSolicitudesAdmin;
    final icono = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.orangePrimary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Icon(
        Icons.move_to_inbox_outlined,
        color: AppColors.orangePrimary,
      ),
    );
    const encabezado = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Solicitudes de clientes',
            style: TextStyle(
              color: AppColors.labelDark,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 3),
          Text(
            'Revisa, acepta o gestiona las citas solicitadas.',
            style: TextStyle(color: AppColors.textGray, fontSize: 11),
          ),
          SizedBox(height: 3),
          Text(
            'Datos de demostración; las acciones no se guardan.',
            style: TextStyle(color: AppColors.textGray, fontSize: 10),
          ),
        ],
      ),
    );
    final contador = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.orangePrimary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${solicitudes.length} nuevas',
        style: const TextStyle(
          color: AppColors.orangePrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardWhite,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 380) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [icono, const SizedBox(width: 12), encabezado],
                    ),
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: contador),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icono,
                  const SizedBox(width: 12),
                  encabezado,
                  const SizedBox(width: 10),
                  contador,
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        if (solicitudes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.inputBorder),
            ),
            child: const Row(
              children: [
                Icon(Icons.inbox_outlined, color: AppColors.placeholderGray),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Todavía no hay solicitudes. Cuando un cliente envíe una cita, aparecerá aquí.',
                    style: TextStyle(
                      color: AppColors.textGray,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          for (final solicitud in solicitudes) ...[
            _SolicitudCard(solicitud: solicitud),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _SolicitudCard extends StatelessWidget {
  const _SolicitudCard({required this.solicitud});

  final SolicitudCitaCliente solicitud;

  @override
  Widget build(BuildContext context) {
    final pendiente = solicitud.estado == EstadoSolicitudCita.pendiente;
    final colorEstado = pendiente ? AppColors.pendientes : AppColors.blueAccent;
    final labelEstado = pendiente ? 'Nueva solicitud' : 'Propuesta enviada';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inputBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  solicitud.cliente,
                  style: const TextStyle(
                    color: AppColors.labelDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _EstadoBadge(label: labelEstado, color: colorEstado),
            ],
          ),
          const SizedBox(height: 10),
          _dato(Icons.phone_outlined, solicitud.telefono),
          _dato(Icons.location_on_outlined, solicitud.taller),
          _dato(Icons.directions_car_outlined, solicitud.vehiculo),
          _dato(
            Icons.build_outlined,
            solicitud.servicios.isEmpty
                ? 'Sin servicio especificado'
                : solicitud.servicios.join(', '),
          ),
          _dato(
            Icons.calendar_month_outlined,
            '${_fecha(solicitud.fecha)} · ${solicitud.hora.format(context)}',
          ),
          if (solicitud.descripcion.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              solicitud.descripcion,
              style: const TextStyle(
                color: AppColors.textGray,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _gestionarSolicitud(context, solicitud),
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('Gestionar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.headerNavy,
                  side: const BorderSide(color: AppColors.inputBorder),
                ),
              ),
              if (pendiente) ...[
                OutlinedButton.icon(
                  onPressed: () => _confirmarRechazo(context, solicitud),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Rechazar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.atrasadas,
                    side: BorderSide(
                      color: AppColors.atrasadas.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _mostrarMensaje(
                    context,
                    'Vista de demostración: la cita no cambia de estado.',
                  ),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Aceptar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.greenAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _dato(IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textGray),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.labelDark, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarRechazo(
    BuildContext context,
    SolicitudCitaCliente solicitud,
  ) async {
    final rechazar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: Text('¿Quieres rechazar la cita de ${solicitud.cliente}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Rechazar',
              style: TextStyle(color: AppColors.atrasadas),
            ),
          ),
        ],
      ),
    );
    if (rechazar != true || !context.mounted) return;
    _mostrarMensaje(
      context,
      'Vista de demostración: la cita no cambia de estado.',
    );
  }

  Future<void> _gestionarSolicitud(
    BuildContext context,
    SolicitudCitaCliente solicitud,
  ) async {
    var fecha = solicitud.fecha;
    var hora = solicitud.hora;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Gestionar solicitud'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${solicitud.cliente} · ${solicitud.taller}',
                style: const TextStyle(color: AppColors.textGray, fontSize: 12),
              ),
              const SizedBox(height: 18),
              const Text(
                'Proponer fecha y hora',
                style: TextStyle(
                  color: AppColors.labelDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final nuevaFecha = await showDatePicker(
                          context: context,
                          initialDate: fecha.isBefore(DateTime.now())
                              ? DateTime.now()
                              : fecha,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (nuevaFecha != null) {
                          setDialogState(() => fecha = nuevaFecha);
                        }
                      },
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(_fecha(fecha)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final nuevaHora = await showTimePicker(
                          context: context,
                          initialTime: hora,
                        );
                        if (nuevaHora != null) {
                          setDialogState(() => hora = nuevaHora);
                        }
                      },
                      icon: const Icon(Icons.schedule, size: 16),
                      label: Text(hora.format(context)),
                    ),
                  ),
                ],
              ),
              if (solicitud.estado == EstadoSolicitudCita.pendiente) ...[
                const SizedBox(height: 10),
                const Text(
                  'Puedes enviar otra fecha como propuesta para que el cliente la confirme.',
                  style: TextStyle(color: AppColors.textGray, fontSize: 11),
                ),
              ] else ...[
                const SizedBox(height: 10),
                const Text(
                  'Esperando que el cliente responda a la fecha propuesta.',
                  style: TextStyle(
                    color: AppColors.blueAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
            if (solicitud.estado == EstadoSolicitudCita.pendiente ||
                solicitud.estado == EstadoSolicitudCita.fechaPropuesta)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _mostrarMensaje(
                    context,
                    'Vista de demostración: la propuesta no se guarda.',
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.headerNavy,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Enviar propuesta'),
              )
            else
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _mostrarMensaje(
                    context,
                    'Vista de demostración: el horario no se guarda.',
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.headerNavy,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Guardar horario'),
              ),
          ],
        ),
      ),
    );
  }

  String _fecha(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

  void _mostrarMensaje(BuildContext context, String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
    );
  }
}

class _EstadoBadge extends StatelessWidget {
  const _EstadoBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
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

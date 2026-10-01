import 'package:flutter/material.dart';

import '../../models/demo_admin_data.dart';
import '../../models/solicitud_cita_cliente.dart';
import '../../screens/admin/impresoras_bluetooth_screen.dart';
import '../../models/servicio_taller.dart';
import '../../theme/app_colors.dart';

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

class CitaClasificadaAdminCard extends StatelessWidget {
  const CitaClasificadaAdminCard({
    required this.solicitud,
    this.previewOnly = false,
    super.key,
  });

  final SolicitudCitaCliente solicitud;
  final bool previewOnly;

  @override
  Widget build(BuildContext context) {
    final vehicle = _parseVehicle(solicitud.vehiculo);
    final statusColor = _statusColor(solicitud.estado);
    final statusLabel = _statusLabel(solicitud.estado);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE0E4EA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F3F7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    previewOnly ? 'DEMO' : '#${solicitud.id}',
                    style: const TextStyle(
                      color: AppColors.headerNavy,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                _estadoBadge(statusColor, statusLabel),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE7EAF0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 500 ? 2 : 1;
                final fieldWidth =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                final fields = [
                  ('CLIENTE', solicitud.cliente),
                  ('TELÉFONO', solicitud.telefono),
                  ('VEHÍCULO', vehicle.name),
                  ('PLACA', vehicle.plate),
                  ('TÉCNICO', previewOnly ? 'Técnico 2' : 'Sin asignar'),
                  ('FECHA', _formatSchedule(context)),
                ];
                return Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    for (final field in fields)
                      SizedBox(
                        width: fieldWidth,
                        child: _CitaInfoField(label: field.$1, value: field.$2),
                      ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SERVICIOS',
                  style: TextStyle(
                    color: AppColors.placeholderGray,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: solicitud.servicios.isEmpty
                      ? [const _ServicioChip(label: 'Sin servicios')]
                      : [
                          for (final servicio in solicitud.servicios)
                            _ServicioChip(label: servicio),
                        ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE7EAF0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'RD\$ —',
                        style: TextStyle(
                          color: AppColors.completado,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () =>
                          _mostrarDetalle(context, previewOnly: previewOnly),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.headerNavy,
                        side: const BorderSide(color: AppColors.inputBorder),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Ver detalle'),
                    ),
                  ],
                ),
                if (solicitud.estado == EstadoSolicitudCita.completada) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => _mostrarRecibo(context),
                      icon: const Icon(Icons.receipt_long_outlined, size: 17),
                      label: const Text('Imprimir recibo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.greenAccent,
                        side: const BorderSide(color: AppColors.greenAccent),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarRecibo(BuildContext context) {
    final vehicle = _parseVehicle(solicitud.vehiculo);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.orangePrimary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.build_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AutoFix',
                                style: TextStyle(
                                  color: AppColors.headerNavy,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'RECIBO DE SERVICIO',
                                style: TextStyle(
                                  color: AppColors.textGray,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.greenAccent.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: AppColors.greenAccent,
                                size: 15,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'SERVICIO COMPLETADO',
                                style: TextStyle(
                                  color: AppColors.greenAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Divider(color: AppColors.inputBorder),
                      _ReciboDato(
                        label: 'Recibo',
                        value:
                            'REC-2026-${solicitud.id.toString().padLeft(4, '0')}',
                      ),
                      _ReciboDato(
                        label: 'Fecha',
                        value: _formatSchedule(context),
                      ),
                      const SizedBox(height: 14),
                      const _CitaDetailSectionTitle('CLIENTE'),
                      _ReciboDato(label: 'Nombre', value: solicitud.cliente),
                      _ReciboDato(label: 'Teléfono', value: solicitud.telefono),
                      const SizedBox(height: 14),
                      const _CitaDetailSectionTitle('VEHÍCULO'),
                      _ReciboDato(label: 'Vehículo', value: vehicle.name),
                      _ReciboDato(label: 'Placa', value: vehicle.plate),
                      const SizedBox(height: 18),
                      const Divider(color: AppColors.inputBorder),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'SERVICIO',
                                style: TextStyle(
                                  color: AppColors.textGray,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            Text(
                              'IMPORTE',
                              style: TextStyle(
                                color: AppColors.textGray,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (final servicio in solicitud.servicios)
                        _ReciboDato(label: servicio, value: 'RD\$ —'),
                      const Divider(color: AppColors.inputBorder),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'TOTAL',
                                style: TextStyle(
                                  color: AppColors.headerNavy,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              'RD\$ —',
                              style: TextStyle(
                                color: AppColors.headerNavy,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(color: AppColors.inputBorder),
                      const SizedBox(height: 12),
                      const Text(
                        'Gracias por confiar en AutoFix.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textGray,
                          fontSize: 12,
                        ),
                      ),
                      if (previewOnly) ...[
                        const SizedBox(height: 9),
                        const Text(
                          'Vista de demostración · Los importes se completarán más adelante.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.placeholderGray,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.inputBorder),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cerrar'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ImpresorasBluetoothScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.print_outlined, size: 17),
                      label: const Text('Imprimir'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.headerNavy,
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSchedule(BuildContext context) {
    final date = solicitud.fecha;
    final formattedDate =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return '$formattedDate ${solicitud.hora.format(context)}';
  }

  Widget _estadoBadge(Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  _VehicleFields _parseVehicle(String value) {
    final parts = value.split('·').map((part) => part.trim()).toList();
    final plate = parts.length > 1 ? parts.last : 'No indicada';
    final vehicleMatch = RegExp(r'^(.*?)\s*\((\d{4})\)$')
        .firstMatch(parts.first);
    final vehicleName = vehicleMatch?.group(1)?.trim() ?? parts.first;
    final year = vehicleMatch?.group(2) ?? 'No indicado';
    final words = vehicleName.split(RegExp(r'\s+'));
    final brand = words.isEmpty ? vehicleName : words.first;
    final model = words.length > 1 ? words.skip(1).join(' ') : 'No indicado';
    return _VehicleFields(brand: brand, model: model, year: year, plate: plate);
  }

  Color _statusColor(EstadoSolicitudCita estado) => switch (estado) {
    EstadoSolicitudCita.aceptada => AppColors.pendientes,
    EstadoSolicitudCita.atrasada => AppColors.atrasadas,
    EstadoSolicitudCita.esperandoPieza => AppColors.blueAccent,
    EstadoSolicitudCita.enProceso => AppColors.enProceso,
    EstadoSolicitudCita.completada => AppColors.completado,
    _ => AppColors.pendientes,
  };

  String _statusLabel(EstadoSolicitudCita estado) => switch (estado) {
    EstadoSolicitudCita.aceptada => 'Pendiente',
    EstadoSolicitudCita.atrasada => 'Atrasadas',
    EstadoSolicitudCita.esperandoPieza => 'Esperando Pieza',
    EstadoSolicitudCita.enProceso => 'En proceso',
    EstadoSolicitudCita.completada => 'Completado',
    _ => 'Pendiente',
  };

  void _mostrarDetalle(BuildContext context, {required bool previewOnly}) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final vehicle = _parseVehicle(solicitud.vehiculo);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  child: Column(
                    children: [
                      Text(
                        previewOnly
                            ? 'CITA DE DEMOSTRACIÓN'
                            : 'CITA #${solicitud.id}',
                        style: const TextStyle(
                          color: AppColors.placeholderGray,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'INFORMACIÓN DE LA CITA',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.headerNavy,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE7EAF0)),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _CitaDetailSectionTitle('CLIENTE'),
                        _CitaDetailGrid(
                          fields: [
                            ('Nombre', solicitud.cliente),
                            ('Teléfono', solicitud.telefono),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const _CitaDetailSectionTitle('VEHÍCULO'),
                        _CitaDetailGrid(
                          fields: [
                            ('Marca', vehicle.brand.toUpperCase()),
                            ('Modelo', vehicle.model.toUpperCase()),
                            ('Año', vehicle.year),
                            ('Placa', vehicle.plate.toUpperCase()),
                            (
                              'Técnico',
                              previewOnly ? 'Técnico 2' : 'Sin asignar',
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const _CitaDetailSectionTitle('SERVICIOS'),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: solicitud.servicios.isEmpty
                              ? [const _ServicioChip(label: 'Sin servicios')]
                              : [
                                  for (final service in solicitud.servicios)
                                    _ServicioChip(label: service),
                                ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'RD\$ —',
                          style: TextStyle(
                            color: AppColors.completado,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const _CitaDetailSectionTitle('ESTADO'),
                        Row(
                          children: [
                            _EstadoBadge(
                              label: _statusLabel(solicitud.estado),
                              color: _statusColor(solicitud.estado),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _formatSchedule24h(),
                              style: const TextStyle(
                                color: AppColors.textGray,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const _CitaDetailSectionTitle('DESCRIPCIÓN'),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F3F7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            solicitud.descripcion.isEmpty
                                ? 'Sin descripción adicional.'
                                : solicitud.descripcion,
                            style: const TextStyle(
                              color: AppColors.labelDark,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE7EAF0)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                  child: Row(
                    children: [
                      const Spacer(),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _editarCita(context, previewOnly: previewOnly);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.headerNavy,
                          side: const BorderSide(color: AppColors.inputBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Editar'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.headerNavy,
                          side: const BorderSide(color: AppColors.inputBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatSchedule24h() {
    final date = solicitud.fecha;
    final hour = solicitud.hora.hour.toString().padLeft(2, '0');
    final minute = solicitud.hora.minute.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} · $hour:$minute';
  }

  Future<void> _editarCita(
    BuildContext context, {
    required bool previewOnly,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _EditarCitaDialog(solicitud: solicitud, previewOnly: previewOnly),
    );
  }
}

class _EditarCitaDialog extends StatefulWidget {
  const _EditarCitaDialog({required this.solicitud, this.previewOnly = false});

  final SolicitudCitaCliente solicitud;
  final bool previewOnly;

  @override
  State<_EditarCitaDialog> createState() => _EditarCitaDialogState();
}

class _EditarCitaDialogState extends State<_EditarCitaDialog> {
  static const _marcas = demoMarcasVehiculo;
  static const _tecnicos = demoTecnicosAdmin;
  static const _estados = [
    (EstadoSolicitudCita.aceptada, 'Pendiente'),
    (EstadoSolicitudCita.atrasada, 'Atrasadas'),
    (EstadoSolicitudCita.esperandoPieza, 'Esperando Pieza'),
    (EstadoSolicitudCita.enProceso, 'En proceso'),
    (EstadoSolicitudCita.completada, 'Completado'),
  ];

  late final TextEditingController _clienteController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _marcaController;
  late final TextEditingController _modeloController;
  late final TextEditingController _anioController;
  late final TextEditingController _placaController;
  late final TextEditingController _descripcionController;
  late final Set<String> _serviciosSeleccionados;
  late DateTime _fecha;
  late TimeOfDay _hora;
  late EstadoSolicitudCita _estado;
  String? _marcaSeleccionada;
  String? _tecnico;

  List<ServicioTaller> get _catalogo {
    final selectedNotCatalogued = _serviciosSeleccionados
        .where((name) => _servicio(name) == null)
        .map((name) => ServicioTaller(nombre: name, precioEtiqueta: 'RD\$ —'));
    return [...serviciosTaller, ...selectedNotCatalogued];
  }

  @override
  void initState() {
    super.initState();
    final vehicle = _parseVehicle(widget.solicitud.vehiculo);
    _clienteController = TextEditingController(text: widget.solicitud.cliente);
    _telefonoController = TextEditingController(
      text: widget.solicitud.telefono,
    );
    _marcaController = TextEditingController(text: vehicle.brand);
    _marcaSeleccionada = _marcas.contains(vehicle.brand) ? vehicle.brand : null;
    _modeloController = TextEditingController(text: vehicle.model);
    _anioController = TextEditingController(text: vehicle.year);
    _placaController = TextEditingController(text: vehicle.plate);
    _descripcionController = TextEditingController(
      text: widget.solicitud.descripcion,
    );
    _serviciosSeleccionados = {...widget.solicitud.servicios};
    _fecha = widget.solicitud.fecha;
    _hora = widget.solicitud.hora;
    _tecnico = widget.previewOnly ? 'Técnico 2' : null;
    _estado =
        widget.solicitud.estado == EstadoSolicitudCita.fechaPropuesta ||
            widget.solicitud.estado == EstadoSolicitudCita.pendiente
        ? EstadoSolicitudCita.aceptada
        : widget.solicitud.estado;
  }

  @override
  void dispose() {
    _clienteController.dispose();
    _telefonoController.dispose();
    _marcaController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _placaController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.sizeOf(context).height * 0.96,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              decoration: const BoxDecoration(
                color: AppColors.headerNavy,
                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Editar Cita',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _titulo('DATOS DEL CLIENTE'),
                    _campo(
                      label: 'Nombre completo',
                      controller: _clienteController,
                    ),
                    const SizedBox(height: 12),
                    _campo(
                      label: 'Teléfono',
                      controller: _telefonoController,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 20),
                    _titulo('DATOS DEL VEHÍCULO'),
                    Row(
                      children: [
                        Expanded(
                          child: _campoDropdown(
                            label: 'Marca',
                            value: _marcaSeleccionada,
                            items: [
                              if (_marcaController.text.isNotEmpty &&
                                  !_marcas.contains(_marcaController.text))
                                _marcaController.text,
                              ..._marcas,
                            ],
                            onChanged: (value) {
                              setState(() {
                                _marcaSeleccionada = value;
                                _marcaController.text = value ?? '';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _campo(
                            label: 'Modelo',
                            controller: _modeloController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _campo(
                            label: 'Año',
                            controller: _anioController,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _campo(
                            label: 'Placa',
                            controller: _placaController,
                            capitalization: TextCapitalization.characters,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _titulo('SERVICIOS'),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Seleccionar servicios',
                            style: TextStyle(
                              color: AppColors.labelDark,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          '${_serviciosSeleccionados.length} seleccionados',
                          style: const TextStyle(
                            color: AppColors.orangePrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Container(
                      height: 190,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.inputBorder),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _catalogo.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Color(0xFFF0F2F5)),
                        itemBuilder: (context, index) {
                          final service = _catalogo[index];
                          final selected = _serviciosSeleccionados.contains(
                            service.nombre,
                          );
                          return Material(
                            color: Colors.transparent,
                            child: CheckboxListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              activeColor: AppColors.orangePrimary,
                              value: selected,
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _serviciosSeleccionados.add(service.nombre);
                                  } else {
                                    _serviciosSeleccionados.remove(
                                      service.nombre,
                                    );
                                  }
                                });
                              },
                              title: Text(
                                service.nombre,
                                style: const TextStyle(
                                  color: AppColors.labelDark,
                                  fontSize: 12,
                                ),
                              ),
                              secondary: Text(
                                service.precioEtiqueta,
                                style: const TextStyle(
                                  color: AppColors.textGray,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildServiceSummary(),
                    const SizedBox(height: 20),
                    _titulo('ASIGNACIÓN'),
                    const Text(
                      'Técnico',
                      style: TextStyle(
                        color: AppColors.labelDark,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _tecnico,
                      isExpanded: true,
                      decoration: _inputDecoration(),
                      hint: const Text('Seleccionar técnico'),
                      items: _tecnicos
                          .map(
                            (technician) => DropdownMenuItem(
                              value: technician,
                              child: Text(technician),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _tecnico = value),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _dateTimeControl(
                            label: 'Fecha',
                            value:
                                '${_fecha.day.toString().padLeft(2, '0')}/${_fecha.month.toString().padLeft(2, '0')}/${_fecha.year}',
                            icon: Icons.calendar_today_outlined,
                            onTap: _seleccionarFecha,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _dateTimeControl(
                            label: 'Hora',
                            value:
                                '${_hora.hour.toString().padLeft(2, '0')}:${_hora.minute.toString().padLeft(2, '0')}',
                            icon: Icons.access_time,
                            onTap: _seleccionarHora,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Estado',
                      style: TextStyle(
                        color: AppColors.labelDark,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<EstadoSolicitudCita>(
                      initialValue: _estado,
                      isExpanded: true,
                      decoration: _inputDecoration(),
                      items: [
                        for (final option in _estados)
                          DropdownMenuItem(
                            value: option.$1,
                            child: Text(option.$2),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _estado = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    _campo(
                      label: 'Descripción',
                      controller: _descripcionController,
                      minLines: 3,
                      maxLines: 4,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orangePrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  child: const Text(
                    'Guardar Cambios',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceSummary() {
    final selected = _catalogo
        .where((service) => _serviciosSeleccionados.contains(service.nombre))
        .toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FA),
        border: Border.all(color: const Color(0xFFE3E8EE)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        children: [
          for (final service in selected)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      service.nombre,
                      style: const TextStyle(
                        color: AppColors.textGray,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Text(
                    service.precioEtiqueta,
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 14, color: Color(0xFFE0E5EB)),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(
                    color: AppColors.labelDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Text(
                'RD\$ 11.000',
                style: TextStyle(
                  color: AppColors.completado,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _titulo(String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        value,
        style: const TextStyle(
          color: AppColors.textGray,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.45,
        ),
      ),
    );
  }

  Widget _campo({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.words,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.labelDark,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: capitalization,
          minLines: minLines,
          maxLines: maxLines,
          decoration: _inputDecoration(),
        ),
      ],
    );
  }

  Widget _campoDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.labelDark,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: _inputDecoration(),
          hint: const Text('Seleccionar'),
          items: items
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  InputDecoration _inputDecoration() => InputDecoration(
    isDense: true,
    filled: true,
    fillColor: AppColors.cardWhite,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.inputBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.orangePrimary, width: 1.4),
    ),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  );

  Widget _dateTimeControl({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.labelDark,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: _inputDecoration(),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
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
      ],
    );
  }

  Future<void> _seleccionarFecha() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _fecha.isBefore(DateTime.now()) ? DateTime.now() : _fecha,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (value != null) setState(() => _fecha = value);
  }

  Future<void> _seleccionarHora() async {
    final value = await showTimePicker(context: context, initialTime: _hora);
    if (value != null) setState(() => _hora = value);
  }

  ServicioTaller? _servicio(String name) {
    for (final service in serviciosTaller) {
      if (service.nombre == name) return service;
    }
    return null;
  }

  _VehicleFields _parseVehicle(String value) {
    final parts = value.split('·').map((part) => part.trim()).toList();
    final vehicleMatch = RegExp(r'^(.*?)\s*\((\d{4})\)$')
        .firstMatch(parts.first);
    final vehicleName = vehicleMatch?.group(1)?.trim() ?? parts.first;
    final year = vehicleMatch?.group(2) ?? '';
    final words = vehicleName.split(RegExp(r'\s+'));
    return _VehicleFields(
      brand: words.first,
      model: words.length > 1 ? words.skip(1).join(' ') : '',
      year: year,
      plate: parts.length > 1 ? parts.last : '',
    );
  }
}

class _VehicleFields {
  const _VehicleFields({
    required this.brand,
    required this.model,
    required this.year,
    required this.plate,
  });

  final String brand;
  final String model;
  final String year;
  final String plate;

  String get name => '$brand $model $year';
}

class _ReciboDato extends StatelessWidget {
  const _ReciboDato({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textGray, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: AppColors.labelDark,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CitaDetailSectionTitle extends StatelessWidget {
  const _CitaDetailSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textGray,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.45,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Divider(height: 1, color: Color(0xFFE7EAF0))),
        ],
      ),
    );
  }
}

class _CitaDetailGrid extends StatelessWidget {
  const _CitaDetailGrid({required this.fields});

  final List<(String, String)> fields;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (final field in fields)
              SizedBox(
                width: width,
                child: _CitaDetailValue(label: field.$1, value: field.$2),
              ),
          ],
        );
      },
    );
  }
}

class _CitaDetailValue extends StatelessWidget {
  const _CitaDetailValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FB),
        border: Border.all(color: const Color(0xFFEDF0F4)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.placeholderGray,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.headerNavy,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CitaInfoField extends StatelessWidget {
  const _CitaInfoField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.placeholderGray,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.35,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F3F7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.labelDark,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _ServicioChip extends StatelessWidget {
  const _ServicioChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFD9F8E6),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF087A45),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
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

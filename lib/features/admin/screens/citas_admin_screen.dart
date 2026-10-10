import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/auth/credenciales_seguras.dart';
import 'package:autofix/core/data/limpieza_local.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/admin/widgets/solicitudes_citas_admin_section.dart';
import 'package:autofix/features/auth/screens/login_screen.dart';
import 'package:autofix/features/citas/models/cita.dart' as cita_data;
import 'package:autofix/features/citas/presentation/citas_controller.dart';
import 'package:autofix/features/configuracion/data/grupo_servicio_item_repository.dart';
import 'package:autofix/features/configuracion/data/grupo_servicio_repository.dart';
import 'package:autofix/features/configuracion/data/marca_repository.dart';
import 'package:autofix/features/configuracion/data/tecnico_repository.dart';
import 'package:autofix/features/configuracion/data/tipo_servicio_repository.dart';
import 'package:autofix/features/configuracion/models/grupo_servicio.dart';
import 'package:autofix/features/configuracion/models/grupo_servicio_item.dart';
import 'package:autofix/features/configuracion/models/marca.dart';
import 'package:autofix/features/configuracion/models/tecnico.dart';
import 'package:autofix/features/configuracion/models/tipo_servicio.dart';
import 'package:autofix/features/sync/sync_service.dart';
import 'package:autofix/shared/models/cita_admin.dart';
import 'package:autofix/shared/theme/app_colors.dart';

import 'dashboard_admin_screen.dart';
import 'configuracion_admin_screen.dart';
import 'impresoras_bluetooth_screen.dart';
import 'editar_perfil_admin_screen.dart';

const Map<String, Color> kColorPorEstado = {
  'ATRASADAS': AppColors.atrasadas,
  'Pendiente': AppColors.pendientes,
  'Esperando Pieza': AppColors.esperandoPieza,
  'En proceso': AppColors.enProceso,
  'Completado': AppColors.completado,
};

/// Estados disponibles para el dropdown de edición de citas.
const List<String> kEstadosCitaAdmin = [
  'Pendiente',
  'Aceptada',
  'Esperando Pieza',
  'En proceso',
  'Completado',
  'Rechazada',
];

class CitaAdminCard extends StatelessWidget {
  const CitaAdminCard({
    required this.cita,
    this.serviciosDisponibles = const <TipoServicio>[],
    this.tecnicosDisponibles = const <Tecnico>[],
    this.gruposServicio = const <GrupoServicio>[],
    this.grupoServicioItems = const <GrupoServicioItem>[],
    this.marcas = const <Marca>[],
    this.onEdited,
    this.onDeleted,
    this.onEstadoCambiado,
    super.key,
  });

  final CitaAdmin cita;
  final List<TipoServicio> serviciosDisponibles;
  final List<Tecnico> tecnicosDisponibles;
  final List<GrupoServicio> gruposServicio;
  final List<GrupoServicioItem> grupoServicioItems;
  final List<Marca> marcas;
  final ValueChanged<CitaAdmin>? onEdited;

  /// Borrado logico: recibe el UUID de la cita (`String` desde la v7), no un
  /// numero.
  final ValueChanged<String>? onDeleted;

  /// Cambio de estado del desplegable.
  ///
  /// Va separado de [onEdited] a proposito. Un cambio de estado es un UPDATE
  /// parcial: solo cambia `estado` y `actualizado_en`. Si viajara por
  /// [onEdited], el admin reescribiria la fila completa, y con ella las
  /// columnas que la pantalla no edita (`taller_id`, `creado_en`), que es
  /// exactamente como una cita se desasociaba de su taller al mover el
  /// desplegable.
  final void Function(EstadoCitaAdmin nuevoEstado)? onEstadoCambiado;

  static String _estadoTexto(EstadoCitaAdmin estado) {
    switch (estado) {
      case EstadoCitaAdmin.atrasada:
        return 'Atrasadas';
      case EstadoCitaAdmin.pendiente:
      case EstadoCitaAdmin.aceptada:
      case EstadoCitaAdmin.rechazada:
        return 'Pendiente';
      case EstadoCitaAdmin.esperandoPieza:
        return 'Esperando Pieza';
      case EstadoCitaAdmin.enProceso:
        return 'En proceso';
      case EstadoCitaAdmin.completada:
        return 'Completado';
    }
  }

  static Color _estadoColor(EstadoCitaAdmin estado) {
    switch (estado) {
      case EstadoCitaAdmin.atrasada:
        return AppColors.atrasadas;
      case EstadoCitaAdmin.pendiente:
      case EstadoCitaAdmin.aceptada:
      case EstadoCitaAdmin.rechazada:
        return AppColors.pendientes;
      case EstadoCitaAdmin.esperandoPieza:
        return AppColors.esperandoPieza;
      case EstadoCitaAdmin.enProceso:
        return AppColors.enProceso;
      case EstadoCitaAdmin.completada:
        return AppColors.completado;
    }
  }

  String _fechaFormateada() =>
      '${cita.fecha.day.toString().padLeft(2, '0')}/${cita.fecha.month.toString().padLeft(2, '0')}/${cita.fecha.year}';

  void _mostrarRecibo(BuildContext context) {
    Widget linea(String etiqueta, String valor, {bool destacado = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                etiqueta,
                style: TextStyle(
                  color: destacado ? AppColors.headerNavy : AppColors.textGray,
                  fontSize: destacado ? 14 : 12,
                  fontWeight: destacado ? FontWeight.w800 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                valor,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: AppColors.headerNavy,
                  fontSize: destacado ? 16 : 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

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
                      linea('Recibo', cita.codigoVisible),
                      linea(
                        'Fecha',
                        '${_fechaFormateada()} · ${cita.hora.format(context)}',
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'CLIENTE',
                        style: TextStyle(
                          color: AppColors.textGray,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 5),
                      linea('Nombre', cita.cliente),
                      linea('Teléfono', cita.telefono),
                      if (cita.correoCliente.isNotEmpty)
                        linea('Correo', cita.correoCliente),
                      const SizedBox(height: 14),
                      const Text(
                        'VEHÍCULO',
                        style: TextStyle(
                          color: AppColors.textGray,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 5),
                      linea(
                        'Vehículo',
                        '${cita.marca} ${cita.modelo} ${cita.anio}'.trim(),
                      ),
                      linea('Placa', cita.placa),
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
                      if (cita.servicios.isEmpty)
                        linea('Servicios', 'Sin servicios registrados')
                      else
                        for (final servicio in cita.servicios)
                          linea(servicio, 'RD\$ —'),
                      const Divider(color: AppColors.inputBorder),
                      linea(
                        'TOTAL',
                        'RD\$ ${cita.total.toStringAsFixed(0)}',
                        destacado: true,
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
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.inputBorder),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cerrar'),
                    ),
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

  Future<void> _editarCita(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _EditarCitaDialog(
        cita: cita,
        serviciosDisponibles: serviciosDisponibles,
        tecnicosDisponibles: tecnicosDisponibles,
        gruposServicio: gruposServicio,
        grupoServicioItems: grupoServicioItems,
        marcas: marcas,
        onSaved: (citaActualizada) {
          onEdited?.call(citaActualizada);
        },
      ),
    );
  }

  void _mostrarDetalle(BuildContext context) {
    final partesNombre = cita.cliente.trim().split(RegExp(r'\s+'));
    final nombre = partesNombre.isEmpty || partesNombre.first.isEmpty
        ? ''
        : partesNombre.first;
    final apellido = partesNombre.length > 1
        ? partesNombre.skip(1).join(' ')
        : '—';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
                      const _SectionTitle('CLIENTE'),
                      _DetailGrid(
                        fields: [
                          ('Nombre', nombre),
                          ('Apellido', apellido),
                          ('Teléfono', cita.telefono),
                        ],
                      ),
                      const Divider(height: 32, color: Color(0xFFE7EAF0)),
                      const _SectionTitle('CITA'),
                      _DetailGrid(
                        fields: [
                          ('Fecha', _fechaFormateada()),
                          ('Hora', cita.hora.format(context)),
                        ],
                      ),
                      const Divider(height: 32, color: Color(0xFFE7EAF0)),
                      const _SectionTitle('VEHÍCULO'),
                      _DetailGrid(
                        fields: [
                          ('Marca', cita.marca.toUpperCase()),
                          ('Modelo', cita.modelo.toUpperCase()),
                          ('Año', cita.anio),
                          ('Placa', cita.placa.toUpperCase()),
                          ('Técnico', cita.tecnico ?? 'Sin asignar'),
                        ],
                      ),
                      const Divider(height: 32, color: Color(0xFFE7EAF0)),
                      const _SectionTitle('SERVICIOS'),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: cita.servicios.isEmpty
                            ? [const _Chip(label: 'Sin servicios')]
                            : [
                                for (final servicio in cita.servicios)
                                  _Chip(label: servicio),
                              ],
                      ),
                      const Divider(height: 32, color: Color(0xFFE7EAF0)),
                      const _SectionTitle('DESCRIPCIÓN'),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F3F7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          cita.descripcion.isEmpty
                              ? 'Sin descripción'
                              : cita.descripcion,
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 420;
                    final buttonPadding = EdgeInsets.symmetric(
                      horizontal: compact ? 8 : 16,
                      vertical: 8,
                    );
                    final deleteButton = OutlinedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        // Una cita sin id todavia no existe en la base, asi que no
                        // hay nada que borrar. Sin este chequeo, `onDeleted!` con
                        // null llega hasta el repositorio y revienta el WHERE con
                        // un id nulo en vez de no hacer nada.
                        final id = cita.id;
                        if (onDeleted != null && id != null) onDeleted!(id);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFFECACA)),
                        padding: buttonPadding,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Eliminar'),
                    );
                    final editButton = OutlinedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _editarCita(context);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.headerNavy,
                        side: const BorderSide(color: AppColors.inputBorder),
                        padding: buttonPadding,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Editar'),
                    );
                    final closeButton = OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.headerNavy,
                        side: const BorderSide(color: AppColors.inputBorder),
                        padding: buttonPadding,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Cerrar'),
                    );

                    if (compact) {
                      return Row(
                        children: [
                          Expanded(child: deleteButton),
                          const SizedBox(width: 6),
                          Expanded(child: editButton),
                          const SizedBox(width: 6),
                          Expanded(child: closeButton),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        deleteButton,
                        const Spacer(),
                        editButton,
                        const SizedBox(width: 10),
                        closeButton,
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _estadoColor(cita.estado);
    final statusLabel = _estadoTexto(cita.estado);
    
    // Una vez aceptada/rechazada, no puede volver a "Pendiente" (solicitudes de citas)
    final estadosPosAceptacion = {
      EstadoCitaAdmin.aceptada,
      EstadoCitaAdmin.rechazada,
      EstadoCitaAdmin.esperandoPieza,
      EstadoCitaAdmin.enProceso,
      EstadoCitaAdmin.completada,
    };
    final puedeVolverAPendiente = !estadosPosAceptacion.contains(cita.estado);
    
    final statusOptions = [...kEstadosCitaAdmin];
    if (!puedeVolverAPendiente) {
      statusOptions.remove('Pendiente');
    }
    if (statusLabel == 'Atrasadas') statusOptions.insert(0, statusLabel);
    final fields = [
      _Field(label: 'CLIENTE', value: cita.cliente),
      _Field(label: 'TELÉFONO', value: cita.telefono),
      if (cita.correoCliente.isNotEmpty)
        _Field(label: 'CORREO', value: cita.correoCliente),
      _Field(
        label: 'VEHÍCULO',
        value: '${cita.marca} ${cita.modelo} ${cita.anio}',
      ),
      _Field(label: 'PLACA', value: cita.placa),
      _Field(label: 'TÉCNICO', value: cita.tecnico ?? 'Sin asignar'),
      _Field(label: 'FECHA', value: _fechaFormateada()),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EBF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                // Indicador de sincronizacion (Fase 3): nube con reloj/check
                if (cita.syncStatus != null) ...[
                  Icon(
                    cita.syncStatus == 'synced'
                        ? Icons.cloud_done
                        : Icons.cloud_queue,
                    size: 14,
                    color: cita.syncStatus == 'synced'
                        ? AppColors.greenAccent
                        : AppColors.orangePrimary,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    cita.codigoVisible,
                    style: const TextStyle(
                      color: AppColors.headerNavy,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.20),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: statusLabel,
                      isDense: true,
                      alignment: Alignment.center,
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: AppColors.headerNavy,
                      ),
                      dropdownColor: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                      items: statusOptions.map((label) {
                        return DropdownMenuItem<String>(
                          value: label,
                          enabled: label != 'Atrasadas',
                          child: Text(label),
                        );
                      }).toList(),
                      onChanged: (nuevoEstado) {
                        if (nuevoEstado == null) return;
                        final nuevoEstadoEnum = switch (nuevoEstado) {
                          'Pendiente' => EstadoCitaAdmin.pendiente,
                          'Esperando Pieza' => EstadoCitaAdmin.esperandoPieza,
                          'En proceso' => EstadoCitaAdmin.enProceso,
                          'Completado' => EstadoCitaAdmin.completada,
                          _ => cita.estado,
                        };

                        // 'Atrasadas' no es un estado: es una vista calculada
                        // (fecha ya pasada) sobre citas pendientes. Por eso el
                        // item viene deshabilitado y aqui nunca se persiste.
                        if (nuevoEstadoEnum == EstadoCitaAdmin.atrasada) return;

                        if (onEstadoCambiado != null) {
                          onEstadoCambiado!(nuevoEstadoEnum);
                          return;
                        }

                        // Sin handler de update parcial (la tarjeta se usa
                        // suelta en tests o previews) se cae al guardado
                        // completo, arrastrando ahora los campos de
                        // auditoria para no perderlos en el camino.
                        onEdited?.call(
                          CitaAdmin(
                            id: cita.id,
                            codigoVisible: cita.codigoVisible,
                            cliente: cita.cliente,
                            telefono: cita.telefono,
                            correoCliente: cita.correoCliente,
                            marca: cita.marca,
                            modelo: cita.modelo,
                            anio: cita.anio,
                            placa: cita.placa,
                            servicios: cita.servicios,
                            fecha: cita.fecha,
                            hora: cita.hora,
                            estado: nuevoEstadoEnum,
                            descripcion: cita.descripcion,
                            tecnico: cita.tecnico,
                            total: cita.total,
                            tallerId: cita.tallerId,
                            creadoEn: cita.creadoEn,
                            actualizadoEn: cita.actualizadoEn,
                            syncStatus: cita.syncStatus,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE7EAF0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 500 ? 2 : 1;
                final fieldWidth =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;

                return Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    for (final field in fields)
                      SizedBox(
                        width: fieldWidth,
                        child: _FieldWidget(
                          label: field.label,
                          value: field.value,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
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
                  spacing: 6,
                  runSpacing: 6,
                  children: cita.servicios.isEmpty
                      ? const [SizedBox.shrink()]
                      : [
                          for (final servicio in cita.servicios)
                            _Chip(label: servicio),
                        ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE7EAF0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'RD\$ ${cita.total.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: AppColors.completado,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _mostrarDetalle(context),
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
                if (cita.estado == EstadoCitaAdmin.completada) ...[
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
}

class _EditarCitaDialog extends StatefulWidget {
  const _EditarCitaDialog({
    required this.cita,
    required this.onSaved,
    required this.serviciosDisponibles,
    required this.tecnicosDisponibles,
    required this.gruposServicio,
    required this.grupoServicioItems,
    required this.marcas,
  });

  final CitaAdmin cita;
  final ValueChanged<CitaAdmin> onSaved;
  final List<TipoServicio> serviciosDisponibles;
  final List<Tecnico> tecnicosDisponibles;
  final List<GrupoServicio> gruposServicio;
  final List<GrupoServicioItem> grupoServicioItems;
  final List<Marca> marcas;

  @override
  State<_EditarCitaDialog> createState() => _EditarCitaDialogState();
}

class _EditarCitaDialogState extends State<_EditarCitaDialog> {
  late final TextEditingController _clienteController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _correoController;
  late final TextEditingController _modeloController;
  late final TextEditingController _anioController;
  late final TextEditingController _placaController;
  late final TextEditingController _descripcionController;
  late DateTime _fecha;
  late TimeOfDay _hora;
  late String? _marcaSeleccionada;
  late String? _tecnicoSeleccionado;
  late String _estadoSeleccionado;
  final Set<String> _serviciosMarcados = {};

  @override
  void initState() {
    super.initState();
    _clienteController = TextEditingController(text: widget.cita.cliente);
    _telefonoController = TextEditingController(text: widget.cita.telefono);
    _correoController = TextEditingController(text: widget.cita.correoCliente);
    _modeloController = TextEditingController(text: widget.cita.modelo);
    _anioController = TextEditingController(text: widget.cita.anio);
    _placaController = TextEditingController(text: widget.cita.placa);
    _descripcionController = TextEditingController(
      text: widget.cita.descripcion,
    );
    _fecha = widget.cita.fecha;
    _hora = widget.cita.hora;
    final nombresMarcas = widget.marcas.where((m) => m.activo).map((m) => m.nombre).toList();
    _marcaSeleccionada = nombresMarcas.contains(widget.cita.marca)
        ? widget.cita.marca
        : (nombresMarcas.isNotEmpty ? nombresMarcas.first : null);
    _tecnicoSeleccionado =
        widget.tecnicosDisponibles.any(
          (tecnico) => tecnico.nombre == widget.cita.tecnico,
        )
        ? widget.cita.tecnico
        : null;
    _estadoSeleccionado = switch (widget.cita.estado) {
      EstadoCitaAdmin.atrasada => 'Pendiente',
      EstadoCitaAdmin.pendiente => 'Pendiente',
      EstadoCitaAdmin.aceptada => 'Pendiente',
      EstadoCitaAdmin.rechazada => 'Pendiente',
      EstadoCitaAdmin.esperandoPieza => 'Esperando Pieza',
      EstadoCitaAdmin.enProceso => 'En proceso',
      EstadoCitaAdmin.completada => 'Completado',
    };
    _serviciosMarcados.addAll(widget.cita.servicios);
  }

  @override
  void dispose() {
    _clienteController.dispose();
    _telefonoController.dispose();
    _correoController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _placaController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  InputDecoration _decoracionCampo(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.textGray),
      hintStyle: const TextStyle(
        color: AppColors.placeholderGray,
        fontSize: 13,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: AppColors.orangePrimary,
          width: 1.5,
        ),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  String _formatearFechaCorta(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

  Widget _buildServiciosAgrupados() {
    // Servicios sin grupo asignado
    final serviciosConGrupo = <String>{};
    for (final item in widget.grupoServicioItems) {
      serviciosConGrupo.add(item.tipoServicioId);
    }
    final serviciosSinGrupo = widget.serviciosDisponibles
        .where((s) => !serviciosConGrupo.contains(s.id))
        .toList();

    // Mapa de grupo -> lista de servicios
    final Map<String, List<TipoServicio>> serviciosPorGrupo = {};
    for (final grupo in widget.gruposServicio) {
      final servicioIds = widget.grupoServicioItems
          .where((item) => item.grupoId == grupo.id && item.activo)
          .map((item) => item.tipoServicioId)
          .toSet();
      final servicios = widget.serviciosDisponibles
          .where((s) => servicioIds.contains(s.id))
          .toList();
      if (servicios.isNotEmpty) {
        serviciosPorGrupo[grupo.nombre] = servicios;
      }
    }

    return Column(
      children: [
        // Grupos con servicios
        ...serviciosPorGrupo.entries.map((entry) {
          final grupoNombre = entry.key;
          final servicios = entry.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                color: const Color(0xFFF3F5F8),
                child: Text(
                  grupoNombre.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textGray,
                  ),
                ),
              ),
              ...servicios.map(
                (servicio) => CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _serviciosMarcados.contains(servicio.nombre),
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _serviciosMarcados.add(servicio.nombre);
                      } else {
                        _serviciosMarcados.remove(servicio.nombre);
                      }
                    });
                  },
                  title: Text(
                    '${servicio.nombre} · RD\$ ${servicio.precio}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          );
        }),
        // Servicios sin grupo
        if (serviciosSinGrupo.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            color: const Color(0xFFF3F5F8),
            child: const Text(
              'SIN GRUPO',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textGray,
              ),
            ),
          ),
          ...serviciosSinGrupo.map(
            (servicio) => CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _serviciosMarcados.contains(servicio.nombre),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _serviciosMarcados.add(servicio.nombre);
                  } else {
                    _serviciosMarcados.remove(servicio.nombre);
                  }
                });
              },
              title: Text(
                '${servicio.nombre} · RD\$ ${servicio.precio}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
        // Sin servicios
        if (widget.serviciosDisponibles.isEmpty)
          const ListTile(
            dense: true,
            title: Text('No hay servicios activos configurados.'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: AppColors.headerNavy,
                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Editar Cita',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Material(
                color: AppColors.background,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DATOS DEL CLIENTE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textGray,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _clienteController,
                        decoration: _decoracionCampo('Nombre completo'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _telefonoController,
                        decoration: _decoracionCampo('Teléfono'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _correoController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _decoracionCampo('Correo del cliente'),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'DATOS DEL VEHÍCULO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textGray,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _marcaSeleccionada,
                              decoration: _decoracionCampo('Marca'),
items: widget.marcas
    .where((m) => m.activo)
    .map(
      (m) => DropdownMenuItem(
        value: m.nombre,
        child: Text(
          m.nombre,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    )
    .toList(),
                              onChanged: (valor) =>
                                  setState(() => _marcaSeleccionada = valor),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _modeloController,
                              decoration: _decoracionCampo('Modelo'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _anioController,
                              keyboardType: TextInputType.number,
                              decoration: _decoracionCampo('Año'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _placaController,
                              decoration: _decoracionCampo('Placa'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'SERVICIOS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textGray,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.inputBorder),
                          borderRadius: BorderRadius.circular(8),
                        ),
child: _buildServiciosAgrupados(),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'ASIGNACIÓN',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textGray,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _tecnicoSeleccionado,
                        decoration: _decoracionCampo('Técnico'),
                        items: widget.tecnicosDisponibles
                            .map(
                              (tecnico) => DropdownMenuItem(
                                value: tecnico.nombre,
                                child: Text(
                                  tecnico.nombre,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (valor) =>
                            setState(() => _tecnicoSeleccionado = valor),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final nuevaFecha = await showDatePicker(
                                  context: context,
                                  initialDate: _fecha,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (nuevaFecha != null) {
                                  setState(() => _fecha = nuevaFecha);
                                }
                              },
                              child: InputDecorator(
                                decoration: _decoracionCampo('Fecha'),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatearFechaCorta(_fecha),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 16,
                                      color: AppColors.textGray,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final nuevaHora = await showTimePicker(
                                  context: context,
                                  initialTime: _hora,
                                );
                                if (nuevaHora != null) {
                                  setState(() => _hora = nuevaHora);
                                }
                              },
                              child: InputDecorator(
                                decoration: _decoracionCampo('Hora'),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _hora.format(context),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const Icon(
                                      Icons.access_time,
                                      size: 16,
                                      color: AppColors.textGray,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _estadoSeleccionado,
                        decoration: _decoracionCampo('Estado'),
                        items: kEstadosCitaAdmin
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text(
                                  e,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (valor) => setState(
                          () => _estadoSeleccionado =
                              valor ?? _estadoSeleccionado,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _descripcionController,
                        maxLines: 3,
                        decoration: _decoracionCampo('Descripción'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(18),
              child: ElevatedButton(
                onPressed: () {
                  final citaActualizada = CitaAdmin(
                    id: widget.cita.id,
                    codigoVisible: widget.cita.codigoVisible,
                    cliente: _clienteController.text.trim(),
                    telefono: _telefonoController.text.trim(),
                    correoCliente: _correoController.text.trim().toLowerCase(),
                    marca: _marcaSeleccionada ?? widget.cita.marca,
                    modelo: _modeloController.text.trim(),
                    anio: _anioController.text.trim(),
                    placa: _placaController.text.trim(),
                    servicios: _serviciosMarcados.toList(),
                    fecha: _fecha,
                    hora: _hora,
                    estado: switch (_estadoSeleccionado) {
                      'Atrasadas' => EstadoCitaAdmin.atrasada,
                      'Pendiente' => EstadoCitaAdmin.pendiente,
                      'Esperando Pieza' => EstadoCitaAdmin.esperandoPieza,
                      'En proceso' => EstadoCitaAdmin.enProceso,
                      'Completado' => EstadoCitaAdmin.completada,
                      _ => EstadoCitaAdmin.pendiente,
                    },
                    descripcion: _descripcionController.text.trim(),
                    tecnico: _tecnicoSeleccionado ?? widget.cita.tecnico,
                    total: widget.cita.total,
                    tallerId: widget.cita.tallerId,
                    creadoEn: widget.cita.creadoEn,
                    actualizadoEn: widget.cita.actualizadoEn,
                    syncStatus: widget.cita.syncStatus,
                  );
                  widget.onSaved(citaActualizada);
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orangePrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Guardar cambios',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;
}

class _FieldWidget extends StatelessWidget {
  const _FieldWidget({required this.label, required this.value});

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
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFEDEFF3)),
          ),
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.fields});

  final List<(String, String)> fields;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 420 ? 2 : 1;
        final fieldWidth =
            (constraints.maxWidth - (columns - 1) * 12) / columns;

        return Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (final field in fields)
              SizedBox(
                width: fieldWidth,
                child: _FieldWidget(label: field.$1, value: field.$2),
              ),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textGray,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F7EF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCFEAD9)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.headerNavy,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class CitasScreen extends StatefulWidget {
  const CitasScreen({super.key});

  @override
  State<CitasScreen> createState() => _CitasScreenState();
}

class _CitasScreenState extends State<CitasScreen> {
  DateTime _fechaSeleccionada = DateTime.now();
  bool _filtrosExpandido = false;
  String? _categoriaExpandida;
  late final TextEditingController _busquedaController;
  String? _tecnicoFiltro;
  bool _buscarEnTodasLasFechas = false;
  final CitasController _citasController = CitasController();
  List<TipoServicio> _serviciosDisponibles = const <TipoServicio>[];
  List<Tecnico> _tecnicosDisponibles = const <Tecnico>[];
  List<GrupoServicio> _gruposServicio = const <GrupoServicio>[];
  List<GrupoServicioItem> _grupoServicioItems = const <GrupoServicioItem>[];
  List<Marca> _marcasDisponibles = const <Marca>[];
  bool _cargandoCatalogos = true;

  @override
  void initState() {
    super.initState();
    _busquedaController = TextEditingController();
    _citasController.cargar();
    _cargarCatalogos();
    SyncService.instance.addListener(_alCambiarCatalogos);
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _citasController.dispose();
    SyncService.instance.removeListener(_alCambiarCatalogos);
    super.dispose();
  }

  Future<void> _cargarCatalogos() async {
    final tallerId = SesionAdmin.instance.tallerId;
    if (mounted) setState(() => _cargandoCatalogos = true);
    if (tallerId == null || tallerId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _serviciosDisponibles = const <TipoServicio>[];
        _tecnicosDisponibles = const <Tecnico>[];
        _gruposServicio = const <GrupoServicio>[];
        _grupoServicioItems = const <GrupoServicioItem>[];
        _marcasDisponibles = const <Marca>[];
        _cargandoCatalogos = false;
      });
      return;
    }

    try {
      await DatabaseHelper.instance.asegurarCatalogosParaTaller(tallerId);
      final resultados = await Future.wait(<Future<Object?>>[
        TipoServicioRepository.instance.obtenerTodasPorTaller(tallerId),
        TecnicoRepository.instance.obtenerActivosPorTaller(tallerId),
        GrupoServicioRepository.instance.obtenerActivosPorTaller(tallerId),
        MarcaRepository.instance.obtenerActivasPorTaller(tallerId),
      ]);
      if (!mounted || SesionAdmin.instance.tallerId != tallerId) return;

      // Obtener items de grupos-servicios
      final items = await GrupoServicioItemRepository.instance.obtenerActivosPorTaller(tallerId);

      setState(() {
        _serviciosDisponibles = (resultados[0] as List<TipoServicio>)
            .where((servicio) => servicio.activo)
            .toList(growable: false);
        _tecnicosDisponibles = resultados[1] as List<Tecnico>;
        _gruposServicio = resultados[2] as List<GrupoServicio>;
        _marcasDisponibles = resultados[3] as List<Marca>;
        _grupoServicioItems = items.where((item) => item.activo).toList(growable: false);
        _cargandoCatalogos = false;
        if (_tecnicoFiltro != null &&
            !_tecnicosDisponibles.any(
              (tecnico) => tecnico.nombre == _tecnicoFiltro,
            )) {
          _tecnicoFiltro = null;
        }
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _cargandoCatalogos = false);
      debugPrint('[CitasScreen] No se pudieron cargar los catálogos: $error');
    }
  }

  void _alCambiarCatalogos() {
    if (mounted) unawaited(_cargarCatalogos());
  }

  List<cita_data.Cita> _obtenerCitasFiltradas(String categoria) {
    final query = _busquedaController.text.trim().toLowerCase();
    final bool hayFiltroTecnico =
        _tecnicoFiltro != null && _tecnicoFiltro != 'Todos';

    List<cita_data.Cita> listaBase;
    if (_buscarEnTodasLasFechas) {
      final momento = DateTime.now();
      listaBase = _citasController.citas.where((c) {
        final estadoCita = c.esAtrasada(momento)
            ? cita_data.Cita.etiquetaAtrasadas
            : c.etiquetaUI(momento);
        return estadoCita == categoria;
      }).toList();
    } else {
      final agrupadas = _citasController.agruparPorEstado(_fechaSeleccionada);
      listaBase = agrupadas[categoria] ?? const <cita_data.Cita>[];
    }

    if (query.isEmpty && !hayFiltroTecnico) {
      return listaBase;
    }

    return listaBase.where((cita) {
      if (hayFiltroTecnico && cita.tecnico != _tecnicoFiltro) {
        return false;
      }
      if (query.isNotEmpty) {
        final cliente = cita.cliente.toLowerCase();
        final telefono = cita.telefono.toLowerCase();
        final correo = cita.correoCliente.toLowerCase();
        final vehiculo = cita.vehiculo.toLowerCase();
        final marca = cita.marca.toLowerCase();
        final modelo = cita.modelo.toLowerCase();
        final placa = cita.placa.toLowerCase();
        final tecnico = cita.tecnico.toLowerCase();
        final descripcion = cita.descripcion.toLowerCase();
        final servicios = cita.servicios.join(' ').toLowerCase();

        final coincide =
            cliente.contains(query) ||
            telefono.contains(query) ||
            correo.contains(query) ||
            vehiculo.contains(query) ||
            marca.contains(query) ||
            modelo.contains(query) ||
            placa.contains(query) ||
            tecnico.contains(query) ||
            descripcion.contains(query) ||
            servicios.contains(query);

        if (!coincide) return false;
      }
      return true;
    }).toList();
  }

  cita_data.Cita _aCitaPersistida(CitaAdmin cita) {
    final estado = switch (cita.estado) {
      EstadoCitaAdmin.atrasada => cita_data.EstadoCita.pendiente,
      EstadoCitaAdmin.pendiente => cita_data.EstadoCita.pendiente,
      EstadoCitaAdmin.aceptada => cita_data.EstadoCita.pendiente,
      // Lado del cliente: todo lo posterior a "aceptada" se ve como "aceptada"
      EstadoCitaAdmin.rechazada => cita_data.EstadoCita.pendiente,
      EstadoCitaAdmin.esperandoPieza => cita_data.EstadoCita.aceptada,
      EstadoCitaAdmin.enProceso => cita_data.EstadoCita.aceptada,
      EstadoCitaAdmin.completada => cita_data.EstadoCita.aceptada,
    };
    final fechaCita = DateTime(
      cita.fecha.year,
      cita.fecha.month,
      cita.fecha.day,
      cita.hora.hour,
      cita.hora.minute,
    );
    return cita_data.Cita(
      id: cita.id,
      codigoVisible: cita.codigoVisible,
      cliente: cita.cliente,
      telefono: cita.telefono,
      correoCliente: cita.correoCliente,
      vehiculo: _vehiculoPersistible(
        marca: cita.marca,
        modelo: cita.modelo,
        anio: cita.anio,
        placa: cita.placa,
      ),
      marca: cita.marca,
      modelo: cita.modelo,
      anio: int.tryParse(cita.anio) ?? 0,
      placa: cita.placa,
      servicios: cita.servicios,
      tecnico: cita.tecnico ?? '',
      descripcion: cita.descripcion,
      fechaCita: fechaCita,
      estado: estado,
      // `Cita` de v5 guarda el total como `int`; `CitaAdmin` lo maneja como
      // `double` para el formateo de moneda. La conversion va en el puente.
      total: cita.total.round(),
      // Sin esto el mapeo se perdia de ida y vuelta: la cita volvia a
      // `base` sin taller y sin fecha de alta.
      tallerId: cita.tallerId,
      creadoEn: cita.creadoEn,
      actualizadoEn: cita.actualizadoEn,
    );
  }

  String _vehiculoPersistible({
    required String marca,
    required String modelo,
    required String anio,
    required String placa,
  }) {
    final detalleAnio = anio.trim().isEmpty ? '' : ' (${anio.trim()})';
    final detallePlaca = placa.trim().isEmpty ? '' : ' · ${placa.trim()}';
    return '${marca.trim()} ${modelo.trim()}$detalleAnio$detallePlaca'.trim();
  }

  CitaAdmin _citaParaTarjeta(cita_data.Cita cita) {
    final estado = cita.esAtrasada(DateTime.now())
        ? EstadoCitaAdmin.atrasada
        : switch (cita.estado) {
            cita_data.EstadoCita.pendiente => EstadoCitaAdmin.pendiente,
            // BD tiene 'aceptada' pero en admin se muestra como 'Pendiente'
            cita_data.EstadoCita.aceptada => EstadoCitaAdmin.pendiente,
            // BD tiene 'rechazada' pero en admin se muestra como 'Pendiente'
            cita_data.EstadoCita.rechazada => EstadoCitaAdmin.pendiente,
            cita_data.EstadoCita.esperandoPieza => EstadoCitaAdmin.esperandoPieza,
            cita_data.EstadoCita.enProceso => EstadoCitaAdmin.enProceso,
            cita_data.EstadoCita.completado => EstadoCitaAdmin.completada,
          };

    return CitaAdmin(
      // `id: cita.id` y no `cita.id!`: `CitaAdmin.id` es `String?` porque la
      // pantalla tambien pinta citas recien creadas que todavia no se guardaron
      // (el formulario arma el modelo antes del `INSERT`). Con el `!` una cita
      // sin guardar revienta la pantalla al construir la tarjeta, en vez de
      // aparecer sin id.
      id: cita.id,
      codigoVisible: cita.codigoVisible,
      cliente: cita.cliente,
      telefono: cita.telefono,
      correoCliente: cita.correoCliente,
      marca: cita.marca,
      modelo: cita.modelo,
      anio: cita.anio.toString(),
      placa: cita.placa,
      servicios: cita.servicios,
      // `fechaCita` viene en UTC de la base; la tarjeta pinta el
      // horario local del taller, que es lo que eligio el usuario.
      fecha: cita.fechaCita.toLocal(),
      hora: TimeOfDay.fromDateTime(cita.fechaCita.toLocal()),
      estado: estado,
      descripcion: cita.descripcion,
      tecnico: cita.tecnico,
      total: cita.total.toDouble(),
      tallerId: cita.tallerId,
      creadoEn: cita.creadoEn,
      actualizadoEn: cita.actualizadoEn,
      syncStatus: cita.syncStatus,
    );
  }

  Future<void> _guardarEdicion(CitaAdmin cita) async {
    final guardada = await _citasController.guardar(_aCitaPersistida(cita));
    if (!guardada && mounted) _mostrarErrorPersistencia();
  }

  /// Mueve la cita de estado sin reescribir el resto de la fila.
  ///
  /// 'Atrasadas' no se persiste: es una etiqueta derivada de la fecha, no un
  /// estado guardado. Si el admin la eligiera, la cita quedaria con un estado
  /// que ninguna consulta por estado reconoce.
  ///
  /// El id es `String` (UUID) desde la v7.
  Future<void> _cambiarEstadoCita(String id, EstadoCitaAdmin nuevo) async {
    if (nuevo == EstadoCitaAdmin.atrasada) return;
    final estado = switch (nuevo) {
      EstadoCitaAdmin.pendiente => cita_data.EstadoCita.pendiente,
      EstadoCitaAdmin.aceptada => cita_data.EstadoCita.pendiente,
      EstadoCitaAdmin.rechazada => cita_data.EstadoCita.pendiente,
      EstadoCitaAdmin.esperandoPieza => cita_data.EstadoCita.esperandoPieza,
      EstadoCitaAdmin.enProceso => cita_data.EstadoCita.enProceso,
      EstadoCitaAdmin.completada => cita_data.EstadoCita.completado,
      EstadoCitaAdmin.atrasada => cita_data.EstadoCita.pendiente,
    };
    final cambiado = await _citasController.cambiarEstado(id, estado);
    if (!cambiado && mounted) _mostrarErrorPersistencia();
  }

  /// Aceptar o rechazar es un cambio parcial en SQLite; el controller marca la
  /// fila como `pending` y solicita a SyncService subirla cuando haya red.
  Future<void> _responderSolicitud(
    cita_data.Cita cita,
    cita_data.EstadoCita estado, {
    String? motivoRechazo,
  }) async {
    final id = cita.id;
    if (id == null) {
      _mostrarErrorPersistencia();
      return;
    }

    if (estado == cita_data.EstadoCita.aceptada) {
      // Aceptar: pasa a "aceptada" -> aparece en accordion "Pendiente"
      final guardada = await _citasController.cambiarEstado(id, cita_data.EstadoCita.aceptada);
      if (!mounted) return;
      if (!guardada) {
        _mostrarErrorPersistencia();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud aceptada.')),
      );
    } else if (estado == cita_data.EstadoCita.rechazada) {
      // Rechazar: pasa a "rechazada" con motivo -> desaparece de "Solicitudes" y en cliente se ve "Rechazada"
      final guardada = await _citasController.cambiarEstado(id, cita_data.EstadoCita.rechazada, motivoRechazo: motivoRechazo);
      if (!mounted) return;
      if (!guardada) {
        _mostrarErrorPersistencia();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud rechazada.')),
      );
    }
  }

  /// BORRADO LOGICO desde la v7: `_citasController.eliminar` no borra la fila,
  /// la marca. Ver `lib/core/utils/borrado_logico.dart`.
  Future<void> _eliminarCita(String id) async {
    final eliminada = await _citasController.eliminar(id);
    if (!eliminada && mounted) _mostrarErrorPersistencia();
  }

  void _mostrarErrorPersistencia() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_citasController.error ?? 'No se pudo guardar la cita.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      drawer: _buildDrawer(context),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroCard(),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: _citasController,
              builder: (context, _) => SolicitudesCitasAdminSection(
                citas: _citasController.citas,
                onCambiarEstado: _responderSolicitud,
                cargando: _citasController.cargando,
              ),
            ),
            const SizedBox(height: 16),
            _buildFiltrosAvanzados(),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: _citasController,
              builder: (context, _) {
                return Column(
                  children: [
                    for (final categoria in kColorPorEstado.keys) ...[
                      if (categoria != 'ATRASADAS' ||
                          _obtenerCitasFiltradas(categoria).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildEstadoAccordion(
                            nombre: categoria,
                            color: kColorPorEstado[categoria]!,
                            expanded: _categoriaExpandida == categoria,
                            onTap: () => setState(() {
                              _categoriaExpandida =
                                  _categoriaExpandida == categoria
                                  ? null
                                  : categoria;
                            }),
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final taller = SesionAdmin.instance.tallerNombre ?? 'SISTEMA DE GESTIÓN';
    final email = SesionAdmin.instance.adminEmail ?? 'Admin';
    final inicial = email.isNotEmpty ? email[0].toUpperCase() : 'A';

    return AppBar(
      backgroundColor: AppColors.headerNavy,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'AutoFix',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              taller.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: CircleAvatar(
            backgroundColor: AppColors.orangePrimary,
            radius: 18,
            child: Text(
              inicial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final taller = SesionAdmin.instance.tallerNombre ?? 'SISTEMA DE GESTIÓN';
    final email = SesionAdmin.instance.adminEmail ?? '';

    return Drawer(
      backgroundColor: AppColors.headerNavy,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AutoFix',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      taller,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.orangePrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _drawerItem(
              icon: Icons.grid_view_rounded,
              label: 'Dashboard',
              selected: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DashboardScreen()),
              ),
            ),
            _drawerItem(
              icon: Icons.calendar_today_outlined,
              label: 'Citas',
              selected: true,
            ),
            _drawerItem(
              icon: Icons.settings_outlined,
              label: 'Configuración',
              selected: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConfiguracionScreen()),
              ),
            ),
            _drawerItem(
              icon: Icons.manage_accounts_outlined,
              label: 'Editar Perfil',
              selected: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const EditarPerfilAdminScreen(),
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: TextButton.icon(
                onPressed: () async {
                  // `await` porque cerrar sesion ahora tambien borra la caché
                  // local de sesion: sin este orden el proximo arranque entraria
                  // solo al Dashboard y pareceria que el logout no sirvio.
                  //
                  // ANTES de eso va la decision de limpieza local (reglas 1 y
                  // 2 de `LimpiezaLocal`): lee el keystore y purga las citas y
                  // el perfil locales si el usuario NO pidio recordar. Va
                  // primero porque despues `CredencialesSeguras.borrar()`
                  // se lleva la unica evidencia del recordamiento, y porque el
                  // ultimo push necesita la sesion de Auth todavia abierta.
                  await LimpiezaLocal.alCerrarSesion();
                  await SesionAdmin.instance.cerrar();
                  await CredencialesSeguras.borrar();
                  await SyncService.instance.stop();
                  try {
                    await FirebaseAuth.instance.signOut();
                    await FirebaseAuth.instance.signInAnonymously();
                    await SyncService.instance.start();
                  } catch (_) {}
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  }
                },
                icon: const Icon(
                  Icons.logout,
                  size: 18,
                  color: Colors.redAccent,
                ),
                label: const Text(
                  'Cerrar Sesión',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    return Material(
      color: selected
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color: selected ? AppColors.orangePrimary : Colors.white70,
          size: 20,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.orangePrimary : Colors.white70,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        shape: selected
            ? const Border(
                left: BorderSide(color: AppColors.orangePrimary, width: 3),
              )
            : null,
      ),
    );
  }

  Widget _buildHeroCard() {
    final bool esHoy = _esMismoDia(_fechaSeleccionada, DateTime.now());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.headerNavy,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CITAS DE',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            esHoy ? 'Hoy' : _formatearFechaLarga(_fechaSeleccionada),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _navCircleButton(
                Icons.chevron_left,
                onTap: () {
                  setState(
                    () => _fechaSeleccionada = _fechaSeleccionada.subtract(
                      const Duration(days: 1),
                    ),
                  );
                },
              ),
              _buildCampoFechaHero(),
              _navCircleButton(
                Icons.chevron_right,
                onTap: () {
                  setState(
                    () => _fechaSeleccionada = _fechaSeleccionada.add(
                      const Duration(days: 1),
                    ),
                  );
                },
              ),
              ElevatedButton.icon(
                onPressed: _abrirFormularioNuevaCita,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nueva'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orangePrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCampoFechaHero() {
    return InkWell(
      onTap: () async {
        final nuevaFecha = await showDatePicker(
          context: context,
          initialDate: _fechaSeleccionada,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (nuevaFecha != null) setState(() => _fechaSeleccionada = nuevaFecha);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 40,
        constraints: const BoxConstraints(minWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatearFechaCorta(_fechaSeleccionada),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.calendar_today_outlined,
              color: Colors.white54,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navCircleButton(IconData icon, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white38),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
    );
  }

  Widget _buildFiltrosAvanzados() {
    final hayFiltrosActivos =
        _busquedaController.text.isNotEmpty ||
        (_tecnicoFiltro != null && _tecnicoFiltro != 'Todos') ||
        _buscarEnTodasLasFechas;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _filtrosExpandido = !_filtrosExpandido),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_alt_outlined,
                    size: 18,
                    color: hayFiltrosActivos
                        ? AppColors.orangePrimary
                        : AppColors.textGray,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hayFiltrosActivos
                          ? 'Filtros avanzados (Activos)'
                          : 'Filtros avanzados',
                      style: TextStyle(
                        color: hayFiltrosActivos
                            ? AppColors.orangePrimary
                            : AppColors.textGray,
                        fontSize: 14,
                        fontWeight: hayFiltrosActivos
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (hayFiltrosActivos) ...[
                    InkWell(
                      onTap: () {
                        setState(() {
                          _busquedaController.clear();
                          _tecnicoFiltro = null;
                          _buscarEnTodasLasFechas = false;
                        });
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          'Limpiar',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  AnimatedRotation(
                    turns: _filtrosExpandido ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _filtrosExpandido
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _busquedaController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Buscar por cliente, vehículo o placa...',
                      hintStyle: const TextStyle(
                        color: AppColors.placeholderGray,
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 18,
                        color: AppColors.textGray,
                      ),
                      suffixIcon: _busquedaController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _busquedaController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.inputBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.orangePrimary,
                          width: 1.5,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_cargandoCatalogos) ...[
                    const LinearProgressIndicator(minHeight: 2),
                    const SizedBox(height: 10),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: _tecnicoFiltro ?? 'Todos',
                    decoration: InputDecoration(
                      labelText: 'Filtrar por técnico',
                      labelStyle: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textGray,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.inputBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.orangePrimary,
                          width: 1.5,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'Todos',
                        child: Text(
                          'Todos los técnicos',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      ..._tecnicosDisponibles.map(
                        (tecnico) => DropdownMenuItem(
                          value: tecnico.nombre,
                          child: Text(
                            tecnico.nombre,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() {
                      _tecnicoFiltro = val == 'Todos' ? null : val;
                    }),
                  ),
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.transparent,
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.orangePrimary,
                      title: const Text(
                        'Buscar en todas las fechas',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      value: _buscarEnTodasLasFechas,
                      onChanged: (val) => setState(() {
                        _buscarEnTodasLasFechas = val ?? false;
                      }),
                    ),
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoAccordion({
    required String nombre,
    required Color color,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    final citas = _obtenerCitasFiltradas(nombre);
    final cantidadVisible = citas.length;
    return Column(
      children: [
        Material(
          color: color,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      nombre.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    child: Text(
                      '$cantidadVisible',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardWhite,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: _citasController.cargando
                ? const Center(child: CircularProgressIndicator())
                : _citasController.error != null
                ? Text(
                    'No se pudieron cargar las citas: ${_citasController.error}',
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 13,
                    ),
                  )
                : citas.isEmpty
                ? const Text(
                    'No hay citas en este estado.',
                    style: TextStyle(color: AppColors.textGray, fontSize: 13),
                  )
                : Column(
                    children: [
                      for (final cita in citas)
                        CitaAdminCard(
                          cita: _citaParaTarjeta(cita),
                          serviciosDisponibles: _serviciosDisponibles,
                          tecnicosDisponibles: _tecnicosDisponibles,
                          gruposServicio: _gruposServicio,
                          grupoServicioItems: _grupoServicioItems,
                          marcas: _marcasDisponibles,
                          onEdited: (citaActualizada) {
                            _guardarEdicion(citaActualizada);
                          },
                          onEstadoCambiado: (nuevoEstado) {
                            final id = cita.id;
                            if (id == null) return;
                            _cambiarEstadoCita(id, nuevoEstado);
                          },
                          onDeleted: (id) {
                            _eliminarCita(id);
                          },
                        ),
                    ],
                  ),
          ),
          secondChild: const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }

  bool _esMismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatearFechaCorta(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  String _formatearFechaLarga(DateTime fecha) {
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return '${fecha.day} de ${meses[fecha.month - 1]}';
  }

  Future<void> _abrirFormularioNuevaCita() async {
    await _cargarCatalogos();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        return _CrearCitaDialog(
          serviciosDisponibles: _serviciosDisponibles,
          tecnicosDisponibles: _tecnicosDisponibles,
          gruposServicio: _gruposServicio,
          grupoServicioItems: _grupoServicioItems,
          marcas: _marcasDisponibles,
          onSaved: (cita) async {
            final guardada = await _citasController.guardar(cita);
            if (!mounted) return guardada;
            if (!guardada) {
              _mostrarErrorPersistencia();
            }
            return guardada;
          },
        );
      },
    );
  }
}

class _CrearCitaDialog extends StatefulWidget {
  const _CrearCitaDialog({
    required this.onSaved,
    required this.serviciosDisponibles,
    required this.tecnicosDisponibles,
    required this.gruposServicio,
    required this.grupoServicioItems,
    required this.marcas,
  });

  final Future<bool> Function(cita_data.Cita cita) onSaved;
  final List<TipoServicio> serviciosDisponibles;
  final List<Tecnico> tecnicosDisponibles;
  final List<GrupoServicio> gruposServicio;
  final List<GrupoServicioItem> grupoServicioItems;
  final List<Marca> marcas;

  @override
  State<_CrearCitaDialog> createState() => _CrearCitaDialogState();
}

class _CrearCitaDialogState extends State<_CrearCitaDialog> {
  late final TextEditingController _clienteController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _correoController;
  late final TextEditingController _modeloController;
  late final TextEditingController _anioController;
  late final TextEditingController _placaController;
  late final TextEditingController _descripcionController;

  String? _marcaSeleccionada;
  String? _tecnicoSeleccionado;
  String _estadoSeleccionado = 'Pendiente';
  DateTime _fecha = DateTime.now();
  TimeOfDay? _hora;
  final Set<String> _serviciosMarcados = {};
  final _formKey = GlobalKey<FormState>();
  bool _guardando = false;
  bool _intentoGuardar = false;

  int get _totalEstimado =>
      TipoServicio.totalDe(widget.serviciosDisponibles, _serviciosMarcados);

  @override
  void initState() {
    super.initState();
    _clienteController = TextEditingController();
    _telefonoController = TextEditingController();
    _correoController = TextEditingController();
    _modeloController = TextEditingController();
    _anioController = TextEditingController();
    _placaController = TextEditingController();
    _descripcionController = TextEditingController();
  }

  @override
  void dispose() {
    _clienteController.dispose();
    _telefonoController.dispose();
    _correoController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _placaController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  InputDecoration _decoracionCampo(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.textGray),
      hintStyle: const TextStyle(
        color: AppColors.placeholderGray,
        fontSize: 13,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: AppColors.orangePrimary,
          width: 1.5,
        ),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  String _formatearFechaCorta(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  String _vehiculoPersistible({
    required String marca,
    required String modelo,
    required String anio,
    required String placa,
  }) {
    final detalleAnio = anio.trim().isEmpty ? '' : ' (${anio.trim()})';
    final detallePlaca = placa.trim().isEmpty ? '' : ' · ${placa.trim()}';
    return '${marca.trim()} ${modelo.trim()}$detalleAnio$detallePlaca'.trim();
  }

  Widget _tituloSeccionModal(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textGray,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildServiciosAgrupados() {
    // Servicios sin grupo asignado
    final serviciosConGrupo = <String>{};
    for (final item in widget.grupoServicioItems) {
      serviciosConGrupo.add(item.tipoServicioId);
    }
    final serviciosSinGrupo = widget.serviciosDisponibles
        .where((s) => !serviciosConGrupo.contains(s.id))
        .toList();

    // Mapa de grupo -> lista de servicios
    final Map<String, List<TipoServicio>> serviciosPorGrupo = {};
    for (final grupo in widget.gruposServicio) {
      final servicioIds = widget.grupoServicioItems
          .where((item) => item.grupoId == grupo.id && item.activo)
          .map((item) => item.tipoServicioId)
          .toSet();
      final servicios = widget.serviciosDisponibles
          .where((s) => servicioIds.contains(s.id))
          .toList();
      if (servicios.isNotEmpty) {
        serviciosPorGrupo[grupo.nombre] = servicios;
      }
    }

    return Column(
      children: [
        // Grupos con servicios
        ...serviciosPorGrupo.entries.map((entry) {
          final grupoNombre = entry.key;
          final servicios = entry.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                color: const Color(0xFFF3F5F8),
                child: Text(
                  grupoNombre.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textGray,
                  ),
                ),
              ),
              ...servicios.map(
                (servicio) => CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _serviciosMarcados.contains(servicio.nombre),
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _serviciosMarcados.add(servicio.nombre);
                      } else {
                        _serviciosMarcados.remove(servicio.nombre);
                      }
                    });
                  },
                  title: Text(
                    '${servicio.nombre} · RD\$ ${servicio.precio}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          );
        }),
        // Servicios sin grupo
        if (serviciosSinGrupo.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            color: const Color(0xFFF3F5F8),
            child: const Text(
              'SIN GRUPO',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textGray,
              ),
            ),
          ),
          ...serviciosSinGrupo.map(
            (servicio) => CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _serviciosMarcados.contains(servicio.nombre),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _serviciosMarcados.add(servicio.nombre);
                  } else {
                    _serviciosMarcados.remove(servicio.nombre);
                  }
                });
              },
              title: Text(
                '${servicio.nombre} · RD\$ ${servicio.precio}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
        // Sin servicios
        if (widget.serviciosDisponibles.isEmpty)
          const ListTile(
            dense: true,
            title: Text('No hay servicios activos configurados.'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final fechaCita = DateTime(
      _fecha.year,
      _fecha.month,
      _fecha.day,
      _hora?.hour ?? 0,
      _hora?.minute ?? 0,
    );
    final fechaAnterior = DateTime(
      _fecha.year,
      _fecha.month,
      _fecha.day,
    ).isBefore(DateTime(hoy.year, hoy.month, hoy.day));
    final horaAnterior =
        _hora != null && fechaCita.isBefore(hoy) && !fechaAnterior;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: AppColors.headerNavy,
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Nueva Cita',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                    },
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Material(
                color: AppColors.background,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _tituloSeccionModal('DATOS DEL CLIENTE'),
                        TextFormField(
                          controller: _clienteController,
                          textCapitalization: TextCapitalization.words,
                          decoration: _decoracionCampo('Nombre completo')
                              .copyWith(hintText: 'Nombre del cliente'),
                          validator: (valor) {
                            final nombre = valor?.trim() ?? '';
                            if (nombre.isEmpty) {
                              return 'Ingresa el nombre del cliente.';
                            }
                            if (nombre.length < 3) {
                              return 'El nombre debe tener al menos 3 caracteres.';
                            }
                            if (RegExp(r'\d').hasMatch(nombre)) {
                              return 'El nombre no puede contener números.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _telefonoController,
                          keyboardType: TextInputType.phone,
                          decoration: _decoracionCampo('Teléfono')
                              .copyWith(hintText: '809-000-0000'),
                          validator: (valor) {
                            final telefono = valor?.trim() ?? '';
                            if (telefono.isEmpty) {
                              return 'Ingresa el teléfono del cliente.';
                            }
                            if (!RegExp(r'^[+\d\s().-]+$').hasMatch(telefono)) {
                              return 'El teléfono contiene caracteres no válidos.';
                            }
                            final digitos = telefono.replaceAll(
                              RegExp(r'\D'),
                              '',
                            );
                            if (digitos.length < 10 || digitos.length > 15) {
                              return 'Ingresa un teléfono válido (10 a 15 dígitos).';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _correoController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _decoracionCampo('Correo del cliente')
                              .copyWith(
                                hintText: 'cliente@ejemplo.com',
                                helperText: 'Vincula esta cita con Mis citas del cliente.',
                              ),
                          validator: (valor) {
                            final correo = valor?.trim() ?? '';
                            if (correo.isEmpty) {
                              return 'Ingresa el correo del cliente para vincular la cita.';
                            }
                            if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch(correo)) {
                              return 'Ingresa un correo válido.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _tituloSeccionModal('DATOS DEL VEHÍCULO'),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _marcaSeleccionada,
                                decoration: _decoracionCampo('Marca'),
                                validator: (valor) => valor == null
                                    ? 'Selecciona la marca.'
                                    : null,
                                hint: const Text(
                                  'Seleccionar',
                                  style: TextStyle(fontSize: 13),
                                ),
items: widget.marcas
    .where((m) => m.activo)
    .map(
      (m) => DropdownMenuItem(
        value: m.nombre,
        child: Text(
          m.nombre,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    )
    .toList(),
                                onChanged: (valor) =>
                                    setState(() => _marcaSeleccionada = valor),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _modeloController,
                                textCapitalization: TextCapitalization.words,
                                decoration: _decoracionCampo('Modelo')
                                    .copyWith(hintText: 'Ej: Corolla'),
                                validator: (valor) {
                                  if (valor?.trim().isEmpty ?? true) {
                                    return 'Ingresa el modelo.';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _anioController,
                                keyboardType: TextInputType.number,
                                decoration: _decoracionCampo('Año')
                                    .copyWith(hintText: '2020'),
                                validator: (valor) {
                                  final anio = int.tryParse(
                                    valor?.trim() ?? '',
                                  );
                                  final anioActual = DateTime.now().year;
                                  if (anio == null) {
                                    return 'Ingresa un año válido.';
                                  }
                                  if (anio < 1900 || anio > anioActual + 1) {
                                    return 'El año debe estar entre 1900 y ${anioActual + 1}.';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _placaController,
                                decoration: _decoracionCampo('Placa')
                                    .copyWith(hintText: 'A123456'),
                                textCapitalization:
                                    TextCapitalization.characters,
                                validator: (valor) {
                                  final placa = valor?.trim() ?? '';
                                  if (placa.isEmpty) {
                                    return 'Ingresa la placa.';
                                  }
                                  if (!RegExp(r'^[A-Za-z0-9-]{4,10}$')
                                      .hasMatch(placa)) {
                                    return 'Usa de 4 a 10 letras, números o guiones.';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _tituloSeccionModal('SERVICIOS'),
                        const Text(
                          'Seleccionar servicios',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textGray,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          key: const ValueKey('servicios-cita'),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.inputBorder),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _buildServiciosAgrupados(),
                        ),
                        if (_intentoGuardar && _serviciosMarcados.isEmpty) ...[
                          const SizedBox(height: 6),
                          const Text(
                            'Selecciona al menos un servicio.',
                            style: TextStyle(
                              color: Color(0xFFB3261E),
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (_serviciosMarcados.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Total estimado: RD\$ $_totalEstimado',
                              style: const TextStyle(
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _tituloSeccionModal('ASIGNACIÓN'),
                        if (widget.tecnicosDisponibles.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                              'No hay técnicos activos; la cita quedará sin asignar.',
                              style: TextStyle(
                                color: AppColors.textGray,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        DropdownButtonFormField<String>(
                          initialValue: _tecnicoSeleccionado,
                          decoration: _decoracionCampo('Técnico'),
                          validator: (valor) =>
                              widget.tecnicosDisponibles.isNotEmpty &&
                                  valor == null
                              ? 'Selecciona un técnico.'
                              : null,
                          hint: const Text(
                            'Seleccionar técnico',
                            style: TextStyle(fontSize: 13),
                          ),
                          items: widget.tecnicosDisponibles
                              .map(
                                (tecnico) => DropdownMenuItem(
                                  value: tecnico.nombre,
                                  child: Text(
                                    tecnico.nombre,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: widget.tecnicosDisponibles.isEmpty
                              ? null
                              : (valor) => setState(
                                  () => _tecnicoSeleccionado = valor,
                                ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final nuevaFecha = await showDatePicker(
                                    context: context,
                                    initialDate: _fecha,
                                    firstDate: DateTime(
                                      hoy.year,
                                      hoy.month,
                                      hoy.day,
                                    ),
                                    lastDate: DateTime(2100),
                                  );
                                  if (nuevaFecha != null) {
                                    setState(() => _fecha = nuevaFecha);
                                  }
                                },
                                child: InputDecorator(
                                  decoration: _decoracionCampo('Fecha')
                                      .copyWith(
                                        errorText:
                                            _intentoGuardar && fechaAnterior
                                            ? 'La fecha no puede ser anterior a hoy.'
                                            : null,
                                      ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatearFechaCorta(_fecha),
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      const Icon(
                                        Icons.calendar_today_outlined,
                                        size: 16,
                                        color: AppColors.textGray,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final nuevaHora = await showTimePicker(
                                    context: context,
                                    initialTime: _hora ?? TimeOfDay.now(),
                                  );
                                  if (nuevaHora != null) {
                                    setState(() => _hora = nuevaHora);
                                  }
                                },
                                child: InputDecorator(
                                  decoration: _decoracionCampo('Hora').copyWith(
                                    errorText: _intentoGuardar
                                        ? _hora == null
                                              ? 'Selecciona la hora.'
                                              : horaAnterior
                                              ? 'La hora debe ser futura.'
                                              : null
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _hora == null
                                            ? '--:--'
                                            : _hora!.format(context),
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      const Icon(
                                        Icons.access_time,
                                        size: 16,
                                        color: AppColors.textGray,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _estadoSeleccionado,
                          decoration: _decoracionCampo('Estado'),
                          items: kEstadosCitaAdmin
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(
                                    e,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (valor) => setState(
                            () => _estadoSeleccionado =
                                valor ?? _estadoSeleccionado,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _descripcionController,
                          maxLines: 3,
                          decoration: _decoracionCampo('Descripción').copyWith(
                            hintText: 'Notas adicionales sobre la cita...',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: AppColors.headerNavy,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _guardando
                        ? null
                        : () async {
                            setState(() => _intentoGuardar = true);
                            final formularioValido =
                                _formKey.currentState?.validate() ?? false;
                            final fechaValida =
                                !fechaAnterior &&
                                _hora != null &&
                                !horaAnterior;
                            final serviciosValidos =
                                _serviciosMarcados.isNotEmpty;
                            if (!formularioValido ||
                                !fechaValida ||
                                !serviciosValidos) {
                              return;
                            }

                            final estado = switch (_estadoSeleccionado) {
                              'Esperando Pieza' =>
                                cita_data.EstadoCita.esperandoPieza,
                              'En proceso' => cita_data.EstadoCita.enProceso,
                              'Completado' => cita_data.EstadoCita.completado,
                              _ => cita_data.EstadoCita.pendiente,
                            };
                            final anio = _anioController.text.trim();
                            final cita = cita_data.Cita(
                              cliente: _clienteController.text.trim(),
                              correoCliente: _correoController.text
                                  .trim()
                                  .toLowerCase(),
                              telefono: _telefonoController.text.trim(),
                              vehiculo: _vehiculoPersistible(
                                marca: _marcaSeleccionada!,
                                modelo: _modeloController.text,
                                anio: anio,
                                placa: _placaController.text,
                              ),
                              marca: _marcaSeleccionada!,
                              modelo: _modeloController.text.trim(),
                              anio: int.tryParse(anio) ?? 0,
                              placa: _placaController.text.trim(),
                              servicios: _serviciosMarcados.toList(),
                              fechaCita: DateTime(
                                _fecha.year,
                                _fecha.month,
                                _fecha.day,
                                _hora!.hour,
                                _hora!.minute,
                              ),
                              estado: estado,
                              descripcion: _descripcionController.text.trim(),
                              tecnico: _tecnicoSeleccionado ?? '',
                              total: _totalEstimado,
                            );

                            setState(() => _guardando = true);
                            final guardada = await widget.onSaved(cita);
                            if (!guardada) {
                              setState(() => _guardando = false);
                              return;
                            }
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orangePrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _guardando
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Guardar Cita',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

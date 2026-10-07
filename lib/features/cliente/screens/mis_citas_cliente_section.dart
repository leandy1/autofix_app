import 'dart:async';

import 'package:flutter/material.dart';

import 'package:autofix/features/cliente/presentation/mis_citas_controller.dart';
import 'package:autofix/features/cliente/widgets/cliente_section_widgets.dart';
import 'package:autofix/features/cliente/widgets/codigo_qr_cita.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/sync/sync_service.dart';
import 'package:autofix/shared/theme/app_colors.dart';

/// Colores por etiqueta de estado, con las MISMAS llaves y colores que
/// `kColorPorEstado` de la pantalla de citas del admin.
///
/// Va en la vista y no en el controller porque el color es una decision de
/// diseno: el controller devuelve texto ('Pendiente', 'ATRASADAS') y quien
/// decide que color le corresponde es la pantalla. Duplicar el mapa aqui (en
/// vez de importar el del archivo de admin) es deliberado tambien: importar un
/// screen desde otro screen ataria este archivo a toda la pantalla de admin,
/// su `firebase_auth` y su `SyncService`.
const Map<String, Color> _colorPorEtiqueta = {
  Cita.etiquetaAtrasadas: AppColors.atrasadas,
  'Pendiente': AppColors.pendientes,
  'Aceptada': AppColors.greenAccent,
  'Rechazada': AppColors.atrasadas,
  'Esperando Pieza': AppColors.esperandoPieza,
  'En proceso': AppColors.enProceso,
  'Completado': AppColors.completado,
};

/// "9:30 a. m." / "2:05 p. m." -- hora local sin depender de `intl`.
///
/// Top-level y publica a proposito, igual que `formatearPesosDR` en el
/// formulario: es la que mas se rompe en silencio (una hora 00:30 que imprime
/// "0:30 a. m." o un mediodia que dice "0:00 p. m.") y por eso se puede
/// probar sin montar la pantalla.
///
/// No se usa `DateFormat('h:mm a', 'es')` porque el paquete `intl` solo trae
/// los locales que se cargan a mano; sin datos de locale `es_DO` esa llamada
/// revienta en runtime con un error de locale, no de formato. El sufijo en
/// espanol se arma a mano por la misma razon que la lista de meses de
/// `formatearFechaCliente`.
String horaCliente(DateTime horaLocal) {
  final hora12 = horaLocal.hour % 12 == 0 ? 12 : horaLocal.hour % 12;
  final minutos = horaLocal.minute.toString().padLeft(2, '0');
  final sufijo = horaLocal.hour < 12 ? 'a. m.' : 'p. m.';
  return '$hora12:$minutos $sufijo';
}

/// "Mis citas" del cliente, alimentada por la base local del dispositivo.
///
/// Todo lo que pinta esta seccion viene de [MisCitasController], que a su vez
/// lee SQLite: la pantalla funciona completa sin internet, que es el requisito
/// de la unidad de sesion/offline. La unica cosa de red que toca es
/// `SyncService.pushPending`, y la toca el formulario al crear la cita, no
/// esta vista.
class MisCitasClienteSection extends StatefulWidget {
  const MisCitasClienteSection({super.key});

  @override
  State<MisCitasClienteSection> createState() => _MisCitasClienteSectionState();
}

class _MisCitasClienteSectionState extends State<MisCitasClienteSection> {
  late final MisCitasController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MisCitasController();
    SyncService.instance.addListener(_alCambiarSync);
    // Sin `await`: el spinner de carga es el estado que ya arranca en `true`.
    unawaited(_controller.cargar());
  }

  @override
  void dispose() {
    // Sin esto cada vez que el cliente cambia de pestana la seccion acumula un
    // ChangeNotifier vivo que sigue notificando a nadie.
    _controller.dispose();
    SyncService.instance.removeListener(_alCambiarSync);
    super.dispose();
  }

  void _alCambiarSync() {
    if (mounted) unawaited(_controller.cargar());
  }

  @override
  Widget build(BuildContext context) {
    // Escucha SOLO el controller de esta seccion: un `setState` del estado
    // reconstruiria la pestana entera del dashboard, y notificar a nivel de
    // dashboard haria que las otras dos pestanas se repintaran tambien.
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const TituloSeccionCliente(
              eyebrow: 'TUS VISITAS',
              title: 'Mis citas',
              subtitle:
                  'Consulta el estado y presenta el QR cuando acepten tu cita.',
            ),
            const SizedBox(height: 14),
            if (_controller.hayPendientes) ...[
              _AvisoDeCola(pendientes: _controller.pendientesDeSync),
              const SizedBox(height: 14),
            ],
            ..._contenido(),
          ],
        );
      },
    );
  }

  List<Widget> _contenido() {
    if (_controller.cargando) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    final error = _controller.error;
    if (error != null) {
      return [
        _EstadoVacio(
          icono: Icons.error_outline,
          titulo: 'No pudimos abrir tus citas',
          detalle: error,
          boton: _BotonSecundarioCliente(
            etiqueta: 'Reintentar',
            onPressed: () => unawaited(_controller.cargar()),
          ),
        ),
      ];
    }

    if (!_controller.hayCitas) {
      return const [
        _EstadoVacio(
          icono: Icons.confirmation_number_outlined,
          titulo: 'Aún no tienes citas',
          detalle:
              'Agenda tu primera visita desde la pestaña "Agendar" y podrás '
              'seguir aquí su estado y código.',
        ),
      ];
    }

    final items = _controller.items;
    return [
      for (var index = 0; index < items.length; index++) ...[
        if (index > 0) const SizedBox(height: 14),
        _TarjetaCita(item: items[index]),
      ],
    ];
  }
}

/// Aviso general de que hay citas esperando subir.
///
/// Es el aviso que le da confianza al usuario en modo avion: sin estas lineas,
/// una cita creada sin internet parece idéntica a una perdida.
class _AvisoDeCola extends StatelessWidget {
  const _AvisoDeCola({required this.pendientes});

  final int pendientes;

  @override
  Widget build(BuildContext context) {
    final una = pendientes == 1;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.orangePrimary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.orangePrimary.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_upload_outlined,
            size: 18,
            color: AppColors.orangePrimary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              una
                  ? '1 cita en cola: se enviará al taller cuando vuelva la conexión.'
                  : '$pendientes citas en cola: se enviarán al taller cuando vuelva la conexión.',
              style: const TextStyle(
                color: AppColors.labelDark,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado sin datos (vacio o error). Un solo widget para los dos porque el
/// diseno es el mismo y lo único que cambia es el icono, el texto y si hay
/// boton.
class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.boton,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final Widget? boton;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(15),
        boxShadow: clienteCardShadow,
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.orangePrimary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icono, size: 28, color: AppColors.orangePrimary),
          ),
          const SizedBox(height: 14),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.labelDark,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textGray,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          if (boton != null) ...[const SizedBox(height: 16), boton!],
        ],
      ),
    );
  }
}

class _BotonSecundarioCliente extends StatelessWidget {
  const _BotonSecundarioCliente({
    required this.etiqueta,
    required this.onPressed,
  });

  final String etiqueta;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.orangePrimary,
        side: const BorderSide(color: AppColors.orangePrimary, width: 1.4),
      ),
      child: Text(etiqueta),
    );
  }
}

class _TarjetaCita extends StatelessWidget {
  const _TarjetaCita({required this.item});

  final CitaClienteItem item;

  Cita get cita => item.cita;

  @override
  Widget build(BuildContext context) {
    final fechaLocal = cita.fechaCita.toLocal();
    final colorEstado =
        _colorPorEtiqueta[item.etiqueta] ?? AppColors.pendientes;
    final servicios = cita.servicios.isEmpty
        ? 'Servicio por definir'
        : cita.servicios.join(', ');
    final placa = cita.placa.trim();
    final vehiculo = placa.isEmpty
        ? cita.vehiculo
        : '${cita.vehiculo} · $placa';

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
                  formatearFechaCliente(fechaLocal),
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.55,
                  ),
                ),
              ),
              _StatusBadge(label: item.etiqueta, color: colorEstado),
            ],
          ),
          if (item.enCola) ...[
            const SizedBox(height: 8),
            _BadgeEnCola(error: cita.syncStatus == 'error'),
          ],
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
                      item.tallerNombre,
                      style: const TextStyle(
                        color: AppColors.labelDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      servicios,
                      style: const TextStyle(
                        color: AppColors.textGray,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      vehiculo,
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
                horaCliente(fechaLocal),
                style: const TextStyle(
                  color: AppColors.labelDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                // `identificadorParaPantalla` y no `id`: hasta que la nube
                // asigne el numero, esto muestra 'PENDIENTE', que dice la
                // verdad, en vez de un UUID de 36 caracteres.
                'Código ${cita.identificadorParaPantalla}',
                style: const TextStyle(color: AppColors.textGray, fontSize: 11),
              ),
            ],
          ),
          if (cita.estado == EstadoCita.aceptada) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showQrPreview(context),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Ver Código QR'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.orangePrimary,
                  side: const BorderSide(color: AppColors.orangePrimary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showQrPreview(BuildContext context) {
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

/// Insignia de "todavia no subio a la nube".
///
/// Va aparte del badge de estado a proposito: una cita 'Pendiente' que SI esta
/// subida y una 'Pendiente' que aun no son el mismo texto con la misma
/// respuesta y distintas consecuencias. Sin esta linea el usuario no sabe que
/// hay algo esperando red.
class _BadgeEnCola extends StatelessWidget {
  const _BadgeEnCola({required this.error});

  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: (error ? AppColors.atrasadas : AppColors.blueAccent).withValues(
          alpha: 0.13,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            error ? Icons.cloud_off_outlined : Icons.cloud_upload_outlined,
            size: 12,
            color: error ? AppColors.atrasadas : AppColors.blueAccent,
          ),
          SizedBox(width: 5),
          Text(
            error ? 'Error de envío · se reintentará' : 'En cola de envío',
            style: TextStyle(
              color: error ? AppColors.atrasadas : AppColors.blueAccent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
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

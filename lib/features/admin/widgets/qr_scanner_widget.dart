import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/shared/theme/app_colors.dart';

/// Escáner de QR para que el admin escanee el código de la cita del cliente.
/// El QR contiene el código visible de la cita (ej: "CITA-0001").
/// Al escanear, busca la cita en la base local y muestra su información.
class QrScannerWidget extends StatefulWidget {
  const QrScannerWidget({
    required this.onCitaEncontrada,
    super.key,
  });

  /// Callback cuando se encuentra una cita válida.
  /// Recibe la cita y cierra el escáner.
  final void Function(Cita cita) onCitaEncontrada;

  @override
  State<QrScannerWidget> createState() => _QrScannerWidgetState();
}

class _QrScannerWidgetState extends State<QrScannerWidget> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _procesando = false;
  bool _permisoDenegado = false;
  StreamSubscription<BarcodeCapture>? _subscription;

  @override
  void initState() {
    super.initState();
    _iniciarEscaneo();
  }

  Future<void> _iniciarEscaneo() async {
    try {
      await _scannerController.start();
      _subscription = _scannerController.barcodes.listen(_procesarCodigo);
    } catch (e) {
      if (mounted) {
        setState(() => _permisoDenegado = true);
      }
    }
  }

  void _procesarCodigo(BarcodeCapture capture) {
    if (_procesando) return;
    
    final codigo = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (codigo == null || codigo.isEmpty) return;

    // El QR contiene el código visible de la cita (ej: "CITA-0001")
    // Buscamos la cita por su código visible
    _buscarCitaPorCodigo(codigo);
  }

  Future<void> _buscarCitaPorCodigo(String codigoVisible) async {
    if (_procesando) return;
    
    setState(() => _procesando = true);
    
    try {
      final repo = CitaRepository.instance;
      final citas = await repo.obtenerTodas();
      
      // Buscar cita por codigoVisible
      final cita = citas.cast<Cita?>().firstWhere(
        (c) => c?.codigoVisible == codigoVisible,
        orElse: () => null,
      );
      
      if (mounted) {
        if (cita != null) {
          widget.onCitaEncontrada(cita);
        } else {
          _mostrarError('Cita no encontrada: $codigoVisible');
          // Reanudar escaneo después de un breve delay
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) setState(() => _procesando = false);
        }
      }
    } catch (e) {
      if (mounted) {
        _mostrarError('Error al buscar la cita');
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _procesando = false);
      }
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: AppColors.atrasadas,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_permisoDenegado) {
      return _PermisoCamaraDenegado(
        onReintentar: () {
          setState(() {
            _permisoDenegado = false;
            _iniciarEscaneo();
          });
        },
      );
    }

    return Stack(
      children: [
        MobileScanner(controller: _scannerController),
        _OverlayEscaner(
          procesando: _procesando,
          onToggleTorch: () => _scannerController.toggleTorch(),
          onCerrar: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _OverlayEscaner extends StatelessWidget {
  const _OverlayEscaner({
    required this.procesando,
    required this.onToggleTorch,
    required this.onCerrar,
  });

  final bool procesando;
  final VoidCallback onToggleTorch;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Área de escaneo con marco
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.orangePrimary,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                // Esquinas decorativas
                ..._esquinas(),
                if (procesando)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
        
        // Instrucciones
        Positioned(
          bottom: 100,
          left: 24,
          right: 24,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Apunta la cámara al código QR de la cita',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _IconoAccion(
                    icono: Icons.flashlight_on_outlined,
                    etiqueta: 'Linterna',
                    onPressed: onToggleTorch,
                  ),
                  const SizedBox(width: 24),
                  _IconoAccion(
                    icono: Icons.close,
                    etiqueta: 'Cerrar',
                    onPressed: onCerrar,
                    color: AppColors.atrasadas,
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Línea de escaneo animada
        if (!procesando)
          const _LineaEscaneo(),
      ],
    );
  }

  List<Widget> _esquinas() {
    const size = 30.0;
    const stroke = 4.0;
    const color = AppColors.orangePrimary;
    
    return [
      // Esquina superior izquierda
      Positioned(
        top: 0,
        left: 0,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border(
              top: const BorderSide(color: color, width: stroke),
              left: const BorderSide(color: color, width: stroke),
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(13),
            ),
          ),
        ),
      ),
      // Esquina superior derecha
      Positioned(
        top: 0,
        right: 0,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border(
              top: const BorderSide(color: color, width: stroke),
              right: const BorderSide(color: color, width: stroke),
            ),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(13),
            ),
          ),
        ),
      ),
      // Esquina inferior izquierda
      Positioned(
        bottom: 0,
        left: 0,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border(
              bottom: const BorderSide(color: color, width: stroke),
              left: const BorderSide(color: color, width: stroke),
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(13),
            ),
          ),
        ),
      ),
      // Esquina inferior derecha
      Positioned(
        bottom: 0,
        right: 0,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border(
              bottom: const BorderSide(color: color, width: stroke),
              right: const BorderSide(color: color, width: stroke),
            ),
            borderRadius: const BorderRadius.only(
              bottomRight: Radius.circular(13),
            ),
          ),
        ),
      ),
    ];
  }
}

class _LineaEscaneo extends StatefulWidget {
  const _LineaEscaneo();

  @override
  State<_LineaEscaneo> createState() => _LineaEscaneoState();
}

class _LineaEscaneoState extends State<_LineaEscaneo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: _animation.value * 244,
                  left: 3,
                  right: 3,
                  child: Container(
                    height: 2,
                    color: AppColors.orangePrimary,
                    child: Container(
                      width: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.orangePrimary.withValues(alpha: 0),
                            AppColors.orangePrimary,
                            AppColors.orangePrimary.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IconoAccion extends StatelessWidget {
  const _IconoAccion({
    required this.icono,
    required this.etiqueta,
    required this.onPressed,
    this.color = Colors.white,
  });

  final IconData icono;
  final String etiqueta;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          onPressed: onPressed,
          icon: Icon(icono, color: color),
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.5),
            foregroundColor: color,
            fixedSize: const Size(56, 56),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          etiqueta,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PermisoCamaraDenegado extends StatelessWidget {
  const _PermisoCamaraDenegado({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography,
                size: 80,
                color: AppColors.textGray,
              ),
              const SizedBox(height: 20),
              const Text(
                'Permiso de cámara denegado',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.labelDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Para escanear códigos QR, AutoFix necesita '
                'acceso a la cámara. Habilítalo en la configuración '
                'de la app e intenta de nuevo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textGray,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onReintentar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.orangePrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pantalla completa para escanear QR de citas.
/// Úsala con Navigator.push para abrir el escáner.
class QrScannerScreen extends StatelessWidget {
  const QrScannerScreen({super.key});

  static Future<void> abrir(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const QrScannerScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: QrScannerWidget(
          onCitaEncontrada: (cita) {
            Navigator.of(context).pop(cita);
          },
        ),
      ),
    );
  }
}
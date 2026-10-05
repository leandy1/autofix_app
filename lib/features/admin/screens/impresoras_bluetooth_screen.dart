import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:autofix/services/impresora_bluetooth_service.dart';
import 'package:autofix/shared/models/recibo_impresion.dart';
import 'package:autofix/shared/theme/app_colors.dart';

class ImpresorasBluetoothScreen extends StatefulWidget {
  const ImpresorasBluetoothScreen({required this.recibo, super.key});

  final ReciboImpresion recibo;

  @override
  State<ImpresorasBluetoothScreen> createState() =>
      _ImpresorasBluetoothScreenState();
}

class _ImpresorasBluetoothScreenState extends State<ImpresorasBluetoothScreen> {
  static const _duracionBusqueda = Duration(seconds: 15);
  static final _impresoraNombre = RegExp(
    r'(printer|print|thermal|pos[-_ ]?\d|mtp|mpt|zjiang|rongta|xprinter|munbyn|hprt|58\s?mm|80\s?mm|receipt|label|rp[-_ ]?\d)',
    caseSensitive: false,
  );

  final FlutterClassicBluetooth _bluetooth = FlutterClassicBluetooth();
  final ImpresoraBluetoothService _impresoraService =
      ImpresoraBluetoothService();
  final TextEditingController _buscarController = TextEditingController();
  final Map<String, BtcDevice> _vinculados = {};
  final Map<String, BtcDevice> _cercanos = {};

  StreamSubscription<BtcDevice>? _busquedaSubscription;
  StreamSubscription<bool>? _estadoBusquedaSubscription;
  Timer? _temporizadorBusqueda;
  BtcDevice? _seleccionada;
  bool _bluetoothEncendido = false;
  bool _cargando = false;
  bool _buscando = false;
  String? _direccionImprimiendo;
  String? _error;

  @override
  void initState() {
    super.initState();
    _actualizarEstadoBluetooth();
  }

  @override
  void dispose() {
    _temporizadorBusqueda?.cancel();
    _busquedaSubscription?.cancel();
    _estadoBusquedaSubscription?.cancel();
    _buscarController.dispose();
    if (_buscando) {
      unawaited(_detenerBusqueda());
    }
    super.dispose();
  }

  Future<void> _actualizarEstadoBluetooth() async {
    try {
      final encendido = await _bluetooth.isEnabled();
      if (mounted) setState(() => _bluetoothEncendido = encendido);
    } on BtcException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _buscarDispositivos() async {
    if (_buscando) {
      await _detenerBusqueda();
      return;
    }
    if (_cargando) return;

    setState(() {
      _cargando = true;
      _error = null;
      _seleccionada = null;
    });

    try {
      var permisos = await _bluetooth.checkPermissions(
        permissions: {BtcPermission.scan, BtcPermission.connect},
      );
      if (permisos == BtcPermissionStatus.denied) {
        permisos = await _bluetooth.requestPermissions(
          permissions: {BtcPermission.scan, BtcPermission.connect},
        );
      }
      if (permisos == BtcPermissionStatus.permanentlyDenied) {
        throw const _BluetoothScreenException(
          'El permiso de Bluetooth está denegado. Habilítalo en los ajustes '
          'de la aplicación.',
          permisoPermanente: true,
        );
      }
      if (permisos == BtcPermissionStatus.denied) {
        throw const _BluetoothScreenException(
          'Se necesita permiso de Bluetooth para buscar dispositivos.',
        );
      }

      var encendido = await _bluetooth.isEnabled();
      if (!encendido) {
        encendido = await _bluetooth.enableBluetooth();
      }
      if (!encendido) {
        throw const _BluetoothScreenException(
          'Activa Bluetooth para buscar impresoras y dispositivos cercanos.',
        );
      }

      final vinculados = await _bluetooth.getPairedDevices();
      final suscripcion = _bluetooth.discoveryResults.listen(
        (dispositivo) {
          if (!mounted) return;
          setState(() {
            final anterior = _cercanos[dispositivo.address];
            _cercanos[dispositivo.address] = anterior == null
                ? dispositivo
                : anterior.mergedWith(dispositivo);
          });
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() => _error = 'Falló la búsqueda Bluetooth: $error');
        },
      );
      var descubrimientoIniciado = false;
      final suscripcionEstado = _bluetooth.discoveryState.listen((buscando) {
        if (buscando) {
          descubrimientoIniciado = true;
        } else if (descubrimientoIniciado && mounted) {
          _temporizadorBusqueda?.cancel();
          _temporizadorBusqueda = null;
          setState(() => _buscando = false);
          unawaited(_limpiarBusqueda());
        }
      });

      setState(() {
        _bluetoothEncendido = true;
        _vinculados
          ..clear()
          ..addEntries(
            vinculados.map((dispositivo) {
              return MapEntry(dispositivo.address, dispositivo);
            }),
          );
        _cercanos.clear();
        _busquedaSubscription = suscripcion;
        _estadoBusquedaSubscription = suscripcionEstado;
        _cargando = false;
        _buscando = true;
      });

      await _bluetooth.startDiscovery();
      if (!mounted || !_buscando) return;
      _temporizadorBusqueda = Timer(
        _duracionBusqueda,
        () => unawaited(_detenerBusqueda()),
      );
    } on _BluetoothScreenException catch (error) {
      await _limpiarBusqueda();
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _buscando = false;
        _error = error.message;
      });
      if (error.permisoPermanente) {
        await _mostrarAjustesPermisos();
      }
    } on BtcException catch (error) {
      await _limpiarBusqueda();
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _buscando = false;
        _error = error.message;
      });
    } on Exception catch (error) {
      await _limpiarBusqueda();
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _buscando = false;
        _error = 'No se pudo buscar dispositivos Bluetooth: $error';
      });
    }
  }

  Future<void> _detenerBusqueda() async {
    _temporizadorBusqueda?.cancel();
    _temporizadorBusqueda = null;
    try {
      await _bluetooth.stopDiscovery();
    } on BtcException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'No se pudo detener la búsqueda: $error');
      }
    } finally {
      await _limpiarBusqueda();
      if (mounted) {
        setState(() {
          _buscando = false;
          _cargando = false;
        });
      }
    }
  }

  Future<void> _limpiarBusqueda() async {
    final subscription = _busquedaSubscription;
    _busquedaSubscription = null;
    final stateSubscription = _estadoBusquedaSubscription;
    _estadoBusquedaSubscription = null;
    await subscription?.cancel();
    await stateSubscription?.cancel();
  }

  Future<void> _mostrarAjustesPermisos() async {
    if (!mounted) return;
    final abrirAjustes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permiso de Bluetooth'),
        content: const Text(
          'Para buscar dispositivos cercanos, habilita los permisos de '
          'Bluetooth desde los ajustes de la aplicación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abrir ajustes'),
          ),
        ],
      ),
    );
    if (abrirAjustes == true) {
      try {
        final abierto = await _bluetooth.openAppSettings();
        if (!abierto && mounted) {
          setState(() => _error = 'No se pudieron abrir los ajustes.');
        }
      } on BtcException catch (error) {
        if (mounted) setState(() => _error = error.message);
      }
    }
  }

  List<BtcDevice> get _dispositivosVisibles {
    final dispositivos = <String, BtcDevice>{..._vinculados};
    for (final dispositivo in _cercanos.values) {
      final anterior = dispositivos[dispositivo.address];
      dispositivos[dispositivo.address] = anterior == null
          ? dispositivo
          : anterior.mergedWith(dispositivo);
    }

    final consulta = _buscarController.text.trim().toLowerCase();
    final resultado = dispositivos.values.where((dispositivo) {
      final coincide =
          consulta.isEmpty ||
          dispositivo.displayName.toLowerCase().contains(consulta) ||
          dispositivo.address.toLowerCase().contains(consulta);
      return coincide;
    }).toList();
    resultado.sort((a, b) {
      final impresoraA = _esImpresora(a) ? 0 : 1;
      final impresoraB = _esImpresora(b) ? 0 : 1;
      if (impresoraA != impresoraB) return impresoraA.compareTo(impresoraB);
      final vinculadoA = _vinculados.containsKey(a.address) ? 0 : 1;
      final vinculadoB = _vinculados.containsKey(b.address) ? 0 : 1;
      if (vinculadoA != vinculadoB) {
        return vinculadoA.compareTo(vinculadoB);
      }
      return (b.rssi ?? -1000).compareTo(a.rssi ?? -1000);
    });
    return resultado;
  }

  bool _esImpresora(BtcDevice dispositivo) {
    return dispositivo.uuids.any((uuid) => uuid.toUpperCase() == BtcUuid.spp) ||
        _impresoraNombre.hasMatch(dispositivo.displayName);
  }

  Future<void> _seleccionarDispositivo(BtcDevice dispositivo) async {
    if (_direccionImprimiendo != null) return;
    setState(() {
      _seleccionada = dispositivo;
      _direccionImprimiendo = dispositivo.address;
      _error = null;
    });

    try {
      if (_buscando) await _detenerBusqueda();
      await _impresoraService.imprimirRecibo(
        bluetooth: _bluetooth,
        dispositivo: dispositivo,
        recibo: widget.recibo,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recibo enviado a ${dispositivo.displayName}.')),
      );
    } on BtcException catch (error) {
      if (!mounted) return;
      final detalle = error is BtcConnectionException
          ? '${error.cause.description} Detalle: ${error.message}'
          : error.message;
      setState(() => _error = detalle);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo imprimir el recibo: $error');
    } finally {
      if (mounted) setState(() => _direccionImprimiendo = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dispositivos = _dispositivosVisibles;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.headerNavy,
        foregroundColor: Colors.white,
        title: const Text('Impresoras Bluetooth'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Seleccionar impresora',
                    style: TextStyle(
                      color: AppColors.labelDark,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _bluetoothEncendido
                        ? 'Busca dispositivos Bluetooth Classic. Toca una '
                              'impresora para conectarte e imprimir el recibo.'
                        : 'Activa Bluetooth para empezar a buscar.',
                    style: const TextStyle(color: AppColors.textGray),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _buscarController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Filtrar por nombre o dirección',
                      prefixIcon: Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _cargando ? null : _buscarDispositivos,
                      icon: _cargando
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _buscando
                                  ? Icons.stop_circle_outlined
                                  : Icons.bluetooth_searching,
                            ),
                      label: Text(_buscando ? 'Detener búsqueda' : 'Buscar'),
                    ),
                  ),
                  if (_buscando) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 4),
                    const Text(
                      'Buscando dispositivos cercanos…',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textGray, fontSize: 12),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppColors.inputBorder),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: dispositivos.isEmpty
                          ? _estadoVacio
                          : ListView.separated(
                              padding: const EdgeInsets.all(8),
                              itemCount: dispositivos.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final dispositivo = dispositivos[index];
                                return _filaDispositivo(dispositivo);
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget get _estadoVacio {
    final titulo = _buscando
        ? 'Todavía no se encontraron dispositivos'
        : _error == null
        ? 'Los dispositivos encontrados aparecerán aquí'
        : 'No se pudo iniciar la búsqueda';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _error == null
                  ? Icons.bluetooth_searching
                  : Icons.bluetooth_disabled,
              size: 42,
              color: AppColors.placeholderGray,
            ),
            const SizedBox(height: 10),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textGray),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaDispositivo(BtcDevice dispositivo) {
    final impresora = _esImpresora(dispositivo);
    final vinculado =
        _vinculados.containsKey(dispositivo.address) ||
        dispositivo.bondState == BtcBondState.bonded;
    final seleccionado = _seleccionada?.address == dispositivo.address;
    return ListTile(
      selected: seleccionado,
      enabled: _direccionImprimiendo == null,
      selectedTileColor: AppColors.headerNavy.withValues(alpha: 0.08),
      leading: Icon(
        impresora ? Icons.print_outlined : Icons.bluetooth,
        color: impresora ? AppColors.headerNavy : AppColors.textGray,
      ),
      title: Text(
        dispositivo.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          dispositivo.address,
          if (vinculado) 'Vinculado',
          if (dispositivo.rssi != null) '${dispositivo.rssi} dBm',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _direccionImprimiendo == dispositivo.address
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : impresora
          ? const Chip(
              label: Text('Posible impresora'),
              visualDensity: VisualDensity.compact,
            )
          : vinculado
          ? const Icon(Icons.check_circle_outline)
          : null,
      onTap: () => _seleccionarDispositivo(dispositivo),
    );
  }
}

class _BluetoothScreenException implements Exception {
  const _BluetoothScreenException(
    this.message, {
    this.permisoPermanente = false,
  });

  final String message;
  final bool permisoPermanente;
}

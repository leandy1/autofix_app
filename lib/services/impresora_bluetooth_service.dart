import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import '../models/recibo_impresion.dart';

class ImpresoraBluetoothService {
  const ImpresoraBluetoothService();

  static const _tiempoEsperaVinculacion = Duration(seconds: 30);

  Future<void> imprimirRecibo({
    required FlutterClassicBluetooth bluetooth,
    required BtcDevice dispositivo,
    required ReciboImpresion recibo,
  }) async {
    if (dispositivo.bondState != BtcBondState.bonded) {
      final vinculacionCompleta = bluetooth
          .bondState(dispositivo.address)
          .firstWhere((estado) => estado == BtcBondState.bonded)
          .timeout(_tiempoEsperaVinculacion);
      await bluetooth.bondDevice(dispositivo.address);
      try {
        await vinculacionCompleta;
      } on TimeoutException {
        throw const BtcConnectionException(
          'No se completó la vinculación. Acepta la solicitud de enlace '
          'en Android y vuelve a seleccionar el dispositivo.',
          cause: BtcConnectFailure.notPaired,
        );
      }
    }

    final conexion = await bluetooth.connect(
      address: dispositivo.address,
      uuid: BtcUuid.spp,
      timeout: const Duration(seconds: 12),
    );
    try {
      await conexion.output.add(_crearTicket(recibo));
      await conexion.finish();
    } catch (error) {
      try {
        await conexion.close();
      } catch (errorCierre) {
        throw BtcException(
          'Falló la impresión ($error) y no se pudo cerrar la conexión '
          'Bluetooth ($errorCierre).',
        );
      }
      rethrow;
    } finally {
      conexion.dispose();
    }
  }

  Uint8List _crearTicket(ReciboImpresion recibo) {
    final bytes = <int>[];
    void comando(List<int> valor) => bytes.addAll(valor);
    void texto(String valor) {
      bytes
        ..addAll(ascii.encode(_normalizar(valor)))
        ..add(0x0A);
    }

    comando([0x1B, 0x40]);
    comando([0x1B, 0x61, 0x01]);
    comando([0x1B, 0x45, 0x01]);
    texto('AUTOFIX');
    comando([0x1B, 0x45, 0x00]);
    texto('RECIBO DE SERVICIO');
    if (recibo.esDemostracion) {
      texto('*** VISTA DE DEMOSTRACION ***');
    }
    comando([0x1B, 0x61, 0x00]);
    texto('-' * 32);
    _campo(bytes, 'Recibo', recibo.numero);
    _campo(bytes, 'Fecha', recibo.fecha);
    texto('-' * 32);
    comando([0x1B, 0x45, 0x01]);
    texto('CLIENTE');
    comando([0x1B, 0x45, 0x00]);
    _campo(bytes, 'Nombre', recibo.cliente);
    _campo(bytes, 'Telefono', recibo.telefono);
    texto('');
    comando([0x1B, 0x45, 0x01]);
    texto('VEHICULO');
    comando([0x1B, 0x45, 0x00]);
    _campo(bytes, 'Modelo', recibo.vehiculo);
    _campo(bytes, 'Placa', recibo.placa);
    texto('');
    comando([0x1B, 0x45, 0x01]);
    texto('SERVICIOS');
    comando([0x1B, 0x45, 0x00]);
    if (recibo.servicios.isEmpty) {
      texto('Sin servicios registrados.');
    } else {
      for (final servicio in recibo.servicios) {
        _linea(bytes, '- $servicio');
      }
    }
    texto('');
    texto('Importes pendientes de confirmar.');
    texto('-' * 32);
    comando([0x1B, 0x61, 0x01]);
    texto('Gracias por confiar en AutoFix.');
    comando([0x1B, 0x64, 0x04]);

    return Uint8List.fromList(bytes);
  }

  void _campo(List<int> bytes, String etiqueta, String valor) {
    _linea(bytes, '$etiqueta: $valor');
  }

  void _linea(List<int> bytes, String valor) {
    const ancho = 32;
    final palabras = _normalizar(valor).split(RegExp(r'\s+'));
    var linea = '';
    for (final palabra in palabras) {
      if (linea.isNotEmpty && '$linea $palabra'.length > ancho) {
        bytes
          ..addAll(ascii.encode(linea))
          ..add(0x0A);
        linea = palabra;
      } else {
        linea = linea.isEmpty ? palabra : '$linea $palabra';
      }
    }
    if (linea.isNotEmpty) {
      bytes
        ..addAll(ascii.encode(linea))
        ..add(0x0A);
    }
  }

  String _normalizar(String texto) {
    const reemplazos = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'Ü': 'U',
      'Ñ': 'N',
      '¿': '',
      '¡': '',
      '—': '-',
      '–': '-',
      '·': '-',
    };
    return texto
        .replaceAllMapped(
          RegExp('[${reemplazos.keys.join()}]'),
          (match) => reemplazos[match[0]] ?? '',
        )
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '');
  }
}

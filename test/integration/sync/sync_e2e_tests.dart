import 'dart:async';

import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/citas/models/codigo_de_cita.dart';
import 'package:autofix/features/sync/sync_service.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockConnectivityPlatform extends ConnectivityPlatform {
  MockConnectivityPlatform(this._controller);
  final StreamController<List<ConnectivityResult>> _controller;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      _controller.hasListener
      ? [ConnectivityResult.wifi]
      : [ConnectivityResult.none];

  void emit(List<ConnectivityResult> results) {
    if (!_controller.isClosed) {
      _controller.add(results);
    }
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  group('SyncService - Integración E2E', () {
    late DatabaseHelper dbHelper;
    late CitaRepository citaRepo;
    late MockConnectivityPlatform mockConnectivity;
    late StreamController<List<ConnectivityResult>> connectivityController;

    Future<void> prepararDependencias() async {
      connectivityController =
          StreamController<List<ConnectivityResult>>.broadcast();
      mockConnectivity = MockConnectivityPlatform(connectivityController);
      ConnectivityPlatform.instance = mockConnectivity;

      final testDbName = 'test_sync_.db';
      DatabaseHelper.nombreBaseParaPruebas = testDbName;
      dbHelper = DatabaseHelper.instance;
      await dbHelper.base;

      citaRepo = CitaRepository.instance;
    }

    Future<void> librerarDependencias() async {
      try {
        await SyncService.instance.stop();
      } catch (_) {}
      if (!connectivityController.isClosed) {
        await connectivityController.close();
      }
      mockConnectivity.dispose();
      DatabaseHelper.nombreBaseParaPruebas = null;
    }

    test(
      'Escenario 1: Creación offline - pending y codigo PENDIENTE',
      () async {
        await prepararDependencias();
        SesionAdmin.instance.cerrar();

        final cita = Cita(
          cliente: 'Juan Pérez',
          telefono: '8095551234',
          vehiculo: 'Toyota Corolla 2020',
          marca: 'Toyota',
          modelo: 'Corolla',
          anio: 2020,
          placa: 'A123456',
          servicios: ['Cambio de aceite'],
          descripcion: 'Mantenimiento básico',
          fechaCita: DateTime.now().add(const Duration(hours: 24)).toUtc(),
          estado: EstadoCita.pendiente,
          tallerId: 'taller-1',
        );

        final id = await citaRepo.crear(cita);
        final creada = await citaRepo.obtenerPorId(id);

        expect(creada, isNotNull);
        expect(creada!.syncStatus, equals('pending'));
        expect(creada.codigoVisible, equals(codigoCitaTemporal));
        expect(creada.tieneCodigoDefinitivo, isFalse);
        expect(creada.tallerId, equals('taller-1'));

        await librerarDependencias();
      },
    );
    test(
      'Escenario 3: Multitenencia - filtra estrictamente por taller_id',
      () async {
        await prepararDependencias();
        SesionAdmin.instance.cerrar();

        final repo = CitaRepository.instance;
        final c1 = Cita(
          cliente: 'Cliente T1',
          telefono: '8091111111',
          vehiculo: 'Vehiculo1',
          marca: 'Marca',
          modelo: 'Mod',
          anio: 2020,
          placa: 'T1000',
          servicios: ['Serv1'],
          descripcion: 'desc',
          fechaCita: DateTime.now().toUtc(),
          estado: EstadoCita.pendiente,
          tallerId: 'taller-1',
        );
        final c2 = Cita(
          cliente: 'Cliente T2',
          telefono: '8092222222',
          vehiculo: 'Vehiculo2',
          marca: 'Marca',
          modelo: 'Mod',
          anio: 2020,
          placa: 'T2000',
          servicios: ['Serv1'],
          descripcion: 'desc',
          fechaCita: DateTime.now().toUtc(),
          estado: EstadoCita.pendiente,
          tallerId: 'taller-2',
        );

        await repo.crear(c1);
        await repo.crear(c2);

        final porT1 = await repo.obtenerPorTaller('taller-1');
        expect(
          porT1.where((e) => e.tallerId == 'taller-1').length,
          equals(porT1.length),
        );

        final porT2 = await repo.obtenerPorTaller('taller-2');
        expect(
          porT2.where((e) => e.tallerId == 'taller-2').length,
          equals(porT2.length),
        );

        expect(porT1.any((e) => e.tallerId == 'taller-2'), isFalse);
        expect(porT2.any((e) => e.tallerId == 'taller-1'), isFalse);

        await librerarDependencias();
      },
    );
  });
}

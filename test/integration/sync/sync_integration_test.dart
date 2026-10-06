import 'dart:async';

import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/citas/models/codigo_de_cita.dart';
import 'package:autofix/features/sync/sync_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';

class MockConnectivityPlatform extends ConnectivityPlatform {
  MockConnectivityPlatform(this._controller);

  final StreamController<List<ConnectivityResult>> _controller;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      _controller.hasListener ? [ConnectivityResult.wifi] : [ConnectivityResult.none];

  void emit(List<ConnectivityResult> results) {
    if (!_controller.isClosed) {
      _controller.add(results);
    }
  }

  void dispose() {
    _controller.close();
  }
}
    late CitaRepository citaRepo;
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late MockConnectivityPlatform mockConnectivity;
    late StreamController<List<ConnectivityResult>> connectivityController;
    SyncService? syncService;

    Future<void> _setupDependencies({
      String? tallerId,
      String userUid = 'test-uid',
    }) async {
      connectivityController = StreamController<List<ConnectivityResult>>.broadcast();
      mockConnectivity = MockConnectivityPlatform(connectivityController);
      ConnectivityPlatform.instance = mockConnectivity;

      final testDbName = 'test_sync_.db';
      DatabaseHelper.nombreBaseParaPruebas = testDbName;
      dbHelper = DatabaseHelper.instance;
      await dbHelper.base;

      citaRepo = CitaRepository.instance;
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userUid));
    }

    Future<void> _tearDown() async {
      try {
        await syncService?.stop();
      } catch (_) {}
      if (!connectivityController.isClosed) {
        await connectivityController.close();
      }
      mockConnectivity.dispose();
      DatabaseHelper.nombreBaseParaPruebas = null;
    }

    test('Escenario 1: Crear cita offline - debe quedar pending con PENDIENTE', () async {
      await _setupDependencies(tallerId: 'taller-1');
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

      await _tearDown();
    });
    test('Escenario 2: Reconexión y transacción atómica - asigna CITA-0001', () async {
      await _setupDependencies(tallerId: 'taller-1');
      SesionAdmin.instance.cerrar();

      final cita = Cita(
        cliente: 'María García',
        telefono: '8095555678',
        vehiculo: 'Honda Civic 2019',
        marca: 'Honda',
        modelo: 'Civic',
        anio: 2019,
        placa: 'B654321',
        servicios: ['Cambio de frenos'],
        descripcion: 'Revisión de frenos',
        fechaCita: DateTime.now().add(const Duration(hours: 48)).toUtc(),
        estado: EstadoCita.pendiente,
        tallerId: 'taller-1',
      );

      final id = await citaRepo.crear(cita);
      final creada = await citaRepo.obtenerPorId(id);

      expect(creada, isNotNull);
      expect(creada!.syncStatus, equals('pending'));
      expect(creada.codigoVisible, equals(codigoCitaTemporal));

      
      mockConnectivity.emit([ConnectivityResult.wifi]);
      await Future.delayed(const Duration(milliseconds: 500));

      final sincronizada = await citaRepo.obtenerPorId(id);
      expect(sincronizada, isNotNull);
      expect(sincronizada!.syncStatus, equals('synced'));
      expect(sincronizada.tieneCodigoDefinitivo, isTrue);
      expect(sincronizada.codigoVisible, startsWith('CITA-'));
      expect(sincronizada.codigoVisible.length, equals('CITA-0001'.length));

      await _tearDown();
    });
    test('Escenario 2: Reconexión y transacción atómica - asigna CITA-0001', () async {
      await _setupDependencies(tallerId: 'taller-1');
      SesionAdmin.instance.cerrar();

      final cita = Cita(
        cliente: 'María García',
        telefono: '8095555678',
        vehiculo: 'Honda Civic 2019',
        marca: 'Honda',
        modelo: 'Civic',
        anio: 2019,
        placa: 'B654321',
        servicios: ['Cambio de frenos'],
        descripcion: 'Revisión de frenos',
        fechaCita: DateTime.now().add(const Duration(hours: 48)).toUtc(),
        estado: EstadoCita.pendiente,
        tallerId: 'taller-1',
      );

      final id = await citaRepo.crear(cita);
      final creada = await citaRepo.obtenerPorId(id);

      expect(creada, isNotNull);
      expect(creada!.syncStatus, equals('pending'));
      expect(creada.codigoVisible, equals(codigoCitaTemporal));

      
      await SyncService.instance.start();
      mockConnectivity.emit([ConnectivityResult.wifi]);
      await Future.delayed(const Duration(milliseconds: 800));

      final sincronizada = await citaRepo.obtenerPorId(id);
      expect(sincronizada, isNotNull);
      expect(sincronizada!.syncStatus, equals('synced'));
      expect(sincronizada.tieneCodigoDefinitivo, isTrue);
      expect(sincronizada.codigoVisible, startsWith('CITA-'));

      await _tearDown();
    });
  });
}

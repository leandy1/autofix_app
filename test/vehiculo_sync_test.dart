import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/cliente/data/vehiculo_repository.dart';
import 'package:autofix/features/cliente/models/vehiculo.dart';
import 'package:autofix/features/sync/sync_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const correo = 'cliente@ejemplo.com';
  const uid = 'uid-cliente';
  final sync = SyncService.instance;
  final repo = VehiculoRepository.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_vehiculo_sync_test.db';
  });

  setUp(() async {
    await sync.stop();
    await DatabaseHelper.resetParaPruebas();
    SharedPreferences.setMockInitialValues({});
    await SesionAdmin.instance.cerrar();
    await SesionCliente.instance.olvidarTodo();
    await SesionCliente.instance.iniciar(
      nombre: 'Cliente',
      correo: correo,
      persistir: false,
    );
    sync.usarFirestoreParaPruebas(FakeFirebaseFirestore());
    sync.usarAuthUidParaPruebas(uid);
  });

  tearDownAll(() async {
    await sync.stop();
    sync.usarFirestoreParaPruebas(null);
    sync.usarAuthUidParaPruebas(null);
    await SesionCliente.instance.olvidarTodo();
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  test('sube vehículos pendientes y los marca synced', () async {
    final firestore = FakeFirebaseFirestore();
    sync.usarFirestoreParaPruebas(firestore);
    final id = await repo.crear(
      const Vehiculo(
        clienteId: correo,
        marca: 'Toyota',
        modelo: 'Corolla',
        anio: 2022,
      ),
    );

    await sync.start();

    final documento = await firestore.collection('vehiculos').doc(id).get();
    expect(documento.exists, isTrue);
    expect(documento.data()?['ownerUid'], uid);
    expect(documento.data()?['correo_cliente'], correo);
    expect(documento.data()?['sync_status'], 'synced');
    expect((await repo.obtenerPorId(id))?.syncStatus, 'synced');
  });

  test(
    'descarga únicamente el vehículo vinculado a la cuenta cliente',
    () async {
      final firestore = FakeFirebaseFirestore();
      sync.usarFirestoreParaPruebas(firestore);
      await firestore.collection('vehiculos').doc('auto-remoto').set({
        'id': 'auto-remoto',
        'cliente_id': correo,
        'correo_cliente': correo,
        'ownerUid': uid,
        'marca': 'Honda',
        'modelo': 'Civic',
        'anio': 2021,
        'placa': 'A123456',
        'activo': true,
        'creado_en': '2025-01-01T00:00:00.000Z',
        'actualizado_en': '2025-01-02T00:00:00.000Z',
        'eliminado_en': null,
        'sync_status': 'synced',
      });

      await sync.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final vehiculo = await repo.obtenerPorId('auto-remoto');
      expect(vehiculo?.clienteId, correo);
      expect(vehiculo?.marca, 'Honda');
      expect(vehiculo?.syncStatus, 'synced');
    },
  );
}

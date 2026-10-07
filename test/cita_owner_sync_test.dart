import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/sync/sync_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_owner_sync_test.db';
  });

  tearDownAll(() async {
    await SyncService.instance.stop();
    SyncService.instance.usarFirestoreParaPruebas(null);
    SyncService.instance.usarAuthUidParaPruebas(null);
    await SesionAdmin.instance.cerrar();
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    await DatabaseHelper.resetParaPruebas();
    SharedPreferences.setMockInitialValues({});
    SyncService.instance.usarFirestoreParaPruebas(FakeFirebaseFirestore());
    SyncService.instance.usarAuthUidParaPruebas('uid-admin');
    SyncService.instance.usarHookAntesDePushParaPruebas(null);
    await SesionAdmin.instance.iniciar(
      tallerId: 'taller-admin',
      adminUid: 'uid-admin',
      persistir: false,
    );
  });

  test(
    'una cita creada por Admin conserva correo como vínculo del cliente',
    () async {
      const correo = 'cliente@ejemplo.com';
      final firestore = FakeFirebaseFirestore();
      SyncService.instance.usarFirestoreParaPruebas(firestore);

      final id = await CitaRepository.instance.crear(
        Cita(
          cliente: 'Cliente Registrado',
          correoCliente: correo,
          telefono: '8095551234',
          vehiculo: 'Honda Civic 2021',
          marca: 'Honda',
          modelo: 'Civic',
          anio: 2021,
          fechaCita: DateTime.utc(2026, 11, 3, 14),
          tallerId: 'taller-admin',
        ),
      );

      await SyncService.instance.pushPending();

      final documento = await firestore.collection('citas').doc(id).get();
      expect(documento.exists, isTrue);
      expect(documento.data()?['ownerUid'], 'uid-admin');
      expect(documento.data()?['correo_cliente'], correo);
      expect(documento.data()?['estado'], EstadoCita.pendiente.name);
      expect(
        (await CitaRepository.instance.obtenerPorId(id))?.syncStatus,
        'synced',
      );
    },
  );

  test(
    'un documento legacy fallido no bloquea la siguiente cita del lote',
    () async {
      final firestore = FakeFirebaseFirestore();
      SyncService.instance.usarFirestoreParaPruebas(firestore);

      final idFallido = await CitaRepository.instance.crear(
        Cita(
          cliente: 'Cliente antiguo',
          vehiculo: 'Vehículo antiguo',
          fechaCita: DateTime.utc(2026, 11, 3, 14),
        ),
      );
      SyncService.instance.usarHookAntesDePushParaPruebas((cita) async {
        if (cita.id == idFallido) {
          throw StateError('fallo simulado para aislar una fila del lote');
        }
      });
      final idLegacyNormalizable = await CitaRepository.instance.crear(
        Cita(
          codigoVisible: 'CITA-7777',
          cliente: '',
          vehiculo: '',
          fechaCita: DateTime.utc(2026, 11, 4, 14),
        ),
      );

      await SyncService.instance.pushPending();

      expect(
        (await CitaRepository.instance.obtenerPorId(idFallido))?.syncStatus,
        'error',
      );
      expect(
        (await CitaRepository.instance.obtenerPorId(idLegacyNormalizable))
            ?.syncStatus,
        'synced',
      );
      final documento = await firestore
          .collection('citas')
          .doc(idLegacyNormalizable)
          .get();
      expect(documento.data()?['cliente'], 'Cliente sin nombre');
      expect(documento.data()?['vehiculo'], 'Vehículo no especificado');
      expect(documento.data()?['correo_cliente'], '');
    },
  );
}

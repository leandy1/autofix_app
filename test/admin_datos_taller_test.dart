import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/features/admin/presentation/dashboard_admin_controller.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/citas/presentation/citas_controller.dart';
import 'package:autofix/features/talleres/data/taller_repository.dart';
import 'package:autofix/features/talleres/models/taller.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_admin_datos_taller_test.db';
  });

  tearDownAll(() async {
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    await DatabaseHelper.resetParaPruebas();
    SesionAdmin.instance.cerrar();
  });

  tearDown(() {
    SesionAdmin.instance.cerrar();
  });

  final repoCitas = CitaRepository.instance;
  final repoTalleres = TallerRepository.instance;

  final hoy = DateTime(2026, 10, 5);
  final ahora = DateTime(2026, 10, 5, 14, 0);

  test('Los dashboards y citas de distintos administradores son totalmente independientes', () async {
    // 1. Creamos 2 talleres distintos
    final idTallerNorte = await repoTalleres.crear(
      const Taller(
        nombre: 'AutoFix Norte',
        direccion: 'Av. Juan Pablo Duarte 10',
        telefono: '809-555-1111',
        latitud: 19.45,
        longitud: -70.70,
      ),
    );

    final idTallerSur = await repoTalleres.crear(
      const Taller(
        nombre: 'AutoFix Sur',
        direccion: 'Av. Independencia 500',
        telefono: '809-555-2222',
        latitud: 18.44,
        longitud: -69.95,
      ),
    );

    // 2. Sembrar citas para Taller Norte
    // - 2 completadas (RD$ 2,500 y RD$ 3,500 = RD$ 6,000)
    // - 1 en proceso
    // - 1 pendiente
    await repoCitas.crear(
      Cita(
        cliente: 'Cliente Norte 1',
        vehiculo: 'Honda Civic',
        fechaCita: hoy,
        estado: EstadoCita.completado,
        total: 2500,
        tallerId: idTallerNorte,
      ),
    );
    await repoCitas.crear(
      Cita(
        cliente: 'Cliente Norte 2',
        vehiculo: 'Toyota Corolla',
        fechaCita: hoy,
        estado: EstadoCita.completado,
        total: 3500,
        tallerId: idTallerNorte,
      ),
    );
    await repoCitas.crear(
      Cita(
        cliente: 'Cliente Norte 3',
        vehiculo: 'Ford Escape',
        fechaCita: hoy,
        estado: EstadoCita.enProceso,
        total: 1200,
        tallerId: idTallerNorte,
      ),
    );
    await repoCitas.crear(
      Cita(
        cliente: 'Cliente Norte 4',
        vehiculo: 'Hyundai Tucson',
        fechaCita: hoy,
        estado: EstadoCita.pendiente,
        total: 800,
        tallerId: idTallerNorte,
      ),
    );

    // 3. Sembrar citas para Taller Sur
    // - 1 completada (RD$ 10,000)
    // - 2 en proceso
    await repoCitas.crear(
      Cita(
        cliente: 'Cliente Sur 1',
        vehiculo: 'Kia Sportage',
        fechaCita: hoy,
        estado: EstadoCita.completado,
        total: 10000,
        tallerId: idTallerSur,
      ),
    );
    await repoCitas.crear(
      Cita(
        cliente: 'Cliente Sur 2',
        vehiculo: 'Mazda CX-5',
        fechaCita: hoy,
        estado: EstadoCita.enProceso,
        total: 4500,
        tallerId: idTallerSur,
      ),
    );
    await repoCitas.crear(
      Cita(
        cliente: 'Cliente Sur 3',
        vehiculo: 'Nissan Rogue',
        fechaCita: hoy,
        estado: EstadoCita.enProceso,
        total: 3000,
        tallerId: idTallerSur,
      ),
    );

    // 4. Probar Dashboard para Admin del Taller Norte
    SesionAdmin.instance.iniciar(
      tallerId: idTallerNorte,
      adminUid: 'admin-norte-uid',
      tallerNombre: 'AutoFix Norte',
      adminEmail: 'admin.norte@autofix.com',
    );

    final ctrlNorte = DashboardAdminController();
    await ctrlNorte.cargar();

    expect(ctrlNorte.totalCitas, 4);
    expect(ctrlNorte.completadas, 2);
    expect(ctrlNorte.ingresos, 6000);
    expect(ctrlNorte.vehiculosEnTaller, 1);
    expect(ctrlNorte.ordenesAbiertas, 2); // 1 en proceso + 1 pendiente
    expect(ctrlNorte.citasDia.length, 4);
    expect(
      ctrlNorte.citasDia.every((c) => c.tallerId == idTallerNorte),
      isTrue,
    );

    // Probar CitasController para Admin del Taller Norte
    final citasCtrlNorte = CitasController();
    await citasCtrlNorte.cargar();
    expect(citasCtrlNorte.citas.length, 4);
    expect(
      citasCtrlNorte.citas.every((c) => c.tallerId == idTallerNorte),
      isTrue,
    );

    // Guardar una nueva cita con admin Norte -> se le asigna idTallerNorte automáticamente
    await citasCtrlNorte.guardar(
      Cita(
        cliente: 'Nuevo Cliente Norte',
        vehiculo: 'Suzuki Jimny',
        fechaCita: hoy,
      ),
    );
    expect(citasCtrlNorte.citas.length, 5);
    expect(citasCtrlNorte.citas.first.tallerId, idTallerNorte);

    // 5. Cambiar a sesión de Admin del Taller Sur
    SesionAdmin.instance.cerrar();
    SesionAdmin.instance.iniciar(
      tallerId: idTallerSur,
      adminUid: 'admin-sur-uid',
      tallerNombre: 'AutoFix Sur',
      adminEmail: 'admin.sur@autofix.com',
    );

    final ctrlSur = DashboardAdminController();
    await ctrlSur.cargar();

    expect(ctrlSur.totalCitas, 3);
    expect(ctrlSur.completadas, 1);
    expect(ctrlSur.ingresos, 10000);
    expect(ctrlSur.vehiculosEnTaller, 2);
    expect(ctrlSur.ordenesAbiertas, 2); // 2 en proceso
    expect(ctrlSur.citasDia.length, 3);
    expect(
      ctrlSur.citasDia.every((c) => c.tallerId == idTallerSur),
      isTrue,
    );

    // Probar CitasController para Admin del Taller Sur
    final citasCtrlSur = CitasController();
    await citasCtrlSur.cargar();
    expect(citasCtrlSur.citas.length, 3);
    expect(
      citasCtrlSur.citas.every((c) => c.tallerId == idTallerSur),
      isTrue,
    );
  });
}


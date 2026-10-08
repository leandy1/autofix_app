import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/database/semilla_inicial.dart';
import 'package:autofix/features/configuracion/data/grupo_servicio_repository.dart';
import 'package:autofix/features/configuracion/data/marca_repository.dart';
import 'package:autofix/features/configuracion/data/tecnico_repository.dart';
import 'package:autofix/features/configuracion/data/tipo_servicio_repository.dart';
import 'package:autofix/features/configuracion/models/grupo_servicio.dart';
import 'package:autofix/features/configuracion/models/marca.dart';
import 'package:autofix/features/configuracion/models/tecnico.dart';
import 'package:autofix/features/configuracion/models/tipo_servicio.dart';
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
    DatabaseHelper.nombreBaseParaPruebas = 'autofix_catalogo_sync_test.db';
  });

  tearDownAll(() async {
    await SyncService.instance.stop();
    SyncService.instance.usarFirestoreParaPruebas(null);
    await SesionAdmin.instance.cerrar();
    await SesionCliente.instance.olvidarTodo();
    await DatabaseHelper.resetParaPruebas();
    DatabaseHelper.nombreBaseParaPruebas = null;
  });

  setUp(() async {
    await SyncService.instance.stop();
    await DatabaseHelper.resetParaPruebas();
    SharedPreferences.setMockInitialValues({});
    await SesionAdmin.instance.cerrar();
    await SesionCliente.instance.olvidarTodo();
    SyncService.instance.usarFirestoreParaPruebas(FakeFirebaseFirestore());
  });

  test(
    'sube los cuatro catálogos y publica el tombstone como update',
    () async {
      const tallerId = 'taller-sync';
      final firestore = FakeFirebaseFirestore();
      SyncService.instance.usarFirestoreParaPruebas(firestore);
      await SesionAdmin.instance.iniciar(
        tallerId: tallerId,
        adminUid: 'admin-sync',
        persistir: false,
      );

      final idTecnico = await TecnicoRepository.instance.crear(
        const Tecnico(nombre: 'Técnico sincronizado', tallerId: tallerId),
      );
      final idServicio = await TipoServicioRepository.instance.crear(
        const TipoServicio(
          nombre: 'Servicio sincronizado',
          precio: 1450,
          tallerId: tallerId,
        ),
      );
      final idMarca = await MarcaRepository.instance.crear(
        const Marca(nombre: 'Marca sincronizada', tallerId: tallerId),
      );
      final idGrupo = await GrupoServicioRepository.instance.crear(
        const GrupoServicio(nombre: 'Grupo sincronizado', tallerId: tallerId),
      );
      await TecnicoRepository.instance.eliminar(idTecnico);

      const idTecnicoBorradoEnOtroDispositivo = 'tecnico-remoto-borrado';
      await TecnicoRepository.instance.crear(
        const Tecnico(
          id: idTecnicoBorradoEnOtroDispositivo,
          nombre: 'No resucitar',
          tallerId: tallerId,
        ),
      );
      await firestore
          .collection('tecnicos')
          .doc(idTecnicoBorradoEnOtroDispositivo)
          .set(
            _catalogoRemoto(
              id: idTecnicoBorradoEnOtroDispositivo,
              tallerId: tallerId,
              nombre: 'No resucitar',
            )..['eliminado_en'] = '2026-01-03T00:00:00.000Z',
          );

      await SyncService.instance.pushPending();

      final tecnico = await firestore
          .collection('tecnicos')
          .doc(idTecnico)
          .get();
      final servicio = await firestore
          .collection('servicios')
          .doc(idServicio)
          .get();
      final marca = await firestore.collection('marcas').doc(idMarca).get();
      final grupo = await firestore
          .collection('grupos_servicio')
          .doc(idGrupo)
          .get();

      expect(tecnico.data()?['taller_id'], tallerId);
      expect(tecnico.data()?['activo'], isTrue);
      expect(tecnico.data()?['eliminado_en'], isA<String>());
      expect(tecnico.data()?['sync_status'], 'synced');
      final tombstoneRemoto = await firestore
          .collection('tecnicos')
          .doc(idTecnicoBorradoEnOtroDispositivo)
          .get();
      expect(
        tombstoneRemoto.data()?['eliminado_en'],
        '2026-01-03T00:00:00.000Z',
      );
      expect(servicio.data()?['precio'], 1450);
      expect(servicio.data()?['activo'], isTrue);
      expect(marca.data()?['nombre'], 'Marca sincronizada');
      expect(grupo.data()?['nombre'], 'Grupo sincronizado');

      final db = await DatabaseHelper.instance.base;
      final pendientes = await db.rawQuery(
        '''
        SELECT count(*) AS cantidad
        FROM tecnicos
        WHERE taller_id = ? AND sync_status = 'pending'
      ''',
        [tallerId],
      );
      expect(pendientes.single['cantidad'], 0);
    },
  );

  test('el pull de Admin queda limitado al taller de la sesión', () async {
    const tallerAdmin = 'taller-admin-pull';
    final firestore = FakeFirebaseFirestore();
    SyncService.instance.usarFirestoreParaPruebas(firestore);
    await SesionAdmin.instance.iniciar(
      tallerId: tallerAdmin,
      adminUid: 'admin-pull',
      persistir: false,
    );
    await firestore
        .collection('tecnicos')
        .doc('tec-del-admin')
        .set(
          _catalogoRemoto(
            id: 'tec-del-admin',
            tallerId: tallerAdmin,
            nombre: 'Técnico admin',
          ),
        );
    await firestore
        .collection('tecnicos')
        .doc('tec-de-otro')
        .set(
          _catalogoRemoto(
            id: 'tec-de-otro',
            tallerId: 'otro-taller',
            nombre: 'Técnico ajeno',
          ),
        );

    await SyncService.instance.sincronizarCatalogosDeTaller(tallerAdmin);
    var propios = <Tecnico>[];
    for (var intento = 0; intento < 30 && propios.isEmpty; intento++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      propios = await TecnicoRepository.instance.obtenerTodasPorTaller(
        tallerAdmin,
      );
    }
    expect(propios.map((tecnico) => tecnico.id), ['tec-del-admin']);
    expect(
      await TecnicoRepository.instance.obtenerTodasPorTaller('otro-taller'),
      isEmpty,
    );
  });

  test('el cliente descarga los servicios del taller seleccionado', () async {
    final tallerCliente = SemillaInicial.talleres[2].id;
    final idServicioSemillaCentral = SemillaInicial.idCatalogoParaTaller(
      SemillaInicial.tiposServicioIds.first,
      2,
    );
    final firestore = FakeFirebaseFirestore();
    SyncService.instance.usarFirestoreParaPruebas(firestore);
    await SesionCliente.instance.iniciar(
      nombre: 'Cliente',
      correo: 'cliente@example.com',
      persistir: false,
    );
    await firestore
        .collection('servicios')
        .doc(idServicioSemillaCentral)
        .set(
          _catalogoRemoto(
            id: idServicioSemillaCentral,
            tallerId: tallerCliente,
            nombre: 'Servicio del taller',
          )..['precio'] = 920,
        );
    await firestore
        .collection('servicios')
        .doc('srv-ajeno')
        .set(
          _catalogoRemoto(
            id: 'srv-ajeno',
            tallerId: 'otro-taller',
            nombre: 'Servicio ajeno',
          )..['precio'] = 50,
        );

    await SyncService.instance.sincronizarCatalogosDeTaller(tallerCliente);
    var servicios = <TipoServicio>[];
    for (var intento = 0; intento < 30 && servicios.isEmpty; intento++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      servicios = await TipoServicioRepository.instance.obtenerTodasPorTaller(
        tallerCliente,
      );
    }
    final remoto = servicios.firstWhere(
      (servicio) => servicio.id == idServicioSemillaCentral,
    );
    expect(servicios.length, SemillaInicial.tiposServicio.length);
    expect(remoto.nombre, 'Servicio del taller');
    expect(remoto.precio, 920);
    expect(
      await TipoServicioRepository.instance.obtenerTodasPorTaller(
        'otro-taller',
      ),
      isEmpty,
    );
  });
}

Map<String, Object?> _catalogoRemoto({
  required String id,
  required String tallerId,
  required String nombre,
}) => <String, Object?>{
  'id': id,
  'taller_id': tallerId,
  'nombre': nombre,
  'activo': true,
  'creado_en': '2026-01-01T00:00:00.000Z',
  'actualizado_en': '2026-01-02T00:00:00.000Z',
  'sync_status': 'synced',
  'eliminado_en': null,
};

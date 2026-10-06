import 'package:flutter/foundation.dart';

import 'package:autofix/core/auth/credenciales_seguras.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/utils/reloj.dart';
import 'package:autofix/core/utils/uuid.dart';

/// Un cambio de contraseña que la app todavía no pudo aplicar.
class CambioPasswordPendiente {
  const CambioPasswordPendiente({
    required this.id,
    required this.correoCliente,
    required this.syncStatus,
    required this.creadoEn,
  });

  final String id;
  final String correoCliente;

  /// `'pending'` (hay que aplicar) o `'synced'` (ya se aplico). Mismo vocabulario
  /// que `citas.sync_status` para que `SyncService` hable un solo idioma.
  final String syncStatus;

  final DateTime creadoEn;
}

/// La cola local de cambios de contraseña (tabla `cambios_password`).
///
/// ---------------------------------------------------------------
/// COMO FUNCIONA Y POR QUE ESTA PARTIDA EN DOS
/// ---------------------------------------------------------------
/// El requisito es: sin internet el cambio se guarda "en una cola local con
/// estatus pendiente" y `SyncService` lo sube cuando vuelva la red. La
/// IMPLEMENTACION hace eso pero con un matiz de seguridad que no es negociable:
///
/// - **La fila (SQLite)** guarda metadata: id, estatus, fecha. Es lo que la
///   cola ES.
/// - **El secreto (`flutter_secure_storage`)** guarda la contraseña cifrada
///   bajo la clave `cambiosPassword.<id>`. Es lo que la cola CONTIENE.
///
/// Es decir: la contraseña NUNCA se escribe en SQLite en claro, y menos se
/// sube a Firestore. Una contraseña que viaja a la nube es una contraseña
/// filtrada; por eso `SyncService` al drenar esta cola no "sube" el secreto,
/// lo REAPLICA en Firebase Auth (ver `SyncService.pushPending`). Mismo
/// comportamiento que el usuario pide ("se aplicara al conectarse") sin el
/// coste de exponer la credencial.
///
/// Las dos escrituras se hacen en orden secreto-primero, fila-despues: si el
/// keystore falla no queda una fila que promete un cambio que nadie puede
/// aplicar. Y `encolar` devuelve `false` en vez de lanzar, para que la UI
/// pueda decir "no se pudo" en vez de crashear.
class CambiosPasswordRepository {
  CambiosPasswordRepository._();

  static final CambiosPasswordRepository instance =
      CambiosPasswordRepository._();

  static const String _tabla = DatabaseHelper.tablaCambiosPassword;
  static const String _prefijoSeguro =
      DatabaseHelper.prefijoSeguroCambiosPassword;

  /// Encola un cambio pendiente. Devuelve `false` si no se pudo guardar.
  Future<bool> encolar({
    required String contrasena,
    required String correoCliente,
  }) async {
    final correo = correoCliente.trim();
    if (correo.isEmpty) return false;
    final id = Uuid.instancia.generar();

    try {
      // Secreto PRIMERO: ver razon arriba.
      await CredencialesSeguras.guardarClave('$_prefijoSeguro$id', contrasena);
      if (!await CredencialesSeguras.existeClave('$_prefijoSeguro$id')) {
        return false;
      }

      final db = await DatabaseHelper.instance.base;
      await db.insert(_tabla, <String, Object?>{
        DatabaseHelper.colId: id,
        DatabaseHelper.colSyncStatus: 'pending',
        DatabaseHelper.colCorreoCambioPassword: correo,
        DatabaseHelper.colCreadoEn: ahoraIso(),
        DatabaseHelper.colActualizadoEn: '',
      });
      return true;
    } catch (e) {
      debugPrint('CambiosPasswordRepository: no se pudo encolar ($e)');
      return false;
    }
  }

  /// Los cambios todavia no aplicados, del mas viejo al mas reciente.
  Future<List<CambioPasswordPendiente>> pendientes() async {
    final db = await DatabaseHelper.instance.base;
    final filas = await db.query(
      _tabla,
      where: '${DatabaseHelper.colSyncStatus} = ?',
      whereArgs: const ['pending'],
      orderBy: '${DatabaseHelper.colCreadoEn} ASC',
    );

    return filas
        .map(
          (fila) => CambioPasswordPendiente(
            id: fila[DatabaseHelper.colId] as String,
            correoCliente:
                fila[DatabaseHelper.colCorreoCambioPassword] as String? ?? '',
            syncStatus: fila[DatabaseHelper.colSyncStatus] as String,
            creadoEn:
                desdeIso(fila[DatabaseHelper.colCreadoEn] as String?) ??
                DateTime.now().toUtc(),
          ),
        )
        .toList(growable: false);
  }

  /// El secreto de una fila, o `null` si ya no esta (o no se pudo leer).
  Future<String?> leerContrasena(CambioPasswordPendiente cambio) =>
      CredencialesSeguras.leerClave('$_prefijoSeguro${cambio.id}');

  /// Marca la fila como aplicada y tira el secreto.
  ///
  /// El secreto se borra en cuanto se aplico: ya no hace falta y es lo unico
  /// sensible que existia. La fila queda como historial de que hubo un cambio,
  /// con su fecha.
  Future<void> marcarAplicada(CambioPasswordPendiente cambio) async {
    await CredencialesSeguras.borrarClave('$_prefijoSeguro${cambio.id}');
    final db = await DatabaseHelper.instance.base;
    await db.update(
      _tabla,
      <String, Object?>{
        DatabaseHelper.colSyncStatus: 'synced',
        DatabaseHelper.colActualizadoEn: ahoraIso(),
      },
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [cambio.id],
    );
  }

  /// Borra una fila que no se puede aplicar (falta el secreto, por ejemplo).
  ///
  /// Devolver `false` y dejar la fila ahi seria dejar la cola "pendiente" para
  /// siempre: cada reconexion intentaria algo que ya sabemos que no va a
  /// funcionar.
  Future<void> descartar(String id) async {
    await CredencialesSeguras.borrarClave('$_prefijoSeguro$id');
    final db = await DatabaseHelper.instance.base;
    await db.delete(
      _tabla,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
    );
  }
}

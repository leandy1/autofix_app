import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:autofix/core/database/database_helper.dart';
import 'package:autofix/core/utils/reloj.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/cliente/data/vehiculo_repository.dart';
import 'package:autofix/features/cliente/models/vehiculo.dart';
import 'package:autofix/features/devMode/data/audit_log_repository.dart';
import 'package:autofix/features/talleres/data/taller_repository.dart';
import 'package:autofix/features/talleres/models/taller.dart';

class RegistroPapelera {
  const RegistroPapelera({
    required this.tabla,
    required this.modulo,
    required this.id,
    required this.titulo,
    required this.eliminadoEn,
    this.datosNube,
  });

  final String tabla;
  final String modulo;
  final String id;
  final String titulo;
  final String eliminadoEn;
  final Map<String, dynamic>? datosNube;
}

/// Lee y restaura tombstones de todas las tablas sincronizadas.
class PapeleraRepository {
  PapeleraRepository._();

  static final PapeleraRepository instance = PapeleraRepository._();

  Future<List<RegistroPapelera>> obtenerEliminados() async {
    final db = await DatabaseHelper.instance.base;
    final filas = await db.rawQuery('''
      SELECT '${DatabaseHelper.tablaCitas}' AS tabla, 'citas' AS modulo,
        id, COALESCE(NULLIF(codigo_visible, ''), cliente) AS titulo,
        eliminado_en FROM ${DatabaseHelper.tablaCitas}
        WHERE eliminado_en IS NOT NULL
      UNION ALL
      SELECT '${DatabaseHelper.tablaVehiculos}', 'vehiculos', id,
        marca || ' ' || modelo || CASE WHEN placa = '' THEN '' ELSE ' · ' || placa END,
        eliminado_en FROM ${DatabaseHelper.tablaVehiculos}
        WHERE eliminado_en IS NOT NULL
      UNION ALL
      SELECT '${DatabaseHelper.tablaTalleres}', 'talleres', id, nombre,
        eliminado_en FROM ${DatabaseHelper.tablaTalleres}
        WHERE eliminado_en IS NOT NULL
      UNION ALL
      SELECT '${DatabaseHelper.tablaTecnicos}', 'tecnicos', id, nombre,
        eliminado_en FROM ${DatabaseHelper.tablaTecnicos}
        WHERE eliminado_en IS NOT NULL
      UNION ALL
      SELECT '${DatabaseHelper.tablaTiposServicio}', 'servicios', id, nombre,
        eliminado_en FROM ${DatabaseHelper.tablaTiposServicio}
        WHERE eliminado_en IS NOT NULL
      UNION ALL
      SELECT '${DatabaseHelper.tablaMarcas}', 'marcas', id, nombre,
        eliminado_en FROM ${DatabaseHelper.tablaMarcas}
        WHERE eliminado_en IS NOT NULL
      UNION ALL
      SELECT '${DatabaseHelper.tablaGruposServicio}', 'grupos_servicio', id, nombre,
        eliminado_en FROM ${DatabaseHelper.tablaGruposServicio}
        WHERE eliminado_en IS NOT NULL
      ORDER BY eliminado_en DESC
    ''');
    final registros = <String, RegistroPapelera>{
      for (final fila in filas)
        '${fila['tabla']}/${fila['id']}': RegistroPapelera(
          tabla: fila['tabla']! as String,
          modulo: fila['modulo']! as String,
          id: fila['id']! as String,
          titulo: fila['titulo']?.toString() ?? fila['id']! as String,
          eliminadoEn: fila['eliminado_en']! as String,
        ),
    };

    // La Papelera DEV debe contemplar documentos eliminados en cualquier
    // dispositivo, no solo las filas que casualmente existen en esta SQLite.
    const colecciones = <(String, String, String)>[
      ('citas', DatabaseHelper.tablaCitas, 'citas'),
      ('vehiculos', DatabaseHelper.tablaVehiculos, 'vehiculos'),
      ('talleres', DatabaseHelper.tablaTalleres, 'talleres'),
      ('tecnicos', DatabaseHelper.tablaTecnicos, 'tecnicos'),
      ('servicios', DatabaseHelper.tablaTiposServicio, 'servicios'),
      ('marcas', DatabaseHelper.tablaMarcas, 'marcas'),
      (
        'grupos_servicio',
        DatabaseHelper.tablaGruposServicio,
        'grupos_servicio',
      ),
    ];
    for (final (coleccion, tabla, modulo) in colecciones) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection(coleccion)
            .where('eliminado_en', isNotEqualTo: null)
            .orderBy('eliminado_en', descending: true)
            .limit(500)
            .get();
        for (final documento in snapshot.docs) {
          final datos = <String, dynamic>{
            ...documento.data(),
            'id': documento.id,
          };
          final clave = '$tabla/${documento.id}';
          final existente = registros[clave];
          final titulo = _tituloDe(modulo, datos, documento.id);
          registros[clave] = RegistroPapelera(
            tabla: tabla,
            modulo: modulo,
            id: documento.id,
            titulo: existente?.titulo ?? titulo,
            eliminadoEn: _fechaIso(datos['eliminado_en']),
            datosNube: datos,
          );
        }
      } on FirebaseException {
        // Si no hay red o las reglas deniegan la lectura, la papelera local
        // sigue disponible; cada colección remota se intenta aisladamente.
      }
    }

    final lista = registros.values.toList();
    lista.sort((a, b) => b.eliminadoEn.compareTo(a.eliminadoEn));
    return lista;
  }

  Future<bool> restaurar(RegistroPapelera registro) async {
    await _importarSiFalta(registro);
    switch (registro.tabla) {
      case DatabaseHelper.tablaCitas:
        return await CitaRepository.instance.restaurar(registro.id) > 0;
      case DatabaseHelper.tablaVehiculos:
        return await VehiculoRepository.instance.restaurar(registro.id) > 0;
      case DatabaseHelper.tablaTalleres:
        return await TallerRepository.instance.reactivar(registro.id) > 0;
      default:
        final db = await DatabaseHelper.instance.base;
        final ahora = ahoraIso();
        final modificados = await db.update(
          registro.tabla,
          <String, Object?>{
            DatabaseHelper.colEliminadoEn: null,
            DatabaseHelper.colActivo: 1,
            DatabaseHelper.colActualizadoEn: ahora,
            DatabaseHelper.colSyncStatus: 'pending',
          },
          where:
              '${DatabaseHelper.colId} = ? AND '
              '${DatabaseHelper.colEliminadoEn} IS NOT NULL',
          whereArgs: <Object?>[registro.id],
        );
        if (modificados > 0) {
          await AuditLogRepository.instance.registrar(
            modulo: registro.modulo,
            entidadId: registro.id,
            accion: AuditLogRepository.restauracion,
            detalles: <String, Object?>{'titulo': registro.titulo},
          );
        }
        return modificados > 0;
    }
  }

  Future<void> _importarSiFalta(RegistroPapelera registro) async {
    final datos = registro.datosNube;
    if (datos == null) return;
    final db = await DatabaseHelper.instance.base;
    final mapa = _normalizarFechas(datos);
    switch (registro.tabla) {
      case DatabaseHelper.tablaCitas:
        await CitaRepository.instance.fusionarDesdeNube(Cita.fromMap(mapa));
      case DatabaseHelper.tablaVehiculos:
        await VehiculoRepository.instance.aplicarDesdeNube(
          Vehiculo.fromMap(mapa),
          prevaleceBaja: true,
        );
      case DatabaseHelper.tablaTalleres:
        mapa[DatabaseHelper.colActivo] = mapa[DatabaseHelper.colActivo] == true
            ? 1
            : 0;
        final taller = Taller.fromMap(mapa).toMap();
        final filas = await db.update(
          DatabaseHelper.tablaTalleres,
          taller,
          where: '${DatabaseHelper.colId} = ?',
          whereArgs: <Object?>[registro.id],
        );
        if (filas == 0) await db.insert(DatabaseHelper.tablaTalleres, taller);
      default:
        final valores = <String, Object?>{
          ...mapa,
          DatabaseHelper.colActivo: mapa[DatabaseHelper.colActivo] == true
              ? 1
              : 0,
          DatabaseHelper.colSyncStatus: 'synced',
        };
        final filas = await db.update(
          registro.tabla,
          valores,
          where: '${DatabaseHelper.colId} = ?',
          whereArgs: <Object?>[registro.id],
        );
        if (filas == 0) await db.insert(registro.tabla, valores);
    }
  }

  Map<String, Object?> _normalizarFechas(Map<String, dynamic> datos) {
    const columnasFecha = <String>[
      'fecha_cita',
      'creado_en',
      'actualizado_en',
      'eliminado_en',
      'restaurado_en',
    ];
    return <String, Object?>{
      ...datos,
      for (final columna in columnasFecha)
        if (datos.containsKey(columna)) columna: _fechaIso(datos[columna]),
    };
  }

  String _fechaIso(Object? valor) {
    if (valor is Timestamp) return valor.toDate().toUtc().toIso8601String();
    if (valor is DateTime) return valor.toUtc().toIso8601String();
    return valor?.toString() ?? '';
  }

  String _tituloDe(String modulo, Map<String, dynamic> datos, String id) {
    return switch (modulo) {
      'citas' =>
        datos['codigo_visible'] as String? ?? datos['cliente'] as String? ?? id,
      'vehiculos' =>
        '${datos['marca'] ?? ''} ${datos['modelo'] ?? ''}'
            '${(datos['placa'] as String? ?? '').isEmpty ? '' : ' · ${datos['placa']}'}',
      _ => datos['nombre'] as String? ?? id,
    };
  }
}

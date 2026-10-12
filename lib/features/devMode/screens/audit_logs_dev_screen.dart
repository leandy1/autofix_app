import 'package:autofix/features/devMode/data/audit_log_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AuditLogsDevScreen extends StatefulWidget {
  const AuditLogsDevScreen({super.key});

  @override
  State<AuditLogsDevScreen> createState() => _AuditLogsDevScreenState();
}

class _AuditLogsDevScreenState extends State<AuditLogsDevScreen> {
  late Future<List<Map<String, dynamic>>> _logs;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  void _recargar() => _logs = _cargarLogs();

  Future<List<Map<String, dynamic>>> _cargarLogs() async {
    final todos = <String, Map<String, dynamic>>{};
    try {
      final snap = await FirebaseFirestore.instance
          .collection('audit_logs')
          .orderBy('fecha_hora', descending: true)
          .limit(500)
          .get();
      for (final doc in snap.docs) {
        todos[doc.id] = <String, dynamic>{...doc.data(), 'id': doc.id};
      }
    } catch (_) {
      // Se muestran igualmente los logs locales si Firebase no está disponible.
    }
    for (final fila in await AuditLogRepository.instance.obtenerTodos()) {
      final id = fila['id'] as String;
      todos.putIfAbsent(id, () => Map<String, dynamic>.from(fila));
    }
    final lista = todos.values.toList();
    lista.sort(
      (a, b) => _fecha(b['fecha_hora']).compareTo(_fecha(a['fecha_hora'])),
    );
    return lista;
  }

  DateTime _fecha(Object? valor) {
    if (valor is Timestamp) return valor.toDate();
    if (valor is DateTime) return valor;
    return DateTime.tryParse('$valor') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Logs DEV'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => setState(_recargar),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _logs,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('No se pudieron cargar los logs: ${snapshot.error}'),
            );
          }
          final filas = snapshot.data ?? const <Map<String, dynamic>>[];
          if (filas.isEmpty) {
            return const Center(child: Text('No hay eventos registrados.'));
          }
          return ListView.separated(
            itemCount: filas.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final fila = filas[index];
              final accion = fila['accion'] as String? ?? 'evento';
              return ListTile(
                leading: Icon(
                  accion == AuditLogRepository.restauracion
                      ? Icons.restore
                      : Icons.delete_outline,
                ),
                title: Text('${fila['modulo'] ?? '—'} · $accion'),
                subtitle: Text(
                  '${fila['usuario_email'] ?? fila['usuario_uid'] ?? 'usuario local'}\n'
                  '${fila['fecha_hora'] ?? ''} · ${fila['dispositivo'] ?? 'dispositivo local'}\n'
                  'Registro: ${fila['entidad_id'] ?? '—'}',
                ),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }
}

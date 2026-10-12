import 'package:autofix/features/devMode/data/papelera_repository.dart';
import 'package:autofix/features/devMode/sync/devmode_sync_service.dart';
import 'package:autofix/features/devMode/screens/audit_logs_dev_screen.dart';
import 'package:autofix/features/sync/sync_service.dart';
import 'package:flutter/material.dart';

class PapeleraDevScreen extends StatefulWidget {
  const PapeleraDevScreen({super.key});

  @override
  State<PapeleraDevScreen> createState() => _PapeleraDevScreenState();
}

class _PapeleraDevScreenState extends State<PapeleraDevScreen> {
  late Future<List<RegistroPapelera>> _registros;
  final PapeleraRepository _repository = PapeleraRepository.instance;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  void _recargar() => _registros = _repository.obtenerEliminados();

  Future<void> _restaurar(RegistroPapelera registro) async {
    try {
      final restaurado = await _repository.restaurar(registro);
      if (!restaurado) return;
      await SyncService.instance.pushPending();
      if (registro.tabla == 'talleres') {
        await DevModeSyncService.instance.subirTalleresPendientes();
      }
      if (!mounted) return;
      setState(_recargar);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Se restauró ${registro.titulo}.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo restaurar: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Papelera DEV'),
        actions: [
          IconButton(
            tooltip: 'Audit Logs',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AuditLogsDevScreen()),
            ),
            icon: const Icon(Icons.fact_check_outlined),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => setState(_recargar),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<RegistroPapelera>>(
        future: _registros,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('No se pudo cargar la papelera: ${snapshot.error}'),
            );
          }
          final registros = snapshot.data ?? const <RegistroPapelera>[];
          if (registros.isEmpty) {
            return const Center(child: Text('No hay registros eliminados.'));
          }
          return ListView.separated(
            itemCount: registros.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final registro = registros[index];
              return ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(registro.titulo),
                subtitle: Text(
                  '${registro.modulo} · ${registro.eliminadoEn}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: FilledButton.tonalIcon(
                  onPressed: () => _restaurar(registro),
                  icon: const Icon(Icons.restore),
                  label: const Text('Restaurar'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

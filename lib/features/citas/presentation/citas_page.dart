import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/connectivity/widgets/conectivity_banner.dart';
import '../data/cita_repository.dart';
import '../models/cita.dart';

/// Pantalla de demostracion: lista de citas y sus 4 operaciones CRUD sobre
/// SQLite. Al cerrar la app por completo y reabrirla, los datos siguen aqui
/// porque provienen del archivo .db y no de una lista en memoria.
class CitasPage extends StatefulWidget {
  const CitasPage({super.key});

  @override
  State<CitasPage> createState() => _CitasPageState();
}

class _CitasPageState extends State<CitasPage> {
  final CitaRepository _repo = CitaRepository.instance;

  List<Cita> _citas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final citas = await _repo.obtenerTodas();
    if (!mounted) return;
    setState(() {
      _citas = citas;
      _cargando = false;
    });
  }

  Future<void> _abrirFormulario({Cita? cita}) async {
    final guardada = await showModalBottomSheet<Cita>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CitaForm(cita: cita),
    );
    if (guardada == null) return;

    try {
      if (cita == null) {
        await _repo.crear(guardada);
      } else {
        await _repo.actualizar(guardada);
      }
      await _cargar();
    } on Exception catch (e) {
      _mostrarError(e.toString());
    }
  }

  Future<void> _eliminar(Cita cita) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cita'),
        content: Text('Se eliminara la cita de ${cita.cliente}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    await _repo.eliminar(cita.id!);
    await _cargar();
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se pudo guardar: $mensaje')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Citas'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: ConectivityChip()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Nueva cita'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _citas.isEmpty
              ? const Center(child: Text('Aun no hay citas registradas.'))
              : ListView.separated(
                  itemCount: _citas.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _CitaTile(
                    cita: _citas[i],
                    onEditar: () => _abrirFormulario(cita: _citas[i]),
                    onEliminar: () => _eliminar(_citas[i]),
                  ),
                ),
    );
  }
}

class _CitaTile extends StatelessWidget {
  const _CitaTile({
    required this.cita,
    required this.onEditar,
    required this.onEliminar,
  });

  final Cita cita;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  static final DateFormat _fecha = DateFormat('dd/MM/yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(cita.cliente),
      subtitle: Text(
        '${cita.vehiculo}  |  ${_fecha.format(cita.fechaCita)}\nQR: ${cita.codigoQr}',
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (opcion) => opcion == 'editar' ? onEditar() : onEliminar(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'editar', child: Text('Editar')),
          PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
        ],
      ),
    );
  }
}

class _CitaForm extends StatefulWidget {
  const _CitaForm({this.cita});

  final Cita? cita;

  @override
  State<_CitaForm> createState() => _CitaFormState();
}

class _CitaFormState extends State<_CitaForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _qr;
  late final TextEditingController _cliente;
  late final TextEditingController _vehiculo;
  late final TextEditingController _descripcion;
  late DateTime _fecha;
  late EstadoCita _estado;

  @override
  void initState() {
    super.initState();
    final c = widget.cita;
    _qr = TextEditingController(text: c?.codigoQr ?? '');
    _cliente = TextEditingController(text: c?.cliente ?? '');
    _vehiculo = TextEditingController(text: c?.vehiculo ?? '');
    _descripcion = TextEditingController(text: c?.descripcion ?? '');
    _fecha = c?.fechaCita ?? DateTime.now();
    _estado = c?.estado ?? EstadoCita.pendiente;
  }

  @override
  void dispose() {
    _qr.dispose();
    _cliente.dispose();
    _vehiculo.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final dia = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (dia == null || !mounted) return;
    setState(() {
      _fecha = DateTime(
        dia.year,
        dia.month,
        dia.day,
        _fecha.hour,
        _fecha.minute,
      );
    });
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      Cita(
        id: widget.cita?.id,
        codigoQr: _qr.text.trim(),
        cliente: _cliente.text.trim(),
        vehiculo: _vehiculo.text.trim(),
        descripcion: _descripcion.text.trim(),
        fechaCita: _fecha,
        estado: _estado,
        creadoEn: widget.cita?.creadoEn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.cita == null ? 'Nueva cita' : 'Editar cita',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _qr,
                decoration: const InputDecoration(labelText: 'Codigo QR'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _cliente,
                decoration: const InputDecoration(labelText: 'Cliente'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _vehiculo,
                decoration: const InputDecoration(labelText: 'Vehiculo'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _descripcion,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Descripcion'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _elegirFecha,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(DateFormat('dd/MM/yyyy HH:mm').format(_fecha)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<EstadoCita>(
                initialValue: _estado,
                decoration: const InputDecoration(labelText: 'Estado'),
                items: EstadoCita.values
                    .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                    .toList(),
                onChanged: (v) => setState(() => _estado = v ?? _estado),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _guardar,
                child: const Text('Guardar en SQLite'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

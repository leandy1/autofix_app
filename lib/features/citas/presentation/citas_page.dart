import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/connectivity/widgets/conectivity_banner.dart';
import '../../../theme/app_colors.dart';
import '../data/cita_repository.dart';
import '../models/cita.dart';

/// PANTALLA DE REFERENCIA / DEMOSTRACION DEL CRUD.
///
/// ESTA ES MI GARANTIA PARA LA DEFENSA, y es a proposito que se quede en el
/// repo despues del merge (no es codigo muerto):
///
///   - Es la prueba de que el CRUD funciona de punta a punta contra SQLite
///     real, independiente de lo que haga la pantalla de Leandy. Si su
///     `citas_screen.dart` falla al integrar, esta sigue anda y demuestra
///     que el problema NO es de mi capa de datos.
///   - Es la unica pantalla que se ve el CRUD completo: crear, leer, editar,
///     eliminar. Si hay que mostrar "los datos persisten", se cierra la app
///     con el gesto de Home, se vuelve a abrir y la lista sigue ahi.
///
/// No choca con nada de Leandy: vive en `features/citas/presentation/`, el
/// vive en `lib/screens/`. Son rutas distintas, asi que el merge no las ve.
///
/// Lo que esta pantalla consume (y el es el contrato que ofrece al resto del
/// equipo) es unicamente `CitaRepository`. Ni un `await` de sqflite, ni una
/// columna, ni un `Map` de la base: la pantalla no sabe que hay una base de
/// datos, solo pide y recibe objetos `Cita`.
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

  /// READ. Notese el `if (!mounted) return;`: el `await` cede el hilo, el
  /// usuario puede salir de la pantalla mientras tanto, y sin ese chequeo el
  /// `setState` explota con "setState() called after dispose()".
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
      // CREATE o UPDATE, el mismo formulario decide cual por el `id`.
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

  Future<void> _cambiarEstado(Cita cita, EstadoCita estado) async {
    await _repo.cambiarEstado(cita.id!, estado);
    await _cargar();
  }

  /// DELETE, con confirmacion: borrar filas sin preguntar es como se pierden
  /// datos en una app de verdad.
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
        title: const Text('Citas (demo CRUD)'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: ConectivityChip()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirFormulario,
        icon: const Icon(Icons.add),
        label: const Text('Nueva cita'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _citas.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aun no hay citas.\n\nGuarda una, cerrá la app con el boton de '
                      'Home y volvé a abrirla: la lista sigue ahi, porque sale de '
                      'SQLite y no de una lista en memoria.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _citas.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _CitaTile(
                    cita: _citas[i],
                    onEditar: () => _abrirFormulario(cita: _citas[i]),
                    onEliminar: () => _eliminar(_citas[i]),
                    onCambiarEstado: (e) => _cambiarEstado(_citas[i], e),
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
    required this.onCambiarEstado,
  });

  final Cita cita;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;
  final ValueChanged<EstadoCita> onCambiarEstado;

  static final DateFormat _fecha = DateFormat('dd/MM/yyyy HH:mm');

  /// Las mismas 5 llaves del `kColorPorEstado` de Leandy. Se replicate aca a
  /// proposito: es la prueba visible de que `Cita.etiquetaUI` devuelve la llave
  /// EXACTA que su mapa espera. Si el dia de manana el cambia, esta pantalla
  /// deja de pintar y hay que investigar.
  static const Map<String, Color> _colorPorEstado = {
    'ATRASADAS': AppColors.atrasadas,
    'Pendiente': AppColors.pendientes,
    'Esperando Pieza': AppColors.esperandoPieza,
    'En proceso': AppColors.enProceso,
    'Completado': AppColors.completado,
  };

  @override
  Widget build(BuildContext context) {
    final etiqueta = cita.etiquetaUI;
    final color = _colorPorEstado[etiqueta] ?? AppColors.textGray;

    return ListTile(
      title: Row(
        children: [
          Expanded(child: Text(cita.cliente)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              etiqueta.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text('${cita.vehiculo}${cita.placa.isEmpty ? '' : '  |  ${cita.placa}'}'),
          Text('QR: ${cita.codigoQr}   |   ${_fecha.format(cita.fechaCita)}'),
          if (cita.servicios.isNotEmpty)
            Text(
              'Servicios: ${cita.servicios.join(', ')}',
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (opcion) => switch (opcion) {
          'editar' => onEditar(),
          'eliminar' => onEliminar(),
          _ => null,
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'editar', child: Text('Editar')),
          const PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
          const PopupMenuDivider(),
          for (final estado in EstadoCita.values)
            PopupMenuItem(
              value: 'estado:${estado.name}',
              child: Text('Marcar ${estado.etiqueta}'),
            ),
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
  late final TextEditingController _telefono;
  late final TextEditingController _vehiculo;
  late final TextEditingController _placa;
  late final TextEditingController _tecnico;
  late final TextEditingController _descripcion;

  /// Los servicios se editan como texto separado por coma y se guardan como
  /// JSON. Es la puente entre lo que se tipea y lo que entiende la columna.
  late final TextEditingController _servicios;
  late DateTime _fecha;
  late EstadoCita _estado;

  @override
  void initState() {
    super.initState();
    final c = widget.cita;
    _qr = TextEditingController(text: c?.codigoQr ?? '');
    _cliente = TextEditingController(text: c?.cliente ?? '');
    _telefono = TextEditingController(text: c?.telefono ?? '');
    _vehiculo = TextEditingController(text: c?.vehiculo ?? '');
    _placa = TextEditingController(text: c?.placa ?? '');
    _tecnico = TextEditingController(text: c?.tecnico ?? '');
    _descripcion = TextEditingController(text: c?.descripcion ?? '');
    _servicios = TextEditingController(text: c?.servicios.join(', ') ?? '');
    _fecha = c?.fechaCita ?? DateTime.now();
    _estado = c?.estado ?? EstadoCita.pendiente;
  }

  @override
  void dispose() {
    _qr.dispose();
    _cliente.dispose();
    _telefono.dispose();
    _vehiculo.dispose();
    _placa.dispose();
    _tecnico.dispose();
    _descripcion.dispose();
    _servicios.dispose();
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
        telefono: _telefono.text.trim(),
        vehiculo: _vehiculo.text.trim(),
        placa: _placa.text.trim().toUpperCase(),
        tecnico: _tecnico.text.trim(),
        servicios: _servicios.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        descripcion: _descripcion.text.trim(),
        fechaCita: _fecha,
        estado: _estado,
        // `creadoEn` se arrastra para que el UPDATE no pise la fecha de
        // creacion original con la de hoy.
        creadoEn: widget.cita?.creadoEn,
      ),
    );
  }

  InputDecoration _campo(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
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
                decoration: _campo('Codigo QR', hint: 'A-123'),
                validator: _requerido,
              ),
              TextFormField(
                controller: _cliente,
                decoration: _campo('Cliente'),
                validator: _requerido,
              ),
              TextFormField(
                controller: _telefono,
                keyboardType: TextInputType.phone,
                decoration: _campo('Telefono'),
              ),
              TextFormField(
                controller: _vehiculo,
                decoration: _campo('Vehiculo'),
                validator: _requerido,
              ),
              TextFormField(
                controller: _placa,
                textCapitalization: TextCapitalization.characters,
                decoration: _campo('Placa'),
              ),
              TextFormField(
                controller: _tecnico,
                decoration: _campo('Tecnico'),
              ),
              TextFormField(
                controller: _servicios,
                decoration: _campo('Servicios', hint: 'Frenos, Alineacion'),
              ),
              TextFormField(
                controller: _descripcion,
                maxLines: 2,
                decoration: _campo('Descripcion'),
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
                decoration: const InputDecoration(
                  labelText: 'Estado',
                  border: OutlineInputBorder(),
                ),
                // Se muestra la ETIQUETA, no el `.name`: es el mismo texto que
                // usa el dropdown de la pantalla de Leandy.
                items: EstadoCita.values
                    .map((e) => DropdownMenuItem(value: e, child: Text(e.etiqueta)))
                    .toList(),
                onChanged: (v) => setState(() => _estado = v ?? _estado),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _guardar,
                icon: const Icon(Icons.save),
                label: const Text('Guardar en SQLite'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _requerido(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Requerido' : null;
}

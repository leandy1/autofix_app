import 'package:flutter/material.dart';
import '../../models/cliente_dashboard_data.dart';
import '../../theme/app_colors.dart';

class AgendarCitaClienteSection extends StatefulWidget {
  final TallerCliente? tallerSeleccionado;

  const AgendarCitaClienteSection({super.key, this.tallerSeleccionado});

  @override
  State<AgendarCitaClienteSection> createState() => _AgendarCitaClienteSectionState();
}

class _AgendarCitaClienteSectionState extends State<AgendarCitaClienteSection> {
  final _formKey = GlobalKey<FormState>();
  final _motivoController = TextEditingController();
  DateTime? _fechaSeleccionada;
  TimeOfDay? _horaSeleccionada;

  Future<void> _seleccionarFecha(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked != null) {
      setState(() => _fechaSeleccionada = picked);
    }
  }

  Future<void> _seleccionarHora(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) {
      setState(() => _horaSeleccionada = picked);
    }
  }

  void _enviarSolicitud() {
    if (_formKey.currentState!.validate()) {
      if (_fechaSeleccionada == null || _horaSeleccionada == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor selecciona fecha y hora')),
        );
        return;
      }

      // Procesamiento exitoso
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud de cita enviada con éxito')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agendar Cita')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.tallerSeleccionado != null) ...[
                Text(
                  'Taller: ${widget.tallerSeleccionado!.nombre}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(widget.tallerSeleccionado!.direccion),
                const Divider(height: 30),
              ],
              TextFormField(
                controller: _motivoController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo de la cita / Servicio requerido',
                  border: OutlineInputBorder(),
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Ingrese un motivo' : null,
              ),
              const SizedBox(height: 16),
              ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                title: Text(
                  _fechaSeleccionada == null
                      ? 'Seleccionar Fecha'
                      : 'Fecha: ${_fechaSeleccionada!.day}/${_fechaSeleccionada!.month}/${_fechaSeleccionada!.year}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () => _seleccionarFecha(context),
              ),
              const SizedBox(height: 12),
              ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                title: Text(
                  _horaSeleccionada == null
                      ? 'Seleccionar Hora'
                      : 'Hora: ${_horaSeleccionada!.format(context)}',
                ),
                trailing: const Icon(Icons.access_time),
                onTap: () => _seleccionarHora(context),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.background,
                  ),
                  onPressed: _enviarSolicitud,
                  child: const Text('Confirmar y Solicitar Cita'),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
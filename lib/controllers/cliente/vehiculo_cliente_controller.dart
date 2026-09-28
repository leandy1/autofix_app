import 'package:flutter/material.dart';

class VehiculoClienteController extends ChangeNotifier {
  final marcaController = TextEditingController();
  final modeloController = TextEditingController();
  final anioController = TextEditingController();
  final placaController = TextEditingController();

  bool _formularioVisible = false;
  bool _seleccionado = false;
  String? _resumenVehiculo;
  String? _errorFormulario;

  bool get formularioVisible => _formularioVisible;
  bool get seleccionado => _seleccionado;
  String? get resumenVehiculo => _resumenVehiculo;
  String? get errorFormulario => _errorFormulario;

  void abrirFormulario() {
    _errorFormulario = null;
    _formularioVisible = true;
    notifyListeners();
  }

  void cancelarFormulario() {
    _formularioVisible = false;
    _errorFormulario = null;
    notifyListeners();
  }

  void seleccionarVehiculo() {
    _seleccionado = !_seleccionado;
    notifyListeners();
  }

  bool guardarVehiculo() {
    final marca = marcaController.text.trim();
    final modelo = modeloController.text.trim();
    final anio = anioController.text.trim();
    final placa = placaController.text.trim();

    if (marca.isEmpty || modelo.isEmpty || anio.isEmpty || placa.isEmpty) {
      _errorFormulario = 'Completa todos los campos para continuar.';
      notifyListeners();
      return false;
    }

    _resumenVehiculo = '$marca $modelo ($anio) · $placa';
    _formularioVisible = false;
    _seleccionado = true;
    _errorFormulario = null;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    marcaController.dispose();
    modeloController.dispose();
    anioController.dispose();
    placaController.dispose();
    super.dispose();
  }
}

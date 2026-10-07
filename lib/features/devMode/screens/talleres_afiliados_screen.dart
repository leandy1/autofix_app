import 'package:flutter/material.dart';
import 'package:autofix/features/devMode/controllers/dev_mode_controller.dart';
import 'package:autofix/features/talleres/models/taller.dart';
import 'package:autofix/shared/theme/app_colors.dart';
import 'package:autofix/features/devMode/screens/cuentas_admin_screen.dart';

class TalleresAfiliadosScreen extends StatefulWidget {
  const TalleresAfiliadosScreen({super.key});

  @override
  State<TalleresAfiliadosScreen> createState() =>
      _TalleresAfiliadosScreenState();
}

class _TalleresAfiliadosScreenState extends State<TalleresAfiliadosScreen> {
  final DevModeController _controller = DevModeController();
  final TextEditingController _buscarController = TextEditingController();
  bool _operacionEnCurso = false;

  @override
  void initState() {
    super.initState();
    _controller.start();
    _controller.cargarTalleres();
  }

  @override
  void dispose() {
    _controller.stop();
    _controller.dispose();
    _buscarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.headerNavy,
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AutoTaller',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              'DEVELOPER',
              style: TextStyle(
                fontSize: 10,
                color: Colors.white60,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sincronizar',
            icon: const Icon(Icons.sync),
            onPressed: _operacionEnCurso ? null : _sincronizar,
          ),
          IconButton(
            tooltip: 'Cuentas Admin',
            icon: const Icon(Icons.manage_accounts),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CuentasAdminScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final query = _buscarController.text.trim().toLowerCase();
          final talleres = _controller.talleres.where((taller) {
            return (taller.nombre.toLowerCase().contains(query) ||
                taller.direccion.toLowerCase().contains(query));
          }).toList();
          final activos = _controller.talleres
              .where((taller) => taller.activo)
              .length;
          final inactivos = _controller.talleres.length - activos;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'RED AUTOTALLER',
                                style: TextStyle(
                                  color: AppColors.orangePrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'Talleres afiliados',
                                style: TextStyle(
                                  color: AppColors.headerNavy,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Administra los datos y la ubicación de los talleres.',
                                style: TextStyle(
                                  color: AppColors.textGray,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () => _abrirFormulario(),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Agregar taller'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.orangePrimary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _resumen(
                            titulo: 'Total afiliados',
                            valor: '${_controller.talleres.length}',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _resumen(
                            titulo: 'Talleres activos',
                            valor: '$activos',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _resumen(
                            titulo: 'Inactivos',
                            valor: '$inactivos',
                            color: AppColors.textGray,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _directorio(talleres),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _resumen({
    required String titulo,
    required String valor,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E7EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(fontSize: 12, color: color ?? AppColors.textGray),
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: TextStyle(
              color: color ?? AppColors.headerNavy,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _directorio(List<Taller> talleres) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E7EF)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Directorio de talleres',
                        style: TextStyle(
                          color: AppColors.headerNavy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _buscarController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Buscar taller, dirección...',
                      prefixIcon: const Icon(Icons.search, size: 19),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: const BorderSide(
                          color: AppColors.inputBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: const BorderSide(
                          color: AppColors.inputBorder,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF0F1F3)),
          if (_controller.cargando)
            const Padding(
              padding: EdgeInsets.all(28),
              child: CircularProgressIndicator(),
            )
          else if (_controller.error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _controller.error!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            )
          else if (talleres.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No hay talleres para mostrar.',
                style: TextStyle(color: AppColors.textGray),
              ),
            )
          else
            for (final taller in talleres) _filaTaller(taller),
        ],
      ),
    );
  }

  Widget _filaTaller(Taller taller) {
    final initials = taller.nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: const Color(0xFFFFF5E9),
            child: Text(
              initials.isEmpty ? '?' : initials,
              style: const TextStyle(
                color: AppColors.orangePrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      taller.nombre,
                      style: const TextStyle(
                        color: AppColors.headerNavy,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _estado(taller.activo),
                  ],
                ),
                if (taller.direccion.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    taller.direccion,
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    if (taller.telefono.isNotEmpty) _dato(taller.telefono),
                    _dato('${taller.latitud}, ${taller.longitud}'),
                    _dato(taller.codigoVisible),
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              TextButton(
                onPressed: () => _abrirFormulario(taller),
                child: const Text('Editar'),
              ),
              if (taller.activo)
                IconButton(
                  tooltip: 'Dar de baja taller',
                  onPressed: () => _confirmarDarDeBaja(taller),
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.redAccent,
                )
              else
                IconButton(
                  tooltip: 'Reactivar taller',
                  onPressed: () => _confirmarReactivarTaller(taller),
                  icon: const Icon(Icons.refresh),
                  color: const Color(0xFF008B68),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarDarDeBaja(Taller taller) async {
    if (_operacionEnCurso) return;
    _operacionEnCurso = true;
    try {
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Dar de baja taller'),
          content: Text(
            '¿Deseas dar de baja a ${taller.nombre}? Ya no aparecerá en el mapa '
            'ni en el selector de citas. El historial existente se conservará.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Dar de baja'),
            ),
          ],
        ),
      );
      if (confirmado != true || !mounted) return;

      final id = taller.id;
      if (id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo identificar el taller.')),
        );
        return;
      }

      final ok = await _controller.darDeBajaTaller(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'El taller se dio de baja correctamente.'
                : _controller.error ?? 'No se pudo dar de baja el taller.',
          ),
        ),
      );
    } finally {
      _operacionEnCurso = false;
    }
  }

  Future<void> _confirmarReactivarTaller(Taller taller) async {
    if (_operacionEnCurso) return;
    _operacionEnCurso = true;
    try {
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reactivar taller'),
          content: Text(
            '¿Deseas reactivar a ${taller.nombre}? Volverá a aparecer en el mapa '
            'y en el selector de citas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF008B68),
                foregroundColor: Colors.white,
              ),
              child: const Text('Reactivar'),
            ),
          ],
        ),
      );
      if (confirmado != true || !mounted) return;

      final id = taller.id;
      if (id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo identificar el taller.')),
        );
        return;
      }

      final ok = await _controller.reactivarTaller(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'El taller se reactivado correctamente.'
                : _controller.error ?? 'No se pudo reactivar el taller.',
          ),
          backgroundColor: ok ? null : Colors.red.shade700,
        ),
      );
    } finally {
      _operacionEnCurso = false;
    }
  }

  Future<void> _sincronizar() async {
    _operacionEnCurso = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sincronizando con Firebase...')),
    );
    try {
      await _controller.sincronizar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _controller.error == null
                ? 'Sincronización completa.'
                : _controller.error!,
          ),
          backgroundColor: _controller.error == null
              ? Colors.green.shade800
              : Colors.red.shade700,
        ),
      );
    } finally {
      _operacionEnCurso = false;
    }
  }

  Widget _estado(bool activo) {
    final color = activo ? const Color(0xFF008B68) : AppColors.textGray;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: activo ? const Color(0xFFE9FAF3) : const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        activo ? 'Activo' : 'Inactivo',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _dato(String texto) => Text(
    texto,
    style: const TextStyle(fontSize: 11, color: AppColors.textGray),
  );

  Future<void> _abrirFormulario([Taller? taller]) async {
    if (_operacionEnCurso) return;
    _operacionEnCurso = true;
    final idTaller = TextEditingController(text: taller?.id.toString() ?? '');
    final nombre = TextEditingController(text: taller?.nombre ?? '');
    final direccion = TextEditingController(text: taller?.direccion ?? '');
    final telefono = TextEditingController(text: taller?.telefono ?? '');
    final latitud = TextEditingController(
      text: taller == null
          ? ''
          : DevModeController.formatearCoordenada(taller.latitud),
    );
    final longitud = TextEditingController(
      text: taller == null
          ? ''
          : DevModeController.formatearCoordenada(taller.longitud),
    );
    final key = GlobalKey<FormState>();
    Taller? resultado;

    try {
      final ruta = DialogRoute<Taller>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        builder: (dialogContext) => SafeArea(
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: key,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  taller == null
                                      ? 'NUEVO AFILIADO'
                                      : taller.codigoVisible,
                                  style: const TextStyle(
                                    color: AppColors.orangePrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  taller == null
                                      ? 'Agregar taller'
                                      : 'Editar taller',
                                  style: const TextStyle(
                                    color: AppColors.headerNavy,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () {
                              FocusScope.of(dialogContext).unfocus();
                              Navigator.of(dialogContext).pop();
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (taller != null) ...[
                        _campo('ID del taller', '', idTaller, readOnly: true),
                        const SizedBox(height: 14),
                      ],
                      _campo(
                        'Nombre del taller',
                        'Ej: Global Refriauto',
                        nombre,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Escribe el nombre del taller.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      _campo('Dirección', 'Calle, sector y ciudad', direccion),
                      const SizedBox(height: 14),
                      _campo(
                        'Teléfono',
                        '809-555-0101',
                        telefono,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _campo(
                              'Latitud',
                              '18,4861',
                              latitud,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              validator: (value) =>
                                  DevModeController.validarCoordenada(
                                    value,
                                    minimo: -90,
                                    maximo: 90,
                                    nombre: 'latitud',
                                  ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _campo(
                              'Longitud',
                              '-69,9312',
                              longitud,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              validator: (value) =>
                                  DevModeController.validarCoordenada(
                                    value,
                                    minimo: -180,
                                    maximo: 180,
                                    nombre: 'longitud',
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(height: 1, color: Color(0xFFF0F1F3)),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () {
                              FocusScope.of(dialogContext).unfocus();
                              Navigator.of(dialogContext).pop();
                            },
                            child: const Text(
                              'Cancelar',
                              style: TextStyle(color: AppColors.textGray),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              if (!key.currentState!.validate()) return;
                              final lat = DevModeController.leerCoordenada(
                                latitud.text,
                              )!;
                              final lng = DevModeController.leerCoordenada(
                                longitud.text,
                              )!;
                              FocusScope.of(dialogContext).unfocus();
                              Navigator.of(dialogContext).pop(
                                (taller ??
                                        Taller(
                                          nombre: nombre.text,
                                          latitud: lat,
                                          longitud: lng,
                                        ))
                                    .copyWith(
                                      nombre: nombre.text,
                                      direccion: direccion.text,
                                      telefono: telefono.text,
                                      latitud: lat,
                                      longitud: lng,
                                    ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.orangePrimary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                            child: Text(
                              taller == null
                                  ? 'Guardar taller'
                                  : 'Guardar cambios',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      resultado = await Navigator.of(context).push<Taller>(ruta);
      await ruta.completed;
    } finally {
      idTaller.dispose();
      nombre.dispose();
      direccion.dispose();
      telefono.dispose();
      latitud.dispose();
      longitud.dispose();
      _operacionEnCurso = false;
    }

    if (resultado == null) return;
    _operacionEnCurso = true;
    try {
      final ok = await _controller.guardarTaller(resultado);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? taller == null
                      ? 'Taller agregado correctamente.'
                      : 'Cambios guardados correctamente.'
                : _controller.error ?? 'No se pudo guardar el taller.',
          ),
          backgroundColor: ok ? null : Colors.red.shade700,
        ),
      );
    } finally {
      _operacionEnCurso = false;
    }
  }

  Widget _campo(
    String label,
    String hint,
    TextEditingController controller, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.labelDark,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          readOnly: readOnly,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.placeholderGray),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: AppColors.inputBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(
                color: AppColors.orangePrimary,
                width: 1.5,
              ),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
          ),
        ),
      ],
    );
  }
}

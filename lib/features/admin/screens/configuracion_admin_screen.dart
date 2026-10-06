import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:autofix/core/auth/sesion_admin.dart';
import 'package:autofix/core/database/semilla_inicial.dart';
import 'package:autofix/features/configuracion/presentation/configuracion_controller.dart';
import 'package:autofix/features/sync/sync_service.dart';
import 'package:autofix/shared/models/demo_admin_data.dart';
import 'package:autofix/shared/theme/app_colors.dart';

import 'dashboard_admin_screen.dart';
import 'citas_admin_screen.dart';

import 'package:autofix/features/auth/screens/login_screen.dart';

class ConfiguracionScreen extends StatefulWidget {
  /// ID del taller al que pertenece el administrador.
  ///
  /// Se inyecta desde la navegación (viene del LoginController/perfil de admin).
  /// En la rama actual (sin login real) se usa el primer taller de la semilla
  /// como valor por defecto temporal.
  final String? tallerId;

  const ConfiguracionScreen({super.key, this.tallerId});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  // Un solo controller para los tres catalogos que ya escriben en SQLite.
  // Tecnicos, Tipos de Servicio y Estados se leen y se escriben por aca; Marcas y
  // Grupos siguen leyendo `demo_admin_data.dart` (ver la nota de PAUSADO mas
  // abajo). La pantalla no toca un repositorio nunca.

  late final ConfiguracionController _cfg = ConfiguracionController(
    tallerId: widget.tallerId ?? SemillaInicial.talleres.first.id,
  );

  // Controladores solo para los campos de texto. Los de Tecnico, Tipo de
  // Servicio y Estado ya tienen boton conectado; los de Marca y Grupo todavia no.
  final TextEditingController _nombreServicioController =
      TextEditingController();
  final TextEditingController _precioServicioController =
      TextEditingController();
  final TextEditingController _tecnicoController = TextEditingController();
  final TextEditingController _marcaController = TextEditingController();
  final TextEditingController _grupoController = TextEditingController();

  // Solo para la demo visual del acordeón "Grupos de Servicios".
  bool _grupoDemoExpandido = true;

  @override
  void initState() {
    super.initState();
    // Sin `await`: la pantalla aparece de inmediato y el `ListenableBuilder`
    // muestra el estado que haya cuando terminen las lecturas. Una base local
    // tarda milisegundos y no amerita una pantalla de carga propia.
    _cfg.cargar();
  }

  @override
  void dispose() {
    _cfg.dispose();
    _nombreServicioController.dispose();
    _precioServicioController.dispose();
    _tecnicoController.dispose();
    _marcaController.dispose();
    _grupoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      drawer: _buildDrawer(context),
      // `ListenableBuilder` en vez de `setState`: el `setState` de esta pantalla
      // es para el acordeon de Grupos (que es estado puramente visual). Los datos
      // los decide el controller, y el solo avisa cuando hay que repintar. Asi el
      // estado de red de la base no se mezcla con el estado del diseno.
      body: ListenableBuilder(
        listenable: _cfg,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configuración del Sistema',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 16),
              _buildTiposDeServicioCard(),
              const SizedBox(height: 16),
              _buildListaSimpleCard(
                titulo: 'Técnicos',
                hint: 'Ej: Juan Pérez',
                controller: _tecnicoController,
                items: _cfg.tecnicos
                    .map((t) => (nombre: t.nombre, id: t.id))
                    .toList(),
                onAgregar: _agregarTecnico,
                onEliminar: _cfg.eliminarTecnico,
              ),
              const SizedBox(height: 16),
              // v7: Marcas paso de `demoMarcasConfiguracion` (const en
              // `demo_admin_data.dart`) a filas de la tabla `marcas`. El punto 6
              // del encargo define que la fuente es esta base. El `onAgregar` y el
              // `onEliminar` ya no son no-op: el boton esta cableado.
              _buildListaSimpleCard(
                titulo: 'Marcas de Vehículo',
                hint: 'Ej: Nissan',
                controller: _marcaController,
                items: _cfg.marcas
                    .map((m) => (nombre: m.nombre, id: m.id))
                    .toList(),
                onAgregar: _agregarMarca,
                onEliminar: _cfg.eliminarMarca,
              ),
              const SizedBox(height: 16),
              _buildGruposDeServiciosCard(),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // AppBar + Drawer
  // ---------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar() {
    final taller = SesionAdmin.instance.tallerNombre ?? 'SISTEMA DE GESTIÓN';
    final email = SesionAdmin.instance.adminEmail ?? 'Admin';
    final inicial = email.isNotEmpty ? email[0].toUpperCase() : 'A';

    return AppBar(
      backgroundColor: AppColors.headerNavy,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'AutoFix',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              taller.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: CircleAvatar(
            backgroundColor: AppColors.orangePrimary,
            radius: 18,
            child: Text(
              inicial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final taller = SesionAdmin.instance.tallerNombre ?? 'SISTEMA DE GESTIÓN';
    final email = SesionAdmin.instance.adminEmail ?? '';

    return Drawer(
      backgroundColor: AppColors.headerNavy,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AutoFix',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      taller,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.orangePrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _drawerItem(
              icon: Icons.grid_view_rounded,
              label: 'Dashboard',
              selected: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DashboardScreen()),
              ),
            ),
            _drawerItem(
              icon: Icons.calendar_today_outlined,
              label: 'Citas',
              selected: false,
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const CitasScreen())),
            ),
            _drawerItem(
              icon: Icons.settings_outlined,
              label: 'Configuración',
              selected: true,
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: TextButton.icon(
                onPressed: () async {
                  // `await` porque cerrar sesion ahora tambien borra la caché
                  // local de sesion: sin este orden el proximo arranque entraria
                  // solo al Dashboard y pareceria que el logout no sirvio.
                  await SesionAdmin.instance.cerrar();
                  await SyncService.instance.stop();
                  try {
                    await FirebaseAuth.instance.signOut();
                    await FirebaseAuth.instance.signInAnonymously();
                    await SyncService.instance.start();
                  } catch (_) {}
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  }
                },
                icon: const Icon(
                  Icons.logout,
                  size: 18,
                  color: Colors.redAccent,
                ),
                label: const Text(
                  'Cerrar Sesión',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Usa Material (no Container) para que el ListTile no lance el warning
  /// de "background color or ink splashes may be invisible".
  Widget _drawerItem({
    required IconData icon,
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    return Material(
      color: selected
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color: selected ? AppColors.orangePrimary : Colors.white70,
          size: 20,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.orangePrimary : Colors.white70,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        shape: selected
            ? const Border(
                left: BorderSide(color: AppColors.orangePrimary, width: 3),
              )
            : null,
      ),
    );
  }

  /// Contenedor blanco reutilizable para cada sección.
  Widget _sectionCard({required String titulo, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  /// Campo de texto + botón "Agregar".
  ///
  /// [onAgregar] en `null` deja el botón deshabilitado: es lo que necesitan las
  /// tarjetas que todavia no tienen persistencia (Marcas, Grupos), para que se
  /// vea igual que antes pero sin un botón que finja guardar y no guarde.
  Widget _buildCampoAgregar({
    required TextEditingController controller,
    required String hint,
    VoidCallback? onAgregar,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: _decoracionInput(hint),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: onAgregar,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orangePrimary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'Agregar',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    );
  }

  InputDecoration _decoracionInput(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: AppColors.placeholderGray,
        fontSize: 13,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: AppColors.orangePrimary,
          width: 1.5,
        ),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  // ---------------------------------------------------------------------
  // "Tipos de Servicio" — el formulario y el listado salen de SQLite.
  // ---------------------------------------------------------------------

  Widget _buildTiposDeServicioCard() {
    return _sectionCard(
      titulo: 'Tipos de Servicio',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nombreServicioController,
            decoration: _decoracionInput('Ej: Cambio de frenos'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _precioServicioController,
                  keyboardType: TextInputType.number,
                  decoration: _decoracionInput('Precio RD\$'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _agregarTipoServicio,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orangePrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Agregar',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_cfg.tiposServicio.isEmpty)
            const _AvisoSinRegistros()
          else
            for (final servicio in _cfg.tiposServicio)
              _filaItemDemo(
                nombre: servicio.nombre,
                precio: _cfg.formatearPrecio(servicio.precio),
                onEliminar: () => _confirmarEliminar(
                  'el servicio',
                  servicio.nombre,
                  () => _cfg.eliminarTipoServicio(servicio.id!),
                ),
              ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Secciones simples: Técnicos y Marcas de Vehículo.
  //
  // Cada item es un record `(nombre, id)` y el id es nullable por dos motivos:
  // las tarjetas en pausa (Marcas) traen datos de demo que no tienen id, y una
  // entidad recien insertada todavia no lo tiene. El id viaja con el nombre en
  // vez de buscarse: recorrer los catalogos para deducir cual fila se esta
  // borrando borra la equivocada en cuanto dos comparten nombre ('Frenos' puede
  // ser un tecnico y un tipo de servicio).
  //
  // `onAgregar` y `onEliminar` en `null` dejan la tarjeta en modo lectura, que
  // es lo que queda para Marcas mientras se decide su dueno.
  //
  // El `id` es `String?` desde la v7 (UUID), no `int?`. Ver
  // `lib/core/utils/uuid.dart`.
  // ---------------------------------------------------------------------

  Widget _buildListaSimpleCard({
    required String titulo,
    required String hint,
    required TextEditingController controller,
    required List<({String nombre, String? id})> items,
    VoidCallback? onAgregar,
    Future<bool> Function(String id)? onEliminar,
  }) {
    return _sectionCard(
      titulo: titulo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCampoAgregar(
            controller: controller,
            hint: hint,
            onAgregar: onAgregar,
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const _AvisoSinRegistros()
          else
            for (final item in items)
              _filaItemDemo(
                nombre: item.nombre,
                onEliminar: (onEliminar == null || item.id == null)
                    ? null
                    : () => _confirmarEliminar(
                        'el elemento',
                        item.nombre,
                        () => onEliminar(item.id!),
                      ),
              ),
        ],
      ),
    );
  }

  Widget _filaItemDemo({
    required String nombre,
    String? precio,
    VoidCallback? onEliminar,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F1F3))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            nombre,
            style: const TextStyle(fontSize: 13, color: AppColors.textDark),
          ),
          Row(
            children: [
              if (precio != null) ...[
                Text(
                  precio,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textGray,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              // El `X` sigue siendo el mismo icono del diseno: lo unico que
              // cambio es que ahora es tocable. Sin `onEliminar` (tarjetas en
              // pausa) se muestra igual, pero sin gesto, para no alterar la fila.
              if (onEliminar == null)
                const Icon(Icons.close, size: 16, color: Colors.redAccent)
              else
                InkWell(
                  onTap: onEliminar,
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 16, color: Colors.redAccent),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Acciones de las tarjetas con persistencia.
  //
  // Todas pasan por un `_guardar` comun: el controller devuelve `bool` y deja el
  // motivo en `error`. El `if (!mounted)` despues de cada `await` es
  // OBLIGATORIO, no opcional: entre el await y el `setState` el usuario puede
  // haber salido de la pantalla, y `context` sobre un State muerto revienta la
  // app con "setState() called after dispose()".
  //
  // NOTA v7: la accion de agregar ESTADOS se elimino con el catalogo. El estado
  // de una cita es el enum `EstadoCita`, cerrado y no editable; la seccion de
  // estados ya no existe ni en el diseno.
  // ---------------------------------------------------------------------

  Future<void> _agregarTecnico() async {
    final nombre = _tecnicoController.text;
    final ok = await _cfg.guardarTecnico(nombre);
    if (!mounted) return;
    if (ok) {
      _tecnicoController.clear();
    } else {
      _mostrarError();
    }
  }

  Future<void> _agregarTipoServicio() async {
    final ok = await _cfg.guardarTipoServicio(
      _nombreServicioController.text,
      _precioServicioController.text,
    );
    if (!mounted) return;
    if (ok) {
      _nombreServicioController.clear();
      _precioServicioController.clear();
    } else {
      _mostrarError();
    }
  }

  /// Alta de marca (punto 6). Mismo patron que [agregarTecnico]: limpia el campo si
  /// la escritura salio, muestra el error del controller si no.
  ///
  /// El mensaje de error lo pone `ConfiguracionController._validarNombre`, asi que
  /// aca no se distingue "campo vacio" de "ya existe": el controller ya sabe decir
  /// cual de las dos fue y el SnackBar lo muestra tal cual.
  Future<void> _agregarMarca() async {
    final ok = await _cfg.guardarMarca(_marcaController.text);
    if (!mounted) return;
    if (ok) {
      _marcaController.clear();
    } else {
      _mostrarError();
    }
  }

  /// Confirmación antes de borrar.
  ///
  /// El `X` estaba en el diseno sin confirmar nada, y eso no era problema cuando la
  /// fila era de prueba: un tap y se iba. Ahora la fila es una fila de verdad,
  /// asi que se pide confirmacion. El dialogo es un `AlertDialog` nativo, sin
  /// estilos propios, para no inventar un componente que el diseno no tiene.
  Future<void> _confirmarEliminar(
    String queEs,
    String nombre,
    Future<bool> Function() accion,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar'),
        content: Text('¿Estás seguro de eliminar $queEs "$nombre"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textGray),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final eliminado = await accion();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          eliminado
              ? 'Se eliminó "$nombre".'
              : _cfg.error ?? 'No se pudo eliminar.',
        ),
        backgroundColor: eliminado ? null : Colors.red.shade700,
      ),
    );
  }

  void _mostrarError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_cfg.error ?? 'No se pudo completar la operación.'),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // "Grupos de Servicios" (punto 6)
  //
  // QUÉ ESTÁ CONECTADO Y QUÉ NO:
  //
  // - El alta y la lista de GRUPOS sí están conectados: `_cfg.gruposServicio`
  //   viene de la tabla `grupos_servicio` y `_agregarGrupo` escribe en ella.
  // - El ACORDEÓN DE SERVICIOS sigue siendo el de `demoGruposServiciosAdmin`.
  //   Es lo único de esta tarjeta que NO toca la base, y a proposito: la relación
  //   grupo -> servicios necesita una tabla puente y la decisión de si un
  //   servicio puede estar en varios grupos, y esa decisión no está tomada. El
  //   doc de `GrupoServicio` la explica.
  //
  // Cuando se decida, el orden es: (1) tabla puente en la v8, (2) `obtenerServiciosDelGrupo`
  // en `GrupoServicioRepository`, (3) reemplazar `_grupoDemoExpandido` por el id del
  // grupo real y leer de ahi. Ese dia la lista de arriba y el acordeón pasan a
  // ser la misma fila.
  //
  // Por ahora el acordeón muestra `demoGruposServiciosAdmin.first` en vez del
  // primer grupo real, para que no se note el empalme: es la MISMA tarjeta con el
  // mismo texto que la v6 mostraba.
  // ---------------------------------------------------------------------

  Widget _buildGruposDeServiciosCard() {
    return _sectionCard(
      titulo: 'Grupos de Servicios',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCampoAgregar(
            controller: _grupoController,
            hint: 'Ej: Electricidad',
            onAgregar: _agregarGrupo,
          ),
          const SizedBox(height: 12),
          // Los grupos reales. El `X` los borra de verdad (con confirmacion,
          // igual que las marcas).
          for (final grupo in _cfg.gruposServicio)
            _filaItemDemo(
              nombre: grupo.nombre,
              onEliminar: () => _confirmarEliminar(
                'grupo de servicios',
                grupo.nombre,
                () => _cfg.eliminarGrupoServicio(grupo.id!),
              ),
            ),
          // El estado vacio se escribe en vez de dejar la tarjeta en blanco: un
          // espacio sin texto se lee como "la app fallo", y con la base recien
          // creada ese es un resultado legitimo.
          if (_cfg.gruposServicio.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Todavía no hay grupos de servicios.',
                style: TextStyle(
                  color: AppColors.textGray,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 12),
          _buildGrupoDemoAcordeon(),
        ],
      ),
    );
  }

  /// Alta de grupo de servicios. Sin precio: un grupo agrupa, no se cobra.
  Future<void> _agregarGrupo() async {
    final ok = await _cfg.guardarGrupoServicio(_grupoController.text);
    if (!mounted) return;
    if (ok) {
      _grupoController.clear();
    } else {
      _mostrarError();
    }
  }

  Widget _buildGrupoDemoAcordeon() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(
              demoGruposServiciosAdmin.first.nombre,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            leading: InkWell(
              onTap: () =>
                  setState(() => _grupoDemoExpandido = !_grupoDemoExpandido),
              child: AnimatedRotation(
                turns: _grupoDemoExpandido ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(
                  Icons.keyboard_arrow_down,
                  color: AppColors.textGray,
                ),
              ),
            ),
            trailing: const Icon(
              Icons.close,
              size: 18,
              color: Colors.redAccent,
            ),
          ),
          if (_grupoDemoExpandido) ...[
            for (final servicio in demoGruposServiciosAdmin.first.servicios)
              _filaItemDemo(nombre: servicio.nombre, precio: servicio.precio),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _abrirSelectorDeServiciosDemo,
                  icon: const Icon(
                    Icons.add,
                    size: 16,
                    color: AppColors.orangePrimary,
                  ),
                  label: const Text(
                    'Agregar Servicio',
                    style: TextStyle(
                      color: AppColors.orangePrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Modal de ejemplo "Seleccionar Servicios" — los checkboxes se pueden
  /// marcar/desmarcar (interacción básica), pero "Confirmar" solo cierra
  /// el modal, no guarda nada.
  void _abrirSelectorDeServiciosDemo() {
    final Set<String> seleccionados = {};
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Seleccionar Servicios',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...demoServiciosAdmin.map((servicio) {
                        final marcado = seleccionados.contains(servicio.nombre);
                        return CheckboxListTile(
                          value: marcado,
                          onChanged: (checked) {
                            setDialogState(() {
                              if (checked == true) {
                                seleccionados.add(servicio.nombre);
                              } else {
                                seleccionados.remove(servicio.nombre);
                              }
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            servicio.nombre,
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text(
                              'Cancelar',
                              style: TextStyle(color: AppColors.textGray),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context)
                                .pop(), // Solo cierra, no guarda.
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.orangePrimary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                            child: const Text('Confirmar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Texto que se muestra cuando una tarjeta no tiene filas.
///
/// No estaba en el diseno porque con data demo siempre habia algo que listar.
/// Sin el, la tarjeta se queda en blanco y no se distingue de una que todavia no
/// cargo: el usuario no sabe si fallo o si realmente no hay nada.
class _AvisoSinRegistros extends StatelessWidget {
  const _AvisoSinRegistros();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Sin registros',
        style: TextStyle(fontSize: 13, color: AppColors.placeholderGray),
      ),
    );
  }
}

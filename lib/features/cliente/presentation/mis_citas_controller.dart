import 'package:flutter/foundation.dart';

import 'package:autofix/core/auth/sesion_cliente.dart';
import 'package:autofix/features/citas/data/cita_repository.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/talleres/data/taller_repository.dart';

/// Una fila de "Mis citas", ya armada para la vista.
///
/// Va como DTO y no como `Cita` cruda por dos motivos que son decisiones de
/// diseno y no de datos: la etiqueta de estado se calcula UNA sola vez por
/// carga (si cada widget calculara `DateTime.now()` por su cuenta, dos filas
/// pintadas en milisegundos distintos podrian mostrar estados distintos para la
/// misma hora), y el nombre del taller se resuelve aca porque la vista no debe
/// abrir un repositorio para cada tarjeta.
class CitaClienteItem {
  const CitaClienteItem({
    required this.cita,
    required this.tallerNombre,
    required this.etiqueta,
    required this.enCola,
  });

  final Cita cita;

  /// Nombre del taller, ya resuelto contra la base local.
  final String tallerNombre;

  /// Texto que la vista pone en el badge ('Pendiente', 'ATRASADAS', ...).
  final String etiqueta;

  /// `true` si la cita (o su ultima modificacion) todavia no subio a la nube.
  final bool enCola;
}

/// "Mis citas" del cliente, 100% desde la base local.
///
/// ---------------------------------------------------------------
/// POR QUE ESTE CONTROLLER EXISTE APARTE DE [CitasController]
/// ---------------------------------------------------------------
/// [CitasController] es la pantalla del ADMIN: filtra por `SesionAdmin.tallerId`
/// y agrupa por dia para el acordeon. Este controller usa el correo del perfil
/// local para reunir citas creadas por el cliente y citas que el taller le
/// asignó desde el panel.
///
/// ---------------------------------------------------------------
/// DESCONEXION
/// ---------------------------------------------------------------
/// Los dos repositorios que consulta leen SQLite, no la nube, asi que esta
/// pantalla no puede fallar por falta de red: es la razón por la que no existe
/// ningún manejo de `FirebaseException` ni de timeouts acá. Lo que sí puede
/// fallar es la base local, y eso va a [error] con la lista intacta, para que
/// la vista muestre el reintento en vez de una pantalla en blanco.
class MisCitasController extends ChangeNotifier {
  MisCitasController({
    CitaRepository? citas,
    TallerRepository? talleres,
    String? correoCliente,
  }) : _citas = citas ?? CitaRepository.instance,
       _talleres = talleres ?? TallerRepository.instance,
       _correoCliente = (correoCliente ?? SesionCliente.instance.correo)
           ?.trim()
           .toLowerCase();

  final CitaRepository _citas;
  final TallerRepository _talleres;
  final String? _correoCliente;

  List<CitaClienteItem> _items = const <CitaClienteItem>[];
  bool _cargando = true;
  String? _error;
  int _pendientesDeSync = 0;

  List<CitaClienteItem> get items => List.unmodifiable(_items);
  bool get cargando => _cargando;
  String? get error => _error;

  /// Cuantas citas locales esperan subir. La vista lo muestra como aviso
  /// general: "se enviaran cuando vuelva la conexion".
  int get pendientesDeSync => _pendientesDeSync;
  bool get hayPendientes => _pendientesDeSync > 0;
  bool get hayCitas => _items.isNotEmpty;

  Future<void> cargar() async {
    _cargando = true;
    _error = null;
    notifyListeners();

    try {
      final ahora = DateTime.now();
      // Las dos lecturas son locales. Si la base esta corrupta o inaccesible,
      // la excepcion la agarra el catch de abajo y la lista anterior se
      // conserva: no se pinta una pantalla vacia por un error de disco.
      final citasLocales = await _citas.obtenerTodas();
      final correo = _correoCliente;
      // La base local puede contener citas de otro rol o de una cuenta usada
      // antes en el mismo dispositivo. Mis Citas siempre se aísla por el
      // correo del perfil, igual que el pull de Firestore por ownerUid.
      final citas = correo == null || correo.isEmpty
          ? const <Cita>[]
          : citasLocales
                .where(
                  (cita) => cita.correoCliente.trim().toLowerCase() == correo,
                )
                .toList(growable: false);
      final talleres = await _talleres.obtenerTodas();

      final nombres = <String, String>{
        for (final taller in talleres)
          if (taller.id != null) taller.id!: taller.nombre,
      };

      var pendientes = 0;
      final items = <CitaClienteItem>[];
      for (final cita in citas) {
        if (cita.syncStatus != 'synced') pendientes++;
        items.add(
          CitaClienteItem(
            cita: cita,
            tallerNombre: _nombreDelTaller(cita.tallerId, nombres),
            // Un solo `ahora` para toda la pasada, con la misma razon que en
            // `CitasController.agruparPorEstado`.
            etiqueta: cita.etiquetaUI(ahora),
            enCola: cita.syncStatus != 'synced',
          ),
        );
      }

      _items = _ordenarParaElCliente(items, ahora);
      _pendientesDeSync = pendientes;
    } on Exception catch (e) {
      _error = 'No pudimos leer tus citas guardadas en este dispositivo. ($e)';
    }

    _cargando = false;
    notifyListeners();
  }

  /// El nombre que se pinta en la tarjeta.
  ///
  /// Dos casos que devuelven texto distinto a proposito: sin `tallerId` la cita
  /// se creo antes de elegir taller (o sin taller), y con un id que no esta en
  /// la base local significa que el taller no esta en este dispositivo. Mezclar
  /// los dos en "Taller" le haria creer al usuario que todo esta bien cuando
  /// falta informacion.
  static String _nombreDelTaller(
    String? tallerId,
    Map<String, String> nombres,
  ) {
    if (tallerId == null) return 'Taller sin asignar';
    return nombres[tallerId] ?? 'Taller no disponible';
  }

  /// Proximas primero, pasadas despues.
  ///
  /// El orden "todo ascendente" dejaba las citas viejas (completadas hace
  /// meses) arriba de la cita de manana, que es la unica que al cliente le
  /// importa ver al abrir la pantalla. Y "todo descendente" hacia lo contrario.
  ///
  /// Dos grupos resuelven las dos cosas sin esconder ninguna cita: dentro de
  /// cada grupo el orden es estable respecto de la base, que ya viene por
  /// `fecha_cita DESC`.
  static List<CitaClienteItem> _ordenarParaElCliente(
    List<CitaClienteItem> items,
    DateTime ahora,
  ) {
    final diaDeHoy = DateTime(ahora.year, ahora.month, ahora.day);

    bool esFutura(CitaClienteItem item) =>
        !item.cita.fechaCita.toLocal().isBefore(diaDeHoy);

    final futuras = [
      for (final i in items)
        if (esFutura(i)) i,
    ]..sort((a, b) => a.cita.fechaCita.compareTo(b.cita.fechaCita));
    final pasadas = [
      for (final i in items)
        if (!esFutura(i)) i,
    ]..sort((a, b) => b.cita.fechaCita.compareTo(a.cita.fechaCita));

return [...futuras, ...pasadas];
  }

  /// Cancela una cita (borrado logico).
  ///
  /// Se permite si la cita esta en estado `pendiente` (el admin todavia no la
  /// acepto), `rechazada` (el admin la rechazo) o `completado` (la cita ya
  /// finalizo). Devuelve true si se cancelo correctamente.
  Future<bool> cancelarCita(String citaId) async {
    try {
      // Verificar que la cita existe y es del cliente actual
      final cita = await _citas.obtenerVigentePorId(citaId);
      if (cita == null) return false;

      // Permitir cancelar en pendiente, rechazada o completado
      if (cita.estado != EstadoCita.pendiente &&
          cita.estado != EstadoCita.rechazada &&
          cita.estado != EstadoCita.completado) {
        return false;
      }

      // Verificar que pertenece al cliente actual
      final correo = _correoCliente;
      if (correo == null || correo.isEmpty) return false;
      if (cita.correoCliente.trim().toLowerCase() != correo) return false;

      final filas = await _citas.eliminar(citaId);
      if (filas > 0) {
        await cargar(); // Recargar la lista
        return true;
      }
      return false;
    } on Exception {
      return false;
    }
  }
}

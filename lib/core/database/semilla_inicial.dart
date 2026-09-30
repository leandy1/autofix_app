/// Datos con los que nacen los catalogos de Configuracion.
///
/// Antes de la v3 estos valores vivian sueltos en `lib/models/demo_admin_data.dart`
/// y la pantalla los leia de ahi en cada build: se perdian al reinstalar y no se
/// podian editar de verdad. Con la v3 son filas reales de SQLite.
///
/// NO es data de prueba: es el catalogo inicial que el administrador del taller
/// recibe al instalar la app, y a partir de ahi lo edita y lo borra como quiera.
/// Se siembran una sola vez (en la creacion y en la migracion), y solo si la
/// tabla esta vacia, asi que volver a abrir la app no los duplica.
///
/// Los acentos van con su tilde a proposito: estas cadenas se muestran en
/// pantalla y tienen que coincidir con lo que eligio el diseno. Los COMENTARIOS
/// de este archivo, en cambio, van sin tilde, como el resto del proyecto.
///
/// Nota de alcance: 'Marcas' y 'Grupos de Servicios' siguen en modo demo porque
/// Marcas quedo en pausa hasta que el equipo defina si la fuente es la API web
/// de Andy o esta base. Por eso no hay lista de marcas aqui.
class SemillaInicial {
  SemillaInicial._();

  static const List<String> tecnicos = <String>[
    'Técnico 1',
    'Técnico 2',
    'Técnico 3',
  ];

  /// Los cinco estados que muestra el diseno de Configuracion.
  ///
  /// OJO: esta lista NO es la fuente de verdad de `citas.estado`. Ahi sigue
  /// mandando el enum `EstadoCita`, que es del modulo de Leandy. Esta tabla es
  /// el catalogo que el admin puede curar; hoy NO restringe que estados puede
  /// tomar una cita. Cuando se decida que el estado sea dinamico, esta tabla pasa
  /// a ser la fuente y hay que reemplazar el enum (ver la nota de `EstadoConfig`).
  static const List<String> estados = <String>[
    'Pendiente',
    'En diagnóstico',
    'En proceso',
    'Esperando pieza',
    'Completado',
  ];

  /// Precios en 0 a proposito: asi venían en el diseno, que mostraba 'RD$ —'
  /// porque todavia no se sabia cuanto cuesta cada trabajo. El admin les pone el
  /// precio real desde la pantalla.
  static const List<String> tiposServicio = <String>[
    'Cambio de aceite y filtro',
    'Frenos',
    'Suspensión y dirección',
    'Transmisión y caja',
    'Alineación y balanceo',
    'Cambio de gomas',
  ];

  static const int precioInicial = 0;
}

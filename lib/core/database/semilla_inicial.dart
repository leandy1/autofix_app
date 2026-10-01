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

  /// Talleres AFILIADOS de la red AutoFix (v4).
  ///
  /// Directriz de Leandy: NO se buscan talleres libres en el mundo. El mapa solo
  /// muestra los que estan en esta tabla, y por eso hay que sembrarla: sin
  /// semilla, un dispositivo nuevo abre el mapa y no ve ningun taller, que es
  /// indistinguible de "el mapa esta roto".
  ///
  /// NO es data de prueba: es la red de afiliados con la que se instala la app. A
  /// partir de ahi el administrador la edita y la da de baja como cualquier otro
  /// catalogo.
  ///
  /// Una sola lista de [TallerAfiliado] y no tres listas paralelas de
  /// nombre/direccion/coordenada: con las paralelas, agregar un taller y olvidar
  /// la coordenada no da error de compilacion, da un punto en medio del oceano.
  /// Con un registro, el compilador exige los cuatro campos juntos.
  ///
  /// "AutoFix Central" entra a proposito: `dashboard_cliente_screen.dart` lo tiene
  /// hardcodeado como taller preseleccionado y `agendar_cita_cliente_section.dart`
  /// lo busca con `firstWhere`. Si la semilla no lo contiene, esa pantalla revienta
  /// hasta que David migre el formulario a la base.
  static const List<TallerAfiliado> talleres = <TallerAfiliado>[
    // Santo Domingo, Gazcue: Av. 27 de Febrero con Av. Las Americas.
    TallerAfiliado(
      nombre: 'Global Refriauto',
      direccion: 'Av. 27 de Febrero esq. Las Américas, Gazcue',
      telefono: '809-555-0101',
      latitud: 18.4184,
      longitud: -69.9167,
    ),
    // Santo Domingo, Los Prados.
    TallerAfiliado(
      nombre: 'Taller Gómez',
      direccion: 'Calle Olof Palme, Los Prados',
      telefono: '809-555-0102',
      latitud: 18.4801,
      longitud: -69.8896,
    ),
    // Santiago de los Caballeros, centro.
    TallerAfiliado(
      nombre: 'AutoFix Central',
      direccion: 'Av. Independencia, Santiago de los Caballeros',
      telefono: '809-555-0103',
      latitud: 19.4517,
      longitud: -70.6970,
    ),
  ];

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

/// Un taller de la semilla, con los datos crudos.
///
/// Es un tipo propio y NO el `Taller` del dominio a proposito: la semilla se
/// escribe en el archivo de constantes, y un `Taller` obliga a pasar por
/// `EntidadPersistida`, que es un contrato de lo que YA esta en la base. Aqui no
/// hay nada persistido todavia. El mapeo de uno a otro lo hace el `DatabaseHelper`
/// al sembrar.
class TallerAfiliado {
  const TallerAfiliado({
    required this.nombre,
    required this.direccion,
    required this.telefono,
    required this.latitud,
    required this.longitud,
  });

  final String nombre;
  final String direccion;
  final String telefono;

  /// Coordenadas en grados decimales, con 4 decimales a proposito: 4 decimales
  /// equivalen a unos 11 metros, que es la precision razonable para "este local
  /// esta en esta esquina". Con 2 decimales el punto cae a mas de un kilómetro,
  /// que en una ciudad es otra calle.
  final double latitud;
  final double longitud;
}

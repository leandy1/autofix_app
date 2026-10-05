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
/// Nota de alcance: 'Marcas' y 'Grupos de Servicios' seguian en modo demo porque
/// Marcas quedo en pausa hasta que el equipo defina si la fuente es la API web
/// de Andy o esta base. Por eso no habia lista de marcas aqui (v7: ya se agrego).
///

/// Un taller de la semilla, con los datos crudos.
///
/// Es un tipo propio y NO el `Taller` del dominio a proposito: la semilla se
/// escribe en el archivo de constantes, y un `Taller` obliga a pasar por
/// `EntidadPersistida`, que es un contrato de lo que YA esta en la base. Aqui no
/// hay nada persistido todavia. El mapeo de uno a otro lo hace el `DatabaseHelper`
/// al sembrar.
///
/// v7: ahora incluye `id` (UUID v4 estatico). Antes el id se generaba al sembrar,
/// lo que creaba talleres con ids distintos en cada instalacion y rompia la
/// sincronizacion.
class TallerAfiliado {
  const TallerAfiliado({
    required this.id,
    required this.nombre,
    required this.direccion,
    required this.telefono,
    required this.latitud,
    required this.longitud,
  });

  /// UUID v4 estatico (RFC 4122). Identidad canonica del taller en todos los
  /// dispositivos. No se genera en tiempo de ejecucion.
  final String id;
  final String nombre;
  final String direccion;
  final String telefono;

  /// Coordenadas en grados decimales, y con 4 decimales o mas a proposito: 4
  /// decimales equivalen a unos 11 metros, que es la precision razonable para
  /// "este local esta en esta esquina". Con 2 decimales el punto cae a mas de un
  /// kilometro, que en una ciudad es otra calle. Si en Maps el punto viene con
  /// 6 o 7 decimales se copian tal cual: no hay nada que ganar redondeando.
  final double latitud;
  final double longitud;
}

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
  ///
  /// LOS IDS SON UUIDs ESTATICOS (v7). Antes se generaban con Uuid.instancia.generar()
  /// en cada instalacion, lo que creaba talleres distintos en cada dispositivo y
  /// rompia la sincronizacion: dos dispositivos tenian "Global Refriauto" con ids
  /// distintos y al sincronizar las citas se cruzaban. Con IDs fijos, todos los
  /// dispositivos comparten la misma identidad para cada taller de la red.
  ///
  /// Formato: UUID v4 valido (RFC 4122), version 4, variante RFC 4122.
  static const List<TallerAfiliado> talleres = <TallerAfiliado>[
    // Santo Domingo, Gazcue: Av. 27 de Febrero con Av. Las Americas.
    // Coordenadas reales, tomadas del punto del local en Google Maps. Se
    // corrigieron en esta rama: antes eran una aproximacion a la esquina y el
    // pin caia a unas cuadras del taller.
    TallerAfiliado(
      id: '11111111-1111-4111-8111-111111111111',
      nombre: 'Global Refriauto',
      direccion: 'Av. 27 de Febrero esq. Las Américas, Gazcue',
      telefono: '809-555-0101',
      latitud: 18.4624868,
      longitud: -69.9517036,
    ),
    // Santo Domingo, Los Prados.
    TallerAfiliado(
      id: '22222222-2222-4222-8222-222222222222',
      nombre: 'Taller Gómez',
      direccion: 'Calle Olof Palme, Los Prados',
      telefono: '809-555-0102',
      latitud: 18.4801,
      longitud: -69.8896,
    ),
    // Santiago de los Caballeros, centro.
    TallerAfiliado(
      id: '33333333-3333-4333-8333-333333333333',
      nombre: 'AutoFix Central',
      direccion: 'Av. Independencia, Santiago de los Caballeros',
      telefono: '809-555-0103',
      latitud: 19.4517,
      longitud: -70.6970,
    ),
  ];

  /// UUIDs estaticos para los tecnicos (orden 1:1 con [tecnicos]).
  ///
  /// v7: antes se generaban en la instalacion. IDs fijos garantizan que
  /// "Técnico 1" tenga la misma identidad en todos los dispositivos.
  static const List<String> tecnicosIds = <String>[
    '44444444-4444-4444-8444-444444444444',
    '55555555-5555-4555-8555-555555555555',
    '66666666-6666-4666-8666-666666666666',
  ];

  static const List<String> tecnicos = <String>[
    'Técnico 1',
    'Técnico 2',
    'Técnico 3',
  ];

  /// EN LA v7 SE ELIMINO `SemillaInicial.estados`, junto con la tabla, el modelo
  /// `EstadoConfig` y el `EstadoRepository`.
  ///
  /// Decision de Leandy, y hay una razon tecnica detras que no es "que no se
  /// usaba": aunque se hubiera usado, habria roto la app. El catalogo traia
  /// 'En diagnostico', que NO existe en el enum `EstadoCita` (que es el que de
  /// verdad decide el estado de una cita), y traia 'Esperando pieza' en minuscula
  /// contra el 'Esperando Pieza' del enum. El mapa de colores de la pantalla de
  /// Citas hace match por TEXTO EXACTO, asi que esa fila no tendria color: un
  /// estado visible sin color se lee como un bug de la pantalla.
  ///
  /// Un catalogo que contradice al enum no es data de mas: es una bomba de
  /// tiempo para el dia que alguien cablee `citas.estado` a el.

  /// UUIDs estaticos para los tipos de servicio (orden 1:1 con [tiposServicio]).
  ///
  /// UUIDs v4 validos (RFC 4122). Identidad canonica para sincronizacion.
  static const List<String> tiposServicioIds = <String>[
    '77777777-7777-4777-8777-777777777777', // Cambio de aceite y filtro
    '88888888-8888-4888-8888-888888888888', // Frenos
    '99999999-9999-4999-8999-999999999999', // Suspensión y dirección
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', // Transmisión y caja
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', // Alineación y balanceo
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc', // Cambio de gomas
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

  /// UUIDs estaticos para las marcas (orden 1:1 con [marcas]).
  static const List<String> marcasIds = <String>[
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd', // Toyota
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', // Honda
    'ffffffff-ffff-4fff-8fff-ffffffffffff', // Ford
    '00000000-0000-4000-8000-000000000001', // Hyundai
    '00000000-0000-4000-8000-000000000002', // Suzuki
  ];

  /// Marcas de vehiculo (punto 6 del encargo).
  ///
  /// v7: antes eran `demoMarcasVehiculo`, una `const List<String>` en
  /// `lib/shared/models/demo_admin_data.dart`, y la pantalla de Configuracion las
  /// pintaba de ahi. No eran filas, nadie las podia editar, y cada rebuild las
  /// volvia a poner. Ahora son filas con UUID, y la lista de demo se elimina.
  ///
  /// Los textos son los MISMOS que tenia la lista de demo a proposito: el
  /// switch a la tabla no debe cambiar ni una palabra de lo que ve el admin. Los
  /// acentos van con su tilde porque estas cadenas se muestran en pantalla, como
  /// en el resto del archivo.
  static const List<String> marcas = <String>[
    'Toyota',
    'Honda',
    'Ford',
    'Hyundai',
    'Suzuki',
  ];

  /// UUIDs estaticos para los grupos de servicio (orden 1:1 con [gruposServicio]).
  static const List<String> gruposServicioIds = <String>[
    '00000000-0000-4000-8000-000000000003', // Carrocería
  ];

  /// Grupos de servicios (punto 6 del encargo).
  ///
  /// v7: antes era `demoGruposServiciosAdmin`, una `const` con UN solo grupo
  /// ('Carrocería') y sus servicios escritos a mano. Ahora el grupo es una fila con
  /// UUID.
  ///
  /// Lo que NO se siembra es la lista de servicios que pertenece a cada grupo: esa
  /// relacion necesita una tabla puente que todavia no se ha decidido (ver el doc
  /// de `GrupoServicio`). Sembrarla aqui como texto JSON seria comprometerse con
  /// una decision que Leandy no ha tomado, y cambiar de opinion despues exigiria
  /// otra migracion.
  static const List<String> gruposServicio = <String>['Carrocería'];
}

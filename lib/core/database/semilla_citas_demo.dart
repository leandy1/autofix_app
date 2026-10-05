import 'package:autofix/core/utils/uuid.dart';
import 'package:autofix/features/citas/models/cita.dart';
import 'package:autofix/features/citas/models/codigo_de_cita.dart';

/// Generador de citas de DEMOSTRACION para poder ver el Dashboard con numeros.
///
/// ESTO SI ES DATA DE PRUEBA, a diferencia de `SemillaInicial`. Alli viven los
/// catalogos que el taller recibe al instalar la app (talleres, tecnicos,
/// servicios), y esos son reales. Esto no: son clientes, placas e ingresos
/// inventados, y por eso NO se siembra en `_crearEsquema` ni en `_migrar`.
///
/// La razon de separarlo no es purismo. Si se metiera en la semilla inicial,
/// cada instalacion real de la app abriria el Dashboard del administrador con
/// ~100 clientes que no existen y una linea de "INGRESOS" que no es de nadie,
/// y el admin no tendria forma de distinguir eso de su negocio real. Ademas
/// romperia los tests de `cita_repository_test.dart`, que asumen que una base
/// recien creada no tiene citas.
///
/// Se activa a mano con `DatabaseHelper.sembrarCitasDemo()`, que solo se llama
/// desde `main.dart` en modo debug. En release no corre, y los tests no la
/// llaman, asi que la suite sigue probando contra una base vacia.
///
/// -----------------------------------------------------------------
/// CAMBIOS v7: LOS IDS SON DETERMINISTAS Y MARCADOS COMO DEMO
/// -----------------------------------------------------------------
///
/// Antes cada cita se insertaba sin id y SQLite le ponia el siguiente
/// autoincremento: 1, 2, 3... Con la PK en TEXT eso ya no pasa, y hay que
/// decidir algo.
///
/// Se eligio [Uuid.dePrueba] con un indice, en vez de un UUID aleatorio, por dos
/// razones que las pruebas necesitan:
///
/// 1. DETERMINISMO. La semilla ya usaba un `_Rng` con semilla fija para que el
///    lote fuera siempre el mismo. Si los ids fueran aleatorios, dos corridas
///    darian el mismo lote de citas con ids distintos, y un test que dice "la
///    cita demo-0042 tiene total 2200" dejaria de poder afirmar nada.
///
/// 2. MARCA DE DEMO. El prefijo `demo-` es lo que permite que la sincronizacion
///    NO suba esta data a Firestore. Sin el, habria que agregar una columna
///    `es_demo` a la tabla y mantenerla coherente con el borrado de la semilla;
///    con el, `Uuid.esDemo(cita.id)` responde la pregunta. Menos estado que puede
///    quedar desincronizado.
///
/// La consecuencia de que el lote sea identico en cada instalacion es que dos
/// dispositivos tienen los mismos ids de cita demo. No es un problema porque
/// ninguno sube esos ids a la nube.
///
/// Las fechas son RELATIVAS a un dia de referencia (por defecto, hoy): si
/// fueran fijas, en dos semanas la app abriria con el Dashboard en '--' y no
/// habria nada que ver. Por eso el paso 3 es relativo y no absoluto.
class SemillaCitasDemo {
  SemillaCitasDemo._();

  /// Cuantos dias hacia atras se generan citas. 60 dias dan historia suficiente
  /// para que el grafico que se viene despues tenga una linea con forma, sin
  /// llenar la base de miles de filas que nadie mira.
  static const int diasHaciaAtras = 60;

  /// Cuantos dias hacia adelante. Mas corto que el historico a proposito: un
  /// taller agenda a pocos dias, no a dos meses.
  static const int diasHaciaAdelante = 14;

  /// Citas de HOY. Se fijan a mano en vez de al azar porque son las que el
  /// administrador mira primero al abrir la app: si hoy saliera con cero o con
  /// veinte, la pantalla no se puede auditar.
  static const int citasDeHoy = 8;

  /// Indice del proximo UUID de demo a usar.
  static int _indiceDemo = 0;

  /// Obtiene el siguiente UUID de demo de forma determinista usando los UUIDs
  /// pre-generados de [Uuid.demoIds] (150 UUIDs v4 validos, RFC 4122).
  ///
  /// Estos son los MISMOS UUIDs que usa `Uuid.esDemo()` para detectar data de demo
  /// en la sincronizacion. Garantiza: (1) son UUIDs v4 validos, (2) son unicos,
  /// (3) coinciden con el Set de deteccion en `Uuid.esDemo()`.
  static String _proximoUuidDemo() {
    final ids = Uuid.demoIds.toList();
    if (_indiceDemo >= ids.length) {
      throw StateError(
        'Se agotaron los UUIDs de demo pre-generados (${ids.length}). '
        'Aumenta la lista en Uuid.demoIds.',
      );
    }
    return ids[_indiceDemo++];
  }

  /// Verifica si un ID pertenece a la data de demo.
  ///
  /// v7: delega a [Uuid.esDemo()] que usa el mismo Set de 150 UUIDs v4 validos
  /// pre-generados. Esto permite que la sincronizacion salte la data de demo
  /// sin una columna extra `es_demo`.
  static bool esDemo(String id) => Uuid.esDemo(id);

  /// Genera el lote completo de citas de demostracion.
  ///
  /// [tallerIds] son los ids reales de `talleres` que el `DatabaseHelper` resolvio
  /// por nombre. Se-cyclean entre citas para que los numeros tambien sirvan
  /// para revisar el filtro por taller. Si viene vacio, las citas quedan sin
  /// taller (`taller_id = null`), que es un estado legitimo del modelo.
  ///
  /// [referencia] es el ancla temporal. Se pasa explicita (y no `DateTime.now()`
  /// adentro) para que un test pueda fijar la fecha y verificar que "hoy" cae
  /// donde dice caer.
  ///
  /// Cada cita sale con `id` de prueba (UUID v4 valido de demo) y
  /// `codigoVisible` numerado como si la nube ya lo hubiera confirmado. Se numeran
  /// aqui porque el Dashboard del debug se audita a ojo y ver 100 citas en
  /// 'PENDIENTE' no dice nada del grafico. En la app real el numero lo asigna
  /// Firestore.
  static List<Cita> generar({
    required DateTime referencia,
    required List<String> tallerIds,
  }) {
    _indiceDemo = 0; // Reset para determinismo total en cada llamada.

    final rng = _Rng(20261002);
    final hoy = DateTime(referencia.year, referencia.month, referencia.day);
    final citas = <Cita>[];

    // -------------------------------------------------------------------
    // Pasado: de 60 dias atras a ayer.
    // -------------------------------------------------------------------
    for (var d = diasHaciaAtras; d >= 1; d--) {
      final dia = hoy.subtract(Duration(days: d));
      final cuantas = 1 + rng.siguiente(3);
      for (var i = 0; i < cuantas; i++) {
        citas.add(
          _armar(
            rng: rng,
            fecha: DateTime(
              dia.year,
              dia.month,
              dia.day,
              8 + rng.siguiente(9),
              _minutoDeTaller(rng),
            ),
            estado: _estadoPasado(rng, diasDeDistancia: d),
            tallerIds: tallerIds,
            indice: citas.length,
          ),
        );
      }
    }

    // -------------------------------------------------------------------
    // HOY: horarios de taller (08:00 a 17:00) y los cuatro estados.
    // -------------------------------------------------------------------
    for (var i = 0; i < citasDeHoy; i++) {
      citas.add(
        _armar(
          rng: rng,
          fecha: DateTime(
            hoy.year,
            hoy.month,
            hoy.day,
            8 + i,
            _minutoDeTaller(rng),
          ),
          // Reparto fijo y no al azar: 3 completadas, 2 en proceso, 2 pendientes
          // y 1 esperando pieza. Asi "INGRESOS DEL DIA" y "COMPLETADAS HOY" tienen
          // algo que mostrar siempre, y sigue habiendo de las otras para que la
          // tabla no salga toda verde.
          estado: const <EstadoCita>[
            EstadoCita.completado,
            EstadoCita.enProceso,
            EstadoCita.completado,
            EstadoCita.pendiente,
            EstadoCita.esperandoPieza,
            EstadoCita.completado,
            EstadoCita.pendiente,
            EstadoCita.enProceso,
          ][i],
          tallerIds: tallerIds,
          indice: citas.length,
        ),
      );
    }

    // -------------------------------------------------------------------
    // Futuro: agendado, nunca completado.
    // -------------------------------------------------------------------
    for (var d = 1; d <= diasHaciaAdelante; d++) {
      final dia = hoy.add(Duration(days: d));
      final cuantas = 1 + rng.siguiente(3);
      for (var i = 0; i < cuantas; i++) {
        citas.add(
          _armar(
            rng: rng,
            fecha: DateTime(
              dia.year,
              dia.month,
              dia.day,
              8 + rng.siguiente(9),
              _minutoDeTaller(rng),
            ),
            // Una cita del futuro no puede estar 'Completada': se completaria
            // solo con el paso del tiempo, sin que nadie la haya tocado. Y sin
            // completadas, la suma de ingresos del futuro da 0, que es lo
            // correcto.
            estado: const <EstadoCita>[
              EstadoCita.pendiente,
              EstadoCita.esperandoPieza,
              EstadoCita.pendiente,
              EstadoCita.enProceso,
            ][rng.siguiente(4)],
            tallerIds: tallerIds,
            indice: citas.length,
          ),
        );
      }
    }

    // El orden por `fechaCita` NO cambia los ids: el id se asigno antes de
    // ordenar, con el indice de generacion. Asi el test que busca el `demo-0007`
    // lo encuentra siempre con la misma cita, ordene o no la lista.
    citas.sort((a, b) => a.fechaCita.compareTo(b.fechaCita));
    return citas;
  }

  /// Estado de una cita del pasado.
  ///
  /// Las que se quedaron sin completar son las que `Cita.esAtrasada` marca como
  /// ATRASADAS, asi que este reparto es lo que le da contenido a esa tarjeta.
  ///
  /// [diasDeDistancia] amortigua el desorden conforme la cita se acerca a hoy:
  /// un taller va limpiando su bandeja, y si el 30% de las citas de la semana
  /// pasada siguiera abierta, el dato de atrasadas seria ruido, no informacion.
  ///
  /// Las abiertas se reparten en tres bandas IGUALES sobre el sobrante, y no con
  /// cortes fijos. Los cortes fijos tienen el detalle de que, con una ventana
  /// chica (3 de cada 100), `peso < 100 - 3 + 3` se cumple siempre y las dos
  /// ultimas ramas quedan sin codigo alcanzable: `esperandoPieza` y `pendiente`
  /// no salen nunca en la ultima semana, y una rama muerta aqui es una rama que
  /// nadie nota que dejo de usarse.
  static EstadoCita _estadoPasado(_Rng rng, {required int diasDeDistancia}) {
    // 3 de cada 100 quedan abiertas en la ultima semana; 10 antes de eso.
    final abiertas = diasDeDistancia <= 7 ? 3 : 10;
    final peso = rng.siguiente(100);
    if (peso < 100 - abiertas) return EstadoCita.completado;

    final banda = (peso - (100 - abiertas)) * 3 ~/ abiertas;
    return switch (banda) {
      0 => EstadoCita.enProceso,
      1 => EstadoCita.esperandoPieza,
      _ => EstadoCita.pendiente,
    };
  }

  static Cita _armar({
    required _Rng rng,
    required DateTime fecha,
    required EstadoCita estado,
    required List<String> tallerIds,
    required int indice,
  }) {
    final cliente = _clientes[rng.siguiente(_clientes.length)];
    final vehiculo = _vehiculos[rng.siguiente(_vehiculos.length)];
    final servicios = _servicios[rng.siguiente(_servicios.length)];

    // El `total` va SIEMPRE, completada o no: es el precio cotizado y existe
    // desde que se agenda. Lo que decide si esa plata entro o no es el estado,
    // no el monto. Por eso el filtro de ingresos tiene sentido, y por eso una
    // cita 'Pendiente' con total cargado es normal y no un dato sucio.
    final total = rng.siguiente(20) == 0
        ? 0
        : _montos[rng.siguiente(_montos.length)];

    return Cita(
      // `_proximoUuidDemo` y no `Uuid.instancia.generar()`: el lote tiene que ser
      // identico en cada corrida y, sobre todo, tiene que ser reconocible como
      // data de mentira para que la sincronizacion lo salte.
      //
      // v7: ahora devuelve UUID v4 valido (RFC 4122), no `demo-XXXX`. La
      // deteccion de demo es por pertenencia al Set `_idsDemoSet` (ver `esDemo`).
      id: _proximoUuidDemo(),
      // El numero se ve numerado en el Dashboard del debug. En la app real llega
      // 'PENDIENTE' y lo reemplaza el `onSnapshot`.
      codigoVisible: formatearCodigoCita(indice + 1),
      cliente: cliente.$1,
      telefono: cliente.$2,
      vehiculo: vehiculo.$1,
      marca: vehiculo.$2,
      modelo: vehiculo.$3,
      anio: vehiculo.$4,
      placa: _placas[rng.siguiente(_placas.length)],
      servicios: servicios,
      tecnico: _tecnicos[rng.siguiente(_tecnicos.length)],
      descripcion: '',
      fechaCita: fecha.toUtc(),
      estado: estado,
      tallerId: tallerIds.isEmpty
          ? null
          : tallerIds[rng.siguiente(tallerIds.length)],
      creadoEn: fecha.subtract(const Duration(days: 2)).toUtc(),
      actualizadoEn: fecha.toUtc(),
      total: total,
    );
  }

  /// Minutos que parecen una hora real de taller (0, 15, 30, 45) y no
  /// ':07:23' de un numero aleatorio.
  static int _minutoDeTaller(_Rng rng) =>
      const <int>[0, 15, 30, 45][rng.siguiente(4)];

  static const List<(String, String)> _clientes = <(String, String)>[
    ('Luis Castillo', '809-555-0201'),
    ('María Pérez', '809-555-0202'),
    ('Pedro Núñez', '809-555-0203'),
    ('Isabel Reyes', '809-555-0204'),
    ('Natalia Flores', '809-555-0205'),
    ('Lucía Medina', '809-555-0206'),
    ('Carlos Jiménez', '809-555-0207'),
    ('Ana Torres', '809-555-0208'),
    ('Rafael Ortiz', '809-555-0209'),
    ('Yoselin Peña', '809-555-0210'),
    ('Miguel Santos', '829-555-0211'),
    ('Carmen Díaz', '849-555-0212'),
    ('Jorge Batista', '809-555-0213'),
    ('Rosa Martínez', '849-555-0214'),
    ('Andrés Guerrero', '829-555-0215'),
    ('Paola Herrera', '849-555-0216'),
    ('Eduardo Vargas', '849-555-0217'),
    ('Kimberly Ruiz', '809-555-0218'),
    ('Franklin Sánchez', '829-555-0219'),
    ('Yamilé Peña', '829-555-0220'),
  ];

  /// (vehiculo, marca, modelo, anio)
  static const List<(String, String, String, int)> _vehiculos =
      <(String, String, String, int)>[
        ('Toyota RAV4', 'Toyota', 'RAV4', 2021),
        ('Toyota Hilux', 'Toyota', 'Hilux', 2020),
        ('Honda CR-V', 'Honda', 'CR-V', 2022),
        ('Honda Civic', 'Honda', 'Civic', 2021),
        ('Ford Edge', 'Ford', 'Edge', 2019),
        ('Ford Ranger', 'Ford', 'Ranger', 2022),
        ('Suzuki Jimny', 'Suzuki', 'Jimny', 2023),
        ('Hyundai Tucson', 'Hyundai', 'Tucson', 2021),
        ('Nissan Sentra', 'Nissan', 'Sentra', 2020),
        ('Jeep Wrangler', 'Jeep', 'Wrangler', 2018),
        ('Mazda CX-5', 'Mazda', 'CX-5', 2022),
        ('Chevrolet Aveo', 'Chevrolet', 'Aveo', 2017),
        ('Kia Sportage', 'Kia', 'Sportage', 2021),
        ('Mitsubishi Outlander', 'Mitsubishi', 'Outlander', 2020),
        ('Toyota Corolla', 'Toyota', 'Corolla', 2019),
      ];

  /// Placas de Republica Dominicana: una letra y seis digitos.
  static const List<String> _placas = <String>[
    'A456789',
    'B567890',
    'E567890',
    'F678901',
    'G789012',
    'H890123',
    'J901234',
    'K012345',
    'L234567',
    'M345678',
    'N456789',
    'P567890',
    'R890123',
    'S901234',
    'T012345',
  ];

  static const List<List<String>> _servicios = <List<String>>[
    <String>['Cambio de aceite y filtro'],
    <String>['Frenos', 'Revisión general'],
    <String>['Alineación y balanceo'],
    <String>['Suspensión y dirección'],
    <String>['Transmisión y caja'],
    <String>['Cambio de gomas'],
    <String>['Cambio de aceite y filtro', 'Alineación y balanceo'],
    <String>['Frenos', 'Suspensión y dirección'],
  ];

  static const List<String> _tecnicos = <String>[
    'Técnico 1',
    'Técnico 2',
    'Técnico 3',
  ];

  /// Montos en pesos dominicanos, redondos. Se eligen de una lista y no se
  /// calcula al azar para que los ingresos salgan en cifras que un humano
  /// reconoce como un taller real.
  static const List<int> _montos = <int>[
    850,
    1200,
    1500,
    1800,
    2200,
    2500,
    2800,
    3200,
    3500,
    4000,
    4500,
    5000,
    6500,
    8000,
  ];
}

/// LCG minimo para generar la semilla.
///
/// Un `Random()` sin semilla daria un lote distinto en cada ejecucion, y eso
/// rompe dos cosas: un test que espera "mas de 50 citas" no puede afirmar nada,
/// y al probar la UI un cambio de numero no se sabe si fue un bug o la
/// semilla. Con semilla fija, el mismo codigo produce siempre el mismo taller.
class _Rng {
  _Rng(int semilla) : _estado = semilla & 0x7FFFFFFF;

  int _estado;

  /// Entero en `[0, max)`. Si `max` es 0 devuelve 0, para no tirar una
  /// excepcion de division en un dato de prueba.
  int siguiente(int max) {
    if (max <= 0) return 0;
    _estado = (_estado * 1664525 + 1013904223) & 0x7FFFFFFF;
    return _estado % max;
  }
}

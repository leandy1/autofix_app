/// Estandarizacion de tiempo: TODO lo que se persiste es UTC.
///
/// -----------------------------------------------------------------
/// POR QUE
/// -----------------------------------------------------------------
///
/// La v7 introduce sincronizacion entre dispositivos, y con ella el problema que
/// justificaba toda la arquitectura Offline-First.
///
/// Hasta la v6 el tiempo solo vivia en un dispositivo: `fecha_cita` se escribia
/// con el reloj local, se leia con el reloj local y se comparaba con el reloj
/// local. Tres watches, tres husos, un dashboard con "COMPLETADAS HOY" que de
/// pronto difieren.
///
/// El caso concreto que motivó el cambio:
///
///   - Un celular en Santo Domingo (UTC-4) agenda una cita para las 3:00 PM y
///     guarda `2026-10-05T15:00:00.000` (hora LOCAL, sin offset).
///   - El celular de otro taller, tambien en UTC-4, recibe esa cita por la nube y
///     la guarda tal cual.
///   - Todo parece bien porque los dos estan en el mismo huso.
///
/// ...hasta que uno de los dos cruza el pais, o un cliente con cita en otra
/// region. Entonces el mismo instante tiene dos representaciones distintas y el
/// `GROUP BY fecha_cita` del Dashboard cuenta la cita en dos dias.
///
/// La regla que se aplica en TODA la app a partir de ahora:
///
///   - Lo que se ESCRIBE en SQLite y en Firestore es UTC.
///   - Lo que se LEE de las bases vuelve en UTC.
///   - La conversion a hora local ocurre en el ULTIMO momento, en la capa que
///     pinta, y solo para mostrar.
///   - `fecha_cita` es la excepcion documentada: es un INSTANTE de una cita que
///     el usuario eligio escribiendo "el jueves a las 3", y se guarda como UTC a
///     proposito para que sea comparable entre dispositivos. Para MOSTRARLA se
///     convierte a hora local en la capa de pintado, nunca en el modelo.
///
/// -----------------------------------------------------------------
/// POR QUE NO BASTA CON `toUtc()`
/// -----------------------------------------------------------------
///
/// `toUtc()` convierte, pero el reloj de un celular puede estar mal en horas. En
/// un dispositivo de prueba nuevo la fecha inicializada por el fabricante es la
/// de la ultima compilacion del firmware, que puede ser de hace meses. Por eso
/// el reloj local NO es la fuente de la verdad en la nube: ahi manda
/// `FieldValue.serverTimestamp()`, que es el reloj del servidor de Google. Ver
/// `lib/features/citas/data/cita_repository.dart` y el `SyncService`.
library;

/// Instante actual en UTC.
///
/// Punto unico de entrada al reloj de la app.
///
/// Existe para que [DateTime.now] no aparezca suelto en 40 lugares. Cada
/// aparicion suelta es un `DateTime.now()` que alguien va a "optimizar" poniendole
/// `.toLocal()` y rompe la comparacion entre dispositivos.
///
/// Y para que los tests puedan controlarlo: [Reloj] se puede congelar, asi que
/// un test de migracion o de conflicto de timestamps no depende de la hora en que
/// corrio.
class Reloj {
  Reloj({DateTime Function()? ahora}) : _ahora = ahora ?? _relojDelSistema;

  final DateTime Function() _ahora;

  /// Instancia compartida. Toda la app pasa por aca.
  static final Reloj instancia = Reloj();

  /// Ahora, en UTC.
  DateTime ahora() => _ahora().toUtc();

  static DateTime _relojDelSistema() => DateTime.now();

  /// Reloj congelado, para tests y para semillas deterministas.
  ///
  /// Devolver SIEMPRE el mismo instante es lo que hace que un test pueda
  /// afirmar sobre `actualizado_en` sin tener que compararlo con "antes de
  /// correr".
  factory Reloj.congelado(DateTime instante) =>
      Reloj(ahora: () => instante.toUtc());
}

/// ISO 8601 en UTC, el formato con el que se escribe en SQLite y en Firestore.
///
/// `toIso8601String()` ya escribe `Z` cuando el DateTime es UTC, asi que la
/// conversion previa no es decorativa: es la que hace que aparezca la `Z`.
///
/// Se centraliza porque el string es la CLAVE por la que se comparan fechas en
/// SQL. Los timestamps ISO ordenan lexicograficamente en el mismo orden que
/// cronologicamente, siempre que todos esten en UTC y con el mismo numero de
/// decimales. Mezclar un `Z` con un offset local (`-04:00`) rompe ese orden, y el
/// sintoma es un `obtenerDelDia` que devuelve la mitad de las filas.
String aIsoUtc(DateTime instante) => instante.toUtc().toIso8601String();

/// Lee un ISO que venga de la base.
///
/// Devuelve UTC siempre, sin importar como venga escrito, por el mismo motivo de
/// arriba: la comparacion tiene que ser consistente aunque la fila se haya
/// escrito con otro reloj.
///
/// `null` en vez de una excepcion: una fila con `creado_en` vacio tiene que poder
/// LEERSE para que el administrador la arregle, no reventar la consulta entera.
DateTime? desdeIso(Object? bruto) {
  if (bruto is! String || bruto.isEmpty) return null;
  final leido = DateTime.tryParse(bruto);
  if (leido == null) return null;
  return leido.toUtc();
}

/// Instante actual ya formateado, que es lo que se escribe en el mapa.
String ahoraIso() => aIsoUtc(Reloj.instancia.ahora());

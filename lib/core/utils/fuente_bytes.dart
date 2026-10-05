import 'dart:math';

/// Fuente de entropia criptografica para los UUID.
///
/// -----------------------------------------------------------------
/// POR QUE ESTA AISLADA
/// -----------------------------------------------------------------
///
/// Los tests necesitan dos cosas que la app real no:
///
///   1. UUIDs DETERMINISTAS. `SemillaCitasDemo.generar()` tiene que devolver
///      siempre el mismo lote, porque hay tests que asertan que "la cita 1 del
///      dia 3 tiene tal total" y un lote distinto en cada corrida los hace fallar
///      sin que haya cambiado nada.
///
///   2. Poder PROBAR que dos ids distintos no colisionan. Eso requiere miles de
///      ids, y con `Random.secure()` cada corrida daria un conjunto diferente:
///      el test solo pasaria por suerte, que es la forma mas lenta de test.
///
/// Por eso la entropia se pasa por parametro. En la app es [Random.secure], que
/// es lo que corresponde; en los tests es un `Random(1)`.
/// -----------------------------------------------------------------

/// Genera bytes aleatorios crudos.
///
/// Se declara aqui y no se importa `dart:math` en cada archivo que lo use para
/// que quede explicito que la diferencia entre produccion y test es SOLO el
/// reloj que se le pasa.
typedef FuenteBytes = int Function(int max);

/// UNA sola instancia, estatica y perezosa.
///
/// `Random.secure()` constructs un generador nuevo y cada construccion pide
/// entropia al sistema operativo. El original lo pedia en CADA byte de CADA UUID,
/// o sea unas 16 llamadas al OS por id: en un seeding de 200 filas son 3,200
/// syscalls de entropia, que en Android no es gratis y ademas es el camino
/// tipico a un `PERFORMANCE WARNING` en un gama baja.
///
/// La instancia se reutiliza porque `Random.secure()` YA es un generador
/// criptografico con estado: no hace falta uno nuevo por llamada, y reutilizarlo
/// es justamente lo que se recomienda.
///
/// `final` con inicializador y SIN `late`: en Dart los campos con inicializador ya
/// son perezosos, se evaluan la primera vez que se leen. Por eso importar el
/// archivo no pide entropia al sistema en un test que nunca genera un UUID real,
/// y por eso el linter marca `late` como innecesario aca (`unnecessary_late`).
final Random _seguro = Random.secure();

/// `Random.secure().nextInt`. Entropia del sistema: la unica aceptable en
/// produccion.
///
/// Se declara como FUNCION y no como variable que guarda una closure (`final
/// FuenteBytes bytesSeguros = (max) => ...`) por dos razones: el linter
/// `prefer_function_declarations_over_variables` lo pide, y una funcion
/// declarada no necesita ser INVOCADA para obtener el closure, mientras que la
/// variable obliga a recordarlo en cada uso.
int bytesSeguros(int max) => _seguro.nextInt(max);

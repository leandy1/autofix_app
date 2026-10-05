/// Codigo que el HUMANO lee, separado del id que la BASE usa.
///
/// -----------------------------------------------------------------
/// EL PROBLEMA QUE RESUELVE
/// -----------------------------------------------------------------
///
/// Desde la v7 el id de una cita es un UUID: 36 caracteres, un guion cada ocho
/// letras, nada que ver con una placa.
///
/// Eso es correcto para la base y para Firestore, e inservible para pantalla.
/// Antes se mostraba `REC-000042`, generado por autoincremento, y ese numero era
/// exactamente lo que el administrador leia al telefono ("buscame la 42"), lo que
/// escribia en la hoja, y lo que el cliente dictaba. Si se hubiera asignado el
/// numero con autoincremento en cada dispositivo, cada uno tendria el 1, el 2 y
/// el 3, y dos talleres comparando su cita 3 creerian que es la misma orden. Un
/// numero que se ve en
/// pantalla tiene que ser unico en la nube.
///
/// Por eso hay DOS identificadores con trabajos distintos:
///
///   - `id` (UUID): clave foranea, la que usan los JOIN y los documentos de
///     Firestore. Se genera en el cliente, sin red, y nunca cambia.
///   - `codigoVisible` ("CITA-0004"): lo que se muestra y lo que se dicta. Es
///     secuencial y por eso NO se puede generar sin la nube.
///
/// -----------------------------------------------------------------
/// LA SECUENCIA DIFERIDA
/// -----------------------------------------------------------------
///
/// Un numero secuencial exige un contador compartido, y un contador compartido
/// vive en la nube. Pero la app tiene que funcionar sin conexion, y ahí nace el
/// conflicto: si el codigo se genera al guardar y la red se cae, la cita queda
/// sin numero; si espera al numero, el usuario no ve su cita.
///
/// La salida es que el codigo tenga DOS estados de vida:
///
///   1. Offline (o antes de sincronizar): la cita se guarda con [temporal], un
///      marcador visible tipo "PENDIENTE". La cita EXISTE, se ve, aparece en el
///      Dashboard y el administrador puede trabajar con ella. Lo unico que no
///      tiene es un numero propio, y el marcador lo dice sin mentir.
///
///   2. Online: el `SyncService` pide el numero en una transaccion de Firestore
///      sobre un documento contador, escribe el definitivo en el documento, y
///      el `onSnapshot` del propio cliente lo baja. La fila local cambia de
///      "PENDIENTE" a "CITA-0004" sola, sin que nadie recargue la pantalla.
///
/// Que el numero llegue por el MISMO canal que el resto de los datos y no por
/// un callback aparte es lo que evita la condicion de carrera clasica: si el
/// numero volviera por un listener propio, podria appliedise DESPUES de un
/// `onSnapshot` que traiga el documento viejo y dejara "PENDIENTE" pegado en la
/// UI para siempre.
///
/// -----------------------------------------------------------------
/// LO QUE NO SE HACE AQUI
/// -----------------------------------------------------------------
///
/// Ni el formateo del numero ni la reserva. [formatear] es una funcion pura y
/// testeable; el numero en si lo asigna `SyncService` con una transaccion en
/// la nube. Este archivo no importa nada de Firebase a proposito: es el modelo,
/// y si dependiera del SDK no se podria probar sin el plugin.
library;

/// Prefijo de todos los codigos de orden. Se lee en voz alta como "cita", que es
/// lo que el administrador escribe en la hoja.
const String prefijoCodigoCita = 'CITA-';

/// Estado en el que vive un codigo todavia sin numero definitivo.
///
/// En mayusculas y sin digitos a proposito: delata a simple vista una fila que
/// la nube todavia no ha confirmado, y no se confunde con un numero real que se
/// perdio en un recorte de pantalla.
const String codigoCitaTemporal = 'PENDIENTE';

/// Cuantos digitos lleva el numero.
///
/// 4 da cabida a 9999 ordenes por cliente, que es lo que cabe antes de que se piense en
/// un formato por anio ('CITA-2026-0001'). Con 5 el numero tiene un caracter mas
/// y hay que revisar todos los anchos de la UI antes de cambiarlo; con 3 se
/// desborda a los 1000. 9999 es el techo de la v7.
const int digitosCodigoCita = 4;

/// Construye el codigo visible a partir de un numero de secuencia.
///
/// El `padLeft` es lo que hace que el ancho del texto sea estable: sin el, el
/// 7 seria 'CITA-7' y el 1200 seria 'CITA-1200', y una columna de codigos con
/// anchos distintos se ve rota.
///
/// Solo formatea. NO decide el numero ni lo reserva: eso lo hace el
/// `SyncService` con el documento contador de Firestore, porque un numero
/// secuencial solo es correcto si nadie mas lo tomo antes.
String formatearCodigoCita(int secuencia) {
  return '$prefijoCodigoCita${secuencia.toString().padLeft(digitosCodigoCita, '0')}';
}

/// Si el codigo todavia no fue confirmado por la nube.
///
/// Es la condicion que decide si la UI avisa o no. Se calcula comparando contra
/// [codigoCitaTemporal] y no "si no parece un numero", porque un parser que
/// adivina el formato se rompe en silencio el dia que el formato cambie.
bool esCodigoTemporal(String codigo) => codigo == codigoCitaTemporal;

/// Un codigo es `null` o temporal: la cita existe pero todavia no tiene numero.
///
/// Parametro aparte de [esCodigoTemporal] porque hay DOS formas legitimas de no
/// tener numero y se comportan distinto en la UI: una cita que aun no se ha
/// sincronizado tiene `codigoCitaTemporal` (hay que empujarla), y una fila
/// importada sin codigo tiene `null` (hay que rellenarla). La UI pinta "PENDIENTE"
/// para las dos, pero la sincronizacion distingue.
bool esCodigoAusente(String? codigo) =>
    codigo == null || esCodigoTemporal(codigo);

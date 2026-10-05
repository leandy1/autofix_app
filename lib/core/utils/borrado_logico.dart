/// BORRADO LOGICO (Tombstone Pattern).
///
/// -----------------------------------------------------------------
/// POR QUE NO HAY `DELETE`
/// -----------------------------------------------------------------
///
/// La v6 hacia `db.delete(tabla, where: 'id = ?')` cuando el administrador
/// borraba una cita. Con un solo dispositivo eso no tiene consecuencias. Con
/// varios, cada borrado fisico es una bomba:
///
///   - El dispositivo A borra la cita 7. Firestore no se entera de nada.
///   - El dispositivo B tiene esa cita en su SQLite y en su proximo
///     `onSnapshot` recibe el documento, porque en la nube SIGUE ESTANDO.
///   - La cita reaparece en la pantalla de B. El admin la ve borrar, B no la
///     ve borrar, y vuelve a aparecer. Ciclico, y el usuario pierde confianza en
///     la pantalla.
///
/// El unico borrado que dos dispositivos pueden ponerse de acuerdo es el que se
/// ESCRIBE, no el que se ejecuta.
///
/// Por eso el borrado pasa a ser una marca de tiempo. La fila sigue en la base
/// con `eliminado_en` puesto; las consultas normales la filtran con
/// `WHERE eliminado_en IS NULL` y el usuario no la ve; la sincronizacion la sube
/// a Firestore como una cita mas con su `eliminado_en`; y el `onSnapshot` del
/// otro dispositivo la marca tambien. Los tres quedan viendo lo mismo.
///
/// -----------------------------------------------------------------
/// LAS TRES COLUMNAS, Y POR QUE TRES
/// -----------------------------------------------------------------
///
/// `eliminado_en`:   CUANDO se borro. Sin esto no se puede ordenar una papelera
///                    ni responder "borraste esto hace dos dias", que es la
///                    pregunta que se le hace a un administrador.
///
/// `eliminado_por`:  QUIEN lo borro. Es el que hace que dos editores del mismo
///                    documento NO se pisen: si A borra y B edita medio segundo
///                    despues, la columna dice que hay dos intenciones distintas
///                    y el que gana el ultimo es el de la nube, no el del reloj
///                    local. Ver [resolverConflictoDeBorrado].
///
/// `restaurado_en`:  CUANDO volvio, si volvio. Sin esta columna no se puede
///                    restaurar sin perder informacion: hay que limpiar
///                    `eliminado_en`, y al hacerlo desaparece la huella de que ese
///                    documento estuvo borrado. Con ella, restaurar es un segundo
///                    cambio de estado y queda la traza.
///
/// -----------------------------------------------------------------
/// LO QUE NO ESTA HECHO
/// -----------------------------------------------------------------
///
/// La PAPIELERA (la pantalla que lista lo borrado y ofrece "Restaurar") no se
/// construye en esta rama. Lo que si queda es el soporte completo para
/// construirla: [Trazabilidad] viaja en el modelo, los repositorios filtran, y
/// `restaurar` es un metodo publico que el Admin puede llamar desde donde
/// quiera. La API queda lista antes que la pantalla, para que cuando el Admin la
/// pinte no haya que volver a tocar el modelo.
library;

import 'package:autofix/core/utils/reloj.dart';

/// Estado de borrado de una fila.
///
/// Es un valor y no un `bool`, porque con dos booleanos (`eliminado` y
/// `restaurado`) aparecen los cuatro estados posibles y dos son invalidos: "borrada
/// y restaurada a la vez", que no dice nada. Con un solo campo, los tres estados
/// posibles son los tres estados reales.
enum EstadoBorrado {
  /// La fila esta activa. Es el estado de toda fila recien creada.
  viva,

  /// La fila fue borrada logicamente en [Trazabilidad.eliminadoEn].
  ///
  /// Notar que [Trazabilidad.restauradoEn] puede venir lleno con fecha: eso
  /// significa que la fila fue borrada, restaurada, y borrada de nuevo. Es el
  /// estado que se consulta con [Trazabilidad.estaBorrada] y es exactamente lo
  /// que un `bool` no puede expresar.
  borrada,

  /// La fila fue borrada y luego DEVUELTA. Distinto de [viva] justamente porque
  /// conserva la huella: la UI puede marcar "restaurada" y la auditoria sabe que
  /// estuvo fuera.
  restaurada;

  /// `true` solo para [borrada]. [restaurada] NO cuenta como borrada: la fila
  /// esta visible.
  bool get estaBorrada => this == EstadoBorrado.borrada;

  /// Nombre estable que se persiste. `.name` y no el indice del enum: reordenar
  /// el enum no debe cambiar lo que hay escrito en las bases de los dispositivos ya
  /// instalados.
  String get nombre => name;

  /// Lee desde la base. Ante un valor desconocido devuelve [viva], que es la
  /// postura honesta: si no sabemos el estado, mostramos la fila.
  static EstadoBorrado desdeNombre(Object? valor) => switch (valor) {
    'borrada' => EstadoBorrado.borrada,
    'restaurada' => EstadoBorrado.restaurada,
    _ => EstadoBorrado.viva,
  };
}

/// Las tres columnas de trazabilidad de una fila.
///
/// Se agrupan en una clase para que la columna de borrado se escriba y se lea
/// siempre completa, y para que [mapaDeTrazabilidad] sea generica entre tablas.
class Trazabilidad {
  const Trazabilidad({this.eliminadoEn, this.eliminadoPor, this.restauradoEn});

  /// Trazabilidad de una fila recien creada: las tres columnas vacias.
  static const Trazabilidad vacia = Trazabilidad();

  /// Instante UTC del borrado, o `null` si la fila esta viva.
  final DateTime? eliminadoEn;

  /// Quien ejecuto el borrado (id de usuario). `null` hasta que haya
  /// autenticacion; con [EstadoBorrado.borrada] siempre informado.
  final String? eliminadoPor;

  /// Instante UTC de la restauracion, o `null` si nunca volvio.
  final DateTime? restauradoEn;

  /// Estado derivado de las tres columnas.
  ///
  /// El orden de las preguntas importa: primero se pregunta por el borrado,
  /// porque una fila que esta borrada ahora lo estuvo aunque vuelve antes. Solo si
  /// no esta borrada se mira si hubo una restauracion.
  EstadoBorrado get estado {
    if (eliminadoEn != null) return EstadoBorrado.borrada;
    if (restauradoEn != null) return EstadoBorrado.restaurada;
    return EstadoBorrado.viva;
  }

  /// Lo unico que las consultas de la UI necesitan: la fila NO se muestra.
  bool get estaBorrada => eliminadoEn != null;

  /// Copia con solo el borrado puesto. Es la operacion que hace `eliminar`.
  Trazabilidad marcarBorrada({required DateTime cuando, String? por}) {
    return Trazabilidad(
      eliminadoEn: cuando,
      eliminadoPor: por,
      // Se CONSERVA la restauracion previa: el documento estuvo fuera y esa
      // informacion no se pierde al volver a borrarse. Sin esto, borrar y
      // restaurar dos veces deja el mismo rastro que borrar una.
      restauradoEn: restauradoEn,
    );
  }

  /// Copia con solo la restauracion puesta. Es la operacion que hace `restaurar`.
  Trazabilidad marcarRestaurada({required DateTime cuando}) {
    return Trazabilidad(
      eliminadoEn: null,
      eliminadoPor: null,
      restauradoEn: cuando,
    );
  }
}

/// Las tres columnas de trazabilidad, listas para `db.insert` y para `db.update`.
///
/// Los `null` van EXPLICITOS y eso es lo importante, en los dos sentidos:
///
///   - En un INSERT, una columna ausente toma su DEFAULT, que es `NULL`. Mismo
///     resultado, pero mandarlas hace que el mapa sea el mismo que se lee, y una
///     asercion de test que compare `toMap()` contra `PRAGMA table_info` no tiene
///     que tratar un caso especial.
///
///   - En un UPDATE es la diferencia entre "dejar la columna como estaba" y
///     "VACIAR la columna". En SQLite, `UPDATE ... SET col = NULL` borra el
///     valor, y una columna que NO aparece en el mapa no se toca. Por eso
///     `restaurar` puede poner `eliminado_en = NULL` de verdad y por eso un
///     update parcial de otra columna no puede pisar el `eliminado_por` que
///     escribio otro dispositivo.
///
/// Consecuencia para el codigo: toda actualizacion de una fila con trazabilidad
/// pasa por aca, en vez de armar el mapa a mano. Un `copyWith` que se olvide de
/// una de las tres columnas deja una fila en un estado que nadie pidio.
Map<String, Object?> mapaDeTrazabilidad(Trazabilidad t) {
  return <String, Object?>{
    'eliminado_en': t.eliminadoEn == null ? null : aIsoUtc(t.eliminadoEn!),
    'eliminado_por': t.eliminadoPor,
    'restaurado_en': t.restauradoEn == null ? null : aIsoUtc(t.restauradoEn!),
  };
}

/// Resultado de comparar la version local de una fila con la que llega de la nube.
///
/// En vez de decidir dentro del repositorio (que no puede probarse sin base de
/// datos) la decision es una funcion pura: recibe las dos [Trazabilidad] y dice
/// cual gana. Asi el caso mas importante de la sincronizacion, que es cuando dos
/// dispositivos tocaron la misma fila, se testea en dos lineas.
enum GanadorDeConflicto {
  /// La version local manda: la nube no tiene nada que esta fila no sepa.
  local,

  /// La version de la nube manda: la local esta vieja o esta proponiendo algo que
  /// la nube ya decidio.
  nube,

  /// La version local es la mas nueva: hay que SUBIRLA.
  localAdelantada;

  bool get ganaLocal =>
      this == GanadorDeConflicto.local ||
      this == GanadorDeConflicto.localAdelantada;
}

/// Decide que version de una fila sobrevive.
///
/// -----------------------------------------------------------------
/// EL CASO QUE ROMPE LA APP
/// -----------------------------------------------------------------
///
/// Dos dispositivos, mismo documento:
///
///   10:00:01.000  A borra la cita. A: `eliminado_en = 10:00:01`
///   10:00:01.400  B edita el estado de la cita. B: `eliminado_en = NULL`
///
/// Sin esta funcion, el `onSnapshot` de A trae `eliminado_en = NULL` y la cita
/// REAPARECE en la pantalla de A. Y si B sincroniza antes de volver a mirar, el
/// borrado de A se pierde para siempre: la cita queda viva en los dos, y el
/// administrador que la borro no sabe por que.
///
/// -----------------------------------------------------------------
/// LA REGLA
/// -----------------------------------------------------------------
///
/// El borrado es el estado MAS FUERTE: si cualquiera de las dos versiones dice
/// "esta borrada", la fila esta borrada. Es last-write-wins con un estado
/// terminal.
///
/// Es la unica regla que sobrevive a un dispositivo con el reloj corrido, y no es
/// arbitraria: el usuario borro una cita A PROPOSITO y con datos de la pantalla.
/// Que un editor automatico, desde otro dispositivo, con el reloj mal, decida
/// que esa fila vuelve a existir es exactamente el fallo que hace que un usuario
/// deje de confiar en el papel. Un documento borrado que reaparece es peor que
/// un documento que se pierde: el primero hace perder tiempo y credibilidad.
///
/// Y por que el borrado gana tambien cuando la nube lo dice y localmente no: si
/// otro taller borro la cita y esta llego a este dispositivo, este tiene que
/// respetar el borrado. Un `DELETE` local "porque aqui no me sirve" seria
/// inventar una decision de negocio que el taller tomo en otro lado.
///
/// [restaurar] es la unica operacion que le gana a un borrado, y por eso tiene su
/// propia columna ([Trazabilidad.restauradoEn]): es explicita, no se deduce.
GanadorDeConflicto resolverConflictoDeBorrado({
  required Trazabilidad local,
  required Trazabilidad remota,
}) {
  // Borrado remoto contra version local viva o restaurada: el borrado gana.
  if (remota.eliminadoEn != null && local.eliminadoEn == null) {
    return GanadorDeConflicto.nube;
  }

  // Ambas borradas: se queda la mas reciente, que es la ultima intencion.
  if (remota.eliminadoEn != null && local.eliminadoEn != null) {
    return remota.eliminadoEn!.isAfter(local.eliminadoEn!)
        ? GanadorDeConflicto.nube
        : GanadorDeConflicto.localAdelantada;
  }

  // Ninguna borrada. Se comparan los relojes para subir la version mas nueva,
  // que es lo que espera el resto de la app: `actualizado_en` es el campo contra
  // el que `EntidadPersistida` resuelve conflictos desde la v1.
  final instanteLocal = local.restauradoEn;
  final instanteRemoto = remota.restauradoEn;
  if (instanteLocal != null && instanteRemoto != null) {
    return instanteLocal.isAfter(instanteRemoto)
        ? GanadorDeConflicto.localAdelantada
        : GanadorDeConflicto.nube;
  }

  // Solo una de las dos tiene restauracion registrada: la otra no sabe nada del
  // otro documento, asi que se queda igual (no hay nada que subir ni que bajar).
  return GanadorDeConflicto.local;
}

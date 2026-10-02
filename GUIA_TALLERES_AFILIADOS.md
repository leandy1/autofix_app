# Guía: dar de alta talleres afiliados

> **Esto es temporal.** Hoy la red de afiliados se da de alta editando código. Cuando exista el
> módulo de administración de talleres, esto se reemplaza por un formulario y esta guía
> deja de ser el procedimiento. Ver [Por qué es temporal](#por-qué-es-temporal).

El mapa **no busca talleres libres**. Solo muestra los afiliados que están guardados en la tabla
`talleres` de la base local. Esa tabla se siembra en la instalación y se administra después.

Si un taller no está en la semilla, **no aparece en el mapa**, y tampoco sale en el modal de
selección ni en el selector del formulario de cita. No es un error: es exactamente lo que quiere
la directriz de que la app solo ofrezca la red propia.

---

## 1. Dónde está el archivo

```
lib/core/database/semilla_inicial.dart
```

Busca la lista `SemillaInicial.talleres`. Cada entrada es un `TallerAfiliado`.

## 2. Formato de una entrada

```dart
TallerAfiliado(
  nombre: 'Global Refriauto',
  direccion: 'Av. 27 de Febrero esq. Las Américas, Gazcue',
  telefono: '809-555-0101',
  latitud: 18.4624868,
  longitud: -69.9517036,
),
```

| Campo       | Tipo      | Obligatorio | Notas |
|-------------|-----------|-------------|-------|
| `nombre`    | `String`  | Sí          | Único. Hay un índice `UNIQUE` con `COLLATE NOCASE`, así que dos talleres no pueden llamarse "taller gómez" y "Taller Gómez". |
| `direccion` | `String`  | No          | Texto libre, no coordenadas. Se muestra en la tarjeta del modal y en la ficha del mapa. `''` es válido. |
| `telefono`  | `String`  | No          | **Texto, no número.** Escribelo con guiones, como lo lee la persona: `'809-555-0101'`. |
| `latitud`   | `double`  | Sí          | Grados decimales. Norte positivo. |
| `longitud`  | `double`  | Sí          | Grados decimales. **Oeste negativo** (República Dominicana va de −68 a −72). |

Los cinco campos van juntos porque el constructor los marca `required`. Si dejáramos
`latitud`/`longitud` opcionales, agregar un taller y olvidar la coordenada no daría error de
compilación: daría un punto en medio del océano.

## 3. Cómo sacar las coordenadas de Google Maps

1. Abre Google Maps y navega hasta el local.
2. **Clic derecho** sobre el punto (o mantener pulsado en móvil) → **Copiar latitud, longitud**.
3. Pega el resultado en un archivo de texto. Google devuelve un par así:

   ```
   18.4624868,-69.9517036
   ```

4. Sepáralo en los dos campos, tal cual, sin redondear:

   ```dart
   latitud: 18.4624868,     // lo que va antes de la coma
   longitud: -69.9517036,   // lo que va después de la coma, con su signo
   ```

### Errores que se ven seguido

- **Se intercambiaron latitud y longitud.** El punto cae en el mar o en otro país.
- **Se perdió el signo negativo de la longitud.** Sale del lado del Atlántico.
- **Se copió el decimal con coma** (`18,4624868`) en vez de punto. Dart no compila, así que es
  el error más rápido de ver.
- **Se redondeó a 2 decimales.** El punto cae a más de un kilómetro, que en una ciudad es otra
  calle. Con 4 decimales ya son ~11 metros, que es la precisión razonable para "este local está en
  esta esquina".

### No confíes en la barra de direcciones

La barra de Google Maps devuelve el centroide de la ciudad cuando escribes un nombre. Si copias
de ahí y no del punto, caes en el centro de Santo Domingo.

## 4. Verificar que entró bien

Después de editar la semilla:

```bash
flutter test test/talleres_test.dart
flutter analyze
```

El grupo `semilla de afiliados` de `test/talleres_test.dart` falla si:

- la base nueva no nace con todos los talleres de la semilla,
- a un taller le falta `Global Refriauto`,
- alguna coordenada cae fuera de República Dominicana (latitud entre 17.5 y 19.9, longitud entre
  −72 y −68),
- la coordenada se trunca a entero al guardarse.

Y **reinstala la app**, o usa *Borrar datos de almacenamiento* desde los ajustes de Flutter. Ver
la advertencia de abajo.

## 5. ⚠️ La semilla solo corre en una base vacía

`_sembrarTalleres()` en `lib/core/database/database_helper.dart` hace esto:

```dart
final existentes = await db.query(tablaTalleres, columns: [colId], limit: 1);
if (existentes.isNotEmpty) return;
```

Es decir: si la tabla ya tiene **alguna** fila, la semilla no corre. Abcerca la app mil veces no
duplica los talleres, pero también significa que **editar `semilla_inicial.dart` no cambia nada en
un dispositivo que ya tiene la app instalada**.

Qué hacer según el caso:

| Situación | Solución |
|---|---|
| Estás probando en un emulador o dispositivo limpio | Desinstala la app o borra los datos de almacenamiento, y reinstala. |
| Quieres corregir un taller en un dispositivo de pruebas | Ábrelo en Configuración,_edítalo y guarda_, o bórralo. La base es la fuente en tiempo de ejecución. |
| Ya hay producción con la app publicada | Hace falta una **migración** nueva (`_versionBase` + un paso en `_migrar`) con un `UPDATE` dirigido por nombre. Es un paso de migración más, no un cambio de semilla. |

Esto pasa porque los datos ya persistidos son del usuario, no nuestros. La semilla es el
*estado inicial* de una instalación, no un `seed` que se reaplique.

## 6. Por qué es temporal

Editar un archivo Dart para sumar un taller no es operable: obliga a recompilar y publicar una
versión nueva de la app, y un afiliado nuevo tarda días en estar visible. Cuando exista el módulo
de administración, el alta será un `INSERT` sobre la misma tabla `talleres` a través de
`TallerRepository`, y esta guía se archivará.

Mientras tanto: **agregar un afiliado es un cambio de código.** Avísale a quien toque el PR.

---

### Referencias

- Modelo de dominio y fórmula de distancia: `lib/features/talleres/models/taller.dart`
- Consultas y orden: `lib/features/talleres/data/taller_repository.dart`
- Definición de la tabla y siembra: `lib/core/database/database_helper.dart`
- Pantalla del mapa: `lib/screens/cliente/talleres_mapa_screen.dart`
# AutoFix App

## Descripción general

Este proyecto es una app de gestión de citas para un taller automotriz. La funcionalidad principal es permitir registrar citas, guardar la información de forma persistente, editarlas, eliminarlas y organizarlas por estado para la vista administrativa.

La aplicación usa Flutter como framework y SQLite como almacenamiento local. La estructura está pensada para separar claramente la capa de dominio, la capa de datos y la capa de presentación.

## Arquitectura del proyecto

La app está organizada por capas para mantener el código limpio y evitar que la interfaz toque SQLite directamente.

### 1. Modelo de dominio
Archivo principal:
- `lib/features/citas/models/cita.dart`

Este archivo define la entidad `Cita`, que representa una cita real que se va a persistir.

Incluye:
- `id`
- `cliente`
- `telefono`
- `vehiculo`
- `marca`
- `modelo`
- `anio`
- `placa`
- `servicios`
- `tecnico`
- `descripcion`
- `fechaCita`
- `estado`
- `creadoEn`
- `actualizadoEn`
- `total`

También define:
- `EstadoCita`, que representa los estados reales guardados en la base:
  - `pendiente`
  - `esperandoPieza`
  - `enProceso`
  - `completado`
- `esAtrasada(DateTime ahora)`: determina si la cita está vencida según la fecha que se está revisando
- `etiquetaUI(DateTime ahora)`: devuelve la etiqueta visual para la UI, como `ATRASADAS` o `Pendiente`
- `toMap()` y `fromMap()`: convierten la entidad a JSON/Map para SQLite y viceversa

### 2. Repositorio de datos
Archivo principal:
- `lib/features/citas/data/cita_repository.dart`

Esta clase implementa la lógica de acceso a la base de datos. Es la capa que sabe cómo guardar, leer, editar y borrar citas.

Funciones principales:
- `crear(Cita cita)`
  - inserta una nueva cita en SQLite
- `obtenerTodas()`
  - devuelve todas las citas ordenadas por fecha
- `obtenerPorId(int id)`
  - busca una cita concreta por su ID
- `actualizar(Cita cita)`
  - modifica una cita existente
- `cambiarEstado(int id, EstadoCita estado)`
  - actualiza solo el estado, sin tocar el resto de la fila
- `eliminar(int id)`
  - borra una cita de la base
- `obtenerDelDia(DateTime fecha)`
  - devuelve las citas de un día específico

El repositorio no sabe nada de widgets ni de pantallas. Solo sabe sobre la entidad y la base de datos.

### 3. Controlador de presentación
Archivo principal:
- `lib/features/citas/presentation/citas_controller.dart`

`CitasController` es la capa que la UI usa para interactuar con las citas. Extiende de `ChangeNotifier`, lo cual permite que la pantalla reaccione automáticamente cuando cambia el estado de las citas.

Propiedades principales:
- `citas`: lista actual de citas cargadas
- `cargando`: si la carga está en proceso
- `error`: último error que ocurrió

Métodos principales:
- `cargar()`
  - obtiene todas las citas desde el repositorio
- `guardar(Cita cita)`
  - crea o actualiza una cita según si tiene ID o no
- `cambiarEstado(int id, EstadoCita estado)`
  - cambia el estado de una cita
- `eliminar(int id)`
  - elimina una cita
- `agruparPorEstado(DateTime fecha, {DateTime? ahora})`
  - devuelve un mapa con las citas agrupadas en grupos como `ATRASADAS`, `Pendiente`, `Esperando Pieza`, etc.

La idea es que la UI no haga consultas directas a SQLite ni manipule el repositorio. Todo pasa por este controlador.

### 4. Base de datos SQLite
Archivo principal:
- `lib/core/database/database_helper.dart`

Este archivo centraliza la conexión y el esquema de la base.

#### Singleton
La clase usa un patrón singleton:
- `DatabaseHelper.instance`
- solo hay una conexión activa para todo el app
- esto evita conflictos cuando dos operaciones quieren escribir al mismo tiempo

#### Esquema
La tabla principal es:
- `citas`

Campos:
- `id`
- `cliente`
- `vehiculo`
- `telefono`
- `marca`
- `modelo`
- `anio`
- `placa`
- `servicios`
- `tecnico`
- `descripcion`
- `fecha_cita`
- `estado`
- `creado_en`
- `actualizado_en`
- `total`

#### Migración de versión
La base tiene versión controlada por:
- `_versionBase = 3`

Migraciones:
- `v1 -> v2`: agrega teléfono, marca, modelo, año, placa, servicios, técnico y fecha de actualización
- `v2 -> v3`: elimina el campo QR y agrega el campo `total`

La app no borra datos antiguos. En vez de eso, usa `onUpgrade` para adaptar la estructura a la nueva versión.

Esto es importante porque permite mantener citas ya creadas cuando se actualiza la app.

### 5. Vista administrativa
Archivo principal:
- `lib/screens/admin/citas_admin_screen.dart`

Aquí vive la pantalla principal para ver y administrar citas.

Responsabilidades:
- cargar la lista de citas
- filtrar y agrupar por estado
- abrir formulario para crear nueva cita
- abrir edición para una cita existente
- guardar cambios en la base
- eliminar cita
- mostrar detalle de la cita

También hay conversiones entre la entidad real de la base y la entidad UI:
- `CitaAdmin` se usa para la pantalla
- `Cita` se usa para SQLite
- la app convierte entre ambos modelos según sea necesario

## Lógica de citas atrasadas

La marcada de “atrasadas” se hace de forma derivada, no como un estado guardado en la base. Esto es importante porque atrasada no es un estado real; es una condición calculada.

### Regla
Una cita está atrasada cuando:
- su estado no es `completado`
- y la fecha de la cita es anterior al día que se está consultando

### Importante
No se compara por hora exacta. La regla es por fecha calendario.

Ejemplo:

- Si la cita es del 30/9 y la vista está en 1/10, aparece en `ATRASADAS`
- Si la vista está en 30/9, esa cita sigue visible como normal
- Si la cita está completada, no aparece como atrasada

Esto se implementa con:
- `Cita.esAtrasada(DateTime ahora)`
- `Cita.etiquetaUI(DateTime ahora)`

### Por qué se hace así
Porque en la administración se revisan citas por día seleccionado. Un día concreto debe mostrar su estado real, y las citas de días anteriores aparecen como vencidas sin alterar su estado original de base.

## Orden de la lista

El repositorio ordena las citas por fecha de forma ascendente:

```dart
orderBy: '${DatabaseHelper.colFechaCita} ASC'
```

Esto hace que las citas antiguas aparezcan primero cuando corresponde, por ejemplo en la vista de citas atrasadas y en la vista general del día.

## Flujo completo de creación y lectura

### Crear cita
1. La pantalla admin abre un formulario
2. recopila los datos del cliente, vehículo y servicios
3. crea una instancia de `Cita`
4. llama a `CitasController.guardar(cita)`
5. el controller llama al repositorio
6. el repositorio ejecuta `INSERT` en SQLite
7. la lista se vuelve a cargar y la UI actualiza el listado

### Editar cita
1. se abre el diálogo de edición
2. se modifica el `CitaAdmin`
3. se convierte a `Cita`
4. se llama a `guardar()`
5. el repositorio ejecuta `UPDATE` por `id`
6. la lista en pantalla se refresca

### Eliminar cita
1. se dispara la acción desde la card o detalle
2. se llama a `CitasController.eliminar(id)`
3. el repositorio ejecuta `DELETE` por `id`
4. la UI vuelve a recargar la lista

### Leer citas
1. el controller llama a `obtenerTodas()`
2. el repositorio hace `SELECT * FROM citas`
3. `Cita.fromMap()` convierte cada fila en una entidad
4. la UI recibe la lista y la muestra por grupos

## Relación entre modelos

Hay dos representaciones de la cita:

### 1. `Cita` (entidad de persistencia)
Usada por SQLite y el repositorio.

### 2. `CitaAdmin` (entidad de UI)
Usada por la pantalla de administración.

La app convierte entre ellos cuando edita o muestra información para evitar mezclar la lógica de base con la estructura de la interfaz.

## Pruebas importantes

El proyecto tiene tests para verificar:
- `Cita.toMap()` y `Cita.fromMap()`
- migración de esquema SQLite
- CRUD del repositorio
- comportamiento del controller
- lógica de agrupación por estado
- lógica de atrasadas por fecha
- edición y eliminación desde UI

## Ejecutar el proyecto

### Dependencias
```bash
flutter pub get
```

### App normal
```bash
flutter run
```

### Tests
```bash
flutter test
```

## Resumen corto

En resumen, la app funciona así:

- la pantalla admin manda acciones a `CitasController`
- el controller usa `CitaRepository`
- el repositorio guarda y lee en SQLite
- la entidad `Cita` representa los datos reales
- las citas atrasadas se calculan según la fecha del día que se está viendo, no por la hora exacta
- los estados visuales se agrupan para que la administración vea claramente qué necesita atención

Este diseño hace que el proyecto sea más mantenible, fácil de testear y más seguro ante cambios futuros en la UI o en la base de datos.

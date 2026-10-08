# AutoFix — Gestión de Citas para Talleres Automotrices

| | |
|---|---|
| **Proyecto** | ISW307 · Programación de Dispositivos Móviles · Grupo Q |
| **Repositorio** | [github.com/leandy1/autofix_app](https://github.com/leandy1/autofix_app) |
| **Plataforma** | Flutter (Android / iOS / Web / Desktop) |
| **Almacenamiento** | SQLite (offline) + Cloud Firestore (sincronización) |
| **Estado** | Funcional · Arquitectura Offline-First completada |

---

## 1. Visión General del Proyecto

AutoFix es una aplicación móvil para la **gestión integral de citas de talleres automotrices**, con flujos coordinados para el **cliente**, que agenda y consulta sus servicios, y para el **administrador**, que opera su taller desde un panel aislado por tenant.

El problema que resuelve es doble:

1. **Los talleres operan sin una red estable.** Una cita creada en recepción no puede perderse porque se cayó el internet. AutoFix funciona **Offline-First**: todo se escribe primero en SQLite local y la nube se pone al día cuando hay conectividad.
2. **Un mismo taller necesita verse desde varios dispositivos.** La cita que crea el administrador en su panel debe aparecer al instante en el celular del cliente (y en el de otro dispositivo del mismo taller), sin que nadie se pise los datos.

El proyecto nació bajo la **visión, planificación y arquitectura base de Leandy**, quien estableció la estructura inicial de la aplicación y sus módulos. Sobre esa base, Sandy asumió el rol de **co-líder integrador**, evolucionando la arquitectura para resolver los desafíos de persistencia, sincronización y aislamiento de datos, además de cerrar cuellos de botella técnicos y completar funcionalidades en coordinación con Leandy.

Por eso, AutoFix no se limita a un CRUD conectado a la nube: implementa un **flujo de datos local-first con sincronización bidireccional** entre SQLite y Cloud Firestore, control de conflictos, separación multitenant y un ciclo de vida de datos que preserva la privacidad de las sesiones.

> **Producto resultante:** historial completo de citas offline, agenda y mapa de talleres, generación local y sincronizada de códigos QR de confirmación (`CITA-XXXX`), catálogos de servicios/técnicos por taller, dashboard con números reales, sesión persistente y un Modo Desarrollador para la administración de talleres y cuentas.

---

## 2. Arquitectura y Stack Tecnológico

### Stack

- **Flutter / Dart** — SDK `^3.13.2`, Material Design.
- **SQLite (`sqflite`)** — base local, migraciones por versión (esquema **v15** actual).
- **Cloud Firestore + Firebase Auth** — sincronización y autenticación (credenciales del proyecto `autofix-6f844`).
- **`connectivity_plus`** — detector de red en vivo (banner global de conectividad).
- **`qr_flutter`** — generación local de códigos QR.
- **`maplibre_gl` + `geolocator` + `url_launcher`** — mapa de talleres, ubicación y "Abrir en Maps".
- **`http`** — consumo de la API pública **NHTSA vPIC** para catálogo de vehículos.
- **`shared_preferences` + `flutter_secure_storage`** — sesión persistente ("Recuérdame") y cola segura de cambios de contraseña.

### Arquitectura Offline-First

La persistencia se organiza alrededor de SQLite como **fuente de lectura y escritura inmediata para la interfaz**. Las operaciones del usuario se confirman localmente y quedan marcadas como pendientes; Firestore replica los cambios entre dispositivos cuando la sesión y la conectividad lo permiten. Los listeners contextuales aplican los cambios remotos a SQLite mediante upsert, evitando que las pantallas dependan de una llamada de red para mostrar o modificar información.

La separación por capas mantiene las responsabilidades acotadas: las pantallas usan controladores, los controladores coordinan repositorios, los repositorios aplican el contrato de persistencia y `SyncService` coordina el intercambio con Firestore. El detector de conectividad activa reintentos y comunica el estado de red, pero la disponibilidad de la UI no depende de él.

```text
+----------------------------------+          +---------------------------------+
|            Flutter App           |          |             Firebase            |
|                                  |          |                                 |
|  +----------------------------+  |   PUSH   |  +---------------------------+  |
|  | SQLite autofix.db (v15)    |  | pending |  |      Cloud Firestore       |  |
|  |                            |--+--------->|  |                           |  |
|  | citas      · catalogos     |  |  queue  |  | citas    · talleres        |  |
|  | talleres   · admins        |  |         |  | tecnicos · servicios       |  |
|  | clientes   · vehiculos     |<-+----------|  | marcas · grupos · vehiculos |  |
|  +----------------------------+  |   PULL   |  | counters/citas (QR)        |  |
|                ▲                 |onSnapshot|  +---------------------------+  |
|                | Ctrl+Repo       |          |                ▲                |
|  +----------------------------+  |          |  +---------------------------+  |
|  |        SyncService         |  |          |  |   Firebase Auth (roles)   |  |
|  +----------------------------+  |          |  +---------------------------+  |
+----------------------------------+          +---------------------------------+
```

### Patrones y decisiones clave

- **Esquema SQLite versionado (v15):** `DatabaseHelper` centraliza una conexión singleton, el esquema, sus índices y las migraciones. La versión actual incorpora citas, vehículos, perfiles y catálogos con los campos necesarios para sincronización y aislamiento por taller. Las migraciones se ejecutan por versión; la reconstrucción de identidad introducida en v7 fue una decisión del entorno académico que puede descartar datos locales legados. Para conservar datos de usuarios reales se requiere una migración con conversión y copia de filas antes de desplegar una actualización.
- **Tombstones para bajas sincronizables:** las bajas funcionales de citas, vehículos y catálogos se representan con `eliminado_en` y, cuando corresponde, `eliminado_por`/`restaurado_en` (`lib/core/utils/borrado_logico.dart`). Las consultas ordinarias excluyen filas marcadas y la sincronización replica la marca como una actualización; las reglas de Firestore rechazan el borrado físico de estas colecciones. Es distinto de la purga local de `LimpiezaLocal`, que elimina físicamente la copia local al cerrar o cambiar de sesión según la política de "Recuérdame"; el garaje en Firestore se recupera al volver a iniciar sesión.
- **Identidad distribuida y código legible:** las entidades sincronizables usan UUID generados en el cliente como identidad estable, evitando colisiones de autoincrementos entre dispositivos. El código de cita visible (`CITA-XXXX`) es separado e inmutable una vez confirmado; su numeración se reserva mediante una **transacción atómica** sobre `counters/citas`.
- **`SyncService` bidireccional:** `lib/features/sync/sync_service.dart` coordina las colas locales y los listeners de Firestore.
  - **Push:** procesa registros `sync_status = 'pending'` para citas, vehículos, perfiles y catálogos, con reintentos por fila. Los cambios de contraseña se reintentan mediante Firebase Auth; el secreto se conserva temporalmente en almacenamiento seguro y nunca se envía a Firestore. Los fallos de una cola no impiden procesar las demás.
  - **Pull:** listeners `onSnapshot` aplican upserts a SQLite. Los filtros dependen de la sesión: `taller_id` para administración y `ownerUid`/correo para citas y vehículos del cliente. El listener se inicia al establecer el contexto de sesión, no con una descarga global de citas al abrir la app.
  - **Conflictos:** las citas comparan `actualizado_en`; las bajas de catálogos y vehículos tienen protección para evitar que una edición local antigua las resucite. El `codigo_visible` se conserva una vez asignado. Para perfiles, un cambio local pendiente prevalece sobre una copia remota atrasada.
- **Multitenencia por `taller_id`:** citas y catálogos operativos llevan el identificador del taller. SQLite aplica filtros e índices por tenant y limita la unicidad de nombres al taller; Firestore valida la pertenencia del administrador al taller en las escrituras. Los catálogos globales de talleres y cuentas de administrador tienen un flujo separado.
- **Ciclo de vida de sesión y datos:** `lib/core/data/limpieza_local.dart` separa datos temporales del usuario (citas, perfil y vehículos locales) de los datos permanentes de plataforma. Al cambiar de cuenta limpia primero, detiene listeners y hace un intento acotado de enviar pendientes cuando hay conectividad.
- **Reglas de seguridad en la nube:** `firestore.rules` valida estructura y tipos, propiedad del cliente, asociación del administrador con `taller_id`, protección de catálogos y avance monotónico del contador. El acceso no definido queda denegado por defecto.

---

## 3. Módulos Principales

### Cliente
Área de cliente respaldada por un perfil local persistente (`clientes`):

- **Registro híbrido:** acceso por correo/contraseña (Firebase Auth) con **modo invitado** y validación **sin internet** contra credenciales seguras del keystore cuando "Recuérdame" está activo. Memoria de roles (`SesionAdmin`/`SesionCliente`) independientes.
- **Gestión de vehículos:** el "garaje virtual" guarda vehículos en SQLite v15 y sincroniza en ambos sentidos con Firestore, vinculados al UID/correo del cliente. El garaje remoto sobrevive al cierre de sesión y a la limpieza de caché (Garbage Collection) y se restaura al iniciar sesión; incluye autocompletado desde **NHTSA vPIC** y fallback offline.
- **Agenda offline:** crear una cita con taller, vehículo, servicio y técnico del catálogo, fecha y hora; el guardado local no espera a que la sincronización termine.
- **Historial de citas:** estados reales (pendiente, esperando pieza, en proceso, completada); lista "Mis Citas" alimentada por el listener contextual (por `ownerUid` y por `correo_cliente`).
- **QR de confirmación local:** la cita aceptada muestra su código `CITA-XXXX` en un QR generado en el dispositivo, incluso sin red.
- **Mapa de talleres:** red de afiliados (no talleres libres) con MapLibre, marcadores, distancia aproximada y "Abrir en Maps" vía `url_launcher`.

### Administrador
Panel de gestión aislado por taller (`taller_id`):

- **Gestión de solicitudes cruzadas:** el cliente agenda desde su celular y la solicitud nace en su dispositivo; el administrador la **acepta o rechaza** desde su panel y el cliente ve el resultado al instante. Resolución de colisiones en la cola de envío con UUIDs y transacciones atómicas en Firebase.
- **Catálogo de servicios, técnicos, marcas y grupos de servicio:** CRUD completo conectado a SQLite con aislamiento por taller, unicidad de nombres por taller y protección histórica (Soft-Delete).
- **Dashboard con datos reales:** números, gráficos y citas del día conectados a la base (no a mocks), filtrables por fecha.
- **Panel multitenant y Modo Desarrollador:** creación de cuentas de admin y altas/bajas de talleres con sincronización a Firestore; impresión de recibos por Bluetooth (por Luis, integrada por Leandy).

---

## 4. Contribuciones del Equipo


### Leandy Gabin Fermín — Líder principal y arquitecto original
Leandy dio origen al proyecto: definió la visión y el plan inicial, estableció la estructura base de la aplicación y condujo la arquitectura funcional sobre la que se integraron los módulos. En el código, trabajó en el diseño y CRUD administrativo de citas (`feature/leandy-citas-admin`), el acceso Cliente/Admin, el Modo Desarrollador (`feature/leandy-dev-apartado`), las cuentas de administración vinculadas a talleres (`feature/leandy-devMode-Account`), la separación de datos por taller (`feature/leandy-login-admin`) y la integración/revisión general del trabajo del equipo. **Su liderazgo principal y su rol de arquitecto original se mantuvieron durante el desarrollo.**

### Sandy Alexander Ortiz Taveras — Co-líder integrador y responsable del motor Offline-First
Sandy se incorporó como **co-líder integrador**: fortaleció la arquitectura original conforme aparecieron los requisitos de persistencia local, concurrencia, conectividad y sincronización; resolvió cuellos de botella técnicos y llevó módulos críticos a un estado integrado y estable. Su trabajo incluye el motor SQLite (`feature/sandy-conectividad-almacenamiento`, `feature/sandy-configuracion-db`), conectividad, Dashboard real, mapa, esquema v15, sincronización con Firebase (`feature/sandy-firebase-offline-sync`), gestión del ciclo de vida/limpieza local (`sesion-offline`) y cierre de Configuración Admin (`feature/sandy-configuracion-admin`, `feature/sandy-correccion-ids-solicitudes`).

### Aportes iniciales de los demás integrantes

- **Luis Ernesto Hernández Peralta — Bluetooth:** inició el flujo de impresión de recibos (`feature/luis-bluetooth`); Leandy lo integró y completó dentro del flujo de citas (`feature/leandy-recibo-cita`).
- **Rafael David Sánchez Arias — Talleres y agenda del cliente:** inició el mapa y el formulario de agendamiento (`feature/david-busqueda-ubicacion`, `feature/david-mapa-final`); Sandy refinó la integración de MapLibre, la selección de afiliados, las distancias y la navegación a mapas externos.
- **Andy Andrés Rodríguez Abreu — Servicios web y solicitudes:** inició el consumo de API REST y la gestión de solicitudes administrativas (`feature/andy-servicios-web`, `feature/andy-configuracion-marcas`, `feature/andy-solicitudes-admin`). Debido a la carga de trabajo y a las necesidades de integración, Sandy apoyó y finalizó la API de vehículos y el flujo de solicitudes **preservando la lógica base iniciada por Andy**.

### Cierre colaborativo

La distribución original asignó funcionalidades; la entrega requirió integración transversal. **Leandy fue el líder principal y arquitecto original; Sandy fue su co-líder integrador**, reforzando esa arquitectura, resolviendo los bloqueos de persistencia/sincronización y finalizando componentes que necesitaban trabajo adicional. Leandy aportó la dirección inicial y la integración funcional; Sandy consolidó buena parte del motor Offline-First y completó módulos iniciados por Andy, Luis y Rafael junto con Leandy. El resultado actual es un esfuerzo colaborativo cuyo liderazgo y cierre técnico recayeron principalmente en ambos, con responsabilidades distintas y complementarias.

---

## 5. Estructura del Proyecto

```
lib/
├── app/                      # Punto de entrada: MaterialApp, ruta inicial, banner
├── core/
│   ├── auth/                 # Sesiones Admin/Cliente, credenciales seguras, Recuérdame
│   ├── connectivity/         # Detector de red y banner global
│   ├── data/                 # BaseRepository + LimpiezaLocal (garbage collection)
│   ├── database/             # DatabaseHelper (singleton SQLite, migraciones v1→v15)
│   ├── mapa/                 # Estilos y etiquetas del mapa
│   ├── ubicacion/            # Servicio de geolocalización
│   └── utils/                # borrado_logico (tombstones), reloj, uuid
├── features/
│   ├── admin/                # Citas admin, Dashboard, Configuración, Bluetooth
│   ├── auth/                 # Login, cambio de contraseña
│   ├── citas/                # Modelo Cita, repositorio, controller
│   ├── cliente/              # Mis cita, Agendar, Talleres/Mapa, perfil, NHTSA
│   ├── configuracion/        # Catálogos: técnicos, servicios, marcas, grupos
│   ├── devMode/              # Talleres afiliados, cuentas admin, sync global
│   ├── sync/                 # SyncService + catálogos por taller
│   └── talleres/             # Modelo y repositorio de talleres
└── shared/                   # Modelos compartidos y tema (AppColors)
```

---

## 6. Cómo Ejecutar

```bash
flutter pub get      # instalar dependencias
flutter run          # ejecutar la app
flutter test         # correr la suite de tests
flutter analyze      # análisis estático
```

> **Nota Firebase:** la app usa credenciales reales del proyecto `autofix-6f844` (`android/app/google-services.json` + `lib/firebase_options.dart`) y reglas de Firestore versionadas en `firestore.rules`. Los claims de Modo Desarrollador (`dev`) deben emitirse **solo** a través de Firebase Admin SDK; nunca se conceden desde el cliente.

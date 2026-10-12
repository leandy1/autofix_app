# AutoFix — Gestión de talleres y citas automotrices

Aplicación móvil del Grupo Q para conectar a clientes con talleres afiliados y apoyar la operación diaria del taller. El sistema combina una experiencia local-first con sincronización entre dispositivos, una agenda administrable, catálogos por taller y herramientas de atención al cliente.

## 1. Visión General del Proyecto

AutoFix resuelve dos necesidades que suelen entrar en conflicto: poder trabajar cuando la conexión no está disponible y mantener consistentes las citas cuando cliente y administrador usan dispositivos distintos.

El cliente puede registrar vehículos, buscar talleres afiliados, solicitar una cita, revisar su estado y presentar el QR de una cita confirmada. El administrador trabaja con las solicitudes, organiza la agenda y mantiene la información operativa de su taller. Las citas y los datos de operación se guardan primero en el dispositivo; Firebase permite sincronizarlos con el contexto correcto cuando hay conectividad.

El resultado es una aplicación **Offline-First y multitenant**: la pantalla no depende de una lectura remota para operar, los cambios pendientes se conservan localmente y cada cuenta administrativa trabaja asociada a un `taller_id`.

## 2. Arquitectura y Stack Tecnológico

### Stack

- **Flutter y Dart** para la aplicación multiplataforma.
- **SQLite mediante `sqflite`** como persistencia local; el esquema actual es **v17**.
- **Firebase Auth y Cloud Firestore** para identidad, reglas de acceso y sincronización entre dispositivos.
- **`connectivity_plus`** para detectar conectividad y reintentar el envío de pendientes.
- **`mobile_scanner` y `qr_flutter`** para leer los QR de citas desde el panel admin y generar el QR del cliente.
- **NHTSA vPIC mediante `http`** para consultar marcas/modelos; caché local y alternativas offline.
- **MapLibre, `geolocator` y `url_launcher`** para mostrar talleres afiliados, ubicación y navegación externa.
- **`shared_preferences` y `flutter_secure_storage`** para preferencias de sesión y material sensible de acceso/cambios de contraseña.

### Datos local-first y sincronización

La aplicación sigue esta ruta: **UI → controlador → repositorio → SQLite**. `SyncService` conecta la persistencia local con Firestore: sube las filas pendientes y aplica snapshots remotos en la base local. Los controladores notifican a las pantallas después de las escrituras locales o de una actualización recibida. Los listeners se abren con el contexto de la sesión; el administrador filtra por taller y el cliente por UID/correo.

El servicio sincroniza citas, perfiles, vehículos y catálogos operativos del taller. Los registros actualizados localmente entran en `sync_status = 'pending'`; después de una escritura confirmada pasan a `synced`. Los errores se manejan por fila/cola para que el fallo de una entidad no detenga el resto de los intentos.

### SQLite: v15, v16 y v17

La versión vigente es **SQLite v17**. Las migraciones recientes amplían el modelo sin presentar v15 como la versión actual:

| Versión | Cambio relevante |
|---|---|
| **v15** | Vehículos del cliente con estado de sincronización y tombstone, conservando los registros ya guardados al migrar. |
| **v16** | Nueva tabla local `grupo_servicio_items` para relacionar grupos y servicios y definir el orden de presentación. |
| **v17** | Campo `motivo_rechazo` para conservar y mostrar al cliente la explicación del rechazo de una cita. |

`DatabaseHelper` es el punto único de apertura y migración de `autofix.db`. Las entidades usan UUID para mantener identidades estables en distintos dispositivos; los códigos legibles `CITA-XXXX` se asignan en una transacción Firestore.

### Tombstones, conflictos y consistencia

Las bajas funcionales sincronizables se representan mediante marcas como `eliminado_en` (y, en las citas, trazabilidad asociada), no mediante un borrado físico remoto. Las consultas activas ocultan los registros marcados y la nube puede propagar la misma decisión a los demás dispositivos. Los vehículos también conservan su tombstone en SQLite/Firestore.

Para las citas vivas, la sincronización compara `actualizado_en`; para bajas/restauraciones, aplica la regla de trazabilidad que impide resucitar una fila borrada. El `codigo_visible` queda protegido una vez que Firestore lo asigna. Los perfiles pendientes tienen una regla específica para no perder una edición local frente a una copia remota atrasada.

### Multitenencia y seguridad

Las citas y catálogos operativos llevan `taller_id`. SQLite filtra por taller y aplica unicidad de nombres dentro de cada tenant; las reglas `firestore.rules` verifican propietario, pertenencia al taller, forma/tipos de datos y operaciones permitidas. Las colecciones de citas y catálogos no permiten borrado físico y la regla final deniega todo acceso no descrito.

**Alcance actual de dos integraciones:** `grupo_servicio_items` ya está modelada y persistida localmente con `taller_id`, `sync_status` y tombstones; el `SyncService` y `firestore.rules` versionados aún no incluyen su sincronización remota. El panel de Cuentas Admin incorpora una verificación por documento en `adminUsers`, mientras que las reglas actuales de escritura de `admins` y `talleres` siguen requiriendo el claim `dev` y no declaran una regla para `adminUsers`. Para habilitar ese flujo en un despliegue, hay que alinear la autorización de cliente y servidor.

## 3. Módulos Principales

### Cliente

- **Acceso y perfil:** registro/login, modo invitado y sesión local persistente con opción “Recuérdame”. El perfil del cliente se mantiene en SQLite y se sincroniza al recuperar conexión.
- **Vehículos:** alta, edición y selección local; sincronización por UID/correo, con tombstones para las bajas. NHTSA vPIC ayuda a completar marcas/modelos; se usa caché y, si no existe, una lista de 20 marcas comunes y entrada manual.
- **Agenda:** selección de taller afiliado, vehículo, servicio y fecha/hora. Se rechazan fechas pasadas y la solicitud queda guardada localmente mientras espera sincronización.
- **Mis citas:** historial filtrado por el perfil local, estados y motivos de rechazo, indicador de elementos pendientes, recarga manual mediante *pull-to-refresh* y escucha de los cambios notificados por `SyncService`. El cliente puede cancelar solicitudes pendientes y dar de baja citas rechazadas o completadas, sujeto a verificación de propiedad.
- **Confirmación QR:** generación local del QR a partir del código visible de una cita aceptada; el QR puede mostrarse sin hacer una nueva consulta a Firestore.
- **Talleres:** directorio y mapa de afiliados con ubicación, distancia aproximada y apertura de navegación externa.

### Administrador

- **Agenda y solicitudes:** crear/editar citas, filtrar por fecha y estado y administrar solicitudes entrantes. Rechazar una solicitud requiere ingresar un motivo; ese dato se conserva en `motivo_rechazo`, viaja con la cita y se muestra en “Mis citas”. Los estados de aceptación/rechazo se resuelven desde las solicitudes, no desde el selector operativo del editor.
- **Actualización entre dispositivos:** los snapshots de Firestore se aplican a SQLite; las pantallas de Citas y Configuración escuchan a `SyncService` y vuelven a cargar los datos afectados. El Dashboard lee las agregaciones locales al cargar o cambiar la fecha. La cita escaneada por QR abre su detalle dentro del flujo de Citas, usando el mismo diálogo y acciones que la tarjeta normal.
- **Escáner QR:** la cámara lee el código `CITA-XXXX`, lo busca en la base local y permite abrir la cita y su detalle administrativo.
- **Dashboard:** métricas y citas del día agregadas desde SQLite, con selector de fecha; la vista vuelve a calcular los datos al cargar o cambiar el día.
- **Configuración del taller:** CRUD de servicios, técnicos, marcas y grupos. Los servicios pueden asignarse a varios grupos; en la Configuración se pueden agregar/quitar vínculos y ordenar los servicios. El formulario de citas presenta los servicios por grupo y una sección “Sin grupo”. Esta relación se persiste localmente.
- **Marcas desde NHTSA:** el administrador puede importar marcas de la API al catálogo SQLite; luego se pueden usar offline en los formularios de administración.
- **Talleres y cuentas Admin:** Modo Desarrollador para sincronizar talleres y administrar cuentas. La validación de acceso y las reglas de Firestore deben quedar alineadas en el ambiente de despliegue (ver Arquitectura y Stack).
- **Herramientas adicionales:** impresión de recibos por Bluetooth y gestión de perfil del administrador.

## 4. Contribuciones del Equipo

**Leandy Gabin Fermín — líder principal y arquitecto original.** El proyecto nació de su visión, plan inicial y estructura base. Desarrolló la base funcional de la aplicación, los flujos de citas administrativas, acceso Cliente/Admin, Modo Desarrollador y separación de datos por taller. En los cambios más recientes refactorizó la agenda administrativa, integró el rechazo con motivo, el escáner QR y el refresco de las pantallas ante cambios recibidos desde otros dispositivos (`06818ce`, `06dc091`).

**Sandy Alexander Ortiz Taveras — co-líder integrador.** Fortaleció la arquitectura durante el desarrollo y lideró buena parte del motor de persistencia, esquema SQLite, conectividad, sincronización Offline-First, configuración multitenant, perfil y sincronización de vehículos (`714b413`). También resolvió cuellos de botella y completó integraciones iniciadas por compañeros, preservando su lógica base cuando fue posible.

**Contribuciones iniciales integradas:** Andy inició los servicios web de vehículos y la gestión de solicitudes; Sandy cerró su integración al flujo final. Rafael David inició el mapa y el agendamiento cliente, que Sandy refinó dentro de la experiencia de talleres. Luis inició el flujo Bluetooth, integrado por Leandy en los recibos. La distribución original y el historial de ramas muestran esos puntos de partida; la entrega final fue un trabajo colaborativo con liderazgo principal de Leandy y co-liderazgo técnico de Sandy.

## 5. Estructura del Proyecto

```text
lib/
├── app/                         # Arranque, ruta inicial y composición de la app
├── core/
│   ├── auth/                    # Sesiones Admin/Cliente y credenciales locales
│   ├── connectivity/            # Estado de red y banner global
│   ├── data/                    # Repositorios base y limpieza de datos por sesión
│   ├── database/                # SQLite, esquema y migraciones v1–v17
│   ├── mapa/                    # Estilos y etiquetas del mapa
│   ├── ubicacion/               # Acceso a ubicación del dispositivo
│   └── utils/                   # UUID, reloj y lógica de tombstones
├── features/
│   ├── admin/                   # Citas, solicitudes, Dashboard, QR y configuración
│   ├── auth/                    # Login y cambio de contraseña
│   ├── citas/                   # Modelo, repositorio y controlador de citas
│   ├── cliente/                 # Agenda, vehículos, perfil, mapa y Mis Citas
│   ├── configuracion/           # Técnicos, servicios, marcas y grupos
│   ├── devMode/                 # Talleres y cuentas administrativas
│   ├── sync/                    # Coordinación local–Firestore
│   └── talleres/                # Modelo y persistencia de talleres
└── shared/                      # Modelos compartidos y tema visual

docs/                            # Guía de exposición técnica
test/                            # Pruebas de unidad, widgets y sincronización
```

La organización mantiene límites claros: las pantallas componen la experiencia, los controladores coordinan acciones de usuario, los repositorios contienen acceso y persistencia, `core` concentra capacidades transversales y `features` agrupa cada área funcional. Así se pueden probar o modificar módulos sin llevar lógica de base de datos a los widgets.

## 6. Cómo Ejecutar

### Requisitos

- Flutter/Dart compatible con la versión declarada en `pubspec.yaml`.
- Proyecto Firebase configurado para la plataforma objetivo (`lib/firebase_options.dart` y configuración nativa correspondiente).
- Para usar el escáner QR, permisos de cámara en Android/iOS; para el mapa, permisos de ubicación y configuración del proveedor de mapas.

### Preparar y ejecutar

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

### Compilar para distribución

```bash
flutter build apk --release       # Android
flutter build appbundle --release # Android, Google Play
flutter build ipa --release       # iOS (en macOS con Xcode configurado)
```

Antes de desplegar, revisar `firestore.rules` y verificar que las reglas y los documentos de autorización (`adminUsers`/claim `dev`) correspondan al flujo de administración habilitado. Las reglas se pueden publicar con `firebase deploy --only firestore:rules` cuando el proyecto Firebase y su CLI estén configurados.

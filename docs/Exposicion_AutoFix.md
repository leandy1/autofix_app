# AutoFix — Guía de exposición técnica

**Asignatura:** ISW307 · Programación de Dispositivos Móviles · Grupo Q
**Expositores:** Leandy Gabin Fermín y Sandy Alexander Ortiz Taveras
**Repositorio:** [github.com/leandy1/autofix_app](https://github.com/leandy1/autofix_app)

## Apertura: visión, equipo y desafío

> “AutoFix nació de la visión, el plan inicial y la arquitectura base de Leandy, líder principal del proyecto. Conforme crecieron los retos de persistencia y sincronización, Sandy se integró como co-líder técnico: fortaleció esa arquitectura, resolvió bloqueos y ayudó a cerrar módulos que habían iniciado Andy, Luis y Rafael. La solución final conserva esas contribuciones dentro de un sistema integrado, con responsabilidades de liderazgo claras y complementarias.”

AutoFix organiza el vínculo entre el cliente que solicita una cita y el taller que la atiende. El reto de ingeniería fue hacer que esa relación siguiera siendo confiable cuando hay mala conectividad, cuando cada persona usa un dispositivo diferente y cuando una misma plataforma sirve a varios talleres.

La idea que guía la exposición es sencilla: **SQLite permite trabajar ahora; Firestore coordina los cambios entre dispositivos después**. A continuación explicamos qué problemas había, qué decisiones técnicas los resolvieron y qué aporta cada módulo al flujo completo.

---

## 1. Reto arquitectónico: operar sin conexión y sincronizar con seguridad

### El reto

Una app conectada a internet puede guardar una cita directamente en la nube, pero deja de ser útil en recepción cuando la red se cae. Pasar a una base local resuelve la disponibilidad, pero abre nuevos problemas: dos dispositivos pueden editar la misma cita, una baja puede reaparecer al sincronizar y cada taller debe permanecer aislado.

### La solución técnica

- La interfaz lee y escribe en **SQLite**, de modo que las operaciones locales no esperan a Firestore.
- Las modificaciones quedan pendientes (`sync_status = 'pending'`) y `SyncService` las publica al recuperar conectividad. Los snapshots remotos se aplican a SQLite y las pantallas se actualizan desde esa fuente local.
- Las consultas son **contextuales**: el admin trabaja con el `taller_id` de su sesión y el cliente con sus vínculos de UID/correo. No se descarga la colección completa de citas para cada usuario.
- Las entidades usan UUID como identidad técnica; el código humano `CITA-XXXX` es independiente y se reserva mediante una transacción de Firestore.
- Las bajas de negocio se propagan como tombstones en vez de borrados físicos, para que otro dispositivo reciba la misma decisión.

### Versión de la base

La base está actualmente en **SQLite v17**. Las versiones pedidas durante la evolución son hitos, no la versión final: **v15** añadió el estado de sincronización y tombstones a vehículos; **v16** añadió la tabla puente local de grupos/servicios; **v17** añadió `motivo_rechazo` a las citas. La migración estructural v7 reconstruye tablas para adoptar UUID y puede descartar filas legadas; antes de una actualización que deba preservar datos reales se necesita una migración de conversión y respaldo.

### Evidencia de Git

- `714b413` — sincronización de vehículos del cliente con Firestore.
- `06818ce` — refactor de citas admin, rechazo con motivo y sincronización asociada.
- `06dc091` — actualización en tiempo real de la lista de citas tras los snapshots.

---

## 2. Sesión y Garbage Collection de datos locales

### El reto

El dispositivo conserva citas, perfil y vehículos. Si inicia sesión otra persona, mantener esos datos sin separación puede exponer información privada; borrarlos de inmediato, sin detener listeners ni intentar enviar cambios, puede perder escrituras pendientes o volver a insertar filas durante la limpieza.

### La solución técnica

`LimpiezaLocal` administra el ciclo de vida local con un orden deliberado:

1. Detiene los listeners de la sesión para que un `onSnapshot` no repueble una base mientras se purga.
2. Si hay cambios pendientes y conectividad, intenta un último push acotado por timeout.
3. Limpia físicamente las citas, el perfil y los vehículos temporales del usuario según la política de sesión; no elimina los datos permanentes de talleres ni catálogos.
4. Cuando cambia el UID, ejecuta la limpieza antes de iniciar los listeners de la cuenta siguiente.

“Recuérdame” conserva la copia local necesaria para volver a entrar sin red; sin esa opción, la copia se trata como temporal al cerrar sesión. La sesión de administrador y la de cliente se mantienen en contextos diferentes, y el login sigue siendo la decisión explícita de entrada.

El acceso del cliente combina Firebase Auth cuando hay red con credenciales protegidas localmente para el acceso offline recordado. Los cambios de contraseña se aplican mediante Firebase Auth cuando vuelve a existir la sesión correspondiente; el secreto no se sube a Firestore.

### Cómo explicarlo al jurado

> “No bastaba con borrar tablas al cerrar sesión. Primero detenemos los listeners, hacemos un último intento de conservar cambios pendientes y luego purgamos solo los datos personales temporales. Así evitamos tanto la mezcla de cuentas como la pérdida accidental de la sesión persistida.”

---

## 3. Cliente: vehículos, agenda, historial y confirmación

### El reto

El formulario debe ser rápido y confiable aunque no haya internet. Además, una solicitud del cliente tiene que llegar al taller, la decisión del taller debe volver al cliente y el cliente necesita una forma clara de presentar una cita confirmada.

### La solución técnica

- **Vehículos locales y sincronizados:** cada vehículo se persiste en SQLite y, desde v15, tiene `sync_status` y `eliminado_en`. `SyncService` usa una cola y snapshots filtrados por UID/correo; las reglas de Firestore validan la propiedad y no permiten borrado físico.
- **NHTSA vPIC con fallback:** consulta de marcas/modelos con caché local. Sin caché o conexión, el formulario ofrece veinte marcas comunes y entrada manual. Los vehículos previamente registrados siguen seleccionables offline.
- **Agenda con validación:** la cita se guarda localmente con taller, vehículo, servicio y fecha/hora; se bloquean fechas pasadas. Al enviar, el registro queda listo para sincronizar.
- **“Mis citas” desde SQLite:** muestra el historial del cliente sin depender de una petición remota en cada apertura, informa si hay elementos pendientes, escucha las notificaciones de `SyncService` y permite recargar la lista local con *pull-to-refresh*.
- **Rechazo explicado:** cuando el taller rechaza una solicitud, el motivo se conserva con la cita y aparece en el historial del cliente.
- **Cancelación con propiedad y estados:** el cliente puede cancelar una solicitud pendiente o dar de baja citas rechazadas/completadas. Se valida el correo propietario y se registra la baja lógica; el cliente no puede borrar la cita de otra persona.
- **QR local:** una vez asignado el código visible, la app genera la imagen QR en el dispositivo. Mostrarla no requiere conectarse otra vez a Firestore.

### Cómo explicarlo al jurado

> “La API externa mejora la selección del vehículo, pero no bloquea la agenda: combinamos caché, catálogo offline y entrada manual. La cita queda en SQLite primero y luego sincroniza; por eso el cliente puede seguir usando el flujo aunque la conectividad sea intermitente.”

---

## 4. Administrador: agenda en vivo, motivo de rechazo y escáner QR

### El reto

El panel administrativo debe reflejar cambios hechos desde otros dispositivos. También debe separar la decisión de aceptar/rechazar una solicitud del trabajo operativo posterior, explicar al cliente por qué se rechazó y permitir localizar una cita desde el QR que presenta en el taller.

### La solución técnica

- **Refactor de agenda:** los estados de aceptación/rechazo se resuelven en el módulo de solicitudes; el selector del editor queda para los estados operativos del taller. Esto reduce transiciones de negocio inconsistentes.
- **Motivo obligatorio al rechazar:** el flujo abre un diálogo y exige texto antes de confirmar. `motivo_rechazo` se guarda en SQLite v17, se incluye en la serialización de la cita y llega al cliente mediante la sincronización.
- **Actualización entre dispositivos:** el listener de Firestore aplica los cambios remotos en SQLite. La pantalla de Citas escucha las notificaciones de `SyncService`, vuelve a cargar citas y catálogos y actualiza su representación local. El repositorio compara `actualizado_en` para no dejar la cita congelada en un estado anterior.
- **QR integrado al flujo normal:** `mobile_scanner` lee el QR `CITA-XXXX` y busca la cita en la base local. El dashboard navega al apartado de Citas y abre el detalle compartido con la tarjeta; el administrador conserva allí las acciones normales, sin una pantalla de detalle duplicada.
- **Pull-to-refresh en cliente:** el historial permite solicitar otra carga cuando el usuario quiere comprobar cambios recientes.

### Cómo explicarlo al jurado

> “El snapshot solo no actualiza una pantalla que ya leyó SQLite. Por eso conectamos la notificación de sincronización con la recarga del repositorio en la vista administrativa. Así, cuando otro dispositivo cambia una cita, SQLite recibe la versión nueva y el panel vuelve a consultar esa fuente local.”

### Evidencia de Git

`06818ce` integra el refactor de citas, el campo de rechazo y el escáner; `06dc091` corrige la propagación visual de cambios recibidos por snapshot y reutiliza el detalle de cita al entrar por QR.

---

## 5. Configuración del taller: catálogos y servicios agrupados

### El reto

Las opciones de servicio no son iguales en todos los talleres. Una lista plana obliga a buscar entre opciones sin contexto, y una relación rígida uno-a-muchos impediría que un mismo servicio aparezca en más de una categoría.

### La solución técnica

- Técnicos, servicios con precio, marcas y grupos se guardan como catálogos SQLite asociados a `taller_id`.
- **v16 introduce `grupo_servicio_items`**, tabla puente de relación muchos-a-muchos: un grupo contiene varios servicios y un servicio puede pertenecer a más de un grupo. Incluye `orden`, identidad UUID, tenant, baja lógica y estado local; la pantalla permite agregar, quitar y reordenar servicios, y presenta los que aún no se asignaron bajo “Sin grupo”.
- Los formularios de creación y edición de citas muestran los servicios agrupados, y el admin gestiona esos vínculos desde la configuración.
- El administrador puede importar marcas desde la misma API NHTSA usada por el cliente. Las marcas importadas quedan guardadas en el catálogo local para que los formularios sigan disponibles sin conexión.

### Límite de sincronización identificado en la auditoría

La relación `grupo_servicio_items` se persiste y opera localmente, pero la versión actual de `SyncService` y `firestore.rules` no contiene una colección ni un flujo remoto para esa tabla. En la exposición conviene describirla como configuración local por taller, no como catálogo ya replicado a otros dispositivos.

### Cómo explicarlo al jurado

> “El servicio y el grupo son entidades distintas; su vínculo es muchos-a-muchos. La tabla puente guarda qué servicio pertenece a qué grupo y en qué posición aparece. Esa estructura permite reutilizar servicios y personalizar el orden sin duplicar el registro del servicio.”

---

## 6. Multitenencia y seguridad de Firestore

### El reto

Compartir una colección entre talleres no significa compartir sus datos. Las consultas de la interfaz no bastan como control de acceso: las reglas de Firestore también deben verificar propietario, tenant y forma válida de cada escritura.

### La solución técnica

- Las citas administrativas y catálogos operativos incluyen `taller_id`; el listener del administrador se limita a su taller y los datos locales se consultan con el mismo contexto.
- `firestore.rules` verifica la relación entre la cuenta autenticada, su documento Admin y el taller; valida campos y tipos para citas, vehículos y catálogos, impide cambiar de tenant en una edición y bloquea los deletes físicos en entidades que usan tombstones.
- Las citas de cliente usan `ownerUid` y/o correo; los vehículos se filtran por los mismos datos de propietario.
- El contador `counters/citas` avanza de uno en uno y solo permite confirmar el código de una cita accesible.
- Una regla final deniega lecturas y escrituras para colecciones no declaradas.

### Observación de configuración que conviene mencionar si preguntan por DevMode

El commit `06818ce` añade una verificación visual de correo mediante `adminUsers` para entrar a Cuentas Admin. Sin embargo, las reglas versionadas no declaran esa colección y mantienen el claim `dev` para escribir en `admins` y `talleres`. La autorización del panel y la política del servidor deben alinearse para que el flujo funcione en un despliegue. Presentarlo como una comprobación implementada en la UI —no como sustituto de las reglas de servidor— es la descripción exacta del código actual.

### Cómo explicarlo al jurado

> “La interfaz filtra para presentar solo el taller activo, pero la frontera de seguridad está en Firestore: cada escritura se vuelve a validar con la identidad, el propietario y el `taller_id`. El aislamiento no depende de que el usuario no toque una opción de la pantalla.”

---

## 7. Estructura del Proyecto: cómo mantener el código escalable

### El reto

Una app con citas, usuarios, catálogos, mapas, cámara y sincronización puede convertirse rápidamente en una colección de pantallas que acceden a la base o a Firebase directamente. Eso hace difícil probar un módulo y aumenta el riesgo de que un cambio de UI altere las reglas de persistencia.

### La solución: capas compartidas y módulos por dominio

```text
lib/
├── app/                         # Ensamblaje de la aplicación y navegación inicial
├── core/
│   ├── auth/                    # Sesiones y credenciales locales
│   ├── connectivity/            # Estado de red y banner
│   ├── data/                    # Contrato base y ciclo de vida de datos
│   ├── database/                # SQLite, tablas, índices y migraciones v1–v17
│   ├── mapa/                    # Estilos y utilidades geográficas
│   ├── ubicacion/               # Servicio de localización
│   └── utils/                   # UUID, reloj y borrado lógico
├── features/
│   ├── admin/                   # Agenda, solicitudes, Dashboard, QR, configuración
│   ├── auth/                    # Login y cambio de contraseña
│   ├── citas/                   # Modelo, repositorio y controller de citas
│   ├── cliente/                 # Agenda, vehículos, perfil, mapa e historial
│   ├── configuracion/           # Catálogos y vínculo grupo-servicio
│   ├── devMode/                 # Administración de talleres/cuentas
│   ├── sync/                    # SyncService y sincronización de catálogos
│   └── talleres/                # Modelo y repositorio de talleres
└── shared/                      # Tema y modelos compartidos

test/                            # Pruebas de repositorios, UI y sincronización
```

La separación responde a un flujo de responsabilidad: **pantalla → controlador → repositorio → SQLite**. `core` contiene capacidades usadas desde más de un módulo; `features` mantiene juntas las pantallas, modelos y repositorios de cada dominio. `SyncService` cruza dominios solo para orquestar el movimiento de datos, y las pruebas se organizan por modelo, repositorio, controlador, widget y flujo de sincronización.

### Cierre sugerido

> “La arquitectura original de Leandy dio la estructura y el rumbo del producto. Sandy co-lideró la integración y reforzó esa base para resolver persistencia, concurrencia y sincronización. En los últimos ajustes, Leandy volvió a extender la experiencia administrativa con QR, rechazo motivado y actualización en vivo. AutoFix es el resultado de esa dirección inicial y de una ejecución técnica conjunta que incorporó las contribuciones del equipo.”

### Commits recientes para respaldar la exposición

- `714b413` — vehículos de clientes sincronizados con Firestore.
- `06818ce` — refactor admin, grupos de servicio, importación NHTSA, QR, cancelación cliente y motivo de rechazo (SQLite v17).
- `06dc091` — lista administrativa reactiva a snapshots entre dispositivos y apertura unificada del detalle QR.

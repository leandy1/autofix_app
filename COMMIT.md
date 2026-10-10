# Resumen de Cambios - 2026-10-10

## 1. Servicios Agrupados por Grupos en Formulario de Citas (Admin)

### Archivos modificados:
- `lib/core/database/database_helper.dart` - Migración v16: tabla `grupo_servicio_items`
- `lib/features/configuracion/data/grupo_servicio_item_repository.dart` - Nuevo repositorio para tabla puente
- `lib/features/configuracion/presentation/configuracion_controller.dart` - Métodos CRUD para relación grupo-servicio
- `lib/features/admin/screens/configuracion_admin_screen.dart` - UI "Gestionar servicios" por grupo
- `lib/features/admin/screens/citas_admin_screen.dart` - Diálogos `_CrearCitaDialog` y `_EditarCitaDialog` usan servicios agrupados

### Funcionalidad:
- Los servicios ahora se muestran **agrupados por grupo de servicio** en los formularios de crear/editar cita (admin)
- Sección "SIN GRUPO" para servicios no asignados
- Botón visible "Gestionar servicios" en cada grupo para agregar/quitar/reordenar servicios

---

## 2. Importar Marcas desde API NHTSA a BD Local

### Archivos modificados:
- `lib/features/configuracion/presentation/configuracion_controller.dart` - Método `importarMarcasDesdeApi()`
- `lib/features/admin/screens/configuracion_admin_screen.dart` - Botón "Importar desde API"

### Funcionalidad:
- Usa la **misma API NHTSA vPIC** que el formulario de cliente (`CatalogoVehiculosApi`)
- Descarga marcas de vehículos y las **guarda en SQLite local** (`tabla marcas`)
- Funciona **offline** - una vez importadas, no necesita internet
- Botón "Importar desde API" junto a "Agregar marca" en Configuración → Catálogos

---

## 3. Formularios de Cita Admin Usan Marcas de BD Local

### Archivos modificados:
- `lib/features/admin/screens/citas_admin_screen.dart` - `_CrearCitaDialog`, `_EditarCitaDialog`, `CitaAdminCard`
- Agregada carga de `_marcasDisponibles` en `_cargarCatalogos()`
- Eliminado uso de `demoMarcasVehiculo` hardcodeado

### Funcionalidad:
- Dropdown de marca en crear/editar cita ahora usa **marcas de la BD local** (configuración)
- Solo muestra marcas con `activo = true`
- Si no hay marcas, muestra "Seleccionar" como hint

---

## 4. Verificación por Email para Gestión de Cuentas Admin (DevMode)

### Archivos modificados:
- `lib/features/devMode/controllers/cuentas_admin_controller.dart` - Nueva lógica de verificación
- `lib/features/devMode/screens/cuentas_admin_screen.dart` - Diálogo de verificación al entrar

### Cambios:
- **Eliminado** requisito de custom claim `dev: true` en Firebase Auth
- **Agregado** verificación contra colección `adminUsers` en Firestore
- Al entrar a "Cuentas Admin" → **diálogo pide email** → valida si existe en `adminUsers`
- Si autorizado → carga datos y habilita botones (Crear, Editar, Eliminar, Reactivar, Sync)
- Botón "Cambiar cuenta" para cambiar email verificado

### Estructura Firestore requerida:
```
adminUsers/
  ├── admin@ejemplo.com  (documento existe = autorizado)
  ├── otro@ejemplo.com
  └── ...
```

---

## 5. Corrección: Diálogo de Verificación en initState

### Archivo:
- `lib/features/devMode/screens/cuentas_admin_screen.dart`

### Fix:
- `showDialog` en `initState` → `WidgetsBinding.instance.addPostFrameCallback`
- Evita error "context not ready" al mostrar diálogo al abrir la pantalla

---

## Archivos Principales Modificados

```
lib/core/database/database_helper.dart
lib/features/configuracion/data/grupo_servicio_item_repository.dart (nuevo)
lib/features/configuracion/presentation/configuracion_controller.dart
lib/features/admin/screens/configuracion_admin_screen.dart
lib/features/admin/screens/citas_admin_screen.dart
lib/features/devMode/controllers/cuentas_admin_controller.dart
lib/features/devMode/screens/cuentas_admin_screen.dart
```
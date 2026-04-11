# Implementar pantalla "Punto de partida" en la APK Flutter

Necesito que implementes la pantalla **"Punto de partida"** en la aplicación móvil Flutter del POS. Esta funcionalidad ya existe en la versión web y debo replicarla en la app.

---

## ¿Qué es esta pantalla?

Muestra al vendedor un resumen del período de ventas activo: cuántas unidades tenía cada producto al inicio del período, qué movimientos ocurrieron (ventas, entradas, salidas) y cuántas unidades quedan ahora. Es una herramienta de auditoría rápida del inventario.

---

## Punto de entrada en la UI

En la barra superior del POS (la misma donde está el indicador de conexión y el botón de sincronización) debe aparecer un botón con un ícono de **bandera** (`Icons.flag`). Al presionarlo se abre el modal/pantalla de "Punto de partida".

---

## Endpoint

```
GET {BASE_URL}/api/app/resumen-dia/{tiendaId}
```

**Headers:**
```
Authorization: Bearer <token_jwt>
```

**Query params:**

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `cierreId` | string (UUID) | — | ID del período activo. **Obligatorio.** |
| `soloConMovimientos` | bool | `true` | `true` = solo productos con al menos 1 movimiento; `false` = todos los productos con existencia > 0 o con movimientos |

**Ejemplo:**
```
GET /api/app/resumen-dia/abc123?cierreId=def456&soloConMovimientos=true
```

**Respuesta 200:**
```json
{
  "totales": {
    "ventas": 42.5,
    "entradas": 10.0,
    "salidas": 3.0
  },
  "productos": [
    {
      "productoTiendaId": "uuid",
      "productoId": "uuid",
      "nombre": "Coca Cola 500ml",
      "proveedorNombre": null,
      "permiteDecimal": false,
      "categoriaId": "uuid",
      "categoriaNombre": "Bebidas",
      "categoriaColor": "#1565C0",
      "tieneMovimientos": true,
      "ultimaModificacion": "2026-04-10T14:30:00.000Z",
      "cantidadInicial": 20,
      "ventas": 8,
      "entradas": 0,
      "salidas": 0,
      "cantidadFinal": 12
    }
  ]
}
```

> **Relación matemática:** `cantidadFinal = cantidadInicial + entradas - ventas - salidas`

**Errores posibles:**

| Código | Body |
|---|---|
| `400` | `{ "error": "cierreId es requerido" }` |
| `401` | `{ "error": "No autenticado" }` |
| `404` | `{ "error": "Cierre no encontrado" }` |
| `500` | `{ "error": "Error interno del servidor" }` |

---

## Datos disponibles en el estado de la app

- `tiendaId` — ID de la tienda activa del usuario (viene en el JWT / estado de sesión).
- `cierreId` — ID del período activo actual (el mismo que se usa al registrar ventas).

---

## Diseño de la pantalla

Abre como un **modal a pantalla completa** en móvil.

### 1. Header

- Título: `"Punto de partida y comportamiento"` (negrita)
- Botón de **refresh** (ícono reload) a la derecha del título
- Botón de **cerrar** (ícono X) al extremo derecho

### 2. Cards de totales (fila horizontal, 3 tarjetas)

Cada tarjeta muestra un ícono + label + valor:

| Card | Ícono | Color |
|---|---|---|
| Ventas | `Icons.shopping_cart` | Rojo (`Colors.red`) |
| Entradas | `Icons.trending_up` | Verde (`Colors.green`) |
| Salidas | `Icons.trending_down` | Naranja (`Colors.orange`) |

### 3. Barra de filtros (fila horizontal)

- **Campo de búsqueda** (TextField) que filtra por nombre de producto. Placeholder: `"Buscar producto..."`. Filtra en memoria, sin nuevo fetch.
- **Botón ojo** (IconButton toggle):
  - Ojo **cerrado** (`Icons.visibility_off`) = modo por defecto = solo productos con movimientos
  - Ojo **abierto** (`Icons.visibility`) = mostrar todos los productos con existencia > 0

### 4. Lista de productos con scroll vertical

Los productos se agrupan por categoría. Comportamiento:

- Los grupos se ordenan **alfabéticamente** por nombre de categoría.
- Dentro de cada grupo, los productos se ordenan por `ultimaModificacion` **descendente** (nulls al final).
- Encabezado de grupo: círculo pequeño del color de la categoría (`categoriaColor`) + nombre de la categoría en mayúsculas.

### 5. Card de producto

```
┌──────────────────────────────────────────────────┐
│ Nombre del producto (texto, negrita, tamaño 14)  │
│                                                  │
│  ┌────────────────┐  ┌─────────────────────────┐ │
│  │   Inicial      │  │   Existencia actual     │ │
│  │   [número]     │  │   [número]              │ │
│  │   fondo gris   │  │   fondo: verde/naranja  │ │
│  │                │  │   /rojo según valor     │ │
│  └────────────────┘  └─────────────────────────┘ │
│                                                  │
│  ── MOVIMIENTOS ───────────────────────────────  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │ Ventas   │  │ Entradas │  │ Salidas  │       │
│  │ [num]    │  │ [num]    │  │ [num]    │       │
│  │ rojo     │  │ verde    │  │ naranja  │       │
│  └──────────┘  └──────────┘  └──────────┘       │
└──────────────────────────────────────────────────┘
```

**Color de "Existencia actual":**

| Valor | Color |
|---|---|
| `≤ 0` | Rojo |
| `1` a `5` | Naranja |
| `> 5` | Verde |

**Formato de números:**

- `permiteDecimal = true` → 2 decimales (ej. `3.50`)
- `permiteDecimal = false` → entero (ej. `12`)

### 6. Estado vacío

Si la lista filtrada está vacía: ícono de gráfico centrado + texto `"No hay productos para mostrar"`.

### 7. Indicador de carga

Durante el fetch, mostrar un `CircularProgressIndicator` **superpuesto** sobre el contenido existente (no reemplazarlo), con fondo semitransparente. Esto permite ver los datos anteriores mientras se actualiza.

---

## Comportamiento del toggle de visibilidad

```
Al abrir la pantalla:
  → fetch con soloConMovimientos=true
  → ojo en estado "cerrado"

Usuario presiona ojo (abre):
  → Si no se cargaron todos aún: fetch con soloConMovimientos=false, guardar en estado
  → Si ya se cargaron todos: solo cambiar filtro en memoria (sin nuevo fetch)
  → ojo pasa a estado "abierto"

Usuario presiona ojo (cierra):
  → Filtrar en memoria (ya tenemos los datos)
  → ojo pasa a estado "cerrado"

Usuario presiona refresh:
  → Si ojo abierto: fetch con soloConMovimientos=false
  → Si ojo cerrado: fetch con soloConMovimientos=true
```

---

## Notas técnicas Flutter

- `categoriaColor` es un hex string como `"#1565C0"`. Parsearlo así:
  ```dart
  Color(int.parse(colorHex.replaceAll('#', '0xFF')))
  ```
- El campo `nombre` ya viene con el proveedor concatenado si aplica (`"Producto - Proveedor"`). No hay que procesarlo.
- La búsqueda debe normalizar el texto: ignorar mayúsculas, acentos y caracteres especiales antes de comparar.
- No hay paginación. Todos los productos llegan en una sola respuesta.
- El modal no se cierra al hacer refresh; mantiene el scroll y el filtro de búsqueda activos.

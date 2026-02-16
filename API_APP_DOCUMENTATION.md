# API Documentation - App Móvil

Documentación de los endpoints de la API para la aplicación móvil Flutter.

**Base URL:** `{SERVER_URL}/api/app`

---

## Autenticación

Todos los endpoints (excepto `/auth/login`) requieren autenticación mediante token JWT.

### Header de Autenticación

```
Authorization: Bearer <token>
```

El token se obtiene del endpoint de login y tiene una validez de **7 días**.

---

## Índice de Endpoints

1. [Autenticación](#autenticación-1)
   - [Login](#post-authlogin)
   - [Refresh Token](#post-authrefresh)
   - [Cambiar Tienda](#post-authcambiar-tienda)
2. [Productos](#productos)
   - [Listar Productos](#get-productostiendaid)
3. [Período/Cierre de Caja](#períodocierre-de-caja)
   - [Obtener Período Actual](#get-periodotiendaidactual)
   - [Abrir Período](#post-periodotiendaidabrir)
4. [Ventas](#ventas)
   - [Crear Venta](#post-ventatiendaidperiodoid)
   - [Listar Ventas](#get-ventatiendaidperiodoid)
   - [Obtener Detalle de Venta](#get-ventatiendaidperiodoidventaid)
   - [Cancelar Venta](#delete-ventatiendaidperiodoidventaid)
5. [Descuentos](#descuentos)
   - [Preview de Descuentos](#post-descuentospreview)
6. [Destinos de Transferencia](#destinos-de-transferencia)
   - [Listar Destinos](#get-transfer-destinationstiendaid)

---

## Autenticación

### POST /auth/login

Inicia sesión y obtiene el token JWT.

**URL:** `/api/app/auth/login`

**Headers:**
```
Content-Type: application/json
```

**Request Body:**
```json
{
  "usuario": "string",    // Nombre de usuario
  "password": "string"    // Contraseña
}
```

**Response Success (200):**
```json
{
  "success": true,
  "user": {
    "id": "uuid",
    "nombre": "Juan Pérez",
    "usuario": "jperez",
    "rol": "VENDEDOR",
    "negocio": {
      "id": "uuid",
      "nombre": "Mi Negocio",
      "userlimit": 10,
      "limitTime": "2025-12-31T00:00:00.000Z",
      "locallimit": 5,
      "productlimit": 1000
    },
    "localActual": {
      "id": "uuid",
      "nombre": "Tienda Principal",
      "negocioId": "uuid",
      "tipo": "TIENDA"
    },
    "locales": [
      {
        "id": "uuid",
        "nombre": "Tienda Principal",
        "negocioId": "uuid",
        "tipo": "TIENDA"
      }
    ],
    "permisos": ["operaciones.pos-venta.acceder", "operaciones.pos-venta.vender"]
  },
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Response Error (401):**
```json
{
  "error": "Usuario o contraseña incorrectos"
}
```

**Response Error (403):**
```json
{
  "error": "No tienes locales asignados. Contacta al administrador."
}
```

---

### POST /auth/refresh

Refresca el token JWT actual.

**URL:** `/api/app/auth/refresh`

**Headers:**
```
Content-Type: application/json
Authorization: Bearer <token>
```

**Request Body:** Ninguno

**Response Success (200):**
```json
{
  "success": true,
  "user": {
    "id": "uuid",
    "nombre": "Juan Pérez",
    "usuario": "jperez",
    "rol": "VENDEDOR",
    "negocio": { ... },
    "localActual": { ... },
    "locales": [ ... ],
    "permisos": [ ... ]
  },
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Response Error (401):**
```json
{
  "error": "No autenticado"
}
```

---

### POST /auth/cambiar-tienda

Cambia la tienda/local actual del usuario.

**URL:** `/api/app/auth/cambiar-tienda`

**Headers:**
```
Content-Type: application/json
Authorization: Bearer <token>
```

**Request Body:**
```json
{
  "tiendaId": "uuid"    // ID de la tienda a la que se quiere cambiar
}
```

**Response Success (200):**
```json
{
  "success": true,
  "user": {
    "id": "uuid",
    "nombre": "Juan Pérez",
    "usuario": "jperez",
    "rol": "VENDEDOR",
    "negocio": { ... },
    "localActual": {
      "id": "uuid",
      "nombre": "Nueva Tienda",
      "negocioId": "uuid",
      "tipo": "TIENDA"
    },
    "locales": [ ... ],
    "permisos": [ ... ]
  },
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Response Error (403):**
```json
{
  "error": "No tienes acceso a esta tienda"
}
```

---

## Productos

### GET /productos/{tiendaId}

Obtiene todos los productos disponibles para venta en una tienda.

**URL:** `/api/app/productos/{tiendaId}`

**Headers:**
```
Authorization: Bearer <token>
```

**Path Parameters:**
| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| tiendaId | string (uuid) | ID de la tienda |

**Response Success (200):**
```json
{
  "success": true,
  "productos": [
    {
      "id": "uuid",                    // ID del ProductoTienda (usar para ventas)
      "productoId": "uuid",            // ID del Producto base
      "nombre": "Coca Cola 600ml",
      "descripcion": "Refresco de cola",
      "precio": 25.00,
      "costo": 18.00,
      "existencia": 50,
      "permiteDecimal": false,
      "categoria": {
        "id": "uuid",
        "nombre": "Bebidas",
        "color": "#FF5733"
      },
      "codigos": [
        {
          "id": "uuid",
          "codigo": "7501055300846",
          "tipo": "EAN13"
        }
      ],
      "proveedor": null,               // null = producto propio
      "esFraccion": false,
      "fraccionDe": null,
      "unidadesPorFraccion": null
    },
    {
      "id": "uuid",
      "productoId": "uuid",
      "nombre": "Cigarros Marlboro (pieza)",
      "descripcion": "Cigarro individual",
      "precio": 12.00,
      "costo": 8.00,
      "existencia": 15,
      "permiteDecimal": false,
      "categoria": {
        "id": "uuid",
        "nombre": "Cigarros",
        "color": "#333333"
      },
      "codigos": [],
      "proveedor": null,
      "esFraccion": true,
      "fraccionDe": {
        "id": "uuid",
        "nombre": "Cigarros Marlboro (cajetilla)"
      },
      "unidadesPorFraccion": 20
    }
  ],
  "total": 2
}
```

---

## Período/Cierre de Caja

### GET /periodo/{tiendaId}/actual

Obtiene el período actual (abierto o último cerrado) de una tienda.

**URL:** `/api/app/periodo/{tiendaId}/actual`

**Headers:**
```
Authorization: Bearer <token>
```

**Path Parameters:**
| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| tiendaId | string (uuid) | ID de la tienda |

**Response Success (200) - Período Abierto:**
```json
{
  "success": true,
  "periodo": {
    "id": "uuid",
    "fechaInicio": "2024-01-15T08:00:00.000Z",
    "fechaFin": null,
    "tiendaId": "uuid",
    "totalVentas": 0,
    "totalGanancia": 0,
    "totalInversion": 0,
    "totalTransferencia": 0
  },
  "estaAbierto": true
}
```

**Response Success (200) - Período Cerrado:**
```json
{
  "success": true,
  "periodo": {
    "id": "uuid",
    "fechaInicio": "2024-01-15T08:00:00.000Z",
    "fechaFin": "2024-01-15T22:00:00.000Z",
    "tiendaId": "uuid",
    "totalVentas": 5420.50,
    "totalGanancia": 1250.00,
    "totalInversion": 4170.50,
    "totalTransferencia": 1200.00
  },
  "estaAbierto": false
}
```

**Response Success (200) - Sin Períodos:**
```json
{
  "success": true,
  "periodo": null,
  "estaAbierto": false,
  "mensaje": "No hay períodos creados para esta tienda"
}
```

---

### POST /periodo/{tiendaId}/abrir

Abre un nuevo período de caja.

**URL:** `/api/app/periodo/{tiendaId}/abrir`

**Headers:**
```
Content-Type: application/json
Authorization: Bearer <token>
```

**Path Parameters:**
| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| tiendaId | string (uuid) | ID de la tienda |

**Request Body:** Ninguno

**Response Success (201):**
```json
{
  "success": true,
  "periodo": {
    "id": "uuid",
    "fechaInicio": "2024-01-16T08:00:00.000Z",
    "fechaFin": null,
    "tiendaId": "uuid"
  },
  "estaAbierto": true
}
```

**Response Error (400):**
```json
{
  "error": "Ya existe un período abierto. Ciérralo antes de abrir uno nuevo."
}
```

---

## Ventas

### POST /venta/{tiendaId}/{periodoId}

Crea una nueva venta. Soporta sincronización offline mediante `syncId`.

**URL:** `/api/app/venta/{tiendaId}/{periodoId}`

**Headers:**
```
Content-Type: application/json
Authorization: Bearer <token>
```

**Path Parameters:**
| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| tiendaId | string (uuid) | ID de la tienda |
| periodoId | string (uuid) | ID del período de caja |

**Request Body:**
```json
{
  "syncId": "uuid",                    // REQUERIDO: UUID único generado en el cliente
  "createdAt": 1705401600000,          // REQUERIDO: Timestamp de creación (milliseconds)
  "productos": [                        // REQUERIDO: Array de productos
    {
      "productoTiendaId": "uuid",      // ID del ProductoTienda
      "cantidad": 2,                    // Cantidad vendida
      "name": "Coca Cola 600ml",       // Nombre (opcional, para logging)
      "precio": 25.00                  // Precio unitario
    }
  ],
  "total": 50.00,                      // Total de la venta
  "totalcash": 50.00,                  // Pago en efectivo
  "totaltransfer": 0,                  // Pago por transferencia
  "transferDestinationId": null,       // ID destino de transferencia (opcional)
  "wasOffline": false,                 // true si se creó sin conexión
  "syncAttempts": 0,                   // Número de intentos de sincronización
  "discountCodes": ["PROMO10"]         // Códigos de descuento (opcional)
}
```

**Response Success (201):**
```json
{
  "success": true,
  "venta": {
    "id": "uuid",
    "tiendaId": "uuid",
    "usuarioId": "uuid",
    "cierrePeriodoId": "uuid",
    "total": 45.00,
    "totalcash": 50.00,
    "totaltransfer": 0,
    "discountTotal": 5.00,
    "syncId": "uuid",
    "frontendCreatedAt": "2024-01-16T10:00:00.000Z",
    "wasOffline": false,
    "syncAttempts": 0,
    "productos": [
      {
        "id": "uuid",
        "productoTiendaId": "uuid",
        "cantidad": 2,
        "precio": 25.00,
        "costo": 18.00
      }
    ]
  },
  "duplicado": false
}
```

**Response Success (200) - Venta Duplicada (idempotencia):**
```json
{
  "success": true,
  "venta": { ... },
  "duplicado": true
}
```

**Response Error (400):**
```json
{
  "error": "No existe un período abierto en la tienda"
}
```

**Response Error (500):**
```json
{
  "error": "Existencia insuficiente para Coca Cola 600ml"
}
```

---

### GET /venta/{tiendaId}/{periodoId}

Obtiene las ventas de un período específico.

**URL:** `/api/app/venta/{tiendaId}/{periodoId}`

**Headers:**
```
Authorization: Bearer <token>
```

**Path Parameters:**
| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| tiendaId | string (uuid) | ID de la tienda |
| periodoId | string (uuid) | ID del período de caja |

**Response Success (200):**
```json
{
  "success": true,
  "ventas": [
    {
      "id": "uuid",
      "createdAt": "2024-01-16T10:30:00.000Z",
      "total": 125.50,
      "totalcash": 100.00,
      "totaltransfer": 25.50,
      "discountTotal": 10.00,
      "tiendaId": "uuid",
      "usuarioId": "uuid",
      "cierrePeriodoId": "uuid",
      "syncId": "uuid",
      "usuario": {
        "id": "uuid",
        "nombre": "Juan Pérez"
      },
      "productos": [
        {
          "id": "uuid",
          "ventaId": "uuid",
          "productoTiendaId": "uuid",
          "cantidad": 3,
          "name": "Coca Cola 600ml",
          "price": 25.00
        }
      ],
      "appliedDiscounts": [
        {
          "id": "uuid",
          "discountRuleId": "uuid",
          "ventaId": "uuid",
          "amount": 10.00,
          "ruleName": "10% en bebidas",
          "productsAffected": [
            { "productoTiendaId": "uuid", "cantidad": 3 }
          ]
        }
      ]
    }
  ],
  "total": 1
}
```

---

### GET /venta/{tiendaId}/{periodoId}/{ventaId}

Obtiene el detalle de una venta específica.

**URL:** `/api/app/venta/{tiendaId}/{periodoId}/{ventaId}`

**Headers:**
```
Authorization: Bearer <token>
```

**Path Parameters:**
| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| tiendaId | string (uuid) | ID de la tienda |
| periodoId | string (uuid) | ID del período de caja |
| ventaId | string (uuid) | ID de la venta |

**Response Success (200):**
```json
{
  "success": true,
  "venta": {
    "id": "uuid",
    "createdAt": "2024-01-16T10:30:00.000Z",
    "total": 125.50,
    "totalcash": 100.00,
    "totaltransfer": 25.50,
    "discountTotal": 10.00,
    "tiendaId": "uuid",
    "usuarioId": "uuid",
    "cierrePeriodoId": "uuid",
    "syncId": "uuid",
    "wasOffline": false,
    "usuario": {
      "id": "uuid",
      "nombre": "Juan Pérez"
    },
    "productos": [
      {
        "id": "uuid",
        "productoTiendaId": "uuid",
        "cantidad": 3,
        "precio": 25.00,
        "costo": 18.00,
        "nombre": "Coca Cola 600ml",
        "proveedor": null
      }
    ],
    "appliedDiscounts": [
      {
        "id": "uuid",
        "discountRuleId": "uuid",
        "amount": 10.00,
        "ruleName": "10% en bebidas"
      }
    ],
    "transferDestination": {
      "id": "uuid",
      "nombre": "Banco XYZ"
    }
  }
}
```

**Response Error (404):**
```json
{
  "error": "Venta no encontrada"
}
```

---

### DELETE /venta/{tiendaId}/{periodoId}/{ventaId}

Cancela/elimina una venta. Solo funciona si el período está abierto.

**URL:** `/api/app/venta/{tiendaId}/{periodoId}/{ventaId}`

**Headers:**
```
Authorization: Bearer <token>
```

**Path Parameters:**
| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| tiendaId | string (uuid) | ID de la tienda |
| periodoId | string (uuid) | ID del período de caja |
| ventaId | string (uuid) | ID de la venta a cancelar |

**Permisos Requeridos:** `operaciones.pos-venta.cancelarventa` o `operaciones.ventas.eliminar`

**Response Success (200):**
```json
{
  "success": true,
  "message": "Venta cancelada correctamente"
}
```

**Response Error (400):**
```json
{
  "error": "No se puede cancelar una venta de un período cerrado"
}
```

**Response Error (403):**
```json
{
  "error": "No tienes permiso para cancelar ventas"
}
```

**Response Error (404):**
```json
{
  "error": "Venta no encontrada"
}
```

---

## Descuentos

### POST /descuentos/preview

Previsualiza los descuentos que se aplicarían a una venta antes de crearla.

**URL:** `/api/app/descuentos/preview`

**Headers:**
```
Content-Type: application/json
Authorization: Bearer <token>
```

**Request Body:**
```json
{
  "tiendaId": "uuid",
  "products": [
    {
      "productoTiendaId": "uuid",
      "cantidad": 3,
      "precio": 25.00
    }
  ],
  "discountCodes": ["PROMO10"]         // Opcional: códigos de descuento
}
```

**Response Success (200):**
```json
{
  "success": true,
  "originalTotal": 75.00,
  "discountTotal": 7.50,
  "finalTotal": 67.50,
  "applied": [
    {
      "discountRuleId": "uuid",
      "ruleName": "10% en bebidas",
      "amount": 7.50,
      "type": "PERCENTAGE",
      "productsAffected": [
        { "productoTiendaId": "uuid", "cantidad": 3 }
      ]
    }
  ]
}
```

---

## Destinos de Transferencia

### GET /transfer-destinations/{tiendaId}

Obtiene los destinos de transferencia disponibles para una tienda.

**URL:** `/api/app/transfer-destinations/{tiendaId}`

**Headers:**
```
Authorization: Bearer <token>
```

**Path Parameters:**
| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| tiendaId | string (uuid) | ID de la tienda |

**Response Success (200):**
```json
{
  "success": true,
  "destinos": [
    {
      "id": "uuid",
      "nombre": "Banco XYZ - Cuenta Principal",
      "descripcion": "Cuenta empresarial",
      "default": true
    },
    {
      "id": "uuid",
      "nombre": "Mercado Pago",
      "descripcion": null,
      "default": false
    }
  ],
  "total": 2
}
```

---

## Códigos de Error Comunes

| Código | Descripción |
|--------|-------------|
| 400 | Bad Request - Datos faltantes o inválidos |
| 401 | Unauthorized - Token no proporcionado o inválido |
| 403 | Forbidden - Sin permisos para realizar la acción |
| 404 | Not Found - Recurso no encontrado |
| 500 | Internal Server Error - Error del servidor |

---

## Flujo de Sincronización Offline

1. **Al crear una venta offline:**
   - Generar un `syncId` único (UUID v4)
   - Guardar el timestamp en `createdAt` (milliseconds)
   - Marcar `wasOffline: true`
   - Guardar localmente en la app

2. **Al recuperar conexión:**
   - Enviar las ventas pendientes al endpoint POST
   - El servidor usa `syncId` para evitar duplicados
   - Si la venta ya existe, retorna `duplicado: true`
   - Incrementar `syncAttempts` en cada reintento

3. **Validaciones del servidor:**
   - Verifica que el período siga abierto
   - Verifica existencia de productos
   - Si el período ya cerró, rechaza la sincronización

---

## Tipos de Datos

### TipoTienda
```
"TIENDA" | "ALMACEN"
```

### TipoDescuento
```
"PERCENTAGE" | "FIXED" | "PROMO_CODE"
```

### Roles Comunes
```
"SUPER_ADMIN" | "ADMIN" | "VENDEDOR" | "CAJERO" | (roles personalizados)
```

---

## Ejemplo de Flujo Completo

```
1. Login
   POST /api/app/auth/login
   → Obtener token

2. Cargar datos iniciales (en paralelo)
   GET /api/app/productos/{tiendaId}        // Incluye categorías en cada producto
   GET /api/app/periodo/{tiendaId}/actual
   GET /api/app/transfer-destinations/{tiendaId}

3. Verificar período
   - Si estaAbierto = false, mostrar opción de abrir
   - POST /api/app/periodo/{tiendaId}/abrir

4. Realizar venta
   - (Opcional) POST /api/app/descuentos/preview
   - POST /api/app/venta/{tiendaId}/{periodoId}

5. Ver historial
   GET /api/app/venta/{tiendaId}/{periodoId}

6. Cancelar venta (si necesario)
   DELETE /api/app/venta/{tiendaId}/{periodoId}/{ventaId}
```

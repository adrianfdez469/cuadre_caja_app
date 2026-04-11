# Prompt: Asociar código de barras desconocido a producto existente (APK Flutter)

## Contexto del sistema

La aplicación es un POS (punto de venta) multisucursal llamado **Cuadre de Caja**. Los usuarios venden productos escaneando códigos de barras. Cuando un código escaneado no coincide con ningún producto cargado, el flujo actual simplemente muestra un error.

Esta feature permite que un vendedor con el permiso adecuado pueda, en ese mismo momento, **asociar el código desconocido a un producto existente** en su tienda, eliminando la dependencia del administrador para registrar nuevos códigos.

---

## Sistema de permisos

Los permisos llegan en el JWT del usuario autenticado como un string con tokens separados por `|`. Por ejemplo:

```
operaciones.pos-venta.acceder|operaciones.pos-venta.asociar_codigo|operaciones.cierre.acceder
```

El permiso requerido para esta feature es:

```
operaciones.pos-venta.asociar_codigo
```

Para verificar si el usuario tiene un permiso, simplemente comprueba si el string de permisos contiene el token buscado (split por `|` e includes). Los usuarios con rol `SUPER_ADMIN` tienen todos los permisos implícitamente.

---

## API Endpoint

### `POST /api/app/productos/{productoId}/agregar-codigo`

Asocia un código de barras a un producto existente.

**Autenticación:** Bearer token en el header `Authorization`.

**Header requerido:**
```
Authorization: Bearer <jwt_token>
Content-Type: application/json
```

**Path param:**
- `productoId` (`string`) — ID del producto al que se quiere asociar el código.

**Body:**
```json
{
  "codigo": "7501234567890"
}
```

**Respuestas:**

| Status | Descripción | Body |
|--------|-------------|------|
| `201` | Código asociado exitosamente | `{ "success": true, "codigo": { "id": "uuid", "codigo": "7501234567890", "productoId": "uuid" } }` |
| `400` | El campo `codigo` está vacío o ausente | `{ "error": "El campo \"codigo\" es requerido" }` |
| `401` | Sin autenticación | `{ "error": "No autenticado" }` |
| `403` | Sin el permiso requerido | `{ "error": "No tiene permiso para asociar códigos de barras" }` |
| `404` | El `productoId` no existe o no pertenece al negocio del usuario | `{ "error": "Producto no encontrado" }` |
| `409` | El código ya está registrado en otro producto | `{ "error": "Este código ya está asociado a otro producto" }` |
| `500` | Error interno del servidor | `{ "error": "Error al agregar el código al producto" }` |

---

## Flujo de usuario que debes implementar

### 1. Trigger: código escaneado no encontrado

Cuando el scanner (cámara o pistola Bluetooth) lee un código que **no coincide con ningún producto** cargado en la lista local del POS:

- Si el usuario **tiene** el permiso `operaciones.pos-venta.asociar_codigo` → mostrar el **diálogo de asociación** (ver sección siguiente).
- Si el usuario **no tiene** el permiso → mostrar únicamente el error habitual ("Producto no encontrado").

### 2. Diálogo / Bottom Sheet de asociación

Mostrar un modal o bottom sheet con el siguiente contenido:

#### Encabezado
- Ícono de advertencia/enlace
- Título: **"Código no reconocido"**

#### Cuerpo
- Texto descriptivo: *"El código escaneado no está registrado. Puedes asociarlo a un producto existente para agilizar futuras ventas."*
- Mostrar el código escaneado en una etiqueta destacada (estilo `chip` o `badge`), por ejemplo: `7501234567890`
- **Campo de búsqueda** con ícono de lupa: filtra en tiempo real la lista de productos cargados localmente (los que ya están en memoria del POS).
  - La búsqueda es **local** (no requiere llamada a la API), sobre el nombre del producto.
  - Normalizar la búsqueda: ignorar tildes, mayúsculas/minúsculas.
  - Mostrar hasta 8 resultados.
  - Cada resultado muestra: nombre del producto, precio y stock actual.
- Una vez seleccionado un producto, mostrar un mensaje de confirmación: *"Se asociará el código `{codigo}` a `{nombre del producto}`"*.

#### Acciones
- **Cancelar** — cierra el diálogo sin hacer nada.
- **Asociar código** — activo solo cuando hay un producto seleccionado. Llama al API y:
  - Mientras espera: mostrar indicador de carga en el botón.
  - En éxito (`201`):
    - Actualizar la lista local del POS para que el código quede indexado en ese producto (sin necesidad de recargar todo).
    - Cerrar el diálogo.
    - Mostrar snackbar/toast de éxito: *"Código asociado a '{nombre del producto}'"*.
    - Reproducir sonido de éxito si el sistema lo soporta.
    - Mostrar automáticamente el producto seleccionado para que el vendedor lo agregue al carrito.
  - En error `409` (código ya existe en otro producto): mostrar el mensaje de error dentro del diálogo, no cerrarlo.
  - En cualquier otro error: mostrar el mensaje de error dentro del diálogo.

---

## Actualización del estado local tras asociar

Después de una asociación exitosa, **actualizar en memoria** la lista de productos del POS para que el nuevo código quede inmediatamente disponible sin necesidad de recargar. El objeto de producto en la lista local tiene un array `codigos`; agregar el nuevo código a ese array del producto correspondiente.

Estructura del producto en la lista local (referencia del modelo que devuelve `GET /api/app/productos/{tiendaId}`):

```json
{
  "id": "productoTiendaId",
  "productoId": "uuid-del-producto",
  "nombre": "Coca Cola 600ml",
  "precio": 25.0,
  "existencia": 48,
  "codigos": [
    { "id": "uuid", "codigo": "7501055300075", "productoId": "uuid" }
  ],
  ...
}
```

Tras asociar, agregar `{ "id": "uuid-del-nuevo", "codigo": "7501234567890", "productoId": "uuid" }` al array `codigos` del producto en la lista local.

---

## Lógica de búsqueda de producto por código (referencia)

El POS ya debe tener implementado un índice o búsqueda de productos por código. La lógica es:

```
para cada producto en la lista local:
  para cada codigo en producto.codigos:
    si codigo.codigo == codigoEscaneado:
      retornar producto
retornar null
```

Este es el punto exacto donde, si se retorna `null` y el usuario tiene el permiso, se dispara el diálogo.

---

## Resumen de cambios necesarios en la APK

1. **Servicio/repositorio de productos**: agregar método `asociarCodigo(productoId: String, codigo: String)` que llame al endpoint descrito.

2. **Lógica del POS (ViewModel o BLoC)**: al detectar código no encontrado, verificar el permiso y emitir un estado/evento que abra el diálogo de asociación pasando el código escaneado.

3. **Widget/Screen `AsociarCodigoDialog`**: implementar el diálogo según el diseño descrito.

4. **Estado local**: tras asociar con éxito, mutar la lista de productos en memoria para reflejar el nuevo código sin recargar.

5. **Verificador de permisos**: si no existe ya, implementar una utilidad que reciba el string de permisos del usuario (`operaciones.pos-venta.acceder|...`) y verifique si contiene un permiso específico.

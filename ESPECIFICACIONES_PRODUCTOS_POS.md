# Especificaciones de Negocio: Manejo de Productos en el POS

Este documento describe en detalle las reglas de negocio y especificaciones técnicas relacionadas con cómo se muestran, manejan y procesan los productos en el sistema POS (Punto de Venta). Estas especificaciones están basadas en la implementación actual del código y deben ser replicadas en la aplicación móvil (APK) de Flutter.

---

## 1. Información Mostrada de los Productos

### 1.1 Campos Básicos del Producto

Cada producto en el POS muestra la siguiente información:

- **Nombre del producto**: `producto.nombre`
  - Si el producto tiene proveedor asociado, se muestra como: `"${producto.nombre} - ${proveedor.nombre}"`
  - Si no tiene proveedor, solo se muestra el nombre del producto

- **Precio**: `precio` (Float)
  - Se muestra con formato de moneda: `$${precio}`
  - El precio es específico por tienda (`ProductoTienda.precio`)

- **Existencia**: `existencia` (Float)
  - Cantidad disponible en stock en la tienda actual
  - Soporta valores decimales (para productos que permiten decimales)

- **Descripción**: `producto.descripcion` (opcional)
  - Se muestra si está disponible

### 1.2 Información de Disponibilidad Mostrada

La información de disponibilidad se calcula y muestra de manera diferente según el tipo de producto:

#### Productos Normales (No Fracción)

Para productos que **NO** son fracción (`fraccionDeId === null` o `unidadesPorFraccion === null`):

- **Formato de visualización**: `"Cant: ${disponible}"`
- **Cálculo de disponible**:
  ```typescript
  disponible = existencia - cantidadEnCarrito
  ```
- **Máximo permitido**: `existencia` (sin restricciones adicionales)

#### Productos Fracción

Para productos que **SÍ** son fracción (`fraccionDeId !== null` y `unidadesPorFraccion > 0`):

- **Formato de visualización**: `"Stock: ${existenciaReal} | Máx: ${disponible}"`
- **Cálculo de existencia real**:
  ```typescript
  existenciaReal = Math.max(0, producto.existencia || 0)
  ```
- **Cálculo de disponibilidad total**:
  ```typescript
  // Buscar producto padre
  productoPadre = productos.find(p => p.productoId === fraccionDeId)
  existenciaPadre = productoPadre ? Math.max(0, productoPadre.existencia || 0) : 0
  
  // Disponibilidad total = existencia actual + (cajas del padre * unidades por caja)
  disponibilidadTotal = existenciaProducto + (existenciaPadre * unidadesPorFraccion)
  ```
- **Máximo por transacción**:
  ```typescript
  maxFraccion = Math.max(0, unidadesPorFraccion - 1)
  maxPorTransaccion = Math.min(disponibilidadTotal, maxFraccion)
  ```
- **Cálculo de disponible para mostrar**:
  ```typescript
  disponible = maxPorTransaccion - cantidadEnCarrito
  ```

**Ejemplo práctico**:
- Producto fracción: "Cigarro Suelto"
- `unidadesPorFraccion = 20` (una caja tiene 20 cigarrillos)
- `existencia` del fracción = 5 (hay 5 cigarrillos sueltos)
- `existencia` del padre (Caja) = 2 (hay 2 cajas)
- Disponibilidad total = 5 + (2 * 20) = 45 unidades
- Máximo por transacción = min(45, 19) = 19 unidades
- Si hay 3 en el carrito: disponible = 19 - 3 = 16

### 1.3 Información en el Diálogo de Cantidad

Cuando se selecciona un producto para agregar al carrito, se muestra un diálogo con:

- **Nombre del producto**: `productoTienda.producto.nombre`
- **Precio**: `$${productoTienda.precio}`
- **Información de stock**:
  - **Productos normales**: `"Disponibles: ${getMaxForDisplay()}"`
  - **Productos fracción**: `"Stock: ${existenciaReal} | Máx. por venta: ${getMaxForDisplay()}"`

---

## 2. Filtrado y Reglas de Exclusión de Productos

### 2.1 Filtrado por Precio

**Regla**: Solo se muestran productos con `precio > 0`

```typescript
productos.filter((prod) => prod.precio > 0)
```

**Razón de negocio**: Los productos con precio 0 no deben aparecer en el POS porque no tienen precio de venta definido. Estos productos deben configurarse primero antes de poder venderse.

### 2.2 Filtrado por Existencia

**Regla general**: Se filtran productos con `existencia <= 0`, **EXCEPTO** para productos fracción que tienen existencia en el producto padre.

**Lógica de filtrado**:

```typescript
productos.filter((p) => {
  if (p.existencia <= 0) {
    // Si el producto tiene unidades por fracción, verificar que el producto padre tenga existencia
    if (p.producto.fraccionDeId !== null) {
      const pPadre = productos.find(
        (padre) => padre.productoId === p.producto.fraccionDeId
      );
      if (pPadre && pPadre.existencia > 0) {
        return true; // Incluir producto fracción aunque tenga existencia 0
      }
    }
    return false; // Excluir producto sin existencia
  }
  return true; // Incluir producto con existencia > 0
})
```

**Razón de negocio**: 
- Un producto fracción puede tener existencia 0 en sí mismo, pero si el producto padre (caja) tiene existencia, se puede desagregar para vender unidades sueltas.
- Un producto normal sin existencia no puede venderse, por lo que se excluye.

### 2.3 Ordenamiento

Los productos se ordenan alfabéticamente por nombre:

```typescript
productos.sort((a, b) => a.producto.nombre.localeCompare(b.producto.nombre))
```

---

## 3. Manejo de Cantidades en el Carrito

### 3.1 Agregar Producto al Carrito

Cuando se agrega un producto al carrito:

1. **Validación de cantidad máxima**:
   - Para productos normales: `cantidad <= existencia - cantidadYaEnCarrito`
   - Para productos fracción: `cantidad <= maxPorTransaccion - cantidadYaEnCarrito`
     - Donde `maxPorTransaccion = min(disponibilidadTotal, unidadesPorFraccion - 1)`

2. **Actualización del carrito**:
   - Si el producto ya existe en el carrito: se suma la cantidad nueva a la existente
   - Si el producto no existe: se agrega como nuevo ítem

3. **Cálculo del total**:
   ```typescript
   total = items.reduce((sum, item) => sum + item.price * item.quantity, 0)
   ```

### 3.2 Actualizar Cantidad en el Carrito

**Validación al incrementar**:

```typescript
const maxQuantity = productoTienda.producto.unidadesPorFraccion
  ? productoTienda.producto.unidadesPorFraccion - 1  // Producto fracción
  : productoTienda.existencia;  // Producto normal

if (quantity > maxQuantity) {
  return; // No permitir incrementar más allá del máximo
}
```

**Nota importante**: La validación considera la cantidad que ya está en el carrito, por lo que el máximo real disponible es `maxQuantity - cantidadEnCarrito`.

### 3.3 Eliminar Producto del Carrito

Al eliminar un producto del carrito:
- Se remueve el ítem de la lista
- Se recalcula el total
- **NO se restituyen las existencias locales** (solo se restituyen al cancelar una venta completa)

### 3.4 Limpiar Carrito

Al limpiar el carrito:
- Se eliminan todos los ítems del carrito activo
- El total se establece en 0
- **NO se restituyen las existencias locales** (solo se restituyen al cancelar una venta completa)

---

## 4. Rebaja de Cantidades en Ambiente Local

### 4.1 Al Agregar al Carrito

**IMPORTANTE**: En la implementación actual, **NO se rebajan las existencias locales al agregar productos al carrito**. Las existencias solo se rebajan cuando se completa una venta (al procesar el pago).

### 4.2 Al Procesar una Venta (handleMakePay)

Cuando se procesa una venta, se actualizan las existencias locales de la siguiente manera:

#### 4.2.1 Identificación de Desagregaciones Necesarias

Primero se identifican qué productos fracción necesitan desagregación:

```typescript
const desagregaciones = [];

cart.forEach((cartProd) => {
  const productoEnTienda = productosTienda.find(p => p.id === cartProd.productoTiendaId);
  if (productoEnTienda && productoEnTienda.producto.fraccionDeId) {
    // Es un producto fracción
    if (productoEnTienda.existencia < cartProd.quantity) {
      // Necesita desagregación
      desagregaciones.push({
        padreProductoId: productoEnTienda.producto.fraccionDeId,
        cantidad: 1, // Siempre desagrega 1 unidad del padre
        hijoId: productoEnTienda.id,
        unidadesPorFraccion: productoEnTienda.producto.unidadesPorFraccion || 0
      });
    }
  }
});
```

**Regla**: Solo se desagrega si `existenciaFraccion < cantidadAVender`.

#### 4.2.2 Actualización de Existencias

Se actualizan las existencias de todos los productos:

```typescript
const newProds = productosTienda.map((p) => {
  let nuevaExistencia = p.existencia;

  // 1. Verificar si este producto es padre de alguna desagregación
  const desagregacionPadre = desagregaciones.find(d => d.padreProductoId === p.productoId);
  if (desagregacionPadre) {
    // Restar 1 del producto padre
    nuevaExistencia -= desagregacionPadre.cantidad;
  }

  // 2. Verificar si este producto es hijo de alguna desagregación
  const desagregacionHijo = desagregaciones.find(d => d.hijoId === p.id);
  if (desagregacionHijo) {
    // Sumar las unidades por fracción
    nuevaExistencia += desagregacionHijo.unidadesPorFraccion;
  }

  // 3. Verificar si este producto está en el carrito (venta)
  const cartProd = cart.find((cartItem) => cartItem.productoTiendaId === p.id);
  if (cartProd) {
    // Restar la cantidad vendida
    nuevaExistencia -= cartProd.quantity;
  }

  return {...p, existencia: nuevaExistencia};
});
```

**Orden de operaciones**:
1. Primero se procesan las desagregaciones (restar del padre, sumar al hijo)
2. Luego se restan las cantidades vendidas

**Ejemplo práctico**:
- Venta: 25 cigarrillos sueltos
- Existencia fracción: 5
- Existencia padre (caja): 2
- Proceso:
  1. Se necesita desagregar porque 5 < 25
  2. Se resta 1 caja del padre: existenciaPadre = 2 - 1 = 1
  3. Se suman 20 unidades al fracción: existenciaFraccion = 5 + 20 = 25
  4. Se restan 25 unidades vendidas: existenciaFraccion = 25 - 25 = 0
  5. Resultado final: fracción = 0, padre = 1

### 4.3 Validación de Existencias Antes de Vender

Antes de procesar la venta, el backend valida que haya suficiente existencia:

```typescript
if (existenciaAnterior < producto.cantidad) {
  throw new Error(`Existencia insuficiente para realizar la venta de productoTiendaId: ${producto.productoTiendaId}`);
}
```

Esta validación se hace **después** de procesar las desagregaciones, por lo que considera la existencia resultante después de desagregar.

---

## 5. Restitución de Cantidades al Cancelar Ventas

### 5.1 Al Eliminar una Venta Local

Cuando se elimina una venta que aún no está sincronizada (venta local):

```typescript
sale.productos.forEach((p) => {
  incrementarCantidades(p.productoTiendaId, p.cantidad);
});
```

La función `incrementarCantidades` incrementa la existencia local:

```typescript
const incrementarCantidades = (id: string, cantidad: number) => {
  const productIndex = productosTienda.findIndex(p => p.id === id);
  if (productIndex !== -1) {
    const newProds = [...productosTienda];
    newProds[productIndex] = {
      ...newProds[productIndex],
      existencia: newProds[productIndex].existencia + cantidad
    };
    setProductosTienda(newProds);
  }
}
```

**IMPORTANTE**: Esta restitución es simple y directa. **NO revierte las desagregaciones** que se hicieron al crear la venta. Esto significa que:

- Si se vendieron 25 cigarrillos sueltos que requirieron desagregación:
  - Al cancelar, se suman 25 unidades al fracción
  - Pero NO se revierte la desagregación (no se suma 1 caja al padre ni se restan 20 unidades del fracción)

**Nota**: Esta es una limitación conocida de la implementación actual. Para una implementación correcta, se debería:
1. Guardar información de las desagregaciones realizadas en la venta
2. Al cancelar, revertir las desagregaciones (sumar 1 al padre, restar unidadesPorFraccion al hijo)
3. Luego restituir las cantidades vendidas

### 5.2 Al Eliminar una Venta Sincronizada

Cuando se elimina una venta que ya está sincronizada con el backend:

1. **Si hay conexión**: Se llama al endpoint `DELETE /api/app/venta/[tiendaId]/[periodoId]/[ventaId]`
   - El backend revierte automáticamente todos los movimientos de stock
   - Incluye reversión de desagregaciones si las hubo

2. **Siempre**: Se restituyen las cantidades en el almacenamiento local:
   ```typescript
   sale.productos.forEach((p) => {
     incrementarCantidades(p.productoTiendaId, p.cantidad);
   });
   ```

3. **Actualización de productos**: Se recargan los productos desde el servidor si hay conexión:
   ```typescript
   if (isOnline) {
     fetchProductosAndCategories(true);
   }
   ```

### 5.3 Reversión en el Backend

El backend maneja la reversión de manera completa:

```typescript
// Buscar los movimientos generados por la venta
const movimientos = await prisma.movimientoStock.findMany({
  where: { referenciaId: ventaId }
});

// Generar operaciones de reversión
movimientos.forEach((mov) => {
  let tipoMov: MovimientoTipo;
  if (mov.tipo === 'VENTA' || mov.tipo === 'DESAGREGACION_BAJA') {
    tipoMov = MovimientoTipo.AJUSTE_ENTRADA; // Revertir (sumar)
  } else {
    tipoMov = MovimientoTipo.AJUSTE_SALIDA; // Revertir (restar)
  }

  // Actualizar existencia
  await prisma.productoTienda.update({
    where: { id: mov.productoTiendaId },
    data: {
      existencia: {
        increment: isMovimientoBaja(tipoMov) ? -mov.cantidad : mov.cantidad,
      },
    }
  });
});
```

Esto asegura que todas las operaciones (ventas y desagregaciones) se reviertan correctamente.

---

## 6. Reglas de Negocio para Productos con Precio 0

### 6.1 Exclusión del POS

**Regla**: Los productos con `precio === 0` **NO se muestran** en el POS.

**Razón**: Un producto sin precio no puede venderse. Debe configurarse primero un precio antes de poder incluirlo en ventas.

### 6.2 Validación en el Backend

El backend también valida que los productos tengan precio > 0 antes de procesar una venta. Si un producto tiene precio 0, la venta fallará con un error.

---

## 7. Reglas de Negocio para Productos con Existencia 0

### 7.1 Productos Normales

**Regla**: Los productos normales con `existencia <= 0` **NO se muestran** en el POS.

**Razón**: No hay stock disponible para vender.

### 7.2 Productos Fracción

**Regla especial**: Los productos fracción con `existencia <= 0` **SÍ se muestran** si el producto padre tiene existencia > 0.

**Lógica**:
```typescript
if (p.existencia <= 0) {
  if (p.producto.fraccionDeId !== null) {
    const pPadre = productos.find(
      (padre) => padre.productoId === p.producto.fraccionDeId
    );
    if (pPadre && pPadre.existencia > 0) {
      return true; // Mostrar aunque tenga existencia 0
    }
  }
  return false; // No mostrar
}
```

**Razón**: Se puede desagregar una caja del producto padre para generar unidades del fracción.

**Ejemplo**:
- Cigarro Suelto: existencia = 0
- Caja de Cigarro: existencia = 5
- Resultado: Se muestra "Cigarro Suelto" porque se puede desagregar de las cajas

---

## 8. Tratamiento Detallado de Productos Fracción

### 8.1 Definición

Un producto fracción es un producto que se deriva de otro producto (producto padre) mediante desagregación. Ejemplos:
- Cigarro Suelto (fracción) ← Caja de Cigarro (padre)
- Botella de Cerveza (fracción) ← Caja de Cerveza (padre)

**Campos relacionados**:
- `fraccionDeId`: ID del producto padre (null si no es fracción)
- `unidadesPorFraccion`: Cantidad de unidades que se generan al desagregar 1 unidad del padre

### 8.2 Cálculo de Disponibilidad

#### Disponibilidad Total

```typescript
existenciaProducto = Math.max(0, producto.existencia || 0)
existenciaPadre = productoPadre ? Math.max(0, productoPadre.existencia || 0) : 0
disponibilidadTotal = existenciaProducto + (existenciaPadre * unidadesPorFraccion)
```

#### Máximo por Transacción

**Regla crítica**: Un producto fracción **NO puede venderse en cantidades mayores o iguales a `unidadesPorFraccion`** en una sola transacción.

```typescript
maxFraccion = Math.max(0, unidadesPorFraccion - 1)
maxPorTransaccion = Math.min(disponibilidadTotal, maxFraccion)
```

**Razón de negocio**: Si se intenta vender `unidadesPorFraccion` o más unidades, debería venderse como producto padre (caja completa) en lugar de fracción.

**Ejemplo**:
- `unidadesPorFraccion = 20`
- Disponibilidad total = 45 unidades
- Máximo por transacción = min(45, 19) = 19 unidades
- Si el cliente quiere 20 o más, debe comprar cajas completas

### 8.3 Validación al Agregar al Carrito

```typescript
const maxQuantity = productoTienda.producto.unidadesPorFraccion
  ? productoTienda.producto.unidadesPorFraccion - 1
  : productoTienda.existencia;

if (quantity > maxQuantity) {
  return; // No permitir
}
```

### 8.4 Desagregación Automática

Cuando se procesa una venta y un producto fracción necesita más unidades de las que tiene disponibles:

**Condición para desagregar**:
```typescript
if (productoEnTienda.existencia < cartProd.quantity) {
  // Necesita desagregación
}
```

**Proceso de desagregación**:
1. Se resta **1 unidad** del producto padre
2. Se suman `unidadesPorFraccion` unidades al producto fracción
3. Luego se procesa la venta normalmente

**Ejemplo**:
- Venta: 25 cigarrillos sueltos
- Existencia fracción: 5
- Existencia padre: 2 cajas
- `unidadesPorFraccion`: 20

Proceso:
1. Se detecta que 5 < 25, necesita desagregación
2. Se resta 1 caja del padre: padre = 2 - 1 = 1
3. Se suman 20 unidades al fracción: fracción = 5 + 20 = 25
4. Se restan 25 unidades vendidas: fracción = 25 - 25 = 0
5. Resultado: fracción = 0, padre = 1

### 8.5 Validación en el Backend

El backend valida que no se vendan más unidades fracción de las permitidas:

```typescript
if (prodFracc.producto.unidadesPorFraccion <= prod.cantidad) {
  throw new Error(`Vendes más unidades sueltas de las que lleva una caja en una misma venta`);
}
```

Esta validación asegura que `cantidad < unidadesPorFraccion`.

### 8.6 Visualización en la UI

**En listado de productos**:
- Formato: `"Stock: ${existenciaReal} | Máx: ${disponible}"`
- `existenciaReal`: Existencia actual del fracción (sin considerar padre)
- `disponible`: Máximo disponible considerando padre y límite de transacción

**En diálogo de cantidad**:
- Formato: `"Stock: ${existenciaReal} | Máx. por venta: ${maxPorTransaccion}"`
- Muestra claramente el límite de transacción

### 8.7 Restricción de Cantidad Mínima

**No hay restricción de cantidad mínima** para productos fracción. Se puede vender desde 1 unidad hasta `unidadesPorFraccion - 1`.

---

## 9. Productos con Decimales

### 9.1 Campo `permiteDecimal`

Algunos productos pueden tener `permiteDecimal === true`, lo que permite cantidades decimales.

### 9.2 Manejo en el Diálogo de Cantidad

Si `permiteDecimal === true`:
- Cantidad inicial mínima: `0.1` (en lugar de `1`)
- Incrementos disponibles: `+0.01`, `+0.1`, `+0.5`, `+1`, `+10`, `+50`, `+100`
- Decrementos disponibles: `-0.01`, `-0.1`, `-0.5`, `-1`, `-10`, `-50`, `-100`
- Los valores se redondean a 2 decimales para evitar problemas de punto flotante

### 9.3 Validación

La cantidad debe ser `> 0` y `<= maxQuantity`. No hay restricción adicional para decimales.

---

## 10. Resumen de Reglas Críticas

### 10.1 Filtrado de Productos

1. ✅ Mostrar solo productos con `precio > 0`
2. ✅ Excluir productos normales con `existencia <= 0`
3. ✅ Incluir productos fracción con `existencia <= 0` si el padre tiene existencia > 0

### 10.2 Cálculo de Disponibilidad

1. ✅ Productos normales: `disponible = existencia - cantidadEnCarrito`
2. ✅ Productos fracción: `disponible = min(disponibilidadTotal, unidadesPorFraccion - 1) - cantidadEnCarrito`
3. ✅ Disponibilidad total fracción: `existenciaFraccion + (existenciaPadre * unidadesPorFraccion)`

### 10.3 Validación de Cantidades

1. ✅ Máximo para productos normales: `existencia`
2. ✅ Máximo para productos fracción: `unidadesPorFraccion - 1`
3. ✅ Validar antes de agregar al carrito y antes de procesar venta

### 10.4 Actualización de Existencias

1. ✅ **NO** rebajar existencias al agregar al carrito
2. ✅ Rebajar existencias al procesar venta
3. ✅ Procesar desagregaciones antes de rebajar cantidades vendidas
4. ✅ Restituir existencias al cancelar venta (con limitación actual en reversión de desagregaciones)

### 10.5 Desagregación

1. ✅ Solo desagregar si `existenciaFraccion < cantidadAVender`
2. ✅ Siempre desagregar 1 unidad del padre
3. ✅ Sumar `unidadesPorFraccion` al fracción
4. ✅ Validar que `cantidad < unidadesPorFraccion` antes de procesar

---

## 11. Consideraciones para la Implementación en Flutter

### 11.1 Estructura de Datos

Mantener la misma estructura de datos:
- `ProductoTienda`: id, precio, existencia, productoId, proveedorId
- `Producto`: id, nombre, descripcion, fraccionDeId, unidadesPorFraccion, permiteDecimal, codigosProducto

### 11.2 Cálculos

Implementar las mismas funciones de cálculo:
- `calcularDisponibilidadReal()`: Para calcular disponibilidad considerando fracciones
- `getMaxQuantity()`: Para obtener máximo permitido según tipo de producto
- Validaciones antes de agregar al carrito y antes de procesar venta

### 11.3 Manejo de Estado Local

- Mantener estado local de productos (`productosTienda`)
- Actualizar existencias solo al procesar ventas
- Restituir existencias al cancelar ventas
- Considerar implementar reversión completa de desagregaciones (mejora sobre la implementación actual)

### 11.4 Sincronización

- Al sincronizar ventas exitosamente, recargar productos desde el servidor
- Al cancelar ventas sincronizadas, esperar confirmación del servidor antes de actualizar estado local
- Manejar casos de desconexión durante cancelación

### 11.5 Validaciones

Implementar todas las validaciones:
- Precio > 0
- Existencia suficiente (considerando desagregaciones)
- Máximo por transacción para fracciones
- Cantidad > 0 y <= máximo

---

## 12. Casos Especiales y Edge Cases

### 12.1 Producto Fracción sin Producto Padre

Si un producto fracción no tiene producto padre en la lista:
- `disponibilidadTotal = existenciaFraccion`
- `maxPorTransaccion = min(existenciaFraccion, unidadesPorFraccion - 1)`

### 12.2 Producto Fracción con unidadesPorFraccion Inválido

Si `unidadesPorFraccion <= 0` o es null:
- Se trata como producto normal
- No se aplican reglas de fracción

### 12.3 Múltiples Productos Fracción del Mismo Padre

Si hay múltiples productos fracción del mismo padre:
- Cada fracción se calcula independientemente
- Las desagregaciones se procesan por separado
- Una desagregación afecta solo al fracción que la necesita

### 12.4 Carrito con Múltiples Cantidades del Mismo Producto

Si se agrega el mismo producto múltiples veces al carrito:
- Las cantidades se suman
- La validación considera la cantidad total en el carrito
- El máximo disponible se calcula como `maxQuantity - cantidadTotalEnCarrito`

---

## Conclusión

Estas especificaciones cubren todos los aspectos del manejo de productos en el POS, incluyendo visualización, validaciones, actualización de existencias, manejo de fracciones y restitución de cantidades. La implementación en Flutter debe seguir estas mismas reglas para mantener consistencia con el sistema web.

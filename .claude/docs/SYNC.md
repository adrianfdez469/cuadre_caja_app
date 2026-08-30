# Offline-first sync model (read carefully before touching sync)

- **Reads** (`loadProductos`, `loadPeriodoActual`, `loadMultimonedaConfig`, …): try the API first, **fall back to the SQLite cache** on failure. `*LocalOnly` / `get*Local` variants read disk only (no network) — used to refresh the POS instantly after a sale.
- **Writes** (`crearVenta`): always persist to SQLite **first** (into `ventas_pendientes` with a client-generated `syncId`/UUID and `syncState`), then attempt to sync. A sale never blocks on the network.
- **The queue**: `ventas_pendientes` is the write-behind queue. A `Timer.periodic` (every 30s) plus a connectivity listener drain it via `_syncPendingVentas`. On reconnect, `_onConnectionRestored` runs **ventas-first, then refreshes server inventory last** so local stock isn't clobbered before pending sales are posted.
- **`fullSync`** does the full reconcile: período/destinos/monedas → pending ventas → server inventory.
- `SyncService` communicates back to the UI through **callbacks** (`onConnectionChanged`, `onSyncEvent`, `onDataRefreshed`, `onAuthRequired`, `onTokenRefreshed`) that providers register — not streams.
- **Vender sin existencias**: el flag `permitirSinStock` (`lib/core/utils/venta_sin_stock_policy.dart`) relaja toda validación de stock del POS — catálogo, carrito y escáner. Es true sin conexión **y** cuando el usuario activa el ajuste "Vender sin existencias" (`VentaSinStockProvider`, hoja "Cuenta"). Con conexión el servidor puede rechazar la venta con `Existencia insuficiente`: la venta queda en `syncState: error` en la cola y se reintenta desde la lista de ventas.
- Fracción products (sub-units) are "desagregated" into their parent before stock is decremented — see `crearVenta` and `lib/core/utils/producto_pos_rules.dart`.

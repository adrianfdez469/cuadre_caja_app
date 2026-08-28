# Multi-currency (multimoneda)

Sales can be paid in multiple currencies with exchange-rate snapshots stored on each pending venta (`tasaSnapshotJson`, `pagosDetalleJson`). Rates/currencies come from `/monedas/{negocioId}` and `/tasas-cambio/{negocioId}`. Payment math is isolated in `lib/core/utils/payment_logic.dart` and is the best-tested code in the repo — keep it pure and covered.

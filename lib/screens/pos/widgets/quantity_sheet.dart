import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/producto_pos_rules.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../data/models/producto_model.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/monedas_provider.dart';
import '../../../providers/productos_provider.dart';
import '../../../services/hardware_scanner_gate.dart';
import '../../../widgets/numeric_keypad.dart';

/// Hoja de cantidad compartida por la pantalla de venta y el catálogo: elegir
/// cuántas unidades de un producto agregar al carrito, con teclado numérico
/// propio (nunca el del sistema) y atajos rápidos, según `pos-mobile-estados.html`.
class QuantitySheet {
  QuantitySheet._();

  static Future<void> show(
    BuildContext context, {
    required ProductoModel producto,
    required bool isOnline,
  }) async {
    final productosProvider = context.read<ProductosProvider>();
    final cart = context.read<CartProvider>().activeCart;
    final offlineMode = !isOnline;
    final cantidadEnCarrito = cart?.items
            .where((i) => i.productoTiendaId == producto.id)
            .fold<double>(0, (s, i) => s + i.cantidad) ??
        0;
    final maxDisp = ProductoPosRules.getMaxQuantity(
      producto,
      productosProvider.allProductos,
      cantidadEnCarrito: cantidadEnCarrito,
      offlineMode: offlineMode,
    );
    if (!offlineMode && maxDisp <= 0) return;

    HardwareScannerGate.instance.block('quantity_sheet');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _QuantitySheetContent(
        parentContext: context,
        producto: producto,
        isOnline: isOnline,
        maxDisp: maxDisp,
        cantidadEnCarrito: cantidadEnCarrito,
      ),
    ).whenComplete(
      () => HardwareScannerGate.instance.unblock('quantity_sheet'),
    );
  }
}

class _QuantitySheetContent extends StatefulWidget {
  /// Contexto de la pantalla que abrió la hoja: sigue montado después de
  /// cerrarla, a diferencia del contexto propio de la hoja.
  final BuildContext parentContext;
  final ProductoModel producto;
  final bool isOnline;
  final double maxDisp;
  final double cantidadEnCarrito;

  const _QuantitySheetContent({
    required this.parentContext,
    required this.producto,
    required this.isOnline,
    required this.maxDisp,
    required this.cantidadEnCarrito,
  });

  @override
  State<_QuantitySheetContent> createState() => _QuantitySheetContentState();
}

class _QuantitySheetContentState extends State<_QuantitySheetContent> {
  late double _cantidad = widget.producto.permiteDecimal ? 0.1 : 1.0;

  /// Dígitos crudos tecleados en esta sesión del teclado numérico (`null`
  /// mientras no se haya tecleado nada, o tras usar un atajo rápido). Evita
  /// que el primer dígito se anexe sobre la cantidad inicial precargada.
  String? _keypadRaw;

  bool get _permiteDecimal => widget.producto.permiteDecimal;

  String get _cantidadText =>
      _cantidad.toStringAsFixed(_permiteDecimal ? 2 : 0);

  void _setCantidad(double value) {
    var next = value;
    if (_permiteDecimal) {
      next = (next * 100).round() / 100;
      if (next < 0.1) next = 0.1;
    } else {
      next = next.roundToDouble();
      if (next < 1) next = 1;
    }
    if (widget.maxDisp.isFinite && next > widget.maxDisp) next = widget.maxDisp;
    setState(() => _cantidad = next);
  }

  /// Atajo rápido: suma sobre la cantidad actual y reinicia el teclado.
  void _addQuickAmount(double delta) {
    _keypadRaw = null;
    _setCantidad(_cantidad + delta);
  }

  void _appendDigit(String digit) {
    final raw = (_keypadRaw ?? '') + digit;
    final next = double.tryParse(raw);
    if (next == null) return;
    _keypadRaw = raw;
    _setCantidad(_permiteDecimal ? next / 100 : next);
  }

  void _backspace() {
    final raw = _keypadRaw ?? '';
    if (raw.length <= 1) {
      _keypadRaw = null;
      _setCantidad(_permiteDecimal ? 0.1 : 1);
      return;
    }
    final trimmed = raw.substring(0, raw.length - 1);
    _keypadRaw = trimmed;
    final next = double.tryParse(trimmed) ?? 0;
    _setCantidad(_permiteDecimal ? next / 100 : next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final producto = widget.producto;
    final productosProvider = context.read<ProductosProvider>();
    final monedas = context.watch<MonedasProvider>();
    final precioUnitBase =
        monedas.precioEnBase(producto.precio, producto.monedaPrecioCode);
    final subtotalBase = precioUnitBase * _cantidad;
    final stockLabel = ProductoPosRules.textoStockEnDialogo(
      producto,
      productosProvider.allProductos,
      cantidadEnCarrito: widget.cantidadEnCarrito,
      offlineMode: !widget.isOnline,
    );
    final puedeConfirmar = _cantidad > 0 &&
        (!widget.maxDisp.isFinite || _cantidad <= widget.maxDisp);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ProductoPosRules.nombreParaMostrar(producto),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (stockLabel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        stockLabel,
                        style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _cantidadText,
                    style: tabularNums(TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      color: colors.accent,
                    )),
                  ),
                  Text(
                    Formatters.formatMonedaAmount(
                      subtotalBase,
                      simbolo: monedas.simboloFor(monedas.monedaBase),
                      code: monedas.monedaBase,
                    ),
                    style: tabularNums(
                      TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: (_permiteDecimal
                    ? [0.1, 1.0, 10.0, 50.0]
                    : [1.0, 10.0, 50.0, 100.0])
                .map(
                  (d) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: OutlinedButton(
                        onPressed: () => _addQuickAmount(d),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(AppTapTarget.min),
                          side: BorderSide(color: colors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                        child: Text('+${d == d.roundToDouble() ? d.toInt() : d}'),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          NumericKeypad(
            cornerLabel: _permiteDecimal ? null : '00',
            onDigit: _appendDigit,
            onBackspace: _backspace,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: puedeConfirmar
                ? () async {
                    final parentContext = widget.parentContext;
                    final ok = await context.read<CartProvider>().addToCart(
                          producto,
                          cantidad: _cantidad,
                          allProductos: productosProvider.allProductos,
                          isOnline: widget.isOnline,
                        );
                    Navigator.of(context).pop();
                    if (!parentContext.mounted) return;
                    if (ok) {
                      AppSnackBar.show(
                        parentContext,
                        content: Text(
                          '${ProductoPosRules.nombreParaMostrar(producto)} x$_cantidadText agregado',
                        ),
                        backgroundColor: colors.positive,
                        duration: const Duration(seconds: 1),
                      );
                    } else {
                      AppSnackBar.show(
                        parentContext,
                        content: const Text('Cantidad supera el máximo disponible'),
                        backgroundColor: colors.negative,
                      );
                    }
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
              minimumSize: const Size.fromHeight(AppTapTarget.comfortable),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: Text('Agregar $_cantidadText'),
          ),
        ],
      ),
    );
  }
}

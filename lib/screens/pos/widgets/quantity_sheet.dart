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

  /// Paso del stepper "-"/"+": la unidad mínima manejable del producto.
  double get _step => _permiteDecimal ? 0.1 : 1.0;

  String get _stepText => _permiteDecimal ? '0.1' : '1';

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

  /// Atajo rápido: suma (o resta) sobre la cantidad actual y reinicia el teclado.
  void _addQuickAmount(double delta) {
    _keypadRaw = null;
    _setCantidad(_cantidad + delta);
  }

  /// Saltos grandes de los atajos rápidos (el de a 1/0.1 lo cubre el stepper).
  List<double> get _bigSteps => _permiteDecimal ? [1.0, 10.0, 50.0] : [10.0, 50.0, 100.0];

  Widget _quickAmountChip(AppSemanticColors colors, double d, {required bool subtract}) {
    final delta = subtract ? -d : d;
    // El de "+" siempre se puede tocar (ya se satura solo en el máximo
    // disponible); el de "-" se deshabilita si no queda margen para restarlo.
    final habilitado = !subtract || (_cantidad - d) >= _step - 0.0001;
    final label = '${subtract ? '-' : '+'}${d == d.roundToDouble() ? d.toInt() : d}';
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: OutlinedButton(
          onPressed: habilitado ? () => _addQuickAmount(delta) : null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(AppTapTarget.min),
            side: BorderSide(color: colors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
          ),
        ),
      ),
    );
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
              // Paso a paso ("-"/"+" de a una unidad) junto al número: los
              // atajos de abajo solo suman, esta es la única forma de restar.
              _StepButton(
                icon: Icons.remove,
                tooltip: 'Quitar $_stepText',
                onTap: () => _addQuickAmount(-_step),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
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
              const SizedBox(width: 8),
              _StepButton(
                icon: Icons.add,
                tooltip: 'Agregar $_stepText',
                onTap: () => _addQuickAmount(_step),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // El paso de a 1 (o 0.1) ya lo cubre el stepper "-"/"+" de arriba;
          // acá solo quedan los saltos grandes, de a + y de a -.
          Row(
            children: [
              for (final d in _bigSteps)
                _quickAmountChip(colors, d, subtract: false),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final d in _bigSteps)
                _quickAmountChip(colors, d, subtract: true),
            ],
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

/// Botón cuadrado "-"/"+" del stepper de cantidad.
class _StepButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: AppTapTarget.min,
        height: AppTapTarget.min,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            side: BorderSide(color: colors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: Icon(icon, size: 18, color: colors.textPrimary),
        ),
      ),
    );
  }
}

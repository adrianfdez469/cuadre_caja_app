import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Para qué se abrió la hoja de cantidad.
enum QuantitySheetMode {
  /// Desde el catálogo: se elige cuánto **sumar** al carrito y la hoja lo hace.
  agregar,

  /// Desde una línea del carrito: se elige la cantidad **total** de esa línea y
  /// la hoja se limita a devolverla. Ver [QuantitySheet.editar].
  editar,
}

/// Hoja de cantidad compartida por la pantalla de venta y el catálogo: elegir
/// cuántas unidades de un producto agregar al carrito, con teclado numérico
/// propio (nunca el del sistema) y atajos rápidos, según `pos-mobile-estados.html`.
class QuantitySheet {
  QuantitySheet._();

  static Future<void> show(
    BuildContext context, {
    required ProductoModel producto,
    required bool permitirSinStock,
  }) async {
    final productosProvider = context.read<ProductosProvider>();
    final cart = context.read<CartProvider>().activeCart;
    final cantidadEnCarrito = cart?.items
            .where((i) => i.productoTiendaId == producto.id)
            .fold<double>(0, (s, i) => s + i.cantidad) ??
        0;
    final maxDisp = ProductoPosRules.getMaxQuantity(
      producto,
      productosProvider.allProductos,
      cantidadEnCarrito: cantidadEnCarrito,
      permitirSinStock: permitirSinStock,
    );
    if (!permitirSinStock && maxDisp <= 0) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _QuantitySheetContent(
        parentContext: context,
        producto: producto,
        permitirSinStock: permitirSinStock,
        maxDisp: maxDisp,
        cantidadEnCarrito: cantidadEnCarrito,
      ),
    );
  }

  /// Edita la cantidad de una línea del carrito. Devuelve la cantidad elegida,
  /// o `null` si se cerró sin confirmar. **Cero es un resultado válido**:
  /// significa quitar la línea.
  ///
  /// A diferencia de [show], esta hoja **no toca el carrito**: solo elige un
  /// número. Aplicarlo es cosa de quien la abre, porque quitar la última línea
  /// implica además saltar a otra cuenta con productos o cerrar la vista, y esa
  /// lógica ya vive en la pantalla del carrito.
  ///
  /// [cantidadActual] es la de la línea y [maxTotal] el tope **total** que puede
  /// alcanzar (lo disponible más lo que ya está en la línea), no lo que aún
  /// cabría sumar.
  static Future<double?> editar(
    BuildContext context, {
    required ProductoModel producto,
    required bool permitirSinStock,
    required double cantidadActual,
    required double maxTotal,
  }) {
    // Sin la guarda de `show` (`maxDisp <= 0` corta): una línea que ya agotó el
    // stock tiene que poder abrirse, precisamente para bajarla.
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _QuantitySheetContent(
        parentContext: context,
        producto: producto,
        permitirSinStock: permitirSinStock,
        maxDisp: maxTotal,
        cantidadEnCarrito: cantidadActual,
        mode: QuantitySheetMode.editar,
        cantidadInicial: cantidadActual,
      ),
    );
  }
}

class _QuantitySheetContent extends StatefulWidget {
  /// Contexto de la pantalla que abrió la hoja: sigue montado después de
  /// cerrarla, a diferencia del contexto propio de la hoja.
  final BuildContext parentContext;
  final ProductoModel producto;
  final bool permitirSinStock;
  final double maxDisp;
  final double cantidadEnCarrito;
  final QuantitySheetMode mode;

  /// Cantidad con la que arranca la hoja. `null` = la mínima manejable del
  /// producto (1, o 0.1 si admite fracción), que es lo que quiere el catálogo.
  final double? cantidadInicial;

  const _QuantitySheetContent({
    required this.parentContext,
    required this.producto,
    required this.permitirSinStock,
    required this.maxDisp,
    required this.cantidadEnCarrito,
    this.mode = QuantitySheetMode.agregar,
    this.cantidadInicial,
  });

  bool get esEdicion => mode == QuantitySheetMode.editar;

  @override
  State<_QuantitySheetContent> createState() => _QuantitySheetContentState();
}

class _QuantitySheetContentState extends State<_QuantitySheetContent> {
  late double _cantidad = widget.cantidadInicial ??
      (widget.producto.permiteDecimal ? 0.1 : 1.0);

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

  /// Lo que se muestra en grande: mientras se teclea manda el texto crudo, para
  /// que un "1." en curso se vea tal cual y no como "1.00".
  String get _displayText => _keypadRaw ?? _cantidadText;

  /// Cero es un estado válido: el borrado deja la cantidad en cero. Al agregar,
  /// el botón de confirmar se apaga solo; al editar, pasa a "Quitar del carrito".
  void _setCantidad(double value) {
    var next = value;
    if (_permiteDecimal) {
      next = (next * 100).round() / 100;
    } else {
      next = next.roundToDouble();
    }
    if (next < 0) next = 0;
    if (widget.maxDisp.isFinite && next > widget.maxDisp) next = widget.maxDisp;
    setState(() => _cantidad = next);
  }

  /// `double.tryParse` no acepta un punto suelto al final ("1."), que es un
  /// estado normal mientras se teclea.
  double _parseRaw(String raw) {
    final limpio = raw.endsWith('.') ? raw.substring(0, raw.length - 1) : raw;
    return double.tryParse(limpio) ?? 0;
  }

  /// Atajo rápido: suma (o resta) sobre la cantidad actual y reinicia el teclado.
  void _addQuickAmount(double delta) {
    _keypadRaw = null;
    _setCantidad(_cantidad + delta);
  }

  /// Saltos de los atajos rápidos. En productos por fracción se ofrece la
  /// escala fina completa, porque ahí el stepper de a 0.1 se queda corto.
  List<double> get _bigSteps =>
      _permiteDecimal ? [0.1, 0.5, 1.0, 10.0] : [10.0, 50.0, 100.0];

  Widget _quickAmountChip(AppSemanticColors colors, double d, {required bool subtract}) {
    final delta = subtract ? -d : d;
    // El de "+" siempre se puede tocar (ya se satura solo en el máximo
    // disponible); el de "-" se deshabilita si no queda margen para restarlo.
    // Restar puede llegar hasta cero, que ahora es un estado válido.
    final habilitado = !subtract || (_cantidad - d) >= -0.0001;
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

  /// El número se teclea literal: "1", "." y "5" dan 1.5. Con `_keypadRaw` en
  /// `null` —al abrir la hoja o tras un atajo— la primera tecla reemplaza la
  /// cantidad precargada en vez de anexarse a ella.
  void _appendDigit(String digit) {
    var raw = _keypadRaw ?? '';
    if (digit == '.') {
      if (!_permiteDecimal || raw.contains('.')) return;
      raw = raw.isEmpty ? '0.' : '$raw.';
    } else {
      final punto = raw.indexOf('.');
      // Dos decimales como mucho: es la precisión con la que se guarda.
      if (punto >= 0 && raw.length - punto > 2) return;
      raw = raw + digit;
    }

    final next = _parseRaw(raw);
    setState(() => _keypadRaw = raw);
    _setCantidad(next);
    // Si el stock disponible recortó la cantidad, el texto crudo dejaría de
    // reflejarla y hay que volver al valor real.
    if ((_cantidad - next).abs() > 0.0001) {
      setState(() => _keypadRaw = null);
    }
  }

  void _backspace() {
    final raw = _keypadRaw ?? '';
    if (raw.length <= 1) {
      setState(() => _keypadRaw = null);
      _setCantidad(0);
      return;
    }
    final trimmed = raw.substring(0, raw.length - 1);
    setState(() => _keypadRaw = trimmed);
    _setCantidad(_parseRaw(trimmed));
  }

  /// Texto del botón principal. Al editar, cero deja de ser "guardar" para
  /// pasar a ser lo que de verdad va a ocurrir: quitar la línea.
  String get _etiquetaConfirmar {
    if (!widget.esEdicion) return 'Agregar $_cantidadText';
    if (_cantidad <= 0) return 'Quitar del carrito';
    return 'Guardar $_cantidadText';
  }

  /// Modo agregar: suma al carrito y cierra. (En modo edición la hoja solo
  /// devuelve la cantidad; ver [QuantitySheet.editar].)
  Future<void> _confirmarAgregado() async {
    final colors = context.colors;
    final producto = widget.producto;
    final productosProvider = context.read<ProductosProvider>();
    final parentContext = widget.parentContext;

    final ok = await context.read<CartProvider>().addToCart(
          producto,
          cantidad: _cantidad,
          allProductos: productosProvider.allProductos,
          permitirSinStock: widget.permitirSinStock,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!parentContext.mounted) return;

    if (ok) {
      unawaited(HapticFeedback.lightImpact());
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
      permitirSinStock: widget.permitirSinStock,
    );
    // Al agregar, 0 no tiene sentido y apaga el botón. Al editar sí lo tiene:
    // significa quitar la línea del carrito.
    final puedeConfirmar = (_cantidad > 0 || widget.esEdicion) &&
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
                    _displayText,
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
            cornerLabel: _permiteDecimal ? '.' : '00',
            onDigit: _appendDigit,
            onBackspace: _backspace,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: !puedeConfirmar
                ? null
                : widget.esEdicion
                    // La hoja no toca el carrito: devuelve la cantidad y quien
                    // la abrió decide (actualizar, o quitar la línea y cerrar
                    // la vista si la cuenta queda vacía).
                    ? () => Navigator.of(context).pop(_cantidad)
                    : _confirmarAgregado,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
              minimumSize: const Size.fromHeight(AppTapTarget.comfortable),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: Text(_etiquetaConfirmar),
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

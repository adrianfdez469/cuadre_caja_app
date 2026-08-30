import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/payment_logic.dart';
import 'monto_input_sheet.dart';

/// Reparto del cambio elegido en la hoja.
class CambioResult {
  /// Moneda → monto a devolver.
  final Map<String, double> vuelto;

  /// `true` si el cajero armó el reparto a mano: a partir de ahí el cálculo
  /// automático deja de pisarlo.
  final bool manual;

  const CambioResult({required this.vuelto, required this.manual});
}

/// Hoja "Cómo dar el cambio": los repartos que la app propone según los
/// billetes de la moneda con la que pagó el cliente, o uno armado a mano.
class CambioSheet extends StatefulWidget {
  /// Reparto actual (el automático si nunca se tocó).
  final Map<String, double> vueltoActual;

  final bool manualInicial;

  /// Total a devolver en moneda base.
  final double vueltoTotalBase;

  /// Moneda en la que el cliente entregó más efectivo.
  final String monedaCobro;

  final String monedaBase;
  final Map<String, double> tasas;

  /// Monedas en las que la tienda puede entregar cambio.
  final List<String> monedasElegibles;

  final Map<String, List<double>> denominaciones;

  const CambioSheet({
    super.key,
    required this.vueltoActual,
    required this.manualInicial,
    required this.vueltoTotalBase,
    required this.monedaCobro,
    required this.monedaBase,
    required this.tasas,
    required this.monedasElegibles,
    this.denominaciones = const {},
  });

  static Future<CambioResult?> show(
    BuildContext context, {
    required Map<String, double> vueltoActual,
    required bool manualInicial,
    required double vueltoTotalBase,
    required String monedaCobro,
    required String monedaBase,
    required Map<String, double> tasas,
    required List<String> monedasElegibles,
    Map<String, List<double>> denominaciones = const {},
  }) {
    return showModalBottomSheet<CambioResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CambioSheet(
        vueltoActual: vueltoActual,
        manualInicial: manualInicial,
        vueltoTotalBase: vueltoTotalBase,
        monedaCobro: monedaCobro,
        monedaBase: monedaBase,
        tasas: tasas,
        monedasElegibles: monedasElegibles,
        denominaciones: denominaciones,
      ),
    );
  }

  @override
  State<CambioSheet> createState() => _CambioSheetState();
}

class _CambioSheetState extends State<CambioSheet> {
  late List<Map<String, double>> _variantes;

  /// Índice de la variante marcada; `null` cuando está marcado "Otro reparto".
  int? _seleccionada;

  /// Montos escritos a mano, por moneda. Nunca incluye la moneda más fina: esa
  /// recibe el resto.
  final Map<String, double> _manual = {};

  late String _monedaFina;

  @override
  void initState() {
    super.initState();
    _monedaFina = CurrencyUtils.monedaMasFina(
      monedas: widget.monedasElegibles,
      denominaciones: widget.denominaciones,
      tasas: widget.tasas,
      monedaBase: widget.monedaBase,
    );
    _variantes = PaymentLogic.variantesDeVuelto(
      vueltoTotalBase: widget.vueltoTotalBase,
      monedaCobro: widget.monedaCobro,
      monedaBase: widget.monedaBase,
      tasas: widget.tasas,
      denominaciones: widget.denominaciones,
      monedasVuelto: widget.monedasElegibles,
    );

    if (widget.manualInicial) {
      for (final e in widget.vueltoActual.entries) {
        if (e.key != _monedaFina && e.value > 0) _manual[e.key] = e.value;
      }
    } else {
      // Se marca la variante que coincide con lo que ya está aplicado.
      final i = _variantes.indexWhere((v) => _mismoReparto(v, widget.vueltoActual));
      _seleccionada = i >= 0 ? i : (_variantes.isEmpty ? null : 0);
    }
  }

  bool _mismoReparto(Map<String, double> a, Map<String, double> b) {
    final ba = {
      for (final e in b.entries)
        if (e.value > 0) e.key: e.value,
    };
    if (a.length != ba.length) return false;
    return a.entries.every((e) => ba[e.key] == e.value);
  }

  bool get _esManual => _seleccionada == null;

  double get _repartidoBase => _manual.entries.fold<double>(
        0,
        (s, e) => s +
            CurrencyUtils.convertToBase(
              e.value,
              e.key,
              widget.tasas,
              widget.monedaBase,
            ),
      );

  /// Lo que queda por entregar, ya truncado a la denominación mínima de la
  /// moneda más fina: es el monto que se dará en ella.
  double get _resto {
    final pendiente = widget.vueltoTotalBase - _repartidoBase;
    if (pendiente <= 0) return 0;
    final denomMin =
        CurrencyUtils.denominacionMinima(_monedaFina, widget.denominaciones);
    final enFina = CurrencyUtils.convertFromBase(
      pendiente,
      _monedaFina,
      widget.tasas,
      widget.monedaBase,
    );
    final centimos = (enFina * 100).round();
    final pasoCentimos = (denomMin * 100).round();
    if (centimos <= 0 || pasoCentimos <= 0) return 0;
    return (centimos ~/ pasoCentimos) * pasoCentimos / 100;
  }

  /// Monedas que se pueden repartir a mano: todas menos la más fina, que es el
  /// destino del resto y por eso no aparece.
  List<String> get _monedasManuales =>
      widget.monedasElegibles.where((m) => m != _monedaFina).toList();

  Map<String, double> get _repartoActual {
    if (!_esManual) return _variantes[_seleccionada!];
    final resto = _resto;
    return {
      for (final e in _manual.entries)
        if (e.value > 0) e.key: e.value,
      if (resto > 0) _monedaFina: (_manual[_monedaFina] ?? 0) + resto,
    };
  }

  String _etiqueta(Map<String, double> reparto) {
    final partes = reparto.entries
        .where((e) => e.value > 0)
        .map((e) => '${Formatters.formatNumber(e.value)} ${e.key}')
        .toList();
    return partes.isEmpty ? 'Sin cambio' : partes.join(' + ');
  }

  Future<void> _editar(String moneda) async {
    final res = await MontoInputSheet.show(
      context,
      titulo: 'Cambio en $moneda',
      moneda: moneda,
      montoInicial: _manual[moneda] ?? 0,
      denominaciones: widget.denominaciones[moneda] ?? const [],
    );
    if (res == null || !mounted) return;
    setState(() {
      _seleccionada = null;
      if (res.monto <= 0) {
        _manual.remove(moneda);
        return;
      }
      // No se puede repartir más vuelto del que se debe: lo que exceda se
      // recorta para que el resto nunca quede en negativo.
      final otrosBase = _repartidoBase -
          CurrencyUtils.convertToBase(
            _manual[moneda] ?? 0,
            moneda,
            widget.tasas,
            widget.monedaBase,
          );
      final disponibleBase = widget.vueltoTotalBase - otrosBase;
      final maximo = CurrencyUtils.convertFromBase(
        disponibleBase,
        moneda,
        widget.tasas,
        widget.monedaBase,
      );
      _manual[moneda] = res.monto > maximo ? maximo.floorToDouble() : res.monto;
      if ((_manual[moneda] ?? 0) <= 0) _manual.remove(moneda);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cómo dar el cambio',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              '${Formatters.formatNumber(widget.vueltoTotalBase)} '
              '${widget.monedaBase} a dar',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < _variantes.length; i++)
              _opcion(
                colors,
                seleccionada: _seleccionada == i,
                label: _etiqueta(_variantes[i]),
                onTap: () => setState(() => _seleccionada = i),
              ),
            _opcion(
              colors,
              seleccionada: _esManual,
              label: 'Otro reparto',
              onTap: () => setState(() => _seleccionada = null),
            ),
            if (_esManual) ...[
              const SizedBox(height: 4),
              for (final moneda in _monedasManuales) _filaMoneda(colors, moneda),
              const SizedBox(height: 4),
              _filaResto(colors),
            ],
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                context,
                CambioResult(vuelto: _repartoActual, manual: _esManual),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.onAccent,
                minimumSize: const Size.fromHeight(AppTapTarget.comfortable),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: const Text(
                'Listo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _opcion(
    AppSemanticColors colors, {
    required bool seleccionada,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            Icon(
              seleccionada
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 22,
              color: seleccionada ? colors.accent : colors.textDisabled,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaMoneda(AppSemanticColors colors, String moneda) {
    return InkWell(
      key: Key('reparto-$moneda'),
      onTap: () => _editar(moneda),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppTapTarget.min),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: colors.accentWash,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                moneda,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.accent,
                ),
              ),
            ),
            const Spacer(),
            Text(
              formatMontoCampo(_manual[moneda] ?? 0),
              style: tabularNums(
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaResto(AppSemanticColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text(
            'Resto',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const Spacer(),
          Text(
            key: const Key('cambio-resto'),
            '${Formatters.formatNumber(_resto)} $_monedaFina',
            style: tabularNums(
              const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

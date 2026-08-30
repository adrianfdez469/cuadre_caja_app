import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/payment_logic.dart';
import '../../../widgets/numeric_keypad.dart';

/// Resultado de la hoja: el monto y, si se armó con billetes, cuántos de cada
/// denominación. El desglose se devuelve para poder reabrir la hoja con el
/// conteo intacto.
class MontoInputResult {
  final double monto;

  /// Denominación → cantidad. Vacío si el monto se tecleó.
  final Map<double, int> billetes;

  const MontoInputResult({required this.monto, this.billetes = const {}});
}

/// Hoja de entrada de montos del cobro. Los campos de la pantalla de cobro no
/// se editan con el teclado del sistema: se tocan y abren esto, que ofrece dos
/// formas de llegar al mismo número — teclearlo, o ir tocando los billetes que
/// el cliente entrega.
class MontoInputSheet extends StatefulWidget {
  /// Título de la hoja, p. ej. "Efectivo USD" o "Transferencia USD".
  final String titulo;

  /// Código de la moneda, para el sufijo del monto y la línea de contexto.
  final String moneda;

  /// Texto a la derecha de la línea de contexto, p. ej. "Falta 821,48 USD".
  final String? contexto;

  final double montoInicial;

  /// Denominaciones de la moneda. Si viene vacío, la pestaña "Billetes" no se
  /// ofrece y solo queda el teclado.
  final List<double> denominaciones;

  /// Conteo con el que se armó [montoInicial], si se armó con billetes.
  final Map<double, int> billetesIniciales;

  /// `false` en transferencias, donde no se cuentan billetes.
  final bool permiteBilletes;

  const MontoInputSheet({
    super.key,
    required this.titulo,
    required this.moneda,
    required this.montoInicial,
    this.contexto,
    this.denominaciones = const [],
    this.billetesIniciales = const {},
    this.permiteBilletes = true,
  });

  static Future<MontoInputResult?> show(
    BuildContext context, {
    required String titulo,
    required String moneda,
    required double montoInicial,
    String? contexto,
    List<double> denominaciones = const [],
    Map<double, int> billetesIniciales = const {},
    bool permiteBilletes = true,
  }) {
    return showModalBottomSheet<MontoInputResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MontoInputSheet(
        titulo: titulo,
        moneda: moneda,
        montoInicial: montoInicial,
        contexto: contexto,
        denominaciones: denominaciones,
        billetesIniciales: billetesIniciales,
        permiteBilletes: permiteBilletes,
      ),
    );
  }

  @override
  State<MontoInputSheet> createState() => _MontoInputSheetState();
}

class _MontoInputSheetState extends State<MontoInputSheet> {
  /// Dígitos tecleados. `null` mientras no se haya tecleado nada: el monto
  /// mostrado es entonces el inicial o el que suman los billetes.
  String? _tecleado;

  late Map<double, int> _billetes;

  /// Orden en que se tocaron los billetes, para que "Deshacer" quite el último.
  late List<double> _pila;

  bool _modoBilletes = false;

  /// El monto que se ve no lo escribió el usuario (viene de la pantalla, o de
  /// contar billetes), así que la primera tecla lo reemplaza en vez de
  /// añadirse: con 224 en pantalla, pulsar 2 debe dejar 2.
  bool _reemplazarAlTeclear = true;

  @override
  void initState() {
    super.initState();
    _billetes = Map<double, int>.from(widget.billetesIniciales);
    _pila = [
      for (final e in _billetes.entries) ...List.filled(e.value, e.key),
    ];
    // Se abre en la pestaña con la que se armó el monto.
    _modoBilletes = _puedeBilletes && _billetes.isNotEmpty;
    if (_billetes.isEmpty && widget.montoInicial > 0) {
      _tecleado = _formatEntero(widget.montoInicial);
    }
  }

  bool get _puedeBilletes =>
      widget.permiteBilletes && widget.denominaciones.isNotEmpty;

  List<double> get _denomsOrdenadas =>
      widget.denominaciones.where((d) => d > 0).toSet().toList()
        ..sort((a, b) => b.compareTo(a));

  double get _totalBilletes =>
      _billetes.entries.fold<double>(0, (s, e) => s + e.key * e.value);

  double get _monto {
    if (_billetes.isNotEmpty) return _totalBilletes;
    return double.tryParse(_tecleado ?? '') ?? 0;
  }

  static String _formatEntero(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void _appendDigit(String d) {
    setState(() {
      // Teclear reemplaza el desglose: ya no hay billetes que mostrar.
      _billetes = {};
      _pila = [];
      if (_reemplazarAlTeclear) {
        _reemplazarAlTeclear = false;
        _tecleado = d;
        return;
      }
      final actual = _tecleado ?? '';
      if (actual == '0') {
        _tecleado = d;
      } else if (actual.length < 12) {
        _tecleado = actual + d;
      }
    });
  }

  void _backspace() {
    setState(() {
      _billetes = {};
      _pila = [];
      // Borrar sobre un monto precargado sigue siendo útil (224 -> 22), así que
      // no se trata como "empezar de cero".
      _reemplazarAlTeclear = false;
      final actual = _tecleado ?? '';
      _tecleado = actual.length <= 1 ? null : actual.substring(0, actual.length - 1);
    });
  }

  void _agregarBillete(double denom) {
    setState(() {
      // Sumar billetes descarta lo tecleado a mano: el monto pasa a ser el
      // conteo, que es lo que el cajero tiene en la mano.
      _tecleado = null;
      _reemplazarAlTeclear = true;
      _billetes = {..._billetes, denom: (_billetes[denom] ?? 0) + 1};
      _pila = [..._pila, denom];
    });
  }

  void _deshacer() {
    if (_pila.isEmpty) return;
    setState(() {
      _reemplazarAlTeclear = true;
      final ultimo = _pila.last;
      _pila = _pila.sublist(0, _pila.length - 1);
      final restante = (_billetes[ultimo] ?? 0) - 1;
      final copia = Map<double, int>.from(_billetes);
      if (restante <= 0) {
        copia.remove(ultimo);
      } else {
        copia[ultimo] = restante;
      }
      _billetes = copia;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.titulo,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.moneda,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  if (widget.contexto != null)
                    Text(
                      widget.contexto!,
                      style: TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _buildMonto(colors),
              const SizedBox(height: 14),
              if (_puedeBilletes) ...[
                _buildToggle(colors),
                const SizedBox(height: 12),
              ],
              if (_modoBilletes) _buildBilletes(colors) else _buildTeclado(),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () => Navigator.pop(
                  context,
                  MontoInputResult(monto: _monto, billetes: _billetes),
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
      ),
    );
  }

  Widget _buildMonto(AppSemanticColors colors) {
    final monto = _monto;
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.accent, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              _formatEntero(monto),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tabularNums(
                TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.85,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              widget.moneda,
              style: TextStyle(fontSize: 15, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(AppSemanticColors colors) {
    Widget tab(String label, bool activo, VoidCallback onTap) {
      return Expanded(
        child: Material(
          color: activo ? colors.accent : colors.sunken,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              height: AppTapTarget.min,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: activo ? colors.onAccent : colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab('Teclado', !_modoBilletes, () => setState(() => _modoBilletes = false)),
        const SizedBox(width: 8),
        tab('Billetes', _modoBilletes, _irABilletes),
      ],
    );
  }

  /// Al pasar a "Billetes" se preselecciona el desglose del monto que hay: con
  /// 224 escritos, la pestaña abre con 2×100 + 1×20 + 4×1. Si el monto no se
  /// puede armar exactamente con los billetes de la moneda, se abre en blanco y
  /// el monto tecleado se conserva.
  void _irABilletes() {
    setState(() {
      _modoBilletes = true;
      if (_billetes.isNotEmpty) return;
      final desglose = PaymentLogic.desglosarEnBilletes(
        _monto,
        widget.denominaciones,
      );
      if (desglose == null || desglose.isEmpty) return;
      _billetes = desglose;
      // La pila arranca de mayor a menor, así que el primer "Deshacer" quita el
      // billete más chico: el ajuste más fino, que es lo que se espera.
      _pila = [
        for (final d in _denomsOrdenadas)
          ...List.filled(desglose[d] ?? 0, d),
      ];
      _tecleado = null;
      _reemplazarAlTeclear = true;
    });
  }

  Widget _buildTeclado() {
    return NumericKeypad(
      cornerLabel: '000',
      onDigit: _appendDigit,
      onBackspace: _backspace,
    );
  }

  Widget _buildBilletes(AppSemanticColors colors) {
    final denoms = _denomsOrdenadas;
    // Se agrupan de a 3 por fila, como en el diseño.
    final filas = <List<double>>[];
    for (var i = 0; i < denoms.length; i += 3) {
      filas.add(denoms.sublist(i, (i + 3).clamp(0, denoms.length)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final fila in filas)
          Row(
            children: [
              for (final d in fila)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Material(
                      color: colors.sunken,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: InkWell(
                        onTap: () => _agregarBillete(d),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: SizedBox(
                          height: AppTapTarget.comfortable,
                          child: Center(
                            child: Text(
                              _formatEntero(d),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Rellena la última fila para que las teclas no se ensanchen.
              for (var i = fila.length; i < 3; i++) const Expanded(child: SizedBox()),
            ],
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: colors.sunken,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in _denomsOrdenadas)
                      if ((_billetes[d] ?? 0) > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.raised,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(color: colors.border),
                          ),
                          child: Text(
                            '${_billetes[d]}×${_formatEntero(d)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _pila.isEmpty ? null : _deshacer,
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('Deshacer', style: TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Etiqueta del monto tal como se muestra en los campos de la pantalla de
/// cobro: sin decimales cuando es entero, con dos cuando no.
String formatMontoCampo(double monto) => monto == monto.roundToDouble()
    ? monto.toInt().toString()
    : Formatters.formatNumber(monto);

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/bill_denominations.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/moneda_model.dart';
import '../../data/models/pago_multimoneda_model.dart';
import '../../data/models/transfer_destination_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/monedas_provider.dart';
import '../../providers/periodo_provider.dart';
import '../../providers/productos_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/ventas_provider.dart';
import '../../services/sync_service.dart';
import '../../widgets/bill_breakdown_input.dart';

class _PagoMoneda {
  double cash;
  double transfer;
  String transferDestId;

  _PagoMoneda({
    this.cash = 0,
    this.transfer = 0,
    this.transferDestId = '',
  });
}

class PaymentModal extends StatefulWidget {
  const PaymentModal({super.key});

  @override
  State<PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends State<PaymentModal> {
  bool _isProcessing = false;
  bool _initialized = false;

  List<TransferDestinationModel> _transferDestinations = [];
  Map<String, _PagoMoneda> _pagosMap = {};
  Map<String, bool> _showPayBreakdown = {};
  Map<String, int> _payBreakdownResetKeys = {};
  Map<String, Map<double, int>> _savedBillBreakdowns = {};
  /// Por moneda: cash | transfer | mixed
  Map<String, String> _paymentMode = {};
  Map<String, double> _vueltoMap = {};
  bool _vueltoLocked = false;
  bool _showBaseBreakdown = false;
  int _baseBreakdownResetKey = 0;

  final Map<String, TextEditingController> _cashControllers = {};
  final Map<String, TextEditingController> _transferControllers = {};
  final Map<String, TextEditingController> _vueltoControllers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    final auth = context.read<AuthProvider>();
    final monedas = context.read<MonedasProvider>();
    final cart = context.read<CartProvider>();
    final total = monedas.cartTotal(cart.activeCart?.items ?? []);
    final monedaBase = monedas.monedaBase.isNotEmpty
        ? monedas.monedaBase
        : auth.monedaBase;

    final sync = context.read<SyncService>();
    final destinos = await sync.loadTransferDestinations(auth.tiendaId);
    if (!mounted) return;

    final defaultDestId = _defaultDestId(destinos);
    _transferDestinations = destinos;

    _initMoneda(monedaBase, cash: total, transferDestId: defaultDestId);

    setState(() => _initialized = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(_syncVueltoAuto);
    });
  }

  String _defaultDestId(List<TransferDestinationModel> destinos) {
    if (destinos.isEmpty) return '';
    if (destinos.length == 1) return destinos.first.id;
    try {
      return destinos.firstWhere((d) => d.isDefault).id;
    } catch (_) {
      return destinos.first.id;
    }
  }

  bool _admiteEfectivoMoneda(String moneda) {
    if (moneda == _monedaBase) return true;
    final info = _monedaInfo(moneda);
    return info?.admiteEfectivo ?? true;
  }

  bool _admiteTransferMoneda(String moneda) {
    if (moneda == _monedaBase) return true;
    final info = _monedaInfo(moneda);
    return info?.admiteTransferencia ?? false;
  }

  double _montoObjetivoMoneda(String moneda) {
    if (moneda == _monedaBase) return _total;
    return _suggestCash(moneda, excludeMoneda: moneda);
  }

  void _initMoneda(String moneda, {double cash = 0, String transferDestId = ''}) {
    final soloTransfer =
        !_admiteEfectivoMoneda(moneda) && _admiteTransferMoneda(moneda);

    if (soloTransfer) {
      _paymentMode[moneda] = 'transfer';
      _pagosMap[moneda] = _PagoMoneda(
        cash: 0,
        transfer: cash,
        transferDestId: transferDestId,
      );
      _cashControllers[moneda] = TextEditingController(text: '');
      _transferControllers[moneda] = TextEditingController(
        text: cash > 0 ? cash.toStringAsFixed(2) : '',
      );
    } else {
      _paymentMode[moneda] = 'cash';
      _pagosMap[moneda] = _PagoMoneda(
        cash: cash,
        transfer: 0,
        transferDestId: transferDestId,
      );
      _cashControllers[moneda] = TextEditingController(
        text: cash > 0 ? cash.toStringAsFixed(2) : '',
      );
      _transferControllers[moneda] = TextEditingController(text: '');
    }
  }

  void _setPaymentMode(String moneda, String mode) {
    final pago = _pagosMap[moneda];
    if (pago == null) return;
    final objetivo = _montoObjetivoMoneda(moneda);

    setState(() {
      _paymentMode[moneda] = mode;
      if (mode == 'transfer') {
        _showPayBreakdown[moneda] = false;
        if (moneda == _monedaBase) _showBaseBreakdown = false;
      }
      _clearSavedBreakdown(moneda);

      if (mode == 'transfer') {
        pago.cash = 0;
        pago.transfer = objetivo;
        _cashControllers[moneda]?.text = '';
        _transferControllers[moneda]?.text =
            objetivo > 0 ? objetivo.toStringAsFixed(2) : '';
      } else if (mode == 'mixed') {
        pago.cash = 0;
        pago.transfer = 0;
        _cashControllers[moneda]?.text = '';
        _transferControllers[moneda]?.text = '';
      } else {
        pago.cash = objetivo;
        pago.transfer = 0;
        _cashControllers[moneda]?.text =
            objetivo > 0 ? objetivo.toStringAsFixed(2) : '';
        _transferControllers[moneda]?.text = '';
      }
      _syncVueltoAuto();
    });
  }

  @override
  void dispose() {
    for (final c in _cashControllers.values) {
      c.dispose();
    }
    for (final c in _transferControllers.values) {
      c.dispose();
    }
    for (final c in _vueltoControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _total {
    final cart = context.read<CartProvider>();
    final monedas = context.read<MonedasProvider>();
    return monedas.cartTotal(cart.activeCart?.items ?? []);
  }

  MultimonedaConfig get _config {
    final auth = context.read<AuthProvider>();
    final monedas = context.read<MonedasProvider>();
    return monedas.config.negocioId.isNotEmpty
        ? monedas.config
        : MultimonedaConfig(
            negocioId: auth.negocioId,
            monedaBase: auth.monedaBase,
          );
  }

  String get _monedaBase => _config.monedaBase;
  Map<String, double> get _tasas => _config.tasasConversion;
  Map<String, double> get _tasasSnapshot => _config.tasasVigentes;

  Map<String, List<double>> get _denominaciones {
    final map = Map<String, List<double>>.from(_config.denominacionesPorMoneda);
    map.putIfAbsent('CUP', () => List<double>.from(BillDenominations.cup));
    if (!map.containsKey(_monedaBase) || map[_monedaBase]!.isEmpty) {
      if (_monedaBase == 'CUP') {
        map['CUP'] = List<double>.from(BillDenominations.cup);
      }
    }
    return map;
  }

  List<NegocioMonedaModel> get _monedasActivas => _config.monedasActivas;

  bool get _hasExtraCurrencies =>
      _monedasActivas.any((m) => m.monedaCode != _monedaBase);

  List<String> get _todasMonedas {
    final codes = <String>{_monedaBase};
    for (final m in _monedasActivas) {
      codes.add(m.monedaCode);
    }
    return codes.toList();
  }

  List<String> get _monedasDisponibles =>
      _todasMonedas.where((c) => !_pagosMap.containsKey(c)).toList();

  NegocioMonedaModel? _monedaInfo(String code) {
    try {
      return _monedasActivas.firstWhere((m) => m.monedaCode == code);
    } catch (_) {
      return null;
    }
  }

  double _convertToBase(double monto, String moneda) =>
      CurrencyUtils.convertToBase(monto, moneda, _tasas, _monedaBase);

  double _convertFromBase(double montoBase, String moneda) =>
      CurrencyUtils.convertFromBase(montoBase, moneda, _tasas, _monedaBase);

  String _fmtBase(double amount) =>
      Formatters.formatMonedaAmount(amount, code: _monedaBase);

  List<PagoLinea> get _pagosLinea {
    final lines = <PagoLinea>[];
    for (final entry in _pagosMap.entries) {
      final moneda = entry.key;
      final pago = entry.value;
      if (pago.cash > 0) {
        lines.add(PagoLinea(
          tipo: 'cash',
          moneda: moneda,
          monto: pago.cash,
          equivalenteBase: _convertToBase(pago.cash, moneda),
        ));
      }
      if (pago.transfer > 0) {
        lines.add(PagoLinea(
          tipo: 'transfer',
          moneda: moneda,
          monto: pago.transfer,
          equivalenteBase: _convertToBase(pago.transfer, moneda),
          transferDestinationId: pago.transferDestId.isNotEmpty
              ? pago.transferDestId
              : null,
        ));
      }
    }
    return lines;
  }

  double get _totalPagadoBase => _pagosLinea.fold<double>(
        0,
        (sum, p) => sum + p.equivalenteBase,
      );

  bool get _falta =>
      (_totalPagadoBase * 100).round() < (_total * 100).round();

  double get _vueltoTotalBase =>
      _falta ? 0 : (_totalPagadoBase - _total).clamp(0, double.infinity);

  List<String> get _monedasEligiblesVuelto => _todasMonedas
      .where((m) =>
          !_vueltoMap.containsKey(m) && (_denominaciones[m]?.isNotEmpty ?? false))
      .toList();

  void _syncVueltoAuto() {
    if (_falta) {
      if (_vueltoMap.isNotEmpty || _vueltoControllers.isNotEmpty) {
        for (final c in _vueltoControllers.values) {
          c.dispose();
        }
        _vueltoControllers.clear();
        _vueltoMap = {};
        _vueltoLocked = false;
      }
      return;
    }
    if (_vueltoLocked) return;

    final cashPagos = _pagosLinea.where((p) => p.tipo == 'cash').toList()
      ..sort((a, b) => b.equivalenteBase.compareTo(a.equivalenteBase));
    final mainCurrency =
        cashPagos.isNotEmpty ? cashPagos.first.moneda : _monedaBase;

    final auto = CurrencyUtils.calcularVuelto(
      totalBase: _total,
      pagos: _pagosLinea,
      monedaCobro: mainCurrency,
      monedaBase: _monedaBase,
      tasas: _tasas,
      denominaciones: _denominaciones,
    );

    for (final c in _vueltoControllers.values) {
      c.dispose();
    }
    _vueltoControllers.clear();
    _vueltoMap = {
      for (final v in auto)
        if (v.monto > 0) v.moneda: v.monto,
    };
    for (final entry in _vueltoMap.entries) {
      _vueltoControllers[entry.key] = TextEditingController(
        text: entry.value.toStringAsFixed(2),
      );
    }
  }

  double _suggestCash(String moneda, {String? excludeMoneda}) {
    final otherPaid = _pagosMap.entries
        .where((e) => e.key != excludeMoneda)
        .fold<double>(
          0,
          (s, e) =>
              s + _convertToBase(e.value.cash + e.value.transfer, e.key),
        );
    final rem = (_total - otherPaid).clamp(0, double.infinity).toDouble();
    if (rem <= 0) return 0;
    return double.parse(_convertFromBase(rem, moneda).toStringAsFixed(2));
  }

  void _bumpBreakdownResetKey(String moneda) {
    if (moneda == _monedaBase) {
      _baseBreakdownResetKey++;
    } else {
      _payBreakdownResetKeys[moneda] =
          (_payBreakdownResetKeys[moneda] ?? 0) + 1;
    }
  }

  void _saveBreakdownCounts(String moneda, Map<double, int> counts) {
    final filtered = Map<double, int>.fromEntries(
      counts.entries.where((e) => e.value > 0),
    );
    if (filtered.isEmpty) {
      _savedBillBreakdowns.remove(moneda);
    } else {
      _savedBillBreakdowns[moneda] = filtered;
    }
  }

  void _clearSavedBreakdown(String moneda) {
    if (!_savedBillBreakdowns.containsKey(moneda)) return;
    _savedBillBreakdowns.remove(moneda);
    _bumpBreakdownResetKey(moneda);
  }

  void _onCashManualEdit(String moneda, String value) {
    final amount = double.tryParse(value) ?? 0;
    setState(() {
      _clearSavedBreakdown(moneda);
      final pago = _pagosMap[moneda];
      if (pago != null) pago.cash = amount;
      _syncVueltoAuto();
    });
  }

  void _setAmountControllerText(TextEditingController? controller, double value) {
    final text = value > 0 ? value.toStringAsFixed(2) : '';
    if (controller != null && controller.text != text) {
      controller.text = text;
    }
  }

  void _formatCashField(String moneda) {
    final pago = _pagosMap[moneda];
    if (pago != null) {
      _setAmountControllerText(_cashControllers[moneda], pago.cash);
    }
  }

  void _formatTransferField(String moneda) {
    final pago = _pagosMap[moneda];
    if (pago != null) {
      _setAmountControllerText(_transferControllers[moneda], pago.transfer);
    }
  }

  void _formatVueltoField(String moneda) {
    _setAmountControllerText(
      _vueltoControllers[moneda],
      _vueltoMap[moneda] ?? 0,
    );
  }

  void _updatePago(
    String moneda, {
    double? cash,
    double? transfer,
    String? transferDestId,
    bool syncControllers = true,
  }) {
    final pago = _pagosMap[moneda];
    if (pago == null) return;
    setState(() {
      if (cash != null) {
        pago.cash = cash;
        if (syncControllers) {
          _setAmountControllerText(_cashControllers[moneda], cash);
        }
      }
      if (transfer != null) {
        pago.transfer = transfer;
        if (syncControllers) {
          _setAmountControllerText(_transferControllers[moneda], transfer);
        }
      }
      if (transferDestId != null) pago.transferDestId = transferDestId;
      _syncVueltoAuto();
    });
  }

  void _addCurrency(String moneda) {
    final cash = _suggestCash(moneda);
    setState(() {
      _initMoneda(
        moneda,
        cash: cash,
        transferDestId: _defaultDestId(_transferDestinations),
      );
      _syncVueltoAuto();
    });
  }

  void _removeCurrency(String moneda) {
    if (moneda == _monedaBase) return;
    setState(() {
      _cashControllers[moneda]?.dispose();
      _transferControllers[moneda]?.dispose();
      _cashControllers.remove(moneda);
      _transferControllers.remove(moneda);
      _pagosMap.remove(moneda);
      _showPayBreakdown.remove(moneda);
      _payBreakdownResetKeys.remove(moneda);
      _savedBillBreakdowns.remove(moneda);
      _paymentMode.remove(moneda);
      _syncVueltoAuto();
    });
  }

  void _togglePayBreakdown(String moneda) {
    setState(() {
      _showPayBreakdown[moneda] = !(_showPayBreakdown[moneda] ?? false);
    });
  }

  void _toggleBaseBreakdown() {
    setState(() {
      _showBaseBreakdown = !_showBaseBreakdown;
    });
  }

  void _updateVuelto(String moneda, double monto, {bool syncController = true}) {
    setState(() {
      _vueltoLocked = true;
      _vueltoMap[moneda] = monto;
      if (syncController) {
        _setAmountControllerText(_vueltoControllers[moneda], monto);
      }
    });
  }

  void _removeVueltoMoneda(String moneda) {
    setState(() {
      _vueltoLocked = true;
      _vueltoControllers[moneda]?.dispose();
      _vueltoControllers.remove(moneda);
      _vueltoMap.remove(moneda);
    });
  }

  void _addVueltoMoneda(String moneda) {
    setState(() {
      _vueltoLocked = true;
      final distBase = _vueltoMap.entries.fold<double>(
        0,
        (s, e) => s + _convertToBase(e.value, e.key),
      );
      final rem = (_vueltoTotalBase - distBase).clamp(0, double.infinity).toDouble();
      final suggested = rem > 0
          ? double.parse(_convertFromBase(rem, moneda).toStringAsFixed(2))
          : 0.0;
      _vueltoMap[moneda] = suggested;
      _vueltoControllers[moneda] = TextEditingController(
        text: suggested > 0 ? suggested.toStringAsFixed(2) : '',
      );
    });
  }

  bool get _canConfirm {
    if (_total <= 0) return _pagosMap.isNotEmpty;
    if (_falta || _totalPagadoBase <= 0) return false;
    for (final p in _pagosLinea) {
      if (p.tipo == 'transfer' &&
          p.monto > 0 &&
          (p.transferDestinationId == null ||
              p.transferDestinationId!.isEmpty)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _pickMoneda(
    BuildContext context,
    List<String> options,
    ValueChanged<String> onPick,
  ) async {
    if (options.length == 1) {
      onPick(options.first);
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map(
                (code) => ListTile(
                  title: Text(code),
                  onTap: () => Navigator.pop(ctx, code),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final monedasKeys = _pagosMap.keys.toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            const TextSpan(
                              text: 'Cobrar: ',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: _fmtBase(_total),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ...monedasKeys.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final moneda = entry.value;
                      return _buildMonedaSection(moneda, idx > 0);
                    }),
                    if (_hasExtraCurrencies && _monedasDisponibles.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          onPressed: () => _pickMoneda(
                            context,
                            _monedasDisponibles,
                            _addCurrency,
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar moneda'),
                        ),
                      ),
                    if (!_falta && _vueltoTotalBase >= 0.0001) ...[
                      const Divider(height: 32),
                      _buildVueltoSection(),
                    ],
                    const Divider(height: 32),
                    _buildSummary(),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed:
                            _canConfirm && !_isProcessing ? _processPayment : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isProcessing
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Confirmar Venta',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonedaSection(String moneda, bool showDivider) {
    final isBase = moneda == _monedaBase;
    final pago = _pagosMap[moneda]!;
    final admiteEfectivo = _admiteEfectivoMoneda(moneda);
    final admiteTransfer = _admiteTransferMoneda(moneda);
    final mode = _paymentMode[moneda] ?? 'cash';
    final showCash = admiteEfectivo && mode != 'transfer';
    final showTransfer = admiteTransfer && mode != 'cash';
    final totalMoneda = pago.cash + pago.transfer;
    final eqBase = !isBase && totalMoneda > 0
        ? _convertToBase(totalMoneda, moneda)
        : null;
    final denoms = _denominaciones[moneda] ?? [];
    final breakdownActive = isBase
        ? _showBaseBreakdown
        : (_showPayBreakdown[moneda] ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDivider) const Divider(height: 20),
        Row(
          children: [
            Chip(
              label: Text(moneda),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              backgroundColor: isBase ? AppColors.primary : null,
              labelStyle: TextStyle(
                color: isBase ? Colors.white : null,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (!isBase)
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _removeCurrency(moneda),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (admiteEfectivo && admiteTransfer) ...[
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cash', label: Text('Efectivo')),
              ButtonSegment(value: 'transfer', label: Text('Transfer.')),
              ButtonSegment(value: 'mixed', label: Text('Mixto')),
            ],
            selected: {mode},
            onSelectionChanged: (selected) =>
                _setPaymentMode(moneda, selected.first),
          ),
          const SizedBox(height: 12),
        ],
        if (showCash) ...[
          TextField(
            controller: _cashControllers[moneda],
            readOnly: breakdownActive,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText: 'Efectivo',
              hintText: '0.00',
              prefixText: '$moneda ',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              filled: breakdownActive,
              fillColor: breakdownActive
                  ? AppColors.textHint.withValues(alpha: 0.08)
                  : null,
            ),
            onTap: () {
              _cashControllers[moneda]?.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _cashControllers[moneda]!.text.length,
              );
            },
            onEditingComplete: () => _formatCashField(moneda),
            onTapOutside: (_) => _formatCashField(moneda),
            onChanged: breakdownActive
                ? null
                : (v) => _onCashManualEdit(moneda, v),
          ),
          if (denoms.isNotEmpty)
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () =>
                  isBase ? _toggleBaseBreakdown() : _togglePayBreakdown(moneda),
              icon: Icon(
                breakdownActive ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(
                breakdownActive ? 'Ocultar desglose' : 'Desglosar billetes',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          if (breakdownActive && denoms.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.textHint.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: BillBreakdownInput(
                denominations: denoms,
                targetAmount: isBase ? _total : pago.cash,
                initialCounts: _savedBillBreakdowns[moneda],
                resetKey: isBase
                    ? _baseBreakdownResetKey
                    : (_payBreakdownResetKeys[moneda] ?? 0),
                onCountsChange: (counts) =>
                    _saveBreakdownCounts(moneda, counts),
                onChange: (total) => _updatePago(moneda, cash: total),
              ),
            ),
        ],
        if (showTransfer) ...[
          if (showCash) const SizedBox(height: 8),
          TextField(
            controller: _transferControllers[moneda],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText: 'Transferencia',
              hintText: '0.00',
              prefixText: '$moneda ',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onEditingComplete: () => _formatTransferField(moneda),
            onTapOutside: (_) => _formatTransferField(moneda),
            onChanged: (v) {
              final newTransfer = double.tryParse(v) ?? 0;
              if (mode == 'mixed') {
                final newCash = (pago.cash + pago.transfer - newTransfer)
                    .clamp(0, double.infinity);
                setState(() {
                  pago.transfer = newTransfer;
                  pago.cash = double.parse(newCash.toStringAsFixed(2));
                  _setAmountControllerText(_cashControllers[moneda], pago.cash);
                  _syncVueltoAuto();
                });
              } else {
                _updatePago(
                  moneda,
                  transfer: newTransfer,
                  cash: 0,
                  syncControllers: false,
                );
              }
            },
          ),
          if (pago.transfer > 0 && _transferDestinations.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: pago.transferDestId.isNotEmpty ? pago.transferDestId : null,
              decoration: InputDecoration(
                labelText: 'Destino de transferencia',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: _transferDestinations
                  .map(
                    (d) => DropdownMenuItem<String>(
                      value: d.id,
                      child: Text(d.nombre),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) _updatePago(moneda, transferDestId: value);
              },
            ),
          ],
        ],
        if (eqBase != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '≈ ${_fmtBase(eqBase)}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildVueltoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Cambio a dar',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              '${_vueltoTotalBase.toStringAsFixed(2)} $_monedaBase equiv.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._vueltoMap.entries.map((entry) {
          final moneda = entry.key;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Chip(label: Text(moneda), visualDensity: VisualDensity.compact),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _vueltoControllers[moneda],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onEditingComplete: () => _formatVueltoField(moneda),
                    onTapOutside: (_) => _formatVueltoField(moneda),
                    onChanged: (v) => _updateVuelto(
                      moneda,
                      double.tryParse(v) ?? 0,
                      syncController: false,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => _removeVueltoMoneda(moneda),
                ),
              ],
            ),
          );
        }),
        if (_monedasEligiblesVuelto.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => _pickMoneda(
              context,
              _monedasEligiblesVuelto,
              _addVueltoMoneda,
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Dar cambio en otra moneda'),
          ),
      ],
    );
  }

  Widget _buildSummary() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Total:', style: TextStyle(fontSize: 18)),
            Text(
              _fmtBase(_total),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_falta)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Falta:', style: TextStyle(fontSize: 18, color: AppColors.error)),
              Text(
                _fmtBase(_total - _totalPagadoBase),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
                ),
              ),
            ],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cambio:',
                style: TextStyle(fontSize: 18, color: AppColors.success),
              ),
              Text(
                _fmtBase(_vueltoTotalBase),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _processPayment() async {
    setState(() => _isProcessing = true);

    try {
      final auth = context.read<AuthProvider>();
      final cart = context.read<CartProvider>();
      final periodo = context.read<PeriodoProvider>();
      final ventas = context.read<VentasProvider>();
      final sync = context.read<SyncProvider>();
      final productos = context.read<ProductosProvider>();

      if (cart.activeCart == null || periodo.periodoId == null) {
        throw Exception('No hay carrito o período activo');
      }

      final pagos = _pagosLinea;
      if (pagos.isEmpty) {
        throw Exception('Debe ingresar al menos un pago');
      }

      for (final p in pagos) {
        if (p.tipo == 'transfer' &&
            p.monto > 0 &&
            (p.transferDestinationId == null ||
                p.transferDestinationId!.isEmpty)) {
          throw Exception('Seleccione destino de transferencia');
        }
      }

      final vuelto = _vueltoMap.entries
          .where((e) => e.value > 0)
          .map((e) => VueltoLinea(moneda: e.key, monto: e.value))
          .toList();

      final totalcashBase = pagos
          .where((p) => p.tipo == 'cash')
          .fold<double>(0, (s, p) => s + p.equivalenteBase);
      final totalTransferBase = pagos
          .where((p) => p.tipo == 'transfer')
          .fold<double>(0, (s, p) => s + p.equivalenteBase);
      final firstTransferDest = pagos
          .where((p) =>
              p.tipo == 'transfer' &&
              p.transferDestinationId != null &&
              p.transferDestinationId!.isNotEmpty)
          .map((p) => p.transferDestinationId)
          .cast<String?>()
          .firstOrNull;

      final tasaSnapshot = Map<String, double>.from(_tasasSnapshot);

      await ventas.crearVenta(
        tiendaId: auth.tiendaId,
        periodoId: periodo.periodoId!,
        cart: cart.activeCart!,
        totalcash: totalcashBase,
        totaltransfer: totalTransferBase,
        transferDestinationId: firstTransferDest,
        isOffline: !sync.isOnline,
        multimoneda: _config,
        pagosDetalle: pagos,
        vueltoDetalle: vuelto,
        tasaSnapshot: tasaSnapshot,
        monedaCobro: _monedaBase,
      );

      await productos.refreshFromLocalCache(auth.tiendaId);
      await cart.clearActiveCart();
      await cart.onPurchaseCompleted();

      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
        AppSnackBar.show(
          context,
          content: Text(
            sync.isOnline
                ? 'Venta guardada. Sincronización con el servidor en segundo plano.'
                : 'Venta guardada - se sincronizará al conectarse',
          ),
          backgroundColor: AppColors.success,
        );
      }

      unawaited(productos.loadProductos(auth.tiendaId, showLoading: false));
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        );
      }
    }

    if (mounted) setState(() => _isProcessing = false);
  }
}

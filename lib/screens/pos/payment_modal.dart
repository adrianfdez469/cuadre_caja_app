import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/bill_denominations.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/cash_amount_input_formatter.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/payment_logic.dart';
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
import '../../services/hardware_scanner_gate.dart';
import '../../services/sync_service.dart';
import '../../widgets/bill_breakdown_input.dart';
import '../../widgets/multi_currency_amount.dart';
import '../../widgets/numeric_keypad.dart';

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

/// Pasos del flujo de cobro, según `pos/cobro.html`.
enum _PaymentStep { metodo, efectivo, transferencia, mixto, exito }

/// Snapshot de la venta ya confirmada, tomado antes de vaciar el carrito, para
/// poder mostrar la pantalla de éxito con datos que ya no viven en el carrito.
class _UltimaVenta {
  final double totalBase;
  final List<VueltoLinea> vuelto;
  final String monedaCobro;
  final bool isOnline;

  const _UltimaVenta({
    required this.totalBase,
    required this.vuelto,
    required this.monedaCobro,
    required this.isOnline,
  });
}

class PaymentModal extends StatefulWidget {
  const PaymentModal({
    super.key,
    this.getTransferDestinationsLocalOverride,
    this.loadTransferDestinationsOverride,
  });

  /// Solo para tests: evita depender de SyncService real (lectura local).
  final Future<List<TransferDestinationModel>> Function(String tiendaId)?
      getTransferDestinationsLocalOverride;

  /// Solo para tests: rescate por red cuando el cache local está vacío.
  final Future<List<TransferDestinationModel>> Function(String tiendaId)?
      loadTransferDestinationsOverride;

  /// Abre el modal de cobro bloqueando el escáner de hardware mientras está
  /// visible (si no, la pistola inyecta texto en los campos de importe).
  /// Devuelve `true` si la venta se completó.
  static Future<bool?> show(BuildContext context) {
    HardwareScannerGate.instance.block('payment');
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PaymentModal(),
    ).whenComplete(() => HardwareScannerGate.instance.unblock('payment'));
  }

  @override
  State<PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends State<PaymentModal> {
  bool _isProcessing = false;
  bool _initialized = false;

  _PaymentStep _step = _PaymentStep.metodo;
  String? _metodoSeleccionado;
  String? _efectivoKeypadRaw;
  _UltimaVenta? _ultimaVenta;

  List<TransferDestinationModel> _transferDestinations = [];
  Map<String, _PagoMoneda> _pagosMap = {};
  Map<String, bool> _showPayBreakdown = {};
  Map<String, int> _payBreakdownResetKeys = {};
  Map<String, Map<double, int>> _savedBillBreakdowns = {};
  Map<String, bool> _showTransfer = {};
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

    final syncService = context.read<SyncService>();
    final loadDestinosLocal = widget.getTransferDestinationsLocalOverride ??
        syncService.getTransferDestinationsLocal;
    var destinos = await loadDestinosLocal(auth.tiendaId);
    if (!mounted) return;

    // Rescate: el cache local solo se puebla en `fullSync`, así que puede estar
    // vacío (primer login sin red, o el GET falló). Sin destinos no se dibuja el
    // selector y la transferencia quedaba sin destino posible; se reintenta por
    // red antes de rendirse.
    if (destinos.isEmpty) {
      final loadDestinosRemoto = widget.loadTransferDestinationsOverride ??
          syncService.loadTransferDestinations;
      try {
        destinos = await loadDestinosRemoto(auth.tiendaId);
      } catch (e) {
        logDebug('⚠️ No se pudieron recuperar destinos de transferencia: $e');
      }
      if (!mounted) return;
    }

    final defaultDestId = _defaultDestId(destinos);
    _transferDestinations = destinos;

    // El efectivo solo admite enteros, así que el monto predefinido se redondea
    // hacia arriba para cubrir el total (igual que suggestCash para el resto de
    // monedas). Con el total crudo, un total de 3.25 mostraba "3" en el campo
    // mientras internamente cobraba 3.25 (Efectivo 3 / Total 3.25 / Cambio 0).
    _initMoneda(
      monedaBase,
      cash: PaymentLogic.ceilCash(total),
      transferDestId: defaultDestId,
    );

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

  void _initMoneda(String moneda, {double cash = 0, String transferDestId = ''}) {
    final soloTransfer =
        !_admiteEfectivoMoneda(moneda) && _admiteTransferMoneda(moneda);

    if (soloTransfer) {
      _showTransfer[moneda] = true;
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
      _showTransfer[moneda] = false;
      _pagosMap[moneda] = _PagoMoneda(
        cash: cash,
        transfer: 0,
        transferDestId: transferDestId,
      );
      _cashControllers[moneda] = TextEditingController(
        text: formatCashDisplay(cash),
      );
      _transferControllers[moneda] = TextEditingController(text: '');
    }
  }

  /// Limpia todo el estado de pagos y lo deja con una sola moneda (sin
  /// importe), para los pasos "efectivo" y "tarjeta" que cobran en una única
  /// moneda a la vez. El paso "mixto" no usa esto — conserva lo que ya había.
  void _resetToSingleMoneda(String moneda) {
    for (final c in _cashControllers.values) {
      c.dispose();
    }
    for (final c in _transferControllers.values) {
      c.dispose();
    }
    for (final c in _vueltoControllers.values) {
      c.dispose();
    }
    _cashControllers.clear();
    _transferControllers.clear();
    _vueltoControllers.clear();
    _pagosMap.clear();
    _showPayBreakdown.clear();
    _payBreakdownResetKeys.clear();
    _savedBillBreakdowns.clear();
    _showTransfer.clear();
    _vueltoMap = {};
    _vueltoLocked = false;
    _initMoneda(moneda, transferDestId: _defaultDestId(_transferDestinations));
  }

  void _selectEfectivo(String moneda) {
    _resetToSingleMoneda(moneda);
    _efectivoKeypadRaw = null;
    _updatePago(moneda, cash: _suggestCash(moneda, excludeMoneda: moneda));
    setState(() => _step = _PaymentStep.efectivo);
  }

  /// Monto exacto (con decimales) que corresponde transferir en [moneda] para
  /// cubrir el total — a diferencia del efectivo, la transferencia no se
  /// redondea.
  double _transferExacta(String moneda) => _convertFromBase(_total, moneda);

  /// Vista previa del efectivo sugerido en [moneda] para la tarjeta del paso
  /// 1, calculada **desde cero** (el total completo, redondeado por exceso) —
  /// a diferencia de [_suggestCash], que resta lo ya pagado en otras monedas
  /// y no sirve aquí porque `_pagosMap` todavía tiene el sembrado inicial de
  /// `_initialize()` en la moneda base.
  double _cashPreview(String moneda) =>
      PaymentLogic.ceilCash(_convertFromBase(_total, moneda));

  void _selectTransferencia(String moneda) {
    _resetToSingleMoneda(moneda);
    _toggleTransfer(moneda);
    _updatePago(moneda, transfer: _transferExacta(moneda));
    setState(() => _step = _PaymentStep.transferencia);
  }

  void _selectMixto() {
    setState(() => _step = _PaymentStep.mixto);
  }

  static const _cashPrefix = 'cash:';
  static const _transferPrefix = 'transfer:';

  void _onConfirmMetodo() {
    final metodo = _metodoSeleccionado;
    if (metodo == null) return;
    if (metodo == 'mixto') {
      _selectMixto();
    } else if (metodo.startsWith(_transferPrefix)) {
      _selectTransferencia(metodo.substring(_transferPrefix.length));
    } else if (metodo.startsWith(_cashPrefix)) {
      _selectEfectivo(metodo.substring(_cashPrefix.length));
    }
  }

  Map<String, PagoMonedaState> get _pagosState => {
        for (final e in _pagosMap.entries)
          e.key: PagoMonedaState(
            cash: e.value.cash,
            transfer: e.value.transfer,
            transferDestId: e.value.transferDestId,
          ),
      };

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

  List<PagoLinea> get _pagosLinea =>
      PaymentLogic.buildPagosLinea(_pagosState, _monedaBase, _tasas);

  double get _totalPagadoBase =>
      PaymentLogic.totalPagadoBase(_pagosState, _monedaBase, _tasas);

  bool get _falta => PaymentLogic.falta(_total, _totalPagadoBase);

  double get _vueltoTotalBase => PaymentLogic.vueltoTotalBase(
        total: _total,
        totalPagadoBase: _totalPagadoBase,
        falta: _falta,
      );

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

  double _suggestCash(String moneda, {String? excludeMoneda}) =>
      PaymentLogic.suggestCash(
        total: _total,
        pagos: _pagosState,
        moneda: moneda,
        monedaBase: _monedaBase,
        tasas: _tasas,
        excludeMoneda: excludeMoneda,
      );

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
    final amount = parseCashAmount(value);
    setState(() {
      _clearSavedBreakdown(moneda);
      final pago = _pagosMap[moneda];
      if (pago != null) pago.cash = amount;
      _syncVueltoAuto();
    });
  }

  void _setCashControllerText(TextEditingController? controller, double value) {
    final text = formatCashDisplay(value);
    if (controller != null && controller.text != text) {
      controller.text = text;
    }
  }

  void _setTransferControllerText(
    TextEditingController? controller,
    double value,
  ) {
    final text = value > 0 ? value.toStringAsFixed(2) : '';
    if (controller != null && controller.text != text) {
      controller.text = text;
    }
  }

  void _formatCashField(String moneda) {
    final pago = _pagosMap[moneda];
    if (pago != null) {
      _setCashControllerText(_cashControllers[moneda], pago.cash);
    }
  }

  void _formatTransferField(String moneda) {
    final pago = _pagosMap[moneda];
    if (pago != null) {
      _setTransferControllerText(_transferControllers[moneda], pago.transfer);
    }
  }

  void _formatVueltoField(String moneda) {
    _setTransferControllerText(
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
          _setCashControllerText(_cashControllers[moneda], cash);
        }
      }
      if (transfer != null) {
        pago.transfer = transfer;
        if (syncControllers) {
          _setTransferControllerText(_transferControllers[moneda], transfer);
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
      _showTransfer.remove(moneda);
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

  void _toggleTransfer(String moneda) {
    final pago = _pagosMap[moneda];
    if (pago == null) return;

    setState(() {
      final showing = _showTransfer[moneda] ?? false;
      _showTransfer[moneda] = !showing;
      if (showing) {
        final collapsed = PaymentLogic.collapseTransferToCash(
          cash: pago.cash,
          transfer: pago.transfer,
        );
        pago.cash = collapsed.cash;
        pago.transfer = collapsed.transfer;
        _setCashControllerText(_cashControllers[moneda], pago.cash);
        _setTransferControllerText(_transferControllers[moneda], 0);
      }
      _syncVueltoAuto();
    });
  }

  void _updateVuelto(String moneda, double monto, {bool syncController = true}) {
    setState(() {
      _vueltoLocked = true;
      _vueltoMap[moneda] = monto;
      if (syncController) {
        _setTransferControllerText(_vueltoControllers[moneda], monto);
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

  bool get _canConfirm => PaymentLogic.canConfirm(
        total: _total,
        falta: _falta,
        totalPagadoBase: _totalPagadoBase,
        pagosLinea: _pagosLinea,
        hasPagos: _pagosMap.isNotEmpty,
        hasTransferDestinations: _transferDestinations.isNotEmpty,
      );

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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          child: switch (_step) {
            _PaymentStep.metodo => _buildMetodoStep(),
            _PaymentStep.efectivo => _buildEfectivoStep(),
            _PaymentStep.transferencia => _buildTransferenciaStep(),
            _PaymentStep.mixto => _buildMixtoStep(),
            _PaymentStep.exito => _buildExitoStep(),
          },
        ),
      ),
    );
  }

  /// Encabezado común a todos los pasos: "←" (si hay paso anterior), título,
  /// "✕" para cerrar el modal.
  Widget _buildHeader(String title, {VoidCallback? onBack}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 4),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: onBack != null
                ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack)
                : null,
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// Resumen "A cobrar": monto y "N productos · M unidades", igual al de
  /// `pos/cobro.html` (resuelve el contador ambiguo de antes).
  Widget _buildResumen() {
    final colors = context.colors;
    final items = context.watch<CartProvider>().activeCart?.items ?? [];
    final unidades = items.fold<double>(0, (s, i) => s + i.cantidad);
    final unidadesText = unidades == unidades.roundToDouble()
        ? unidades.toStringAsFixed(0)
        : unidades.toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('A cobrar', style: TextStyle(fontSize: 11, color: colors.textSecondary)),
          if (items.isNotEmpty)
            Text(
              '${items.length} ${items.length == 1 ? 'producto' : 'productos'} · $unidadesText ${unidades == 1 ? 'unidad' : 'unidades'}',
              style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
            ),
          const SizedBox(height: 4),
          Text(
            _fmtBase(_total),
            style: tabularNums(TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            )),
          ),
        ],
      ),
    );
  }

  /// Barra de cobro fija (fondo invertido), en el mismo lenguaje visual que la
  /// pantalla de venta: el total y la acción nunca se separan.
  Widget _buildCheckoutFooter() {
    final colors = context.colors;
    return Container(
      color: colors.inverse,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MultiCurrencyAmount(
              amount: _total,
              variant: MultiCurrencyVariant.checkout,
              onInverseSurface: true,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: AppTapTarget.comfortable,
              child: ElevatedButton(
                onPressed: _canConfirm && !_isProcessing ? _processPayment : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: _isProcessing
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: colors.onAccent,
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
    );
  }

  // ---------------------------------------------------------------------
  // Paso 1: elegir forma de pago
  // ---------------------------------------------------------------------

  Widget _buildMetodoStep() {
    final colors = context.colors;
    // Una tarjeta "Efectivo <moneda>" / "Transferencia <moneda>" por cada
    // moneda activa que admita ese método — no una por moneda, sino una por
    // combinación (moneda, método) realmente disponible. El efectivo siempre
    // redondeado por exceso a un entero; la transferencia, con el monto
    // exacto de la conversión.
    final opciones = <(String id, String label, String subtitle)>[
      for (final moneda in _todasMonedas) ...[
        if (_admiteEfectivoMoneda(moneda))
          (
            '$_cashPrefix$moneda',
            'Efectivo $moneda',
            '${Formatters.formatNumber(_cashPreview(moneda), decimals: 0)} $moneda',
          ),
        if (_admiteTransferMoneda(moneda))
          (
            '$_transferPrefix$moneda',
            'Transferencia $moneda',
            Formatters.formatMonedaAmount(_transferExacta(moneda), code: moneda),
          ),
      ],
      ('mixto', 'Pago mixto', 'Dos o más formas'),
    ];

    return Column(
      children: [
        _buildHeader('Elegir forma de pago'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              _buildResumen(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Forma de pago',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colors.textSecondary),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 9,
                  crossAxisSpacing: 9,
                  childAspectRatio: 2.3,
                  children: opciones
                      .map(
                        (o) => _buildMetodoCard(
                          label: o.$2,
                          subtitle: o.$3,
                          selected: _metodoSeleccionado == o.$1,
                          onTap: () => setState(() => _metodoSeleccionado = o.$1),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
        _buildMetodoFooter(),
      ],
    );
  }

  Widget _buildMetodoCard({
    required String label,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.accentWash : colors.raised,
          border: Border.all(
            color: selected ? colors.accent : colors.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: selected ? colors.accent : colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tabularNums(TextStyle(fontSize: 11.5, color: colors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetodoFooter() {
    final colors = context.colors;
    return Container(
      color: colors.inverse,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _metodoSeleccionado == null ? 'Elegí una forma de pago' : 'Total a cobrar',
              style: TextStyle(fontSize: 11.5, color: colors.onInverseMuted),
            ),
            const SizedBox(height: 6),
            MultiCurrencyAmount(
              amount: _total,
              variant: MultiCurrencyVariant.checkout,
              onInverseSurface: true,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: AppTapTarget.comfortable,
              child: ElevatedButton(
                onPressed: _metodoSeleccionado == null ? null : _onConfirmMetodo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.onAccent,
                  disabledBackgroundColor: colors.onInverseMuted.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: const Text(
                  'Confirmar cobro',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Paso 2: efectivo y vuelto (una sola moneda)
  // ---------------------------------------------------------------------

  void _efectivoAppendDigit(String moneda, String digit) {
    final raw = (_efectivoKeypadRaw ?? '') + digit;
    final value = double.tryParse(raw);
    if (value == null) return;
    _efectivoKeypadRaw = raw;
    _updatePago(moneda, cash: value);
  }

  void _efectivoBackspace(String moneda) {
    final raw = _efectivoKeypadRaw ?? '';
    if (raw.length <= 1) {
      _efectivoKeypadRaw = null;
      _updatePago(moneda, cash: 0);
      return;
    }
    final trimmed = raw.substring(0, raw.length - 1);
    _efectivoKeypadRaw = trimmed;
    _updatePago(moneda, cash: double.tryParse(trimmed) ?? 0);
  }

  void _efectivoSetExacto(String moneda) {
    _efectivoKeypadRaw = null;
    // excludeMoneda: el propio pago ya tecleado no debe restarse de sí mismo,
    // o "Exacto" sugeriría cada vez menos según lo que ya hubiera en el campo.
    _updatePago(moneda, cash: _suggestCash(moneda, excludeMoneda: moneda));
  }

  Widget _buildEfectivoStep() {
    final colors = context.colors;
    final moneda = _pagosMap.keys.first;
    final pago = _pagosMap[moneda]!;
    final tasa = moneda != _monedaBase ? _tasas[moneda] : null;
    final totalEnMoneda = _convertFromBase(_total, moneda);

    return Column(
      children: [
        _buildHeader(
          'Efectivo $moneda',
          onBack: () => setState(() => _step = _PaymentStep.metodo),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              Text('A cobrar en $moneda', style: TextStyle(fontSize: 11, color: colors.textSecondary)),
              if (tasa != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Tasa ${tasa.toStringAsFixed(2)}',
                  style: tabularNums(TextStyle(fontSize: 11.5, color: colors.textSecondary)),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                Formatters.formatMonedaAmount(totalEnMoneda, code: moneda),
                style: tabularNums(TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                )),
              ),
              if (moneda != _monedaBase) ...[
                const SizedBox(height: 2),
                Text(
                  '= ${_fmtBase(_total)}',
                  style: tabularNums(TextStyle(fontSize: 12.5, color: colors.textSecondary)),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      formatCashDisplay(pago.cash),
                      style: tabularNums(TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: colors.accent,
                      )),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => _efectivoSetExacto(moneda),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, AppTapTarget.min),
                      side: BorderSide(color: colors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: const Text('Exacto'),
                  ),
                ],
              ),
              Text('Recibido', style: TextStyle(fontSize: 11, color: colors.textSecondary)),
              const SizedBox(height: 12),
              NumericKeypad(
                cornerLabel: '000',
                onDigit: (d) => _efectivoAppendDigit(moneda, d),
                onBackspace: () => _efectivoBackspace(moneda),
              ),
              if (!_falta && _vueltoTotalBase >= 0.0001) ...[
                const Divider(height: 32),
                _buildVueltoSection(),
              ],
              const SizedBox(height: 16),
              _buildSummary(),
            ],
          ),
        ),
        _buildCheckoutFooter(),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Paso "tarjeta" (transferencia por el total, vía POS bancario)
  // ---------------------------------------------------------------------

  Widget _buildTransferenciaStep() {
    final colors = context.colors;
    final moneda = _pagosMap.keys.first;
    final pago = _pagosMap[moneda]!;
    final tasa = moneda != _monedaBase ? _tasas[moneda] : null;

    return Column(
      children: [
        _buildHeader(
          'Transferencia $moneda',
          onBack: () => setState(() => _step = _PaymentStep.metodo),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              Text('A transferir en $moneda', style: TextStyle(fontSize: 11, color: colors.textSecondary)),
              if (tasa != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Tasa ${tasa.toStringAsFixed(2)}',
                  style: tabularNums(TextStyle(fontSize: 11.5, color: colors.textSecondary)),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                Formatters.formatMonedaAmount(pago.transfer, code: moneda),
                style: tabularNums(TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                )),
              ),
              if (moneda != _monedaBase) ...[
                const SizedBox(height: 2),
                Text(
                  '= ${_fmtBase(_total)}',
                  style: tabularNums(TextStyle(fontSize: 12.5, color: colors.textSecondary)),
                ),
              ],
              const SizedBox(height: 20),
              if (_transferDestinations.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: pago.transferDestId.isNotEmpty ? pago.transferDestId : null,
                  decoration: InputDecoration(
                    labelText: 'Destino de transferencia',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  items: _transferDestinations
                      .map((d) => DropdownMenuItem<String>(value: d.id, child: Text(d.nombre)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) _updatePago(moneda, transferDestId: value);
                  },
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: colors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Sin destinos de transferencia configurados. La venta se '
                        'registrará sin destino.',
                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        _buildCheckoutFooter(),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Paso "mixto": el contenido multimoneda de siempre, sin cambios.
  // ---------------------------------------------------------------------

  Widget _buildMixtoStep() {
    final monedasKeys = _pagosMap.keys.toList();
    return Column(
      children: [
        _buildHeader('Pago mixto', onBack: () => setState(() => _step = _PaymentStep.metodo)),
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
              const SizedBox(height: 24),
              _buildSummary(),
            ],
          ),
        ),
        _buildCheckoutFooter(),
      ],
    );
  }

  Widget _buildMonedaSection(String moneda, bool showDivider) {
    final isBase = moneda == _monedaBase;
    final pago = _pagosMap[moneda]!;
    final admiteEfectivo = _admiteEfectivoMoneda(moneda);
    final admiteTransfer = _admiteTransferMoneda(moneda);
    final soloTransfer = !admiteEfectivo && admiteTransfer;
    final transferExpanded = _showTransfer[moneda] ?? false;
    final showCash = admiteEfectivo;
    final showTransfer = admiteTransfer &&
        (soloTransfer || transferExpanded || pago.transfer > 0);
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Chip(
              label: Text(moneda),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              backgroundColor: isBase ? context.colors.accent : null,
              labelStyle: TextStyle(
                color: isBase ? context.colors.onAccent : null,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (showCash && admiteTransfer)
              Padding(
                padding: EdgeInsets.only(right: isBase ? 0 : 4),
                child: OutlinedButton.icon(
                  onPressed: () => _toggleTransfer(moneda),
                  icon: const Icon(Icons.credit_card, size: 16),
                  label: const Text(
                    'Transferencia',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  iconAlignment: IconAlignment.end,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: (transferExpanded || pago.transfer > 0)
                        ? context.colors.accentWash
                        : null,
                    foregroundColor: (transferExpanded || pago.transfer > 0)
                        ? context.colors.accent
                        : null,
                    side: BorderSide(
                      color: (transferExpanded || pago.transfer > 0)
                          ? context.colors.accent
                          : context.colors.border,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
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
        if (showCash || showTransfer) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showCash)
                Expanded(
                  child: TextField(
                    controller: _cashControllers[moneda],
                    readOnly: breakdownActive,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [CashAmountInputFormatter()],
                    decoration: InputDecoration(
                      labelText: 'Efectivo',
                      hintText: '0',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      filled: breakdownActive,
                      fillColor: breakdownActive ? context.colors.sunken : null,
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
                ),
              if (showCash && showTransfer) const SizedBox(width: 12),
              if (showTransfer)
                Expanded(
                  child: TextField(
                    controller: _transferControllers[moneda],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Transferencia',
                      hintText: '0.00',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    onEditingComplete: () => _formatTransferField(moneda),
                    onTapOutside: (_) => _formatTransferField(moneda),
                    onChanged: (v) {
                      final newTransfer = double.tryParse(v) ?? 0;
                      if (soloTransfer) {
                        _updatePago(
                          moneda,
                          transfer: newTransfer,
                          cash: 0,
                          syncControllers: false,
                        );
                      } else {
                        final updated = PaymentLogic.applyMixedTransferEdit(
                          currentCash: pago.cash,
                          currentTransfer: pago.transfer,
                          newTransfer: newTransfer,
                        );
                        setState(() {
                          pago.transfer = updated.transfer;
                          pago.cash = updated.cash;
                          _setCashControllerText(
                            _cashControllers[moneda],
                            pago.cash,
                          );
                          _syncVueltoAuto();
                        });
                      }
                    },
                  ),
                ),
            ],
          ),
          if (showCash && denoms.isNotEmpty)
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
                border: Border.all(color: context.colors.border),
                borderRadius: BorderRadius.circular(AppRadius.sm),
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
        if (showTransfer && pago.transfer > 0 && _transferDestinations.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: context.colors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Sin destinos de transferencia configurados. La venta se '
                    'registrará sin destino.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (showTransfer &&
            pago.transfer > 0 &&
            _transferDestinations.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: pago.transferDestId.isNotEmpty ? pago.transferDestId : null,
              decoration: InputDecoration(
                labelText: 'Destino de transferencia',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
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
        if (eqBase != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '≈ ${_fmtBase(eqBase)}',
              style: tabularNums(
                TextStyle(color: context.colors.textSecondary, fontSize: 12),
              ),
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
                color: context.colors.textSecondary,
              ),
            ),
            Text(
              '${_vueltoTotalBase.toStringAsFixed(2)} $_monedaBase equiv.',
              style: tabularNums(
                TextStyle(fontSize: 12, color: context.colors.textSecondary),
              ),
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
                        borderRadius: BorderRadius.circular(AppRadius.sm),
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

  /// Panel de "falta"/"cambio", en el mismo lenguaje que `cobro.html`: rojo
  /// tenue mientras no se cubre el total, verde tenue una vez que sí.
  Widget _buildSummary() {
    final colors = context.colors;
    final falta = _falta;
    final color = falta ? colors.negative : colors.positive;
    final wash = falta ? colors.negativeWash : colors.positiveWash;
    final label = falta ? 'Falta:' : 'Cambio:';
    final amount = falta ? (_total - _totalPagadoBase) : _vueltoTotalBase;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
          Text(
            _fmtBase(amount),
            style: tabularNums(TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            )),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Paso 4: cobro registrado
  // ---------------------------------------------------------------------

  Widget _buildExitoStep() {
    final colors = context.colors;
    final venta = _ultimaVenta;
    if (venta == null) return const SizedBox.shrink();

    final vueltoTotalBase = venta.vuelto.fold<double>(
      0,
      (s, v) => s + _convertToBase(v.monto, v.moneda),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 4),
          child: Row(
            children: [
              const SizedBox(width: 48),
              const Expanded(
                child: Text(
                  'Cobro registrado',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(color: colors.positive, shape: BoxShape.circle),
                    child: const Icon(Icons.check, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cobrado ${_fmtBase(venta.totalBase)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  if (vueltoTotalBase >= 0.0001) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${_fmtBase(vueltoTotalBase)} de vuelto',
                      style: tabularNums(TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.85,
                        color: colors.positive,
                      )),
                    ),
                  ],
                  if (!venta.isOnline) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Sin conexión: la venta queda guardada y se sube al sincronizar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
              minimumSize: const Size.fromHeight(AppTapTarget.comfortable),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: const Text('Nueva venta', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
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

      // Solo se exige destino si la tienda tiene alguno configurado (ver
      // PaymentLogic.canConfirm); si no, la venta va con destino nulo.
      if (_transferDestinations.isNotEmpty) {
        for (final p in pagos) {
          if (p.tipo == 'transfer' &&
              p.monto > 0 &&
              (p.transferDestinationId == null ||
                  p.transferDestinationId!.isEmpty)) {
            throw Exception('Seleccione destino de transferencia');
          }
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

      // Snapshot tomado antes de vaciar el carrito: la pantalla de éxito ya no
      // puede leer `_total`/`_vueltoMap` una vez que dependen del carrito vacío.
      final totalSnapshot = _total;
      final monedaCobroSnapshot = _monedaBase;
      final isOnlineSnapshot = sync.isOnline;

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
        setState(() {
          _ultimaVenta = _UltimaVenta(
            totalBase: totalSnapshot,
            vuelto: vuelto,
            monedaCobro: monedaCobroSnapshot,
            isOnline: isOnlineSnapshot,
          );
          _step = _PaymentStep.exito;
        });
      }

      unawaited(productos.loadProductos(auth.tiendaId, showLoading: false));
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          content: Text('Error: $e'),
          backgroundColor: context.colors.negative,
        );
      }
    }

    if (mounted) setState(() => _isProcessing = false);
  }
}

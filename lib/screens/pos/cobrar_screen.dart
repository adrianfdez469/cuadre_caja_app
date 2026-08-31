import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/payment_logic.dart';
import '../../core/utils/slide_route.dart';
import '../../core/widgets/app_snackbar.dart';
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
import '../../widgets/multi_currency_amount.dart';
import 'cart_items_screen.dart';
import 'widgets/agregar_pago_sheet.dart';
import 'widgets/cambio_sheet.dart';
import 'widgets/moneda_pago_sheet.dart';
import 'widgets/monto_input_sheet.dart';

/// Abre el cobro. Devuelve `true` si la venta se completó.
/// Cómo terminó la pantalla de cobro.
enum CobrarResult {
  /// La venta se registró.
  vendida,

  /// Se volvió atrás sin vender.
  cancelada,

  /// La cuenta se quedó sin productos mientras se cobraba (se vació desde el
  /// carrito). Quien abrió el cobro y también muestre ese carrito debe
  /// cerrarse, para no dejar al usuario mirando una cuenta vacía.
  carritoVacio,
}

Future<CobrarResult> showCobrarScreen(BuildContext context) async {
  final res = await Navigator.of(context).push<CobrarResult>(
    slideFromRightRoute<CobrarResult>(const CobrarScreen()),
  );
  return res ?? CobrarResult.cancelada;
}

/// Snapshot de la venta ya confirmada, tomado antes de vaciar el carrito, para
/// poder mostrar la pantalla de éxito con datos que ya no viven en el carrito.
class _UltimaVenta {
  final double totalBase;
  final List<PagoLinea> pagos;
  final List<VueltoLinea> vuelto;
  final bool isOnline;

  /// Nombre del cajero y hora del cobro. Se capturan al confirmar, no al
  /// pintar: para entonces el carrito ya se vació y los providers cambiaron.
  final String cajero;
  final DateTime hora;

  const _UltimaVenta({
    required this.totalBase,
    required this.pagos,
    required this.vuelto,
    required this.isOnline,
    required this.cajero,
    required this.hora,
  });
}

/// Pantalla de cobro. Reemplaza al antiguo modal de cinco pasos: todas las
/// formas de pago se ven y se editan a la vez, en una sola vista que entra
/// desde la derecha.
class CobrarScreen extends StatefulWidget {
  /// Solo para tests: evita depender de `SyncService` para los destinos.
  final Future<List<TransferDestinationModel>> Function(String tiendaId)?
      getTransferDestinationsLocalOverride;

  /// Solo para tests: reemplaza el rescate por red de los destinos.
  final Future<List<TransferDestinationModel>> Function(String tiendaId)?
      loadTransferDestinationsOverride;

  const CobrarScreen({
    super.key,
    this.getTransferDestinationsLocalOverride,
    this.loadTransferDestinationsOverride,
  });

  @override
  State<CobrarScreen> createState() => _CobrarScreenState();
}

class _CobrarScreenState extends State<CobrarScreen> {
  bool _initialized = false;
  bool _isProcessing = false;
  _UltimaVenta? _ultimaVenta;

  /// Bloques de pago, en el orden en que se agregaron. El primero es el
  /// principal: es el que lleva los montos rápidos.
  final Map<String, PagoMonedaState> _pagos = {};

  /// Por moneda: si el campo de transferencia está desplegado.
  final Map<String, bool> _showTransfer = {};

  /// Desglose en billetes con el que se armó cada monto, para poder reabrir la
  /// hoja de entrada sin perder el conteo.
  final Map<String, Map<double, int>> _billetes = {};

  Map<String, double> _vuelto = {};

  /// Una vez el cajero arma el cambio a mano, el cálculo automático deja de
  /// pisarlo.
  bool _vueltoManual = false;

  List<TransferDestinationModel> _transferDestinations = [];

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
    final monedaBase =
        monedas.monedaBase.isNotEmpty ? monedas.monedaBase : auth.monedaBase;

    final syncService = context.read<SyncService>();
    final loadDestinosLocal = widget.getTransferDestinationsLocalOverride ??
        syncService.getTransferDestinationsLocal;
    var destinos = await loadDestinosLocal(auth.tiendaId);
    if (!mounted) return;

    // Rescate: el cache local solo se puebla en `fullSync`, así que puede estar
    // vacío (primer login sin red, o el GET falló). Sin destinos no se dibuja el
    // selector y la transferencia quedaría sin destino posible.
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

    _transferDestinations = destinos;

    // El efectivo se cobra en enteros, así que el monto predefinido se redondea
    // hacia arriba para cubrir el total: con el total crudo, 3.25 mostraba "3"
    // mientras internamente cobraba 3.25.
    _initMoneda(
      monedaBase,
      monto: PaymentLogic.ceilCash(total),
      transferDestId: PaymentLogic.defaultDestId(destinos),
    );

    setState(() => _initialized = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(_syncVueltoAuto);
    });
  }

  // ── Datos derivados ────────────────────────────────────────────────────

  double get _total {
    final cart = context.read<CartProvider>();
    final monedas = context.read<MonedasProvider>();
    return monedas.cartTotal(cart.activeCart?.items ?? []);
  }

  MultimonedaConfig get _config {
    final monedas = context.read<MonedasProvider>();
    if (monedas.config.negocioId.isNotEmpty) return monedas.config;
    final auth = context.read<AuthProvider>();
    return MultimonedaConfig(
      negocioId: auth.negocioId,
      monedaBase: auth.monedaBase,
    );
  }

  String get _monedaBase => _config.monedaBase;
  Map<String, double> get _tasas => _config.tasasConversion;
  Map<String, double> get _tasasSnapshot => _config.tasasVigentes;

  Map<String, List<double>> get _denominaciones =>
      PaymentLogic.denominacionesConFallback(_config);

  List<NegocioMonedaModel> get _monedasActivas => _config.monedasActivas;

  NegocioMonedaModel? _monedaInfo(String code) {
    for (final m in _monedasActivas) {
      if (m.monedaCode == code) return m;
    }
    return null;
  }

  bool _admiteEfectivo(String moneda) {
    if (moneda == _monedaBase) return true;
    return _monedaInfo(moneda)?.admiteEfectivo ?? true;
  }

  bool _admiteTransferencia(String moneda) {
    if (moneda == _monedaBase) return true;
    return _monedaInfo(moneda)?.admiteTransferencia ?? false;
  }

  List<String> get _todasMonedas {
    final set = <String>{_monedaBase};
    for (final m in _monedasActivas) {
      set.add(m.monedaCode);
    }
    return set.toList();
  }

  List<String> get _monedasDisponibles =>
      _todasMonedas.where((m) => !_pagos.containsKey(m)).toList();

  List<PagoLinea> get _pagosLinea =>
      PaymentLogic.buildPagosLinea(_pagos, _monedaBase, _tasas);

  double get _totalPagadoBase =>
      PaymentLogic.totalPagadoBase(_pagos, _monedaBase, _tasas);

  bool get _falta => PaymentLogic.falta(_total, _totalPagadoBase);

  double get _restanteBase => (_total - _totalPagadoBase).clamp(0, double.infinity);

  double get _vueltoTotalBase => PaymentLogic.vueltoTotalBase(
        total: _total,
        totalPagadoBase: _totalPagadoBase,
        falta: _falta,
      );

  bool get _canConfirm => PaymentLogic.canConfirm(
        total: _total,
        falta: _falta,
        totalPagadoBase: _totalPagadoBase,
        pagosLinea: _pagosLinea,
        hasPagos: _pagos.isNotEmpty,
        hasTransferDestinations: _transferDestinations.isNotEmpty,
        hasItems: !_cuentaVacia,
      );

  /// La cuenta que se está cobrando se quedó sin productos.
  bool get _cuentaVacia =>
      context.read<CartProvider>().activeCart?.isEmpty ?? true;

  String _fmtBase(double v) =>
      '${Formatters.formatNumber(v)} $_monedaBase';

  /// Monedas en las que tiene sentido dar cambio: la base y las que admiten
  /// efectivo con tasa vigente.
  List<String> get _monedasElegiblesVuelto => _todasMonedas
      .where((m) => m == _monedaBase || _admiteEfectivo(m))
      .toList();

  // ── Mutaciones ─────────────────────────────────────────────────────────

  void _initMoneda(
    String moneda, {
    double monto = 0,
    String transferDestId = '',
  }) {
    // Una moneda que solo admite transferencia arranca con el importe ya en
    // ese campo, no en efectivo.
    final soloTransfer = !_admiteEfectivo(moneda) && _admiteTransferencia(moneda);
    _showTransfer[moneda] = soloTransfer;
    _pagos[moneda] = PagoMonedaState(
      cash: soloTransfer ? 0 : monto,
      transfer: soloTransfer ? monto : 0,
      transferDestId: transferDestId,
    );
  }

  void _setCash(String moneda, double cash, {Map<double, int>? billetes}) {
    setState(() {
      _pagos[moneda] = (_pagos[moneda] ?? const PagoMonedaState())
          .copyWith(cash: cash);
      if (billetes != null) {
        if (billetes.isEmpty) {
          _billetes.remove(moneda);
        } else {
          _billetes[moneda] = billetes;
        }
      }
      _syncVueltoAuto();
    });
  }

  void _setTransfer(String moneda, double transfer) {
    setState(() {
      final actual = _pagos[moneda] ?? const PagoMonedaState();
      // Lo que entra por transferencia sale del efectivo: el total que pone el
      // cliente no cambia por elegir otro medio.
      final r = PaymentLogic.applyMixedTransferEdit(
        currentCash: actual.cash,
        currentTransfer: actual.transfer,
        newTransfer: transfer,
      );
      _pagos[moneda] = actual.copyWith(cash: r.cash, transfer: r.transfer);
      _billetes.remove(moneda);
      _syncVueltoAuto();
    });
  }

  void _toggleTransfer(String moneda) {
    setState(() {
      final activo = _showTransfer[moneda] ?? false;
      final actual = _pagos[moneda] ?? const PagoMonedaState();
      if (activo) {
        final r = PaymentLogic.collapseTransferToCash(
          cash: actual.cash,
          transfer: actual.transfer,
        );
        _pagos[moneda] = actual.copyWith(
          cash: r.cash,
          transfer: r.transfer,
          transferDestId: PaymentLogic.defaultDestId(_transferDestinations),
        );
        _showTransfer[moneda] = false;
      } else {
        _showTransfer[moneda] = true;
        if (actual.transferDestId.isEmpty) {
          _pagos[moneda] = actual.copyWith(
            transferDestId: PaymentLogic.defaultDestId(_transferDestinations),
          );
        }
      }
      _syncVueltoAuto();
    });
  }

  void _setDestino(String moneda, String destId) {
    setState(() {
      _pagos[moneda] =
          (_pagos[moneda] ?? const PagoMonedaState()).copyWith(transferDestId: destId);
    });
  }

  void _cambiarMoneda(String vieja, String nueva) {
    if (vieja == nueva || _pagos.containsKey(nueva)) return;
    setState(() {
      // Se rehace el mapa para conservar el orden de los bloques.
      final entradas = _pagos.entries.toList();
      _pagos.clear();
      for (final e in entradas) {
        if (e.key == vieja) {
          _pagos[nueva] = PagoMonedaState(
            cash: PaymentLogic.suggestCash(
              total: _total,
              pagos: {
                for (final o in entradas)
                  if (o.key != vieja) o.key: o.value,
              },
              moneda: nueva,
              monedaBase: _monedaBase,
              tasas: _tasas,
            ),
            transferDestId: e.value.transferDestId,
          );
        } else {
          _pagos[e.key] = e.value;
        }
      }
      _showTransfer[nueva] = false;
      _showTransfer.remove(vieja);
      _billetes.remove(vieja);
      _syncVueltoAuto();
    });
  }

  void _agregarMoneda(String moneda) {
    setState(() {
      _initMoneda(
        moneda,
        monto: PaymentLogic.suggestCash(
          total: _total,
          pagos: _pagos,
          moneda: moneda,
          monedaBase: _monedaBase,
          tasas: _tasas,
        ),
        transferDestId: PaymentLogic.defaultDestId(_transferDestinations),
      );
      _syncVueltoAuto();
    });
  }

  void _quitarMoneda(String moneda) {
    if (_pagos.length <= 1) return;
    setState(() {
      _pagos.remove(moneda);
      _showTransfer.remove(moneda);
      _billetes.remove(moneda);
      _syncVueltoAuto();
    });
  }

  /// Recalcula el cambio propuesto. La moneda de referencia es aquella en la
  /// que más efectivo entregó el cliente: es la que tiene en la mano.
  ///
  /// Se llama solo cuando cambia el pago, y por eso **descarta el reparto
  /// manual**: uno armado a mano lo estaba para otro vuelto, así que aplicarlo
  /// tal cual tras cambiar el monto entregaría de más o de menos. El reparto
  /// elegido en la hoja sobrevive hasta el siguiente cambio de pago.
  void _syncVueltoAuto() {
    _vueltoManual = false;
    if (_falta) {
      _vuelto = {};
      return;
    }
    _vuelto = {
      for (final l in _vueltoAutoLineas) l.moneda: l.monto,
    };
  }

  /// Moneda en la que el cliente entregó más efectivo: la que tiene en la mano
  /// y, por tanto, en la que conviene devolverle lo grueso del cambio.
  String get _monedaPrincipalPago {
    final cashPagos = _pagosLinea.where((p) => p.tipo == 'cash').toList()
      ..sort((a, b) => b.equivalenteBase.compareTo(a.equivalenteBase));
    return cashPagos.isNotEmpty ? cashPagos.first.moneda : _monedaBase;
  }

  List<VueltoLinea> get _vueltoAutoLineas {
    final principal = _monedaPrincipalPago;
    return PaymentLogic.calcularVueltoAuto(
      totalBase: _total,
      pagos: _pagosLinea,
      monedaCobro: principal,
      monedaBase: _monedaBase,
      tasas: _tasas,
      denominaciones: _denominaciones,
      monedasVuelto: _monedasElegiblesVuelto,
    );
  }

  // ── Acciones de UI ─────────────────────────────────────────────────────

  Future<void> _editarEfectivo(String moneda) async {
    final pago = _pagos[moneda] ?? const PagoMonedaState();
    final res = await MontoInputSheet.show(
      context,
      titulo: 'Efectivo $moneda',
      moneda: moneda,
      montoInicial: pago.cash,
      contexto: _falta
          ? 'Falta ${_fmtBase(_restanteBase)}'
          : 'Total ${_fmtBase(_total)}',
      denominaciones: _denominaciones[moneda] ?? const [],
      billetesIniciales: _billetes[moneda] ?? const {},
    );
    if (res == null || !mounted) return;
    _setCash(moneda, res.monto, billetes: res.billetes);
  }

  Future<void> _editarTransferencia(String moneda) async {
    final pago = _pagos[moneda] ?? const PagoMonedaState();
    final res = await MontoInputSheet.show(
      context,
      titulo: 'Transferencia $moneda',
      moneda: moneda,
      montoInicial: pago.transfer,
      contexto: _falta
          ? 'Falta ${_fmtBase(_restanteBase)}'
          : 'Total ${_fmtBase(_total)}',
      permiteBilletes: false,
    );
    if (res == null || !mounted) return;
    _setTransfer(moneda, res.monto);
  }

  Future<void> _elegirMoneda(String moneda) async {
    final elegida = await MonedaPagoSheet.show(
      context,
      monedas: _todasMonedas,
      seleccionada: moneda,
      totalBase: _total,
      monedaBase: _monedaBase,
      tasas: _tasas,
    );
    if (elegida == null || !mounted) return;
    _cambiarMoneda(moneda, elegida);
  }

  Future<void> _agregarFormaDePago() async {
    final disponibles = _monedasDisponibles;
    if (disponibles.isEmpty) return;
    final elegida = await AgregarPagoSheet.show(
      context,
      monedas: disponibles,
      restanteBase: _restanteBase,
      totalBase: _total,
      monedaBase: _monedaBase,
      tasas: _tasas,
    );
    if (elegida == null || !mounted) return;
    _agregarMoneda(elegida);
  }

  Future<void> _editarCambio() async {
    final res = await CambioSheet.show(
      context,
      vueltoActual: _vuelto,
      manualInicial: _vueltoManual,
      vueltoTotalBase: _vueltoTotalBase,
      monedaCobro: _monedaPrincipalPago,
      monedaBase: _monedaBase,
      tasas: _tasas,
      monedasElegibles: _monedasElegiblesVuelto,
      denominaciones: _denominaciones,
    );
    if (res == null || !mounted) return;
    setState(() {
      _vuelto = res.vuelto;
      _vueltoManual = res.manual;
    });
  }

  Future<void> _abrirCarrito() async {
    // Se abre el detalle completo; su botón de cobro solo cierra, porque ya
    // estamos cobrando.
    final totalAntes = _total;
    await showCartItemsScreen(context, onCobrar: () => Navigator.pop(context));
    if (!mounted) return;

    // Vaciar la cuenta desde el carrito deja esta pantalla cobrando una venta
    // que ya no existe.
    if (_cuentaVacia) {
      Navigator.pop(context, CobrarResult.carritoVacio);
      return;
    }

    final totalAhora = _total;
    if (totalAhora != totalAntes) {
      // Cambió lo que hay que cobrar: lo que puso el cliente ya no corresponde
      // a esta venta, así que se vuelve a sembrar igual que al abrir.
      setState(() => _sembrarPagoInicial(totalAhora));
    } else {
      setState(_syncVueltoAuto);
    }
  }

  /// Deja un único pago en la moneda base por el total, como al entrar.
  void _sembrarPagoInicial(double total) {
    _pagos.clear();
    _billetes.clear();
    _showTransfer.clear();
    _vueltoManual = false;
    _initMoneda(
      _monedaBase,
      monto: PaymentLogic.ceilCash(total),
      transferDestId: PaymentLogic.defaultDestId(_transferDestinations),
    );
    _syncVueltoAuto();
  }

  // ── Venta ──────────────────────────────────────────────────────────────

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
        throw Exception('No hay cuenta o período activo');
      }
      // Red de seguridad: el botón ya está deshabilitado sin productos, pero un
      // tap en carrera con el vaciado no debe registrar una venta vacía.
      if (cart.activeCart!.isEmpty) {
        throw Exception('La cuenta no tiene productos');
      }
      final pagos = _pagosLinea;
      if (pagos.isEmpty) throw Exception('Debe ingresar al menos un pago');

      // Solo se exige destino si la tienda tiene alguno configurado.
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

      final vuelto = _vuelto.entries
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
      // Snapshot tomado antes de vaciar el carrito: después ya no existe.
      final totalSnapshot = _total;
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
            pagos: pagos,
            vuelto: vuelto,
            isOnline: isOnlineSnapshot,
            cajero: auth.usuario?.nombre ?? '',
            hora: DateTime.now(),
          );
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

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Se observa para repintar cuando cambia el carrito o las tasas.
    context.watch<CartProvider>();
    context.watch<MonedasProvider>();

    if (!_initialized) {
      return Scaffold(
        backgroundColor: colors.raised,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_ultimaVenta != null) {
      return Scaffold(
        backgroundColor: colors.raised,
        body: SafeArea(child: _buildExito(colors)),
      );
    }

    return Scaffold(
      backgroundColor: colors.raised,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(colors),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  for (final moneda in _pagos.keys.toList())
                    _buildBloquePago(colors, moneda),
                  _buildAgregarFormaDePago(colors),
                  const SizedBox(height: 16),
                  _buildEstado(colors),
                ],
              ),
            ),
            _buildFooter(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppSemanticColors colors) {
    final cart = context.read<CartProvider>().activeCart;
    final lineas = cart?.items.length ?? 0;
    final unidades = cart?.unidadesCount ?? 0;
    final unidadesTexto = unidades == unidades.roundToDouble()
        ? unidades.toInt().toString()
        : unidades.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Cobrar',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${cart?.nombre ?? '-'} · $lineas '
                  '${lineas == 1 ? 'producto' : 'productos'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            excludeSemantics: true,
            label: 'Ver el detalle de la cuenta',
            child: InkWell(
              onTap: _abrirCarrito,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(Icons.shopping_cart, size: 24, color: colors.textPrimary),
                    if (unidades > 0)
                      Positioned(
                        right: -8,
                        top: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          decoration: BoxDecoration(
                            color: colors.accent,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              unidadesTexto,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colors.onAccent,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBloquePago(AppSemanticColors colors, String moneda) {
    final pago = _pagos[moneda] ?? const PagoMonedaState();
    final transferActiva = _showTransfer[moneda] ?? false;
    final esPrimero = _pagos.keys.first == moneda;
    final puedeQuitar = _pagos.length > 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildMonedaPill(colors, moneda),
              const Spacer(),
              if (_admiteTransferencia(moneda))
                _buildTransferToggle(colors, moneda, transferActiva),
              if (puedeQuitar)
                IconButton(
                  key: Key('quitar-$moneda'),
                  icon: const Icon(Icons.close),
                  color: colors.textSecondary,
                  onPressed: () => _quitarMoneda(moneda),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_admiteEfectivo(moneda))
            _buildMontoCampo(
              colors,
              key: Key('pago-$moneda-cash'),
              valor: pago.cash,
              moneda: moneda,
              destacado: true,
              onTap: () => _editarEfectivo(moneda),
            ),
          if (transferActiva) ...[
            const SizedBox(height: 8),
            _buildMontoCampo(
              colors,
              key: Key('pago-$moneda-transfer'),
              valor: pago.transfer,
              moneda: moneda,
              etiqueta: 'Transferencia',
              onTap: () => _editarTransferencia(moneda),
            ),
            if (pago.transfer > 0) ...[
              const SizedBox(height: 8),
              _buildDestino(colors, moneda, pago),
            ],
          ],
          if (esPrimero && _admiteEfectivo(moneda)) ...[
            const SizedBox(height: 10),
            _buildMontosRapidos(colors, moneda, pago),
          ],
        ],
      ),
    );
  }

  Widget _buildMonedaPill(AppSemanticColors colors, String moneda) {
    return InkWell(
      onTap: () => _elegirMoneda(moneda),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppTapTarget.min),
        padding: const EdgeInsets.only(left: 16, right: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.accentWash,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              moneda,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 18, color: colors.accent),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferToggle(
    AppSemanticColors colors,
    String moneda,
    bool activa,
  ) {
    return Semantics(
      button: true,
      toggled: activa,
      label: 'Pagar parte por transferencia',
      child: InkWell(
        key: Key('transfer-toggle-$moneda'),
        onTap: () => _toggleTransfer(moneda),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: AppTapTarget.min,
          height: AppTapTarget.min,
          decoration: BoxDecoration(
            color: activa ? colors.accentWash : null,
            border: Border.all(color: activa ? colors.accent : colors.border),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(
            Icons.credit_card,
            size: 20,
            color: activa ? colors.accent : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMontoCampo(
    AppSemanticColors colors, {
    required Key key,
    required double valor,
    required String moneda,
    required VoidCallback onTap,
    String? etiqueta,
    bool destacado = false,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: destacado ? 14 : 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: destacado ? colors.textPrimary : colors.border,
            width: destacado ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            if (etiqueta != null)
              Expanded(
                child: Text(
                  etiqueta,
                  style: TextStyle(fontSize: 14, color: colors.textSecondary),
                ),
              ),
            Expanded(
              child: Text(
                formatMontoCampo(valor),
                textAlign: etiqueta != null ? TextAlign.end : TextAlign.start,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tabularNums(
                  TextStyle(
                    fontSize: destacado ? 30 : 16,
                    fontWeight: destacado ? FontWeight.bold : FontWeight.w600,
                    letterSpacing: destacado ? -0.6 : 0,
                  ),
                ),
              ),
            ),
            if (etiqueta == null) ...[
              const SizedBox(width: 8),
              Text(
                moneda,
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDestino(
    AppSemanticColors colors,
    String moneda,
    PagoMonedaState pago,
  ) {
    if (_transferDestinations.isEmpty) {
      return Row(
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
      );
    }

    final valor = _transferDestinations.any((d) => d.id == pago.transferDestId)
        ? pago.transferDestId
        : null;

    return DropdownButtonFormField<String>(
      key: Key('destino-$moneda'),
      initialValue: valor,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Destino',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      items: [
        for (final d in _transferDestinations)
          DropdownMenuItem(value: d.id, child: Text(d.nombre)),
      ],
      onChanged: (v) => v == null ? null : _setDestino(moneda, v),
    );
  }

  Widget _buildMontosRapidos(
    AppSemanticColors colors,
    String moneda,
    PagoMonedaState pago,
  ) {
    final exacto = PaymentLogic.suggestCash(
      total: _total,
      pagos: _pagos,
      moneda: moneda,
      monedaBase: _monedaBase,
      tasas: _tasas,
      excludeMoneda: moneda,
    );
    final rapidos = PaymentLogic.montosRapidos(
      exacto: exacto,
      denominaciones: _denominaciones[moneda] ?? const [],
    );

    Widget chip(String label, double valor) {
      final activo = (pago.cash - valor).abs() < 0.005;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: activo ? colors.accent : colors.sunken,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              onTap: () => _setCash(moneda, valor, billetes: const {}),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(
                height: AppTapTarget.min,
                child: Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
        ),
      );
    }

    return Row(
      children: [
        chip('Exacto', exacto),
        for (final m in rapidos) chip(formatMontoCampo(m), m),
      ],
    );
  }

  Widget _buildAgregarFormaDePago(AppSemanticColors colors) {
    if (_monedasDisponibles.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _agregarFormaDePago,
        icon: const Icon(Icons.add, size: 20),
        label: const Text(
          'Agregar forma de pago',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          minimumSize: const Size(0, AppTapTarget.min),
        ),
      ),
    );
  }

  Widget _buildEstado(AppSemanticColors colors) {
    if (_falta) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: colors.negativeWash,
          border: Border.all(color: colors.negative.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'FALTA POR CUBRIR',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: colors.negative,
                ),
              ),
            ),
            Text(
              _fmtBase(_restanteBase),
              style: tabularNums(
                TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colors.negative,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_vueltoTotalBase < 0.0001) return const SizedBox.shrink();

    final lineas = _vuelto.entries
        .where((e) => e.value > 0)
        .map((e) => '${Formatters.formatNumber(e.value)} ${e.key}')
        .toList();
    if (lineas.isEmpty) lineas.add(_fmtBase(_vueltoTotalBase));
    // El cajero tiene que ver TODO lo que entrega: con varias monedas el texto
    // baja de tamaño y, si aun así no cabe, el Wrap lo parte en varias filas en
    // vez de recortarlo.
    final tamano = switch (lineas.length) { 1 => 20.0, 2 => 17.0, _ => 15.0 };

    return InkWell(
      onTap: _editarCambio,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: colors.positiveWash,
          border: Border.all(color: colors.positive.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'CAMBIO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: colors.positive,
                ),
              ),
            ),
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                runAlignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 2,
                children: [
                  for (final linea in lineas)
                    Text(
                      linea,
                      textAlign: TextAlign.end,
                      style: tabularNums(
                        TextStyle(
                          fontSize: tamano,
                          fontWeight: FontWeight.bold,
                          color: colors.positive,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: colors.positive),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(AppSemanticColors colors) {
    final cart = context.read<CartProvider>().activeCart;

    return Container(
      color: colors.inverse,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A cobrar · ${cart?.nombre ?? '-'}',
              style: TextStyle(fontSize: 11.5, color: colors.onInverseMuted),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            MultiCurrencyAmount(
              amount: _total,
              variant: MultiCurrencyVariant.checkout,
              onInverseSurface: true,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _canConfirm && !_isProcessing ? _processPayment : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.onAccent,
                disabledBackgroundColor:
                    colors.onInverseMuted.withValues(alpha: 0.3),
                minimumSize: const Size.fromHeight(AppTapTarget.comfortable),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Vender',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Línea de detalle del cobro. Con un solo pago se dice cuánto se recibió
  /// frente a lo que hacía falta en esa misma moneda —que es lo que el cajero
  /// necesita para explicarle la cuenta al cliente—; con varios se listan.
  String _detalleVenta(_UltimaVenta venta) {
    final partes = <String>[];

    if (venta.pagos.length == 1) {
      final p = venta.pagos.first;
      final requerido = CurrencyUtils.convertFromBase(
        venta.totalBase,
        p.moneda,
        _tasas,
        _monedaBase,
      );
      partes.add(
        '${p.tipo == 'cash' ? 'Efectivo' : 'Transferencia'} ${p.moneda} · '
        'recibido ${Formatters.formatNumber(p.monto)} de '
        '${Formatters.formatNumber(requerido)}',
      );
    } else {
      for (final p in venta.pagos) {
        partes.add(
          '${p.tipo == 'cash' ? 'Efectivo' : 'Transferencia'} ${p.moneda} '
          '${Formatters.formatNumber(p.monto)}',
        );
      }
    }

    final monedasVuelto =
        venta.vuelto.where((v) => v.monto > 0).map((v) => v.moneda).toSet();
    if (monedasVuelto.isNotEmpty) {
      partes.add('vuelto entregado en ${monedasVuelto.join(' y ')}');
    }

    return partes.join(' · ');
  }

  Widget _buildExito(AppSemanticColors colors) {
    final venta = _ultimaVenta!;
    // Se muestra la moneda con más vuelto: es la que el cajero va a entregar.
    final lineasVuelto = venta.vuelto.where((v) => v.monto > 0).toList()
      ..sort((a, b) => b.monto.compareTo(a.monto));
    final principal = lineasVuelto.isEmpty ? null : lineasVuelto.first;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Material(
                color: colors.sunken,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  onTap: () => Navigator.pop(context, CobrarResult.vendida),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    width: AppTapTarget.min,
                    height: AppTapTarget.min,
                    child: Icon(Icons.close, color: colors.textPrimary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Cobro registrado',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      [
                        Formatters.formatTime(venta.hora),
                        if (venta.cajero.isNotEmpty) venta.cajero,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: colors.positive,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Cobrado ${_fmtBase(venta.totalBase)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (principal != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          Formatters.formatNumber(principal.monto),
                          style: tabularNums(
                            const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.85,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${principal.moneda} de vuelto',
                          style: TextStyle(
                            fontSize: 15,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    _detalleVenta(venta),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                  ),
                  if (!venta.isOnline) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Sin conexión: la venta queda guardada y se sube al '
                      'sincronizar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                      ),
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
            onPressed: () => Navigator.pop(context, CobrarResult.vendida),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
              minimumSize: const Size.fromHeight(AppTapTarget.comfortable),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: const Text(
              'Nueva venta',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}

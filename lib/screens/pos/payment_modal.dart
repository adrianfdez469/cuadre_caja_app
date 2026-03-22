import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/transfer_destination_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/periodo_provider.dart';
import '../../providers/productos_provider.dart';
import '../../providers/ventas_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/sync_service.dart';

class PaymentModal extends StatefulWidget {
  const PaymentModal({super.key});

  @override
  State<PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends State<PaymentModal> {
  final _cashController = TextEditingController();
  final _transferController = TextEditingController();
  bool _isProcessing = false;
  String _paymentMethod = 'cash'; // cash, transfer, mixed
  List<TransferDestinationModel> _transferDestinations = [];
  bool _transferDestinationsLoaded = false;
  String? _selectedTransferDestinationId;

  @override
  void initState() {
    super.initState();
    final total = context.read<CartProvider>().activeTotal;
    _cashController.text = total.toStringAsFixed(2);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTransferDestinations());
  }

  Future<void> _loadTransferDestinations() async {
    final auth = context.read<AuthProvider>();
    final tiendaId = auth.tiendaId;
    if (tiendaId.isEmpty) return;
    final sync = context.read<SyncService>();
    final destinos = await sync.loadTransferDestinations(tiendaId);
    if (!mounted) return;
    setState(() {
      _transferDestinations = destinos;
      _transferDestinationsLoaded = true;
      if (_selectedTransferDestinationId == null && destinos.isNotEmpty) {
        try {
          _selectedTransferDestinationId =
              destinos.firstWhere((d) => d.isDefault).id;
        } catch (_) {
          _selectedTransferDestinationId = destinos.first.id;
        }
      }
    });
  }

  @override
  void dispose() {
    _cashController.dispose();
    _transferController.dispose();
    super.dispose();
  }

  double get _total => context.read<CartProvider>().activeTotal;

  double get _cashAmount =>
      double.tryParse(_cashController.text) ?? 0;

  double get _transferAmount =>
      double.tryParse(_transferController.text) ?? 0;

  double get _totalPaid => _cashAmount + _transferAmount;

  double get _cambio => _totalPaid - _total;

  bool get _canPay => _totalPaid >= _total && _total > 0;

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Cobrar',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),

            // Total
            Center(
              child: Text(
                Formatters.formatCurrency(cartProvider.activeTotal),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Payment method selector
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('Efectivo')),
                ButtonSegment(value: 'transfer', label: Text('Transfer.')),
                ButtonSegment(value: 'mixed', label: Text('Mixto')),
              ],
              selected: {_paymentMethod},
              onSelectionChanged: (selected) {
                setState(() {
                  _paymentMethod = selected.first;
                  if (_paymentMethod == 'cash') {
                    _cashController.text = _total.toStringAsFixed(2);
                    _transferController.text = '0';
                  } else if (_paymentMethod == 'transfer') {
                    _cashController.text = '0';
                    _transferController.text = _total.toStringAsFixed(2);
                  } else {
                    _cashController.text = '';
                    _transferController.text = '';
                  }
                });
              },
            ),
            const SizedBox(height: 16),

            // Cash input
            if (_paymentMethod != 'transfer')
              TextField(
                controller: _cashController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Efectivo',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),

            if (_paymentMethod == 'mixed') const SizedBox(height: 12),

            // Transfer input
            if (_paymentMethod != 'cash')
              TextField(
                controller: _transferController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Transferencia',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),

            // Destino de transferencia (si paga algo por transferencia y hay destinos)
            if (_paymentMethod != 'cash' &&
                _transferAmount > 0 &&
                _transferDestinationsLoaded &&
                _transferDestinations.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedTransferDestinationId,
                decoration: InputDecoration(
                  labelText: 'Destino de transferencia',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: _transferDestinations
                    .map((d) => DropdownMenuItem<String>(
                          value: d.id,
                          child: Text(d.nombre),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedTransferDestinationId = value);
                },
              ),
            ],

            const SizedBox(height: 16),

            // Cambio
            if (_paymentMethod != 'transfer' && _cambio > 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Cambio:', style: TextStyle(fontSize: 16)),
                    Text(
                      Formatters.formatCurrency(_cambio),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Confirm button
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _canPay && !_isProcessing ? _processPayment : null,
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
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
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

      await ventas.crearVenta(
        tiendaId: auth.tiendaId,
        periodoId: periodo.periodoId!,
        cart: cart.activeCart!,
        totalcash: _cashAmount,
        totaltransfer: _transferAmount,
        transferDestinationId:
            _transferAmount > 0 ? _selectedTransferDestinationId : null,
        isOffline: !sync.isOnline,
      );

      // Existencias ya actualizadas en disco; refrescar listas al instante sin red
      await productos.refreshFromLocalCache(auth.tiendaId);

      // Limpiar carrito y aplicar reglas post-venta (eliminar carrito no principal si aplica, seleccionar primero con ítems)
      await cart.clearActiveCart();
      await cart.onPurchaseCompleted();

      if (mounted) {
        Navigator.pop(context); // Cerrar modal
        Navigator.pop(context); // Volver a categorías

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

      // Reconciliar con servidor cuando responda, sin bloquear el POS ni el indicador de carga
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

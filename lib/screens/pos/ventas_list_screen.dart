import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/venta_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/periodo_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/ventas_provider.dart';
import '../../providers/productos_provider.dart';
import 'ventas_detail_screen.dart';

class VentasListScreen extends StatefulWidget {
  const VentasListScreen({super.key});

  @override
  State<VentasListScreen> createState() => _VentasListScreenState();
}

class _VentasListScreenState extends State<VentasListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final periodo = context.read<PeriodoProvider>();
    if (auth.tiendaId.isEmpty || periodo.periodoId == null) return;
    await context.read<VentasProvider>().loadVentasUnificado(
          auth.tiendaId,
          periodo.periodoId!,
        );
  }

  @override
  Widget build(BuildContext context) {
    final ventasProvider = context.watch<VentasProvider>();
    final syncProvider = context.watch<SyncProvider>();
    final auth = context.read<AuthProvider>();
    final periodo = context.read<PeriodoProvider>();
    final list = ventasProvider.ventasUnificado;
    final hasPendientes = list.any((v) => !v.synced && v.syncState != SyncState.syncing);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventas y Sincronizaciones'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (hasPendientes && syncProvider.isOnline)
            TextButton.icon(
              onPressed: ventasProvider.isLoading
                  ? null
                  : () async {
                      await ventasProvider.syncPendientes();
                      if (mounted) await _load();
                    },
              icon: const Icon(Icons.sync, size: 20, color: Colors.white),
              label: const Text('Sincronizar todos', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: ventasProvider.isLoadingVentas
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final v = list[index];
                      return _VentaListItem(
                        venta: v,
                        isOnline: syncProvider.isOnline,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VentasDetailScreen(venta: v),
                          ),
                        ).then((_) => _load()),
                        onSync: () async {
                          await ventasProvider.syncSingleVenta(v.identifier);
                          if (mounted) await _load();
                        },
                        onDelete: () => _confirmDelete(context, v, auth.tiendaId, periodo.periodoId, ventasProvider),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long, size: 64, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text(
            'No hay ventas en este período',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    VentaUnificadaModel venta,
    String tiendaId,
    String? periodoId,
    VentasProvider ventasProvider,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar venta'),
        content: const Text(
          '¿Está seguro que desea eliminar la venta seleccionada? Se restaurará el stock local.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ventasProvider.deleteVenta(venta.identifier, tiendaId);
    if (mounted && periodoId != null) {
      await ventasProvider.loadVentasUnificado(tiendaId, periodoId);
    }
    if (mounted) {
      await context.read<ProductosProvider>().loadProductos(tiendaId);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Venta eliminada'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _VentaListItem extends StatelessWidget {
  final VentaUnificadaModel venta;
  final bool isOnline;
  final VoidCallback onTap;
  final VoidCallback onSync;
  final VoidCallback onDelete;

  const _VentaListItem({
    required this.venta,
    required this.isOnline,
    required this.onTap,
    required this.onSync,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(venta.createdAtMs);
    final syncLabel = _syncStateLabel(venta.syncState);
    final syncColor = _syncStateColor(venta.syncState);
    final canSync = !venta.synced && venta.syncState != SyncState.syncing && isOnline;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Formatters.formatDateTime(date),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: syncColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                syncLabel,
                                style: TextStyle(fontSize: 12, color: syncColor, fontWeight: FontWeight.w500),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${venta.itemCount} ítems',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Formatters.formatCurrency(venta.total),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'Efectivo: ${Formatters.formatCurrency(venta.totalcash)}',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      if (venta.totaltransfer > 0)
                        Text(
                          'Transf: ${Formatters.formatCurrency(venta.totaltransfer)}',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canSync)
                    TextButton.icon(
                      onPressed: onSync,
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Sincronizar'),
                    ),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                    label: Text(
                      'Eliminar',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _syncStateLabel(SyncState s) {
    switch (s) {
      case SyncState.synced:
        return 'Sincronizada';
      case SyncState.syncing:
        return 'Sincronizando';
      case SyncState.pending:
        return 'Pendiente';
      case SyncState.error:
        return 'Error';
    }
  }

  Color _syncStateColor(SyncState s) {
    switch (s) {
      case SyncState.synced:
        return AppColors.synced;
      case SyncState.syncing:
        return AppColors.syncing;
      case SyncState.pending:
        return AppColors.notSynced;
      case SyncState.error:
        return AppColors.syncError;
    }
  }
}

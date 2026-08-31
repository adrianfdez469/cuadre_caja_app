import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/sync_error_messages.dart';
import '../../core/utils/venta_cancel_policy.dart';
import '../../data/models/venta_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/periodo_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/ventas_provider.dart';
import '../../providers/productos_provider.dart';
import 'ventas_detail_screen.dart';

class VentasListScreen extends StatefulWidget {
  const VentasListScreen({super.key});

  /// Muestra el diálogo con el log de error de sincronización (compartido con detalle de venta).
  /// Si el error es un conflicto de período y se provee [currentPeriodoId], ofrece la opción
  /// de mover la venta al período actual para re-sincronizarla.
  static void showErrorLog(
    BuildContext context,
    VentaUnificadaModel venta, {
    String? currentPeriodoId,
    VoidCallback? onPeriodoUpdated,
  }) {
    final title = SyncErrorMessages.title(venta.errorMessage);
    final detail = SyncErrorMessages.detail(venta.errorMessage);
    final isPeriodConflict = SyncErrorMessages.isPeriodConflict(venta.errorMessage);
    final colors = context.colors;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colors.negative, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                detail,
                style: TextStyle(fontSize: 13, color: colors.textPrimary),
              ),
              if (venta.syncAttempts > 0) ...[
                const SizedBox(height: 12),
                Text(
                  'Intentos de sincronización: ${venta.syncAttempts}',
                  style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                ),
              ],
              if (isPeriodConflict && currentPeriodoId != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.cautionWash,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: colors.caution.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Esta venta fue registrada en un período que ya fue cerrado. '
                    'Puedes moverla al período actual para sincronizarla nuevamente.',
                    style: TextStyle(fontSize: 13, color: colors.textPrimary),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          if (isPeriodConflict && currentPeriodoId != null)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (confirmCtx) => AlertDialog(
                    title: const Text('Actualizar período'),
                    content: const Text(
                      '¿Deseas mover esta venta al período actual para sincronizarla nuevamente?\n\n'
                      'La venta quedará en estado pendiente y se sincronizará automáticamente al conectarse.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(confirmCtx, false),
                        child: const Text('Cancelar'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(confirmCtx, true),
                        child: const Text('Actualizar'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await context.read<VentasProvider>().updateVentaPeriodo(
                        venta.identifier,
                        currentPeriodoId,
                      );
                  onPeriodoUpdated?.call();
                  if (context.mounted) {
                    AppSnackBar.show(
                      context,
                      content: const Text('Venta movida al período actual. Se sincronizará pronto.'),
                      backgroundColor: context.colors.positive,
                    );
                  }
                }
              },
              child: Text(
                'Actualizar período',
                style: TextStyle(color: colors.accent, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

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
        actions: [
          if (hasPendientes && syncProvider.isOnline)
            TextButton.icon(
              onPressed: ventasProvider.isLoading
                  ? null
                  : () async {
                      final result = await ventasProvider.syncPendientes();
                      if (mounted) await _load();
                      if (mounted && result.failed > 0) {
                        AppSnackBar.show(
                          context,
                          content: Text(
                            '${result.failed} venta(s) no se sincronizaron. Toca "Ver detalle" en cada una para más información.',
                          ),
                          backgroundColor: context.colors.caution,
                          duration: const Duration(seconds: 5),
                        );
                      }
                    },
              icon: const Icon(Icons.sync, size: 20),
              label: const Text('Sincronizar todos'),
            ),
        ],
      ),
      body: ventasProvider.isLoadingVentas
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? _buildEmpty(context)
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
                        currentPeriodoId: periodo.periodoId,
                        onViewError: switch (v.syncState) {
                          SyncState.error
                              when v.errorMessage?.isNotEmpty ?? false =>
                            () => VentasListScreen.showErrorLog(
                                  context,
                                  v,
                                  currentPeriodoId: periodo.periodoId,
                                  onPeriodoUpdated: () async {
                                    if (mounted) await _load();
                                  },
                                ),
                          // Una anulación rechazada se resuelve con su propio
                          // diálogo: reintentar o descartar.
                          SyncState.cancelError => () =>
                              _resolverAnulacionFallida(
                                context,
                                v,
                                auth.tiendaId,
                                periodo.periodoId,
                                ventasProvider,
                              ),
                          _ => null,
                        },
                        // Solo se anula lo que tiene fila local y no está ya en
                        // proceso de anulación.
                        onDelete: v.puedeAnularse
                            ? () => _confirmDelete(context, v, auth.tiendaId,
                                periodo.periodoId, ventasProvider)
                            : null,
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long, size: 64, color: colors.textDisabled),
          const SizedBox(height: 16),
          Text(
            'No hay ventas en este período',
            style: TextStyle(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// Pide confirmación y anula la venta.
  ///
  /// El texto del diálogo dice lo que va a pasar de verdad en cada caso: una
  /// venta que nunca llegó al servidor se borra en el acto, y una que ya está en
  /// el servidor necesita su confirmación — sin conexión, la anulación queda en
  /// cola. Antes el diálogo prometía lo mismo siempre y el resultado se anunciaba
  /// como "eliminada" aunque el servidor no se hubiera enterado.
  Future<void> _confirmDelete(
    BuildContext context,
    VentaUnificadaModel venta,
    String tiendaId,
    String? periodoId,
    VentasProvider ventasProvider,
  ) async {
    final negative = context.colors.negative;
    final positive = context.colors.positive;
    final caution = context.colors.caution;
    final isOnline = context.read<SyncProvider>().isOnline;
    // Se capturan antes del diálogo: al volver, el elemento puede estar
    // desactivado y `mounted` no basta para que `context.read` sea seguro.
    final productosProvider = context.read<ProductosProvider>();
    final messenger = ScaffoldMessenger.of(context);

    // Sin serverId la venta no existe en el servidor: se borra sin hablar con él.
    final soloLocal = venta.dbId == null || venta.dbId!.isEmpty;
    final quedaraPendiente = !soloLocal && !isOnline;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(soloLocal ? 'Eliminar venta' : 'Anular venta'),
        content: Text(
          soloLocal
              ? '¿Eliminar esta venta? Todavía no se ha subido, así que se '
                  'borra del dispositivo y se devuelve el stock.'
              : quedaraPendiente
                  ? '¿Anular esta venta? Ya está registrada en el servidor y '
                      'ahora no hay conexión: el stock se devuelve al instante y '
                      'la anulación quedará pendiente hasta que el servidor la '
                      'confirme.'
                  : '¿Anular esta venta? Se pedirá al servidor que la cancele y '
                      'se devolverá el stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              soloLocal ? 'Eliminar' : 'Anular',
              style: TextStyle(color: negative),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final resultado = await ventasProvider.anularVenta(venta.identifier);
    if (mounted && periodoId != null) {
      await ventasProvider.loadVentasUnificado(tiendaId, periodoId);
    }
    if (mounted) {
      await productosProvider.loadProductos(tiendaId);
    }

    final (mensaje, color) = switch (resultado) {
      AnulacionResultado.borrada => ('Venta eliminada', positive),
      AnulacionResultado.encolada when quedaraPendiente => (
          'Anulación pendiente — se aplicará al reconectar',
          caution,
        ),
      AnulacionResultado.encolada => ('Anulando la venta…', positive),
      AnulacionResultado.yaEnCurso => (
          'Esta venta ya tiene una anulación pedida',
          caution,
        ),
      AnulacionResultado.subidaEnVuelo => (
          'La venta se está subiendo — inténtalo en unos segundos',
          caution,
        ),
      AnulacionResultado.noPermitida => (
          'Esta venta no se puede anular desde este dispositivo',
          caution,
        ),
    };

    AppSnackBar.showOn(
      messenger,
      content: Text(mensaje),
      backgroundColor: color,
    );
  }

  /// Acciones sobre una anulación que el servidor rechazó. Sin esto la venta se
  /// quedaría en `cancelError` para siempre.
  Future<void> _resolverAnulacionFallida(
    BuildContext context,
    VentaUnificadaModel venta,
    String tiendaId,
    String? periodoId,
    VentasProvider ventasProvider,
  ) async {
    final productosProvider = context.read<ProductosProvider>();
    final colors = context.colors;

    final accion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anulación rechazada'),
        content: Text(
          venta.errorMessage?.isNotEmpty == true
              ? '${venta.errorMessage}\n\nLa venta sigue registrada en el '
                  'servidor y su stock ya se volvió a descontar.'
              : 'El servidor rechazó la anulación. La venta sigue registrada y '
                  'su stock ya se volvió a descontar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cerrar'),
            child: const Text('Cerrar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'descartar'),
            child: const Text('Descartar anulación'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'reintentar'),
            child: Text(
              'Reintentar',
              style: TextStyle(color: colors.accent),
            ),
          ),
        ],
      ),
    );

    if (accion == null || accion == 'cerrar' || !mounted) return;

    if (accion == 'reintentar') {
      await ventasProvider.reintentarAnulacion(venta.identifier);
    } else {
      await ventasProvider.descartarAnulacion(venta.identifier);
    }

    if (mounted && periodoId != null) {
      await ventasProvider.loadVentasUnificado(tiendaId, periodoId);
    }
    if (mounted) {
      await productosProvider.loadProductos(tiendaId);
    }
  }
}

class _VentaListItem extends StatelessWidget {
  final VentaUnificadaModel venta;
  final bool isOnline;
  final String? currentPeriodoId;
  final VoidCallback onTap;
  final VoidCallback onSync;
  final VoidCallback? onViewError;

  /// `null` cuando la venta no se puede anular desde este dispositivo (no tiene
  /// fila local) o ya tiene una anulación pedida.
  final VoidCallback? onDelete;

  const _VentaListItem({
    required this.venta,
    required this.isOnline,
    this.currentPeriodoId,
    required this.onTap,
    required this.onSync,
    this.onViewError,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final date = DateTime.fromMillisecondsSinceEpoch(venta.createdAtMs);
    final syncLabel = _syncStateLabel(venta.syncState);
    final syncColor = _syncStateColor(venta.syncState, colors);
    final canSync = !venta.synced && venta.syncState != SyncState.syncing && isOnline;
    final isFromOtherPeriod = currentPeriodoId != null &&
        venta.periodoId != currentPeriodoId;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isFromOtherPeriod)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.history_toggle_off, size: 14, color: colors.caution),
                      const SizedBox(width: 4),
                      Text(
                        'Período anterior — requiere actualización',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.caution,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
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
                                color: syncColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Text(
                                syncLabel,
                                style: tabularNums(
                                  TextStyle(fontSize: 11.5, color: syncColor, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${venta.itemCount} ítems',
                              style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
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
                        style: tabularNums(
                          TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: colors.accent,
                          ),
                        ),
                      ),
                      Text(
                        'Efectivo: ${Formatters.formatCurrency(venta.totalcash)}',
                        style: tabularNums(TextStyle(fontSize: 11.5, color: colors.textSecondary)),
                      ),
                      if (venta.totaltransfer > 0)
                        Text(
                          'Transf: ${Formatters.formatCurrency(venta.totaltransfer)}',
                          style: tabularNums(TextStyle(fontSize: 11.5, color: colors.textSecondary)),
                        ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onViewError != null)
                    TextButton.icon(
                      onPressed: onViewError,
                      icon: Icon(Icons.info_outline, size: 18, color: colors.negative),
                      label: Text(
                        venta.syncState == SyncState.cancelError
                            ? 'Resolver la anulación'
                            : 'Ver detalle del error',
                        style: TextStyle(color: colors.negative, fontSize: 13),
                      ),
                    ),
                  if (canSync)
                    IconButton(
                      onPressed: onSync,
                      icon: const Icon(Icons.sync),
                      color: colors.accent,
                      tooltip: 'Sincronizar',
                    ),
                  if (onDelete != null)
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                      color: colors.negative,
                      tooltip: venta.dbId == null || venta.dbId!.isEmpty
                          ? 'Eliminar'
                          : 'Anular',
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
      case SyncState.cancelPending:
        return 'Anulación pendiente';
      case SyncState.cancelling:
        return 'Anulando';
      case SyncState.cancelError:
        return 'Anulación fallida';
    }
  }

  Color _syncStateColor(SyncState s, AppSemanticColors colors) {
    switch (s) {
      case SyncState.synced:
        return colors.positive;
      case SyncState.syncing:
        return colors.info;
      case SyncState.pending:
        return colors.caution;
      case SyncState.error:
        return colors.negative;
      case SyncState.cancelPending:
        return colors.caution;
      case SyncState.cancelling:
        return colors.info;
      case SyncState.cancelError:
        return colors.negative;
    }
  }
}

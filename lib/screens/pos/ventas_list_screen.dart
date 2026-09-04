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
import '../../widgets/app_filter_chip.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/sync_state_chip.dart';
import 'ventas_detail_screen.dart';

/// Qué subconjunto de ventas se está mirando.
enum _FiltroVentas { todas, sinSubir, conError }

/// El servidor la rechazó: hay que hacer algo con ella.
bool _esError(VentaUnificadaModel v) =>
    v.syncState == SyncState.error || v.syncState == SyncState.cancelError;

/// Sólo espera conexión o está en vuelo: se resuelve sola.
bool _porSubir(VentaUnificadaModel v) => !v.synced && !_esError(v);

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
    final title = SyncErrorMessages.title(
      venta.errorMessage,
      code: venta.errorCode,
    );
    final detail = SyncErrorMessages.detail(venta.errorMessage);
    final isPeriodConflict = SyncErrorMessages.isPeriodConflict(
      venta.errorMessage,
    );
    final esPermanente = SyncErrorMessages.isPermanent(venta.errorCode);
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
              Text(detail, style: Theme.of(ctx).textTheme.bodyMedium),
              if (venta.syncAttempts > 0) ...[
                const SizedBox(height: 12),
                Text(
                  'Intentos de sincronización: ${venta.syncAttempts}',
                  style: Theme.of(
                    ctx,
                  ).textTheme.bodySmall!.copyWith(color: colors.textSecondary),
                ),
              ],
              // Sin este aviso la venta parece abandonada: se queda en rojo y
              // deja de reintentarse sola, y el cajero no tiene por qué saber
              // que el paso siguiente ocurre fuera de la app.
              if (esPermanente) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.cautionWash,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: colors.caution.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'Esta venta no se reintenta sola: seguirá fallando hasta que '
                    'se resuelva en el sistema. Cuando esté resuelto, usa el '
                    'botón de sincronizar de la venta.',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                ),
              ],
              if (isPeriodConflict && currentPeriodoId != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.cautionWash,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: colors.caution.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'Esta venta fue registrada en un período que ya fue cerrado. '
                    'Puedes moverla al período actual para sincronizarla nuevamente.',
                    style: Theme.of(ctx).textTheme.bodyMedium,
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
                      content: const Text(
                        'Venta movida al período actual. Se sincronizará pronto.',
                      ),
                      backgroundColor: context.colors.positive,
                    );
                  }
                }
              },
              child: Text(
                'Actualizar período',
                style: TextStyle(
                  color: colors.accent,
                  fontWeight: FontWeight.bold,
                ),
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
  _FiltroVentas _filtro = _FiltroVentas.todas;

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
    final colors = context.colors;
    final ventasProvider = context.watch<VentasProvider>();
    final syncProvider = context.watch<SyncProvider>();
    final auth = context.read<AuthProvider>();
    final periodo = context.read<PeriodoProvider>();

    final todas = ventasProvider.ventasUnificado;

    // Los conteos salen de la lista que se está mostrando, no del contador
    // global del provider: si el chip dice "2" tienen que aparecer dos filas al
    // tocarlo.
    final conError = todas.where(_esError).length;
    final sinSubir = todas.where(_porSubir).length;
    final sincronizadas = todas.length - conError - sinSubir;
    final hasPendientes = conError + sinSubir > 0;

    final visibles = switch (_filtro) {
      _FiltroVentas.todas => todas,
      _FiltroVentas.sinSubir => todas.where(_porSubir).toList(),
      _FiltroVentas.conError => todas.where(_esError).toList(),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventas y sincronizaciones'),
        actions: [
          // Se muestra siempre que haya algo que subir. Antes desaparecía sin
          // conexión y no había forma de saber si el botón no estaba o si es
          // que ya no quedaba nada pendiente.
          if (hasPendientes)
            TextButton.icon(
              onPressed:
                  (ventasProvider.isLoadingVentas || !syncProvider.isOnline)
                  ? null
                  : _sincronizarTodas,
              icon: const Icon(Icons.sync, size: 20),
              label: const Text('Sincronizar'),
            ),
        ],
      ),
      body: ventasProvider.isLoadingVentas && todas.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                // Sin esto el estado vacío no se puede tirar hacia abajo, que
                // es justo cuando más falta hace refrescar.
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (!syncProvider.isOnline && hasPendientes)
                    SliverToBoxAdapter(child: _buildBannerSinConexion()),
                  if (todas.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildResumen(
                        total: todas.fold<double>(0, (s, v) => s + v.total),
                        cantidad: todas.length,
                        sincronizadas: sincronizadas,
                        sinSubir: sinSubir,
                        conError: conError,
                      ),
                    ),
                  if (hasPendientes)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _FiltrosHeader(
                        background: colors.page,
                        extent: _alturaFiltros(context),
                        child: _buildFiltros(todas.length, sinSubir, conError),
                      ),
                    ),
                  if (visibles.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmpty(todas.isEmpty),
                    )
                  else
                    _buildListaAgrupada(
                      visibles,
                      syncProvider.isOnline,
                      auth.tiendaId,
                      periodo.periodoId,
                      ventasProvider,
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _sincronizarTodas() async {
    final ventasProvider = context.read<VentasProvider>();
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
  }

  Widget _buildBannerSinConexion() {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      color: colors.cautionWash,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: colors.caution),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sin conexión. Las ventas pendientes se subirán solas al reconectar.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: colors.caution),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumen({
    required double total,
    required int cantidad,
    required int sincronizadas,
    required int sinSubir,
    required int conError,
  }) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    cantidad == 1 ? '1 venta' : '$cantidad ventas',
                    style: text.titleMedium,
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        Formatters.formatCurrency(total),
                        style: tabularNums(
                          text.titleLarge!.copyWith(color: colors.accent),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (sincronizadas > 0)
                    _PuntoEstado(
                      color: colors.positive,
                      texto:
                          '$sincronizadas sincronizada'
                          '${sincronizadas == 1 ? '' : 's'}',
                    ),
                  if (sinSubir > 0)
                    _PuntoEstado(
                      color: colors.caution,
                      texto: '$sinSubir sin subir',
                    ),
                  if (conError > 0)
                    _PuntoEstado(
                      color: colors.negative,
                      texto: '$conError con error',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Alto de la barra de filtros. Se calcula con la escala de fuente del
  /// sistema en vez de fijarlo: un alto literal recortaba los chips en cuanto
  /// el usuario subía la letra.
  double _alturaFiltros(BuildContext context) {
    final escala = MediaQuery.textScalerOf(context).scale(13);
    return escala * 2.2 + 28;
  }

  Widget _buildFiltros(int total, int sinSubir, int conError) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          AppFilterChip(
            label: 'Todas',
            count: total,
            selected: _filtro == _FiltroVentas.todas,
            onTap: () => setState(() => _filtro = _FiltroVentas.todas),
          ),
          if (sinSubir > 0) ...[
            const SizedBox(width: 8),
            AppFilterChip(
              label: 'Sin subir',
              count: sinSubir,
              selected: _filtro == _FiltroVentas.sinSubir,
              onTap: () => setState(() => _filtro = _FiltroVentas.sinSubir),
            ),
          ],
          if (conError > 0) ...[
            const SizedBox(width: 8),
            AppFilterChip(
              label: 'Con error',
              count: conError,
              selected: _filtro == _FiltroVentas.conError,
              onTap: () => setState(() => _filtro = _FiltroVentas.conError),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty(bool periodoVacio) {
    if (periodoVacio) {
      return const EmptyState(
        icon: Icons.receipt_long,
        title: 'No hay ventas en este período',
        message: 'Las ventas que cobres aparecerán aquí.',
      );
    }
    return EmptyState(
      icon: Icons.filter_alt_off_outlined,
      title: 'Nada que revisar',
      message: 'Ninguna venta coincide con este filtro.',
      action: OutlinedButton(
        onPressed: () => setState(() => _filtro = _FiltroVentas.todas),
        child: const Text('Ver todas'),
      ),
    );
  }

  /// Aplana la lista en encabezados de día y ventas, para que el `SliverList`
  /// siga construyendo sólo lo visible.
  Widget _buildListaAgrupada(
    List<VentaUnificadaModel> ventas,
    bool isOnline,
    String tiendaId,
    String? periodoId,
    VentasProvider ventasProvider,
  ) {
    final filas = <Object>[];
    String? diaActual;
    for (final v in ventas) {
      final fecha = DateTime.fromMillisecondsSinceEpoch(v.createdAtMs);
      final dia = Formatters.formatDiaRelativo(fecha);
      if (dia != diaActual) {
        diaActual = dia;
        filas.add(dia);
      }
      filas.add(v);
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      sliver: SliverList.builder(
        itemCount: filas.length,
        itemBuilder: (context, index) {
          final fila = filas[index];
          if (fila is String) return _EncabezadoDia(label: fila);
          final v = fila as VentaUnificadaModel;
          return _VentaListItem(
            venta: v,
            isOnline: isOnline,
            currentPeriodoId: periodoId,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => VentasDetailScreen(venta: v)),
            ).then((_) => _load()),
            onSync: () async {
              await ventasProvider.syncSingleVenta(v.identifier);
              if (mounted) await _load();
            },
            onViewError: switch (v.syncState) {
              SyncState.error when v.errorMessage?.isNotEmpty ?? false =>
                () => VentasListScreen.showErrorLog(
                  context,
                  v,
                  currentPeriodoId: periodoId,
                  onPeriodoUpdated: () async {
                    if (mounted) await _load();
                  },
                ),
              // Una anulación rechazada se resuelve con su propio diálogo:
              // reintentar o descartar.
              SyncState.cancelError => () => _resolverAnulacionFallida(
                context,
                v,
                tiendaId,
                periodoId,
                ventasProvider,
              ),
              _ => null,
            },
            // Solo se anula lo que tiene fila local y no está ya en proceso de
            // anulación.
            onDelete: v.puedeAnularse
                ? () => _confirmDelete(
                    context,
                    v,
                    tiendaId,
                    periodoId,
                    ventasProvider,
                  )
                : null,
          );
        },
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
      // Desde la base local: `anularVenta`/`reintentarAnulacion` ya devolvieron
      // el stock antes de retornar. Un GET aquí no solo sobraba: podía caer en
      // la ventana en que la venta está en `cancelling` —estado que la
      // reconciliación no replaya— y hacer desaparecer el stock devuelto.
      await productosProvider.refreshFromLocalCache(tiendaId);
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
            child: Text('Reintentar', style: TextStyle(color: colors.accent)),
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
      await productosProvider.refreshFromLocalCache(tiendaId);
    }
  }
}

/// Cabecera pegajosa de la barra de filtros: sigue visible mientras se recorre
/// la lista, que es cuando hace falta recordar qué se está mirando.
class _FiltrosHeader extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double extent;
  final Color background;

  const _FiltrosHeader({
    required this.child,
    required this.extent,
    required this.background,
  });

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: background,
      height: extent,
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_FiltrosHeader old) =>
      old.child != child ||
      old.extent != extent ||
      old.background != background;
}

class _PuntoEstado extends StatelessWidget {
  final Color color;
  final String texto;

  const _PuntoEstado({required this.color, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          texto,
          style: Theme.of(
            context,
          ).textTheme.bodySmall!.copyWith(color: context.colors.textSecondary),
        ),
      ],
    );
  }
}

class _EncabezadoDia extends StatelessWidget {
  final String label;

  const _EncabezadoDia({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6, left: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: context.colors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
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
    final text = Theme.of(context).textTheme;
    final date = DateTime.fromMillisecondsSinceEpoch(venta.createdAtMs);
    final canSync =
        !venta.synced && venta.syncState != SyncState.syncing && isOnline;
    final isFromOtherPeriod =
        currentPeriodoId != null && venta.periodoId != currentPeriodoId;

    // El desglose sólo aporta cuando hubo dos formas de pago. En la venta
    // normal, íntegra en efectivo, repetir el total como "Efectivo: …" era una
    // línea de ruido por tarjeta.
    final mixta = venta.totalcash > 0 && venta.totaltransfer > 0;
    final lineas = venta.itemCount == 1
        ? '1 producto'
        : '${venta.itemCount} productos';

    final acciones = <Widget>[
      if (onViewError != null)
        TextButton.icon(
          onPressed: onViewError,
          icon: Icon(Icons.info_outline, size: 18, color: colors.negative),
          label: Text(
            venta.syncState == SyncState.cancelError
                ? 'Resolver la anulación'
                : 'Ver detalle del error',
            style: text.bodyMedium!.copyWith(color: colors.negative),
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
    ];

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
                      Icon(
                        Icons.history_toggle_off,
                        size: 14,
                        color: colors.caution,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Período anterior — requiere actualización',
                          style: text.labelSmall!.copyWith(
                            color: colors.caution,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Semantics(
                label:
                    'Venta de las ${Formatters.formatTime(date)}. '
                    '${SyncStateLabels.label(venta.syncState)}. '
                    '$lineas. Total ${Formatters.formatCurrency(venta.total)}.',
                container: true,
                excludeSemantics: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Reparto 3/2 con los dos lados flexibles: el importe se
                    // encoge dentro de su parte en vez de empujar la fila
                    // fuera de la tarjeta con la letra ampliada.
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                Formatters.formatTime(date),
                                style: text.titleMedium,
                              ),
                              const SizedBox(width: 8),
                              Flexible(child: SyncStateChip(venta.syncState)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            lineas,
                            style: text.bodySmall!.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              Formatters.formatCurrency(venta.total),
                              style: tabularNums(text.titleLarge!),
                            ),
                          ),
                          if (mixta)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                'Ef. ${Formatters.formatCurrency(venta.totalcash)}'
                                ' · Tr. ${Formatters.formatCurrency(venta.totaltransfer)}',
                                style: tabularNums(
                                  text.bodySmall!.copyWith(
                                    color: colors.textSecondary,
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
              // Sin acciones no hay nada que separar: antes el separador y la
              // fila vacía se pintaban igual en toda venta ya sincronizada, que
              // es el caso más común.
              if (acciones.isNotEmpty) ...[
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: acciones,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

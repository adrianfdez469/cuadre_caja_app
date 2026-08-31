import 'dart:async';
import 'package:cuadre_caja_app/core/utils/app_logger.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/release_service.dart'
    show ReleaseService, compareVersions;
import '../../core/widgets/app_snackbar.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/pos_startup.dart';
import '../../core/utils/producto_pos_rules.dart';
import '../../core/utils/venta_sin_stock_policy.dart';
import '../../data/models/categoria_model.dart';
import '../../data/models/producto_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/productos_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/periodo_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/monedas_provider.dart';
import '../../providers/ventas_provider.dart';
import '../../services/screen_wake_service.dart';
import '../../services/sync_service.dart';
import '../../core/utils/app_route_observer.dart';
import '../../widgets/hardware_scanner_listener.dart';
import '../../widgets/multi_currency_amount.dart';
import '../../widgets/stock_local_badge.dart';
import '../../widgets/sync_badge.dart';
import '../login_screen.dart';
import 'barcode_scanner_screen.dart';
import 'cart_items_screen.dart' show CartPanel;
import '../version_screen.dart';
import 'widgets/pos_actions_sheet.dart';
import 'widgets/user_menu_sheet.dart';
import 'widgets/pos_checkout_bar.dart';
import 'widgets/quantity_sheet.dart';

class POSHomeScreen extends StatefulWidget {
  const POSHomeScreen({super.key});

  @override
  State<POSHomeScreen> createState() => _POSHomeScreenState();
}

class _POSHomeScreenState extends State<POSHomeScreen> with RouteAware {
  bool _isInitialized = false;
  String? _initError;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool? _lastPermitirSinStock;

  /// La cabecera (barra superior + buscador + categorías) se oculta al
  /// desplazar el catálogo hacia abajo y reaparece de inmediato al primer
  /// gesto hacia arriba, para dejarle más espacio al listado.
  bool _headerVisible = true;

  bool _onCatalogScroll(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      final pixels = notification.metrics.pixels;
      final showHeader =
          pixels <= 0 || notification.direction == ScrollDirection.forward;
      final hideHeader =
          notification.direction == ScrollDirection.reverse && pixels > 0;
      if (showHeader && !_headerVisible) {
        setState(() => _headerVisible = true);
      } else if (hideHeader && _headerVisible) {
        setState(() => _headerVisible = false);
      }
    }
    return false;
  }

  /// Clave en SharedPreferences para recordar la versión que el usuario decidió omitir.
  static const _skippedVersionKey = 'update_skipped_version';

  /// Evita volver a mostrar el aviso de actualización durante la misma sesión.
  bool _updateBannerShown = false;
  final ReleaseService _releaseService = ReleaseService();

  /// Serializan _refreshUiAfterSync para que refrescos concurrentes (fullSync
  /// inicial, timer, reconexión) no interleaven sus escrituras.
  bool _isRefreshingUi = false;
  bool _refreshUiPending = false;

  /// Acumula lo que reportaron los avisos recibidos mientras había un refresco
  /// en curso, para que un `ventasCambiaron: true` no lo pise un aviso
  /// posterior que no traía novedades del servidor.
  SyncRefreshInfo _pendingRefreshInfo = const SyncRefreshInfo();

  /// Referencia al ScaffoldMessenger capturada mientras el widget está activo,
  /// para poder limpiar banners en dispose() sin llamar a
  /// ScaffoldMessenger.of(context) sobre un element ya defunct (lanza assertion).
  ScaffoldMessengerState? _scaffoldMessenger;
  SyncProvider? _syncProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
    // Se guarda para `dispose`: ahí el elemento ya está desactivado y cualquier
    // `context.read` revienta con "deactivated widget's ancestor".
    _syncProvider = context.read<SyncProvider>();
    final route = ModalRoute.of(context);
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  /// Al abrirse algo encima (el carrito, un modal, otra pantalla) se suelta el
  /// foco del buscador. Si no, al cerrarlo Flutter restaura el foco de esta
  /// ruta y el teclado se vuelve a levantar solo.
  @override
  void didPushNext() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _initialize() async {
    final auth = context.read<AuthProvider>();
    final sync = context.read<SyncProvider>();
    final tiendaId = auth.tiendaId;

    if (tiendaId.isEmpty) {
      setState(() => _initError = 'No hay tienda seleccionada');
      return;
    }

    // Configurar callback para cuando se necesite re-auth
    final syncService = context.read<SyncService>();
    syncService.onAuthRequired = (needsLogin) {
      if (needsLogin && mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    };

    syncService.onDataRefreshed = (info) async {
      if (mounted) {
        await _refreshUiAfterSync(info);
      }
    };

    syncService.onTokenRefreshed = () {
      if (mounted) {
        context.read<AuthProvider>().reloadUserFromStorage();
      }
    };

    // Iniciar monitoreo y esperar al primer chequeo de conectividad (evita "no hay período" en primera instalación)
    await sync.startMonitoring();

    // Cargar datos (ya sabemos si hay conexión; si hay, se traen período y productos del servidor)
    await _loadData();

    // El usuario pudo salir (logout / redirección a login) durante los awaits
    // anteriores: sin este guard, setState sobre un State ya desmontado lanza.
    if (!mounted) return;
    setState(() => _isInitialized = true);

    // Comprobación de actualización en segundo plano (no bloquea el POS).
    // Modo "suave": aviso opcional y descartable, nunca obligatorio.
    unawaited(_maybeCheckForUpdate());
  }

  /// Comprueba en segundo plano si hay una versión más reciente en Drive y,
  /// de haberla, muestra un aviso descartable (no obligatorio).
  Future<void> _maybeCheckForUpdate() async {
    if (_updateBannerShown) return;
    if (AppConstants.driveReleasesJsonFileId.isEmpty) return;
    if (!context.read<SyncProvider>().isOnline) return;

    try {
      final release = await _releaseService.fetchReleases();
      if (release == null || !mounted) return;

      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;
      if (compareVersions(release.version, currentVersion) <= 0) return;

      // Respetar la versión que el usuario decidió omitir previamente.
      final prefs = await SharedPreferences.getInstance();
      final skipped = prefs.getString(_skippedVersionKey);
      if (skipped == release.version) return;

      if (!mounted || _updateBannerShown) return;
      _updateBannerShown = true;
      _showUpdateBanner(release.version);
    } catch (e) {
      // Silencioso: la comprobación automática nunca debe molestar al usuario.
      logDebug('⚠️ Comprobación de actualización falló: $e');
    }
  }

  void _showUpdateBanner(String newVersion) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: context.colors.infoWash,
        leading: Icon(Icons.system_update, color: context.colors.info),
        content: Text('Hay una nueva versión disponible: v$newVersion'),
        actions: [
          TextButton(
            onPressed: () async {
              messenger.hideCurrentMaterialBanner();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(_skippedVersionKey, newVersion);
            },
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VersionScreen()),
              );
            },
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
  }

  /// Arranque en dos tiempos: primero se pinta lo que hay en SQLite (cero
  /// peticiones), y después `fullSync` hace **una sola** ronda de red cuyo
  /// resultado llega a la pantalla por `onDataRefreshed`. Antes estas dos
  /// etapas pedían lo mismo por separado y `fullSync` lo volvía a pedir por
  /// dentro: tres rondas para el mismo arranque.
  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    final tiendaId = auth.tiendaId;

    try {
      final productos = context.read<ProductosProvider>();

      // 1. Pintar desde la base local.
      await Future.wait([
        productos.refreshFromLocalCache(tiendaId),
        context.read<PeriodoProvider>().loadFromCache(tiendaId),
        context.read<CartProvider>().init(tiendaId),
        context.read<VentasProvider>().refreshPendientes(),
        context.read<MonedasProvider>().loadFromCache(
          auth.negocioId,
          fallbackMonedaBase: auth.monedaBase,
        ),
      ]);

      if (!mounted) return;

      productos.applyStockFilter(
        VentaSinStockPolicy.of(context, listen: false),
      );

      final syncProvider = context.read<SyncProvider>();
      if (!syncProvider.isOnline) {
        // Sin conexión no habrá ronda de red ni, por tanto, aviso que recargue
        // el listado: se sirve aquí desde el cache de ventas del servidor.
        final periodoId = context.read<PeriodoProvider>().periodoId;
        if (periodoId != null && periodoId.isNotEmpty) {
          await context.read<VentasProvider>().loadVentasUnificado(
            tiendaId,
            periodoId,
          );
        }
        return;
      }

      // 2. Única ronda de red. Con catálogo en cache el POS ya se puede usar,
      //    así que no se espera; sin catálogo no hay nada que pintar y sí.
      final sync = syncProvider.fullSync(tiendaId, negocioId: auth.negocioId);
      if (debeEsperarPrimerSync(
        tieneCatalogoLocal: productos.tieneCatalogoLocal,
        isOnline: syncProvider.isOnline,
      )) {
        await sync;
      } else {
        // Sin capturar el error, un fallo de esta rama sería una excepción
        // asíncrona no atendida y tumbaría la app en release.
        unawaited(
          sync.catchError((Object e) => logDebug('⚠️ fullSync inicial: $e')),
        );
      }
    } catch (e) {
      logDebug('⚠️ Error inicializando: $e');
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  /// Refresca providers tras una sincronización (reconexión o manual), sin repetir fullSync.
  ///
  /// onDataRefreshed puede dispararse desde varias fuentes a la vez (fullSync de
  /// la carga inicial, timer, reconexión, venta o anulación en segundo plano).
  /// Sin coordinación, dos refrescos concurrentes interleavan sus escrituras y
  /// corren applyStockFilter sobre una lista a medio reconstruir. Este guard
  /// serializa: si ya hay uno en curso, marca uno pendiente y el actual lo
  /// re-ejecuta una vez al terminar, para no perder el último estado.
  Future<void> _refreshUiAfterSync(SyncRefreshInfo info) async {
    _pendingRefreshInfo = _pendingRefreshInfo.merge(info);
    if (_isRefreshingUi) {
      _refreshUiPending = true;
      return;
    }
    _isRefreshingUi = true;
    try {
      do {
        _refreshUiPending = false;
        final actual = _pendingRefreshInfo;
        _pendingRefreshInfo = const SyncRefreshInfo();
        await _doRefreshUiAfterSync(actual);
      } while (_refreshUiPending && mounted);
    } finally {
      _isRefreshingUi = false;
    }
  }

  /// Repintado **desde la base local**: quien acaba de hablar con el servidor es
  /// fullSync / _pullInventario, y ya dejó el resultado escrito en SQLite.
  /// Releerlo por red aquí era lo que multiplicaba las peticiones de cada
  /// sincronización por tres.
  Future<void> _doRefreshUiAfterSync(SyncRefreshInfo info) async {
    final auth = context.read<AuthProvider>();
    final tiendaId = auth.tiendaId;
    if (tiendaId.isEmpty) return;

    try {
      await Future.wait([
        context.read<ProductosProvider>().refreshFromLocalCache(tiendaId),
        context.read<PeriodoProvider>().loadFromCache(tiendaId),
        context.read<VentasProvider>().refreshPendientes(),
        context.read<MonedasProvider>().loadFromCache(
          auth.negocioId,
          fallbackMonedaBase: auth.monedaBase,
        ),
      ]);

      if (!mounted) return;

      context.read<ProductosProvider>().applyStockFilter(
        VentaSinStockPolicy.of(context, listen: false),
      );

      // Lo único que sigue yendo al servidor, y solo si el servidor tiene algo
      // nuevo que contar. Lo consumen VentasListScreen y
      // ProductosVendidosScreen cuando están encima del POS; si no subió ni se
      // anuló nada, releer la lista devolvería exactamente lo mismo.
      if (!info.ventasCambiaron) return;
      final periodoId = context.read<PeriodoProvider>().periodoId;
      if (periodoId != null && periodoId.isNotEmpty) {
        await context.read<VentasProvider>().loadVentasUnificado(
          tiendaId,
          periodoId,
        );
      }
    } catch (e) {
      logDebug('⚠️ Error refrescando UI: $e');
    }
  }

  /// Sincronización manual (menú o pull-to-refresh).
  Future<void> _performSync() async {
    final auth = context.read<AuthProvider>();
    final syncProvider = context.read<SyncProvider>();

    if (!syncProvider.isOnline) {
      if (mounted) {
        AppSnackBar.show(
          context,
          content: const Text('Sin conexión — no se puede sincronizar'),
          backgroundColor: context.colors.caution,
        );
      }
      return;
    }

    await syncProvider.fullSync(auth.tiendaId, negocioId: auth.negocioId);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _scaffoldMessenger?.clearMaterialBanners();
    _syncProvider?.stopMonitoring();
    // Salir del POS o cerrar sesión no puede dejar el wakelock colgado.
    unawaited(ScreenWakeService.instance.liberar());
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Estado de sincronía bajo el nombre del negocio. Sin conexión no puede
  /// pasar desapercibido: se pinta en [AppSemanticColors.caution] y con ícono,
  /// porque es lo que explica que la venta se quede esperando en el equipo.
  Widget _buildStatusSubtitle(
    SyncProvider sync,
    VentasProvider ventas,
    AppSemanticColors colors,
  ) {
    final offline = !sync.isOnline;
    final style = TextStyle(
      fontSize: 11,
      color: offline ? colors.caution : colors.textSecondary,
      fontWeight: offline ? FontWeight.w600 : FontWeight.normal,
    );
    final texto = Text(
      _statusSubtitle(sync, ventas),
      style: style,
      overflow: TextOverflow.ellipsis,
    );
    if (!offline) return texto;
    return Row(
      children: [
        Icon(Icons.cloud_off, size: 12, color: colors.caution),
        const SizedBox(width: 4),
        Flexible(child: texto),
      ],
    );
  }

  String _statusSubtitle(SyncProvider sync, VentasProvider ventas) {
    final base = sync.isOnline ? 'Conectado' : 'Sin conexión';
    // Lo rechazado por el servidor se nombra aparte de lo que sólo espera
    // conexión: mezclarlo en un único "N sin subir" era lo que dejaba pasar
    // desapercibida una venta que nunca va a subir sola.
    final partes = [
      base,
      if (ventas.errorCount > 0) '${ventas.errorCount} con error',
      if (ventas.porSubirCount > 0) '${ventas.porSubirCount} sin subir',
    ];
    return partes.join(' · ');
  }

  /// Qué anuncia el lector de pantalla sobre el badge del botón "⋯".
  String? _pendientesLabel(VentasProvider ventas) {
    if (ventas.errorCount > 0) {
      final n = ventas.errorCount;
      return '$n ${n == 1 ? "venta con error" : "ventas con error"}';
    }
    if (ventas.porSubirCount > 0) {
      final n = ventas.porSubirCount;
      return '$n ${n == 1 ? "venta sin subir" : "ventas sin subir"}';
    }
    return null;
  }

  String _accionesTooltip(VentasProvider ventas) {
    final aviso = _pendientesLabel(ventas);
    return aviso == null ? 'Acciones del POS' : 'Acciones del POS — $aviso';
  }

  String _initials(String nombre) {
    final parts = nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final productosProvider = context.watch<ProductosProvider>();
    final periodoProvider = context.watch<PeriodoProvider>();
    final syncProvider = context.watch<SyncProvider>();
    final ventasProvider = context.watch<VentasProvider>();
    final cartProvider = context.watch<CartProvider>();
    final colors = context.colors;

    // Venta en curso = cualquier cuenta abierta con productos, no solo la
    // activa: con varias cuentas el cajero alterna entre ellas y la pantalla no
    // debe apagarse por estar mirando una vacía. El servicio ignora las
    // repeticiones, así que llamarlo en cada build es barato.
    unawaited(
      ScreenWakeService.instance
          .setActivo(cartProvider.totalItemCountAcrossCarts > 0),
    );

    // El catálogo oculta los productos agotados salvo que se permita venderlos:
    // hay que reconstruirlo tanto al perder/recuperar conexión como al cambiar
    // el ajuste "Vender sin existencias".
    final permitirSinStock = VentaSinStockPolicy.of(context);
    if (_lastPermitirSinStock != permitirSinStock) {
      _lastPermitirSinStock = permitirSinStock;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<ProductosProvider>().applyStockFilter(permitirSinStock);
        }
      });
    }

    // Tablet (≥600dp): catálogo + panel de carrito/cobro fijo a la derecha,
    // en vez de barra de cobro inferior + `CartItemsScreen` a pantalla
    // completa (`rediseno/pos.html` del Design System 4).
    final isTablet = MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;
    final showCartPanel =
        isTablet && _isInitialized && periodoProvider.hasActivePeriodo;

    final body = _buildBody(
      productosProvider,
      periodoProvider,
      syncProvider,
      auth: auth,
      ventasProvider: ventasProvider,
      colors: colors,
    );

    return HardwareScannerListener(
      enabled: _isInitialized && periodoProvider.hasActivePeriodo,
      child: Scaffold(
        body: SafeArea(
          top: true,
          bottom: false,
          child: showCartPanel
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: body),
                    Container(
                      width: 400,
                      decoration: BoxDecoration(
                        color: colors.raised,
                        border: Border(left: BorderSide(color: colors.border)),
                      ),
                      child: const CartPanel(),
                    ),
                  ],
                )
              : body,
        ),
        // La barra aparece con el carrito vacío en cuanto hay más de una
        // cuenta: es la única vía para llegar a la cuenta activa, y sin ella
        // una cuenta recién creada no se podía cerrar sin agregarle antes un
        // producto. Con una sola cuenta vacía no hay nada que hacer ahí, así
        // que se sigue ocultando y la pantalla queda limpia.
        bottomNavigationBar:
            !showCartPanel &&
                _isInitialized &&
                periodoProvider.hasActivePeriodo &&
                (cartProvider.activeItemCount > 0 || cartProvider.cartCount > 1)
            ? const PosCheckoutBar()
            : null,
      ),
    );
  }

  /// Barra superior (tienda + estado de sincronía + avatar), antes vivía en
  /// `Scaffold.appBar`. Ahora es un widget normal para poder incluirla en el
  /// bloque de cabecera que se oculta al desplazar el catálogo.
  Widget _buildTopBar(
    AuthProvider auth,
    SyncProvider syncProvider,
    VentasProvider ventasProvider,
    AppSemanticColors colors,
  ) {
    return Container(
      color: colors.raised,
      // Alto mínimo, no fijo: con la letra ampliada las dos líneas (tienda y
      // estado de sincronía) necesitan más sitio y antes se recortaban.
      constraints: const BoxConstraints(minHeight: kToolbarHeight),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // El ícono de marca solo entra si el ancho disponible (en tablet,
          // el de la columna de catálogo, no el de la pantalla completa)
          // deja espacio de sobra para él sin apretar el nombre ni el avatar.
          final showLogo = constraints.maxWidth >= 340;
          return Row(
            children: [
              if (showLogo) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/branding/logo_mark.png',
                      width: 16,
                      height: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      auth.negocioNombre.isNotEmpty
                          ? '${auth.negocioNombre} · ${auth.tiendaNombre}'
                          : auth.tiendaNombre,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    _buildStatusSubtitle(
                      syncProvider,
                      ventasProvider,
                      colors,
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Cuenta',
                child: Semantics(
                  button: true,
                  excludeSemantics: true,
                  label: 'Cuenta: modo oscuro, versión y cerrar sesión.',
                  child: InkWell(
                    onTap: () =>
                        UserMenuSheet.show(context, onLogout: _confirmLogout),
                    customBorder: const CircleBorder(),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: AppTapTarget.min,
                        minHeight: AppTapTarget.min,
                      ),
                      child: Center(
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: colors.accent,
                          child: Text(
                            _initials(auth.usuario?.nombre ?? ''),
                            style: TextStyle(
                              color: colors.onAccent,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(
    ProductosProvider productosProvider,
    PeriodoProvider periodoProvider,
    SyncProvider syncProvider, {
    required AuthProvider auth,
    required VentasProvider ventasProvider,
    required AppSemanticColors colors,
  }) {
    if (!_isInitialized && _initError == null) {
      return Column(
        children: [
          _buildTopBar(auth, syncProvider, ventasProvider, colors),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    if (_initError != null) {
      return Column(
        children: [
          _buildTopBar(auth, syncProvider, ventasProvider, colors),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: context.colors.negative,
                  ),
                  const SizedBox(height: 16),
                  Text('Error: $_initError'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _initialize,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Verificar período
    if (!periodoProvider.hasActivePeriodo) {
      return Column(
        children: [
          _buildTopBar(auth, syncProvider, ventasProvider, colors),
          Expanded(child: _buildNoPeriodoView(periodoProvider)),
        ],
      );
    }

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: !_headerVisible
              ? const SizedBox(width: double.infinity)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTopBar(auth, syncProvider, ventasProvider, colors),

                    // Sync status bar
                    if (syncProvider.lastMessage.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        color: syncProvider.isOnline
                            ? context.colors.positiveWash
                            : context.colors.cautionWash,
                        child: Text(
                          syncProvider.lastMessage,
                          style: TextStyle(
                            fontSize: 12,
                            color: syncProvider.isOnline
                                ? context.colors.positive
                                : context.colors.caution,
                          ),
                        ),
                      ),

                    // Buscador + "⋯" + escáner (Dirección B: el catálogo se busca, no se navega)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              decoration: InputDecoration(
                                hintText:
                                    'Buscar entre ${productosProvider.allProductos.length} productos',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchController.clear();
                                          productosProvider.searchProductos('');
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: context.colors.raised,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                  borderSide: BorderSide(
                                    color: context.colors.textPrimary,
                                    width: 2,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                  borderSide: BorderSide(
                                    color: context.colors.textPrimary,
                                    width: 2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              onChanged: productosProvider.searchProductos,
                            ),
                          ),
                          const SizedBox(width: 8),
                          BadgedIcon(
                            errorCount: ventasProvider.errorCount,
                            pendingCount: ventasProvider.porSubirCount,
                            semanticsLabel: _pendientesLabel(ventasProvider),
                            child: SizedBox(
                              width: AppTapTarget.comfortable,
                              height: AppTapTarget.comfortable,
                              child: IconButton.filledTonal(
                                onPressed: () => PosActionsSheet.show(
                                  context,
                                  onSync: _performSync,
                                ),
                                icon: const Icon(Icons.more_horiz),
                                tooltip: _accionesTooltip(ventasProvider),
                                style: IconButton.styleFrom(
                                  backgroundColor: context.colors.sunken,
                                  foregroundColor: context.colors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: AppTapTarget.comfortable,
                            height: AppTapTarget.comfortable,
                            child: IconButton.filled(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const BarcodeScannerScreen(),
                                ),
                              ),
                              icon: const Icon(Icons.qr_code_scanner),
                              tooltip: 'Escanear con cámara',
                              style: IconButton.styleFrom(
                                backgroundColor: context.colors.accent,
                                foregroundColor: context.colors.onAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    _CategoriaChips(productosProvider: productosProvider),
                  ],
                ),
        ),

        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onCatalogScroll,
            child: RefreshIndicator(
              color: context.colors.accent,
              onRefresh: _performSync,
              child: productosProvider.isLoading
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(
                          height: 200,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ],
                    )
                  : _CatalogoResultados(
                      productosProvider: productosProvider,
                      onProductTap: _showQuantitySheet,
                      onQuickAdd: _quickAddToCart,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoPeriodoView(PeriodoProvider periodoProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_off, size: 64, color: context.colors.textDisabled),
            const SizedBox(height: 16),
            const Text(
              'No hay período de caja abierto',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Debes abrir un período para comenzar a vender',
              style: TextStyle(color: context.colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: periodoProvider.isLoading
                  ? null
                  : () async {
                      final tiendaId = context.read<AuthProvider>().tiendaId;
                      await periodoProvider.abrirPeriodo(tiendaId);
                    },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Abrir Período'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.positive,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout() {
    final ventas = context.read<VentasProvider>();

    if (ventas.pendingCount > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ventas pendientes'),
          content: Text(
            'Tienes ${ventas.pendingCount} ventas sin sincronizar. '
            'Si cierras sesión se perderán. ¿Sincronizar primero?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await ventas.syncPendientes();
              },
              child: const Text('Sincronizar'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AuthProvider>().logout();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              }
            },
            child: Text(
              'Cerrar sesión',
              style: TextStyle(color: context.colors.negative),
            ),
          ),
        ],
      ),
    );
  }

  /// Agregar 1 unidad al carrito desde el botón "+" del catálogo.
  Future<void> _quickAddToCart(
    BuildContext context,
    ProductoModel producto,
  ) async {
    final productosProvider = context.read<ProductosProvider>();
    final permitirSinStock = VentaSinStockPolicy.of(context, listen: false);
    final cart = context.read<CartProvider>().activeCart;
    final cantidadEnCarrito =
        cart?.items
            .where((i) => i.productoTiendaId == producto.id)
            .fold<double>(0, (s, i) => s + i.cantidad) ??
        0;
    final maxDisp = ProductoPosRules.getMaxQuantity(
      producto,
      productosProvider.allProductos,
      cantidadEnCarrito: cantidadEnCarrito,
      permitirSinStock: permitirSinStock,
    );
    if (!permitirSinStock && maxDisp <= 0) {
      if (context.mounted) {
        AppSnackBar.show(
          context,
          content: const Text('Sin stock'),
          backgroundColor: context.colors.caution,
        );
      }
      return;
    }
    final qty = maxDisp >= 1 ? 1.0 : (producto.permiteDecimal ? 0.1 : 1.0);
    final ok = await context.read<CartProvider>().addToCart(
      producto,
      cantidad: qty,
      allProductos: productosProvider.allProductos,
      permitirSinStock: permitirSinStock,
    );
    if (!context.mounted) return;
    if (ok) {
      // Confirmación táctil: en un mostrador ruidoso, y con el snackbar fuera
      // del punto donde mira el cajero, la vibración es la señal más fiable.
      unawaited(HapticFeedback.lightImpact());
      AppSnackBar.show(
        context,
        content: Text(
          '${ProductoPosRules.nombreParaMostrar(producto)} agregado',
        ),
        backgroundColor: context.colors.positive,
        duration: const Duration(seconds: 1),
      );
      if (permitirSinStock &&
          !ProductoPosRules.tieneStockLocalEfectivo(
            producto,
            productosProvider.allProductos,
            cantidadEnCarrito: cantidadEnCarrito + qty,
          )) {
        AppSnackBar.show(
          context,
          content: const Text('Sin stock — se validará al sincronizar'),
          backgroundColor: context.colors.caution,
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  void _showQuantitySheet(BuildContext context, ProductoModel producto) {
    QuantitySheet.show(
      context,
      producto: producto,
      permitirSinStock: VentaSinStockPolicy.of(context, listen: false),
    );
  }
}

/// Chips de categoría (34px, pill): filtran la lista de resultados en el
/// propio `ProductosProvider`, en vez de navegar a otra pantalla.
class _CategoriaChips extends StatefulWidget {
  final ProductosProvider productosProvider;

  const _CategoriaChips({required this.productosProvider});

  @override
  State<_CategoriaChips> createState() => _CategoriaChipsState();
}

class _CategoriaChipsState extends State<_CategoriaChips> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // El trackpad/rueda del mouse en escritorio manda el gesto en el eje
  // vertical aunque la lista sea horizontal; sin esto, la barra de
  // categorías no responde al scroll (solo al arrastre táctil).
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) return;
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    final position = _scrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.jumpTo(target);
  }

  ProductosProvider get productosProvider => widget.productosProvider;

  @override
  Widget build(BuildContext context) {
    final categoriasConProductos = productosProvider.categorias
        .where(
          (c) =>
              productosProvider.allProductos.any((p) => p.categoriaId == c.id),
        )
        .toList();

    if (categoriasConProductos.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    final seleccionada = productosProvider.selectedCategoriaId;

    Widget chip(
      String label, {
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          showCheckmark: false,
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? colors.onAccent : colors.textSecondary,
          ),
          backgroundColor: colors.sunken,
          selectedColor: colors.accent,
          shape: const StadiumBorder(),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      );
    }

    // Un carril horizontal necesita alto acotado, así que no puede crecer solo:
    // se escala con la letra del sistema para no recortar los chips. (El target
    // táctil ya lo garantiza `ChoiceChip`, que reserva 48 aunque se vea 34.)
    final altoChips = MediaQuery.textScalerOf(context).scale(34) + 16;

    return SizedBox(
      height: altoChips,
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              ...ScrollConfiguration.of(context).dragDevices,
              PointerDeviceKind.mouse,
            },
          ),
          child: ListView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              chip(
                'Todas',
                selected: seleccionada == null,
                onTap: () => productosProvider.filterByCategoria(null),
              ),
              for (final CategoriaModel categoria in categoriasConProductos)
                chip(
                  categoria.nombre.trim(),
                  selected: seleccionada == categoria.id,
                  onTap: () =>
                      productosProvider.filterByCategoria(categoria.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Catálogo unificado: filas de 72px con nombre + stock a la izquierda,
/// precio + conversiones + "+" a la derecha (Dirección B "Pulgar").
class _CatalogoResultados extends StatelessWidget {
  final ProductosProvider productosProvider;
  final void Function(BuildContext context, ProductoModel product) onProductTap;
  final void Function(BuildContext context, ProductoModel product) onQuickAdd;

  const _CatalogoResultados({
    required this.productosProvider,
    required this.onProductTap,
    required this.onQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    final results = productosProvider.productos;
    final monedas = context.watch<MonedasProvider>();
    final isOnline = context.watch<SyncProvider>().isOnline;
    final permitirSinStock = VentaSinStockPolicy.of(context);

    if (results.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 48,
                      color: context.colors.textDisabled,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Sin productos para mostrar',
                      style: TextStyle(color: context.colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    final cart = context.watch<CartProvider>().activeCart;
    final allProductos = productosProvider.allProductos;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final p = results[index];
        final cantidadEnCarrito =
            cart?.items
                .where((i) => i.productoTiendaId == p.id)
                .fold<double>(0, (s, i) => s + i.cantidad) ??
            0;
        final puedeAgregar = ProductoPosRules.puedeAgregar(
          p,
          allProductos,
          cantidadEnCarrito: cantidadEnCarrito,
          permitirSinStock: permitirSinStock,
        );
        final enCarrito = cantidadEnCarrito > 0;
        final sinStockLocal =
            permitirSinStock &&
            !ProductoPosRules.tieneStockLocalEfectivo(
              p,
              allProductos,
              cantidadEnCarrito: cantidadEnCarrito,
            );
        final stockText = ProductoPosRules.textoStockEnCard(
          p,
          allProductos,
          cantidadEnCarrito: cantidadEnCarrito,
          permitirSinStock: permitirSinStock,
        );

        final precioBase = monedas.precioEnBase(p.precio, p.monedaPrecioCode);
        final altLines = MultiCurrencyAmount.alternativeLines(
          context,
          amount: precioBase,
          variant: MultiCurrencyVariant.compact,
          textAlign: TextAlign.end,
        );
        final hasAlts = altLines.isNotEmpty;
        // Todas las conversiones menos la última van arriba, junto al
        // precio; la última comparte fila con "Cant" (ver abajo).
        final topAltLines = hasAlts
            ? altLines.sublist(0, altLines.length - 1)
            : const <Widget>[];
        final lastAltLine = hasAlts ? altLines.last : null;

        // Sin esto TalkBack lee la fila como fragmentos sueltos: el nombre, cada
        // conversión de moneda por separado y el texto de stock. Como una sola
        // etiqueta se entiende de una pasada. El "+" queda fuera del
        // `excludeSemantics` porque es un hijo con su propia etiqueta.
        final semanticaFila = [
          ProductoPosRules.nombreParaMostrar(p),
          Formatters.formatMonedaAmount(
            precioBase,
            simbolo: monedas.simboloFor(monedas.monedaBase),
            code: monedas.monedaBase,
          ),
          if (stockText.isNotEmpty) stockText,
        ].join(', ');

        return Semantics(
          button: puedeAgregar,
          label: semanticaFila,
          child: InkWell(
            onTap: puedeAgregar ? () => onProductTap(context, p) : null,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AppTapTarget.rowLarge,
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: enCarrito ? context.colors.accentWash : null,
                border: Border(
                  bottom: BorderSide(color: context.colors.border),
                ),
              ),
              // `IntrinsicHeight` le da a la fila una altura concreta (la que
              // pida el contenido) para que `stretch` pueda repartirla entre
              // el botón, el precio centrado (sin conversiones) y la columna
              // de texto, en vez de necesitar una altura ya fijada por fuera.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Nombre y precio en la misma línea, para que el
                          // nombre llegue hasta el precio en vez de quedar en
                          // una columna angosta con espacio vacío de por
                          // medio. Sin conversiones, el precio se muestra
                          // centrado aparte (ver más abajo) y esta fila lleva
                          // solo el nombre.
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  ProductoPosRules.nombreParaMostrar(p),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (hasAlts) ...[
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    MultiCurrencyAmount.primaryOnly(
                                      context,
                                      amount: precioBase,
                                      variant: MultiCurrencyVariant.compact,
                                      textAlign: TextAlign.end,
                                    ),
                                    if (topAltLines.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      ...topAltLines,
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
                          if (sinStockLocal)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: StockLocalBadge(
                                compact: true,
                                isOnline: isOnline,
                              ),
                            ),
                          // "Cant" y la última conversión comparten esta fila,
                          // que por el `spaceBetween` de arriba siempre cae en
                          // el borde inferior — el mismo al que se ancla el
                          // botón "+".
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: stockText.isNotEmpty
                                    ? Text(
                                        stockText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: context.colors.textSecondary,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              if (lastAltLine != null) ...[
                                const SizedBox(width: 8),
                                lastAltLine,
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!hasAlts) ...[
                      const SizedBox(width: 8),
                      Center(
                        child: MultiCurrencyAmount.primaryOnly(
                          context,
                          amount: precioBase,
                          variant: MultiCurrencyVariant.compact,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        width: AppTapTarget.min,
                        height: AppTapTarget.min,
                        child: IconButton(
                          icon: const Icon(Icons.add),
                          style: IconButton.styleFrom(
                            backgroundColor: context.colors.accent,
                            foregroundColor: context.colors.onAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          onPressed: puedeAgregar
                              ? () => onQuickAdd(context, p)
                              : null,
                          tooltip:
                              'Agregar 1 de ${ProductoPosRules.nombreParaMostrar(p)}',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

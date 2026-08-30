import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/scan_audio_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/constants/storage_keys.dart';
import '../../core/di/injection.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/utils/producto_pos_rules.dart';
import '../../core/utils/venta_sin_stock_policy.dart';
import '../../widgets/stock_local_badge.dart';
import '../../data/models/producto_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/productos_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/sync_provider.dart';
import 'asociar_codigo_sheet.dart';
import 'widgets/scanner_cart_panel.dart';

/// Fracción de pantalla que ocupa el panel del carrito al abrir la pantalla.
const double _kSheetInitialSize = 0.5;

/// Tope de expansión del panel: deja siempre una franja de cámara visible.
const double _kSheetMaxSize = 0.85;

/// Limita la detección a la franja de cámara visible, para que no entren
/// códigos que el panel del carrito tapa.
///
/// DESACTIVADO: con BoxFit.cover el plugin recorta la ventana a una franja
/// estrecha del sensor y en dispositivos reales deja de detectar. Mientras esté
/// en false se escanea a pantalla completa (comportamiento histórico), con la
/// contrapartida de que un código situado detrás del panel también se lee.
const bool _kUseScanWindow = false;

/// Umbral de actualización de la ventana de escaneo. El plugin compara deltas
/// del rectángulo YA convertido a porcentaje del sensor (0..1), no en píxeles.
const double _kScanWindowUpdateThreshold = 0.05;

/// Colores para el overlay que compone sobre la cámara en vivo: siempre debe
/// leerse como "superficie oscura + texto claro", sin importar el tema
/// claro/oscuro de la app (a diferencia del resto de la UI, que sí cambia con
/// el tema). Por eso usa directamente [AppSemanticColors.light] (cuyos
/// tokens `inverse`/`onInverse`/`onInverseMuted` ya están pensados para fondo
/// oscuro) y [AppSemanticColors.dark] para los tonos vívidos de acento
/// (pensados para verse sobre fondo oscuro), en vez de `context.colors`.
class _ScanOverlayColors {
  const _ScanOverlayColors._();

  static const _surface = AppSemanticColors.light;
  static const _vivid = AppSemanticColors.dark;

  static Color get scrim => _surface.inverse;
  static Color get text => _surface.onInverse;
  static Color get success => _vivid.positive;
  static Color get caution => _vivid.caution;
}

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen>
    with TickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController();

  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  late final AnimationController _ringController;
  late final Animation<double> _ringScale;
  late final Animation<double> _ringOpacity;

  bool _autoScan = false;
  bool _asociarEnabled = true;
  bool _isProcessing = false;

  // Modo no-automático: producto detectado pendiente de confirmación.
  // El máximo disponible NO se guarda: se recalcula en cada build a partir del
  // carrito observado, porque el panel inferior permite cambiar cantidades y un
  // snapshot quedaría obsoleto al instante.
  ProductoModel? _previewProduct;
  String? _lastDetectedCode;

  // --- Panel del carrito ---
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  /// Fracción de pantalla que ocupa el panel. En un ValueNotifier y no en el
  /// State: el arrastre notifica en cada frame y un setState reconstruiría la
  /// pantalla entera (cámara incluida) 60 veces por segundo.
  final ValueNotifier<double> _sheetExtent = ValueNotifier(_kSheetInitialSize);

  /// Copia de [_sheetExtent] con debounce, para no reconfigurar la ventana de
  /// escaneo del plugin durante el arrastre.
  final ValueNotifier<double> _settledExtent = ValueNotifier(_kSheetInitialSize);
  Timer? _settleTimer;

  /// Producto recién agregado por escaneo, para resaltarlo en el panel.
  final ValueNotifier<String?> _highlightedId = ValueNotifier(null);
  Timer? _highlightTimer;

  /// Fracción mínima del panel (solo el encabezado visible). Depende del alto
  /// real de la pantalla, así que se calcula en el LayoutBuilder.
  double _sheetMinSize = 0.18;

  // Se resetea con cada frame detectado; cuando expira, oculta la card
  Timer? _detectionTimer;
  // Modo automático: cooldown entre detecciones para evitar múltiples registros
  Timer? _autoScanCooldown;

  // Control del bottom sheet de asociación para evitar duplicados
  bool _isAssociateSheetOpen = false;
  String? _currentAssociatingCode;
  String? _nextAssociatingCode;

  @override
  void initState() {
    super.initState();
    _loadAutoScanPreference();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _ringScale = Tween<double>(begin: 1.0, end: 1.95).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeOut),
    );

    _ringOpacity = Tween<double>(begin: 0.65, end: 0.0).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeOut),
    );
  }

  Future<void> _loadAutoScanPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _autoScan = prefs.getBool(StorageKeys.scanAutoMode) ?? false;
        _asociarEnabled = prefs.getBool(StorageKeys.scanAsociarEnabled) ?? true;
      });
    }
  }

  Future<void> _setAutoScan(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.scanAutoMode, value);
    if (mounted) {
      _detectionTimer?.cancel();
      _autoScanCooldown?.cancel();
      _autoScanCooldown = null;
      setState(() {
        _autoScan = value;
        _isProcessing = false;
        _previewProduct = null;
        _lastDetectedCode = null;
      });
    }
  }

  Future<void> _setAsociarEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.scanAsociarEnabled, value);
    if (mounted) setState(() => _asociarEnabled = value);
  }

  /// Modal con las opciones de configuración del escáner.
  Future<void> _mostrarConfiguracion(bool userCanAssociate) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.raised,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) {
        // El sheet mantiene su propio estado para reflejar el switch al instante;
        // el estado real vive en la pantalla y se persiste en SharedPreferences.
        return StatefulBuilder(
          builder: (_, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.colors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.settings_outlined,
                            color: context.colors.accent, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Configuración del escáner',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildOpcionConfig(
                      icon: Icons.bolt,
                      iconColor: context.colors.positive,
                      titulo: 'Escaneo automático',
                      descripcion:
                          'Agrega al carrito los productos leídos automáticamente, '
                          'sin necesidad de confirmación del usuario.',
                      value: _autoScan,
                      onChanged: (v) async {
                        await _setAutoScan(v);
                        setSheetState(() {});
                      },
                    ),
                    if (userCanAssociate) ...[
                      const Divider(height: 24),
                      _buildOpcionConfig(
                        icon: Icons.add_link,
                        iconColor: context.colors.caution,
                        titulo: 'Asociar código',
                        descripcion:
                            'Permite asociar códigos nuevos, que el sistema aún no '
                            'reconoce, a productos ya existentes.',
                        value: _asociarEnabled,
                        onChanged: (v) async {
                          await _setAsociarEnabled(v);
                          setSheetState(() {});
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOpcionConfig({
    required IconData icon,
    required Color iconColor,
    required String titulo,
    required String descripcion,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                descripcion,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: context.colors.accent,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _autoScanCooldown?.cancel();
    _highlightTimer?.cancel();
    _settleTimer?.cancel();
    _sheetController.dispose();
    _sheetExtent.dispose();
    _settledExtent.dispose();
    _highlightedId.dispose();
    _pulseController.dispose();
    _ringController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _playSuccess() => ScanAudioService.instance.playSuccess();

  Future<void> _playError() => ScanAudioService.instance.playError();

  // ---------------------------------------------------------------------------
  // Lógica de escaneo
  // ---------------------------------------------------------------------------

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    if (capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue?.trim();
    if (code == null || code.isEmpty) return;

    if (_autoScan) {
      if (_autoScanCooldown != null) return;
      _processCode(code, autoMode: true);
    } else {
      // Resetear el timer de desaparición con cada frame detectado
      _detectionTimer?.cancel();
      _detectionTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            _previewProduct = null;
            _lastDetectedCode = null;
          });
        }
      });

      // Si es el mismo código y ya hay preview, no hace nada (solo se resetó el timer)
      if (code == _lastDetectedCode) return;

      // Código nuevo o diferente: actualizar preview
      _lastDetectedCode = code;
      _processCode(code, autoMode: false);
    }
  }

  void _processCode(String code, {required bool autoMode}) {
    if (!mounted) return;

    final productosProvider = context.read<ProductosProvider>();
    final permitirSinStock = VentaSinStockPolicy.of(context, listen: false);
    final producto = productosProvider.findProductByCodigo(code);

    if (producto == null) {
      final usuario = context.read<AuthProvider>().usuario;
      final canAssociate = _asociarEnabled &&
          usuario != null &&
          usuario.hasPermisoOrAdmin('operaciones.pos-venta.asociar_codigo');

      if (canAssociate) {
        if (autoMode) _startAutoScanCooldown();

        if (_isAssociateSheetOpen) {
          if (_currentAssociatingCode == code) {
            // Mismo código ya en el modal — ignorar
            return;
          }
          // Código diferente: cerrar modal actual y abrir el nuevo
          _nextAssociatingCode = code;
          Navigator.of(context).pop();
          return;
        }

        _showAsociarCodigoSheet(code);
      } else {
        _playError();
        AppSnackBar.show(
          context,
          content: Text('Producto no encontrado para el código: $code'),
          backgroundColor: context.colors.negative,
        );
        if (autoMode) _startAutoScanCooldown();
      }
      return;
    }

    final cart = context.read<CartProvider>().activeCart;
    final cantidadEnCarrito = cart?.items
            .where((i) => i.productoTiendaId == producto.id)
            .fold<double>(0, (s, i) => s + i.cantidad) ??
        0;
    final maxDisp = ProductoPosRules.getMaxQuantity(
      producto,
      productosProvider.allProductos,
      cantidadEnCarrito: cantidadEnCarrito,
      permitirSinStock: permitirSinStock,
    );

    if (autoMode) {
      if (!permitirSinStock && maxDisp <= 0) {
        _playError();
        _startAutoScanCooldown();
        AppSnackBar.show(
          context,
          content: Text(
            '${ProductoPosRules.nombreParaMostrar(producto)}: sin existencias disponibles',
          ),
          backgroundColor: context.colors.caution,
        );
        return;
      }

      if (permitirSinStock &&
          !ProductoPosRules.puedeAgregar(
            producto,
            productosProvider.allProductos,
            cantidadEnCarrito: cantidadEnCarrito,
            permitirSinStock: true,
          )) {
        _playError();
        _startAutoScanCooldown();
        AppSnackBar.show(
          context,
          content: const Text('Cantidad supera el máximo permitido'),
          backgroundColor: context.colors.negative,
        );
        return;
      }

      setState(() => _isProcessing = true);
      final qty = maxDisp >= 1 ? 1.0 : (producto.permiteDecimal ? 0.1 : 1.0);
      context
          .read<CartProvider>()
          .addToCart(
            producto,
            cantidad: qty,
            allProductos: productosProvider.allProductos,
            permitirSinStock: permitirSinStock,
            moverAlInicio: true,
          )
          .then((ok) {
        if (!mounted) return;
        ok ? _playSuccess() : _playError();
        if (ok) {
          // El panel ya confirma visualmente el alta (fila arriba, resaltada y
          // total actualizado): un snackbar solo taparía el botón Cobrar.
          _marcarEscaneado(producto.id);
        } else {
          AppSnackBar.show(
            context,
            content: const Text('Cantidad supera el máximo'),
            backgroundColor: context.colors.negative,
            duration: const Duration(seconds: 1),
          );
        }
        if (mounted) setState(() => _isProcessing = false);
        _startAutoScanCooldown();
      }).catchError((_) {
        if (mounted) {
          setState(() => _isProcessing = false);
          _startAutoScanCooldown();
        }
      });
    } else {
      setState(() => _previewProduct = producto);
    }
  }

  void _startAutoScanCooldown() {
    _autoScanCooldown = Timer(const Duration(milliseconds: 1500), () {
      _autoScanCooldown = null;
    });
  }

  /// Máximo que se puede agregar del producto en preview, recalculado contra el
  /// carrito actual. Sustituye al antiguo snapshot `_previewMaxQty`, que no se
  /// enteraba de los cambios hechos desde el panel.
  double _maxDisponible(BuildContext ctx) {
    final producto = _previewProduct;
    if (producto == null) return 0;
    final allProductos = ctx.read<ProductosProvider>().allProductos;
    final cantidadEnCarrito = ctx
            .read<CartProvider>()
            .activeCart
            ?.items
            .where((i) => i.productoTiendaId == producto.id)
            .fold<double>(0, (s, i) => s + i.cantidad) ??
        0;
    return ProductoPosRules.getMaxQuantity(
      producto,
      allProductos,
      cantidadEnCarrito: cantidadEnCarrito,
      permitirSinStock: VentaSinStockPolicy.of(ctx, listen: false),
    );
  }

  /// Resalta en el panel el producto recién escaneado durante un momento.
  void _marcarEscaneado(String productoTiendaId) {
    _highlightTimer?.cancel();
    _highlightedId.value = productoTiendaId;
    _highlightTimer = Timer(const Duration(milliseconds: 1200), () {
      _highlightedId.value = null;
    });
  }

  void _onSheetExtentChanged(double extent) {
    _sheetExtent.value = extent;
    // El extent "asentado" alimenta la ventana de escaneo: se actualiza cuando
    // el usuario deja de arrastrar, no en cada frame.
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 150), () {
      _settledExtent.value = extent;
    });
  }

  /// Un toque en el asa alterna entre panel plegado y a media altura.
  void _toggleSheet() {
    if (!_sheetController.isAttached) return;
    final target = _sheetController.size > _sheetMinSize + 0.02
        ? _sheetMinSize
        : _kSheetInitialSize;
    _sheetController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Tras cobrar: se sigue escaneando, con el carrito ya vacío.
  void _onSaleCompleted() {
    if (!mounted) return;
    _detectionTimer?.cancel();
    _autoScanCooldown?.cancel();
    _autoScanCooldown = null;
    _highlightTimer?.cancel();
    _highlightedId.value = null;
    setState(() {
      _previewProduct = null;
      _lastDetectedCode = null;
      _isProcessing = false;
    });
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        _kSheetInitialSize,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _addPreviewToCart() {
    final producto = _previewProduct;
    if (producto == null || _isProcessing) return;
    final permitirSinStock = VentaSinStockPolicy.of(context, listen: false);
    // Se revalida en el instante del tap: el carrito pudo cambiar desde el
    // último build (por el panel o por la pistola).
    final maxDisp = _maxDisponible(context);
    if (!permitirSinStock && maxDisp <= 0) return;
    if (permitirSinStock &&
        !ProductoPosRules.puedeAgregar(
          producto,
          context.read<ProductosProvider>().allProductos,
          permitirSinStock: true,
        )) {
      return;
    }

    _detectionTimer?.cancel();
    final productosProvider = context.read<ProductosProvider>();

    setState(() {
      _isProcessing = true;
      _previewProduct = null;
      _lastDetectedCode = null;
    });

    final qty = maxDisp >= 1 ? 1.0 : (producto.permiteDecimal ? 0.1 : 1.0);
    context
        .read<CartProvider>()
        .addToCart(
          producto,
          cantidad: qty,
          allProductos: productosProvider.allProductos,
          permitirSinStock: permitirSinStock,
          moverAlInicio: true,
        )
        .then((ok) {
      if (!mounted) return;
      ok ? _playSuccess() : _playError();
      if (ok) {
        _marcarEscaneado(producto.id);
      } else {
        AppSnackBar.show(
          context,
          content: const Text('Cantidad supera el máximo'),
          backgroundColor: context.colors.negative,
          duration: const Duration(seconds: 1),
        );
      }
      _resetAfterDelay();
    }).catchError((_) {
      if (mounted) _resetAfterDelay();
    });
  }

  void _resetAfterDelay() {
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _isProcessing = false);
    });
  }

  /// Abre el bottom sheet de asociación cuando el código no está registrado.
  /// Gestiona duplicados: mismo código ignorado, código diferente reemplaza el modal.
  /// Tras asociar con éxito, actualiza el estado local y procesa el código.
  Future<void> _showAsociarCodigoSheet(String code) async {
    _isAssociateSheetOpen = true;
    _currentAssociatingCode = code;

    final producto = await AsociarCodigoSheet.show(
      context,
      scannedCode: code,
      productosRemote: injection.productosRemoteDataSource,
    );

    _isAssociateSheetOpen = false;
    _currentAssociatingCode = null;

    // Si hay un código pendiente (modal reemplazado por uno diferente), abrirlo
    final pending = _nextAssociatingCode;
    _nextAssociatingCode = null;
    if (pending != null && mounted && producto == null) {
      _showAsociarCodigoSheet(pending);
      return;
    }

    if (producto == null || !mounted) return;

    _playSuccess();
    AppSnackBar.show(
      context,
      content: Text(
        'Código asociado a "${ProductoPosRules.nombreParaMostrar(producto)}"',
      ),
      backgroundColor: context.colors.positive,
    );

    // El código ya está en la lista local: procesarlo directamente
    _processCode(code, autoMode: _autoScan);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthProvider>().usuario;
    final userCanAssociate = usuario != null &&
        usuario.hasPermisoOrAdmin('operaciones.pos-venta.asociar_codigo');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escáner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configuración del escáner',
            onPressed: () => _mostrarConfiguracion(userCanAssociate),
          ),
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (_, state, __) => Icon(
                state.torchState == TorchState.on
                    ? Icons.flash_on
                    : Icons.flash_off,
              ),
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final alto = constraints.maxHeight;
          // Tope en 0.45: los snapSizes deben ser estrictamente ascendentes, y
          // el mínimo nunca debe igualar al tamaño inicial.
          _sheetMinSize = alto > 0
              ? ((kScannerPanelHeaderHeight +
                          MediaQuery.paddingOf(context).bottom) /
                      alto)
                  .clamp(0.1, 0.45)
              : 0.18;

          return Stack(
            fit: StackFit.expand,
            children: [
              _cameraView,
              _buildCameraLayer(alto),
              // El sheet se pinta dentro de un SizedBox.expand que no consume
              // hits, así que los toques sobre la franja de cámara pasan de
              // largo sin necesidad de IgnorePointer.
              NotificationListener<DraggableScrollableNotification>(
                onNotification: (n) {
                  _onSheetExtentChanged(n.extent);
                  return false;
                },
                child: DraggableScrollableSheet(
                  controller: _sheetController,
                  initialChildSize: _kSheetInitialSize,
                  minChildSize: _sheetMinSize,
                  maxChildSize: _kSheetMaxSize,
                  snap: true,
                  snapSizes: [_sheetMinSize, _kSheetInitialSize, _kSheetMaxSize],
                  builder: (_, scrollController) => ScannerCartPanel(
                    scrollController: scrollController,
                    highlightedId: _highlightedId,
                    onSaleCompleted: _onSaleCompleted,
                    onHandleTap: _toggleSheet,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// La cámara se construye una sola vez y se guarda: así ningún setState de la
  /// pantalla (ni los cambios del carrito) la reconstruye.
  late final Widget _cameraView = _kUseScanWindow
      ? ValueListenableBuilder<double>(
          valueListenable: _settledExtent,
          builder: (_, extent, __) => LayoutBuilder(
            builder: (_, c) => MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              // Solo se detecta en la franja visible: si no, un código tapado
              // por el panel entraría al carrito sin que el usuario lo vea.
              scanWindow: Rect.fromLTWH(
                0,
                0,
                c.maxWidth,
                c.maxHeight * (1 - extent),
              ),
              scanWindowUpdateThreshold: _kScanWindowUpdateThreshold,
            ),
          ),
        )
      : MobileScanner(controller: _controller, onDetect: _onDetect);

  /// Overlay, card de preview y botón de confirmar, confinados a la franja de
  /// cámara que deja libre el panel.
  Widget _buildCameraLayer(double altoTotal) {
    return ValueListenableBuilder<double>(
      valueListenable: _sheetExtent,
      builder: (_, extent, __) {
        final altoCamara = (altoTotal * (1 - extent)).clamp(0.0, altoTotal);

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: altoCamara,
            width: double.infinity,
            child: Consumer<CartProvider>(
              // Observa el carrito para que el máximo disponible del preview se
              // recalcule cuando se editan cantidades en el panel.
              builder: (ctx, _, __) {
                final maxDisp = _maxDisponible(ctx);
                final permitirSinStock =
                    VentaSinStockPolicy.of(ctx, listen: false);
                final canAdd = _previewProduct != null &&
                    !_isProcessing &&
                    (permitirSinStock
                        ? ProductoPosRules.puedeAgregar(
                            _previewProduct!,
                            ctx.read<ProductosProvider>().allProductos,
                            permitirSinStock: true,
                          )
                        : maxDisp > 0);

                return Stack(
                  // Expand, si no el overlay se encoge a su contenido y el Stack
                  // lo alinea arriba-izquierda en vez de centrarlo.
                  fit: StackFit.expand,
                  children: [
                    _buildScanOverlay(maxDisp, altoCamara),
                    if (!_autoScan && _previewProduct != null)
                      Positioned(
                        top: 8,
                        left: 12,
                        right: 12,
                        child: _buildPreviewCard(),
                      ),
                    if (!_autoScan)
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: _buildActionButton(
                          canAdd: canAdd,
                          maxDisp: maxDisp,
                          compacto: altoCamara < 260,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildScanOverlay(double maxDisp, double altoCamara) {
    final String label;
    if (_isProcessing) {
      label = 'Procesando...';
    } else if (_autoScan) {
      label = 'Escaneando automáticamente...';
    } else if (_previewProduct != null) {
      label = maxDisp > 0
          ? 'Presiona el botón para agregar'
          : 'Sin existencias disponibles';
    } else {
      label = 'Apunta a un código de barras';
    }

    final bool activeFrame =
        _autoScan && !_isProcessing && _autoScanCooldown == null;
    final bool previewActive = !_autoScan && _previewProduct != null;
    final Color frameColor;
    final double frameWidth;

    if (activeFrame) {
      frameColor = _ScanOverlayColors.success;
      frameWidth = 3.0;
    } else if (previewActive) {
      frameColor = maxDisp > 0
          ? _ScanOverlayColors.success.withValues(alpha: 0.8)
          : _ScanOverlayColors.caution.withValues(alpha: 0.8);
      frameWidth = 2.5;
    } else {
      frameColor = _ScanOverlayColors.text.withValues(alpha: 0.6);
      frameWidth = 2.0;
    }

    // El recuadro se adapta al dispositivo: proporcional al ancho disponible y
    // limitado por el alto de la franja de cámara, que cambia al arrastrar el
    // panel.
    return LayoutBuilder(
      builder: (_, c) {
        final anchoDisponible = c.maxWidth.isFinite ? c.maxWidth : 0.0;
        final altoDisponible = c.maxHeight.isFinite ? c.maxHeight : altoCamara;
        final frameW = math.max(
          0.0,
          math.min(anchoDisponible * 0.78, anchoDisponible - 32),
        );
        final frameH = math.min(frameW * 0.64, altoDisponible * 0.45);
        final mostrarLabel = altoDisponible >= 200;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: frameW > 0 ? frameW : 0,
              height: frameH > 0 ? frameH : 0,
              decoration: BoxDecoration(
                border: Border.all(color: frameColor, width: frameWidth),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            if (mostrarLabel) ...[
              const SizedBox(height: 16),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: previewActive && maxDisp <= 0
                      ? _ScanOverlayColors.caution
                      : _ScanOverlayColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(
                      color: _ScanOverlayColors.scrim.withValues(alpha: 0.87),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Botón circular inferior en modo no-automático.
  /// Cuando hay producto en preview con stock → activo como "Agregar al carrito".
  /// Cuando no hay preview o sin stock → inactivo/indicativo.
  Widget _buildActionButton({
    required bool canAdd,
    required double maxDisp,
    bool compacto = false,
  }) {
    // Con el panel muy expandido queda poca franja: el botón se reduce para no
    // solaparse con el recuadro de escaneo.
    final double size = compacto ? 56 : 72;

    if (_isProcessing) {
      return Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _ScanOverlayColors.scrim,
            boxShadow: [
              BoxShadow(
                color: _ScanOverlayColors.scrim.withValues(alpha: 0.35),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: CircularProgressIndicator(
              color: _ScanOverlayColors.text,
              strokeWidth: 3,
            ),
          ),
        ),
      );
    }

    final bool noStock = _previewProduct != null && maxDisp <= 0;

    final List<Color> gradientColors;
    final Color ringColor;
    final IconData icon;

    if (canAdd) {
      final success = _ScanOverlayColors.success;
      gradientColors = [success, Color.lerp(success, Colors.black, 0.35)!];
      ringColor = success;
      icon = Icons.add_shopping_cart;
    } else if (noStock) {
      final caution = _ScanOverlayColors.caution;
      gradientColors = [
        caution.withValues(alpha: 0.7),
        caution.withValues(alpha: 0.5),
      ];
      ringColor = caution;
      icon = Icons.remove_shopping_cart_outlined;
    } else {
      gradientColors = [
        _ScanOverlayColors.text.withValues(alpha: 0.18),
        _ScanOverlayColors.text.withValues(alpha: 0.08),
      ];
      ringColor = _ScanOverlayColors.text.withValues(alpha: 0.22);
      icon = Icons.qr_code_scanner;
    }

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ringController,
            builder: (_, __) => Transform.scale(
              scale: _ringScale.value,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ringColor.withValues(
                      alpha: canAdd ? _ringOpacity.value : _ringOpacity.value * 0.4,
                    ),
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _pulseScale,
            builder: (_, child) => Transform.scale(
              scale: canAdd ? _pulseScale.value : 1.0,
              child: child,
            ),
            child: GestureDetector(
              onTap: canAdd ? _addPreviewToCart : null,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradientColors,
                  ),
                  boxShadow: canAdd
                      ? [
                          BoxShadow(
                            color: _ScanOverlayColors.success.withValues(alpha: 0.45),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ]
                      : [],
                ),
                child: Icon(icon, color: _ScanOverlayColors.text, size: compacto ? 26 : 34),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Card compacta semitransparente que aparece en la parte superior.
  Widget _buildPreviewCard() {
    final producto = _previewProduct!;
    final isOnline = context.watch<SyncProvider>().isOnline;
    final allProductos = context.read<ProductosProvider>().allProductos;
    final cart = context.watch<CartProvider>().activeCart;
    final cantidadEnCarrito = cart?.items
            .where((i) => i.productoTiendaId == producto.id)
            .fold<double>(0, (s, i) => s + i.cantidad) ??
        0;
    final permitirSinStock = VentaSinStockPolicy.of(context);
    final sinStockLocal = permitirSinStock &&
        !ProductoPosRules.tieneStockLocalEfectivo(
          producto,
          allProductos,
          cantidadEnCarrito: cantidadEnCarrito,
        );
    final nombreProducto = ProductoPosRules.nombreParaMostrar(producto);
    final existenciaStr = sinStockLocal
        ? (isOnline ? 'Sin stock' : 'Sin stock local')
        : ProductoPosRules.formatearCantidad(
            producto,
            !permitirSinStock
                ? ProductoPosRules.existenciaReal(producto)
                : ProductoPosRules.existenciaLocalEfectiva(
                    producto,
                    allProductos,
                    cantidadEnCarrito: cantidadEnCarrito,
                  ),
          );

    return Container(
      decoration: BoxDecoration(
        color: _ScanOverlayColors.scrim.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: sinStockLocal
              ? SinStockLocalStyles.border(context)
              : _ScanOverlayColors.text.withValues(alpha: 0.18),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _ScanOverlayColors.scrim.withValues(alpha: 0.3),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Icono de estado
          Icon(
            sinStockLocal
                ? Icons.cloud_off_outlined
                : Icons.qr_code_2_outlined,
            color: sinStockLocal
                ? SinStockLocalStyles.accent(context)
                : _ScanOverlayColors.success,
            size: 20,
          ),
          const SizedBox(width: 8),
          // Nombre del producto
          Expanded(
            child: Text(
              nombreProducto,
              style: TextStyle(
                color: _ScanOverlayColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Precio
          Text(
            '\$${producto.precio.toStringAsFixed(2)}',
            style: TextStyle(
              color: _ScanOverlayColors.success,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          // Existencia
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: sinStockLocal
                    ? SinStockLocalStyles.badgeBg(context).withValues(alpha: 0.9)
                    : _ScanOverlayColors.text.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                existenciaStr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: sinStockLocal
                      ? SinStockLocalStyles.accent(context)
                      : _ScanOverlayColors.text,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

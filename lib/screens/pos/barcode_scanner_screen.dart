import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/hardware_scanner_gate.dart';
import '../../services/scan_audio_service.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/storage_keys.dart';
import '../../core/di/injection.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/utils/producto_pos_rules.dart';
import '../../data/models/producto_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/productos_provider.dart';
import '../../providers/cart_provider.dart';
import 'asociar_codigo_sheet.dart';

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

  // Modo no-automático: producto detectado pendiente de confirmación
  ProductoModel? _previewProduct;
  double _previewMaxQty = 0;
  String? _lastDetectedCode;

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
    HardwareScannerGate.instance.block('camera');
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

  @override
  void dispose() {
    HardwareScannerGate.instance.unblock('camera');
    _detectionTimer?.cancel();
    _autoScanCooldown?.cancel();
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
          backgroundColor: AppColors.error,
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
    );

    if (autoMode) {
      if (maxDisp <= 0) {
        _playError();
        _startAutoScanCooldown();
        AppSnackBar.show(
          context,
          content: Text(
            '${ProductoPosRules.nombreParaMostrar(producto)}: sin existencias disponibles',
          ),
          backgroundColor: AppColors.warning,
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
          )
          .then((ok) {
        if (!mounted) return;
        ok ? _playSuccess() : _playError();
        AppSnackBar.show(
          context,
          content: Text(ok
              ? '${ProductoPosRules.nombreParaMostrar(producto)} agregado'
              : 'Cantidad supera el máximo'),
          backgroundColor: ok ? AppColors.success : AppColors.error,
          duration: const Duration(seconds: 1),
        );
        if (mounted) setState(() => _isProcessing = false);
        _startAutoScanCooldown();
      }).catchError((_) {
        if (mounted) {
          setState(() => _isProcessing = false);
          _startAutoScanCooldown();
        }
      });
    } else {
      setState(() {
        _previewProduct = producto;
        _previewMaxQty = maxDisp;
      });
    }
  }

  void _startAutoScanCooldown() {
    _autoScanCooldown = Timer(const Duration(milliseconds: 1500), () {
      _autoScanCooldown = null;
    });
  }

  void _addPreviewToCart() {
    final producto = _previewProduct;
    if (producto == null || _isProcessing || _previewMaxQty <= 0) return;

    _detectionTimer?.cancel();
    final productosProvider = context.read<ProductosProvider>();

    setState(() {
      _isProcessing = true;
      _previewProduct = null;
      _lastDetectedCode = null;
    });

    final qty =
        _previewMaxQty >= 1 ? 1.0 : (producto.permiteDecimal ? 0.1 : 1.0);
    context
        .read<CartProvider>()
        .addToCart(
          producto,
          cantidad: qty,
          allProductos: productosProvider.allProductos,
        )
        .then((ok) {
      if (!mounted) return;
      ok ? _playSuccess() : _playError();
      AppSnackBar.show(
        context,
        content: Text(ok
            ? '${ProductoPosRules.nombreParaMostrar(producto)} agregado'
            : 'Cantidad supera el máximo'),
        backgroundColor: ok ? AppColors.success : AppColors.error,
        duration: const Duration(seconds: 1),
      );
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
      backgroundColor: AppColors.success,
    );

    // El código ya está en la lista local: procesarlo directamente
    _processCode(code, autoMode: _autoScan);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool canAdd =
        _previewProduct != null && _previewMaxQty > 0 && !_isProcessing;

    final usuario = context.watch<AuthProvider>().usuario;
    final userCanAssociate = usuario != null &&
        usuario.hasPermisoOrAdmin('operaciones.pos-venta.asociar_codigo');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear código'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Auto',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Switch(
                  value: _autoScan,
                  onChanged: _setAutoScan,
                  activeThumbColor: Colors.greenAccent,
                  inactiveThumbColor: Colors.white70,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 4),
                if (userCanAssociate) ...[
                  Icon(
                    Icons.add_link,
                    size: 15,
                    color: _asociarEnabled
                        ? Colors.white.withOpacity(0.9)
                        : Colors.white38,
                  ),
                  Switch(
                    value: _asociarEnabled,
                    onChanged: _setAsociarEnabled,
                    activeThumbColor: Colors.amberAccent,
                    inactiveThumbColor: Colors.white38,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ],
            ),
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          _buildScanOverlay(),
          // Card de preview: arriba de todo en modo no-automático
          if (!_autoScan && _previewProduct != null)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _buildPreviewCard(),
            ),
          // Botón circular abajo: en auto es invisible; en manual es el "Agregar"
          if (!_autoScan)
            Positioned(
              bottom: 52,
              left: 0,
              right: 0,
              child: _buildActionButton(canAdd: canAdd),
            ),
        ],
      ),
    );
  }

  Widget _buildScanOverlay() {
    final String label;
    if (_isProcessing) {
      label = 'Procesando...';
    } else if (_autoScan) {
      label = 'Escaneando automáticamente...';
    } else if (_previewProduct != null) {
      label = _previewMaxQty > 0
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
      frameColor = Colors.greenAccent;
      frameWidth = 3.0;
    } else if (previewActive) {
      frameColor = _previewMaxQty > 0
          ? Colors.greenAccent.withOpacity(0.8)
          : AppColors.warning.withOpacity(0.8);
      frameWidth = 2.5;
    } else {
      frameColor = Colors.white.withOpacity(0.6);
      frameWidth = 2.0;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 280,
          height: 180,
          decoration: BoxDecoration(
            border: Border.all(color: frameColor, width: frameWidth),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          label,
          style: TextStyle(
            color: previewActive && _previewMaxQty <= 0
                ? AppColors.warning
                : Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            shadows: const [
              Shadow(
                color: Colors.black87,
                blurRadius: 6,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Botón circular inferior en modo no-automático.
  /// Cuando hay producto en preview con stock → activo como "Agregar al carrito".
  /// Cuando no hay preview o sin stock → inactivo/indicativo.
  Widget _buildActionButton({required bool canAdd}) {
    if (_isProcessing) {
      return Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey.shade700,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Center(
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
          ),
        ),
      );
    }

    final bool noStock = _previewProduct != null && _previewMaxQty <= 0;

    final List<Color> gradientColors;
    final Color ringColor;
    final IconData icon;

    if (canAdd) {
      gradientColors = [Colors.greenAccent.shade700, Colors.green.shade800];
      ringColor = Colors.greenAccent;
      icon = Icons.add_shopping_cart;
    } else if (noStock) {
      gradientColors = [
        AppColors.warning.withOpacity(0.7),
        AppColors.warning.withOpacity(0.5),
      ];
      ringColor = AppColors.warning;
      icon = Icons.remove_shopping_cart_outlined;
    } else {
      gradientColors = [
        Colors.white.withOpacity(0.18),
        Colors.white.withOpacity(0.08),
      ];
      ringColor = Colors.white38;
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
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ringColor.withOpacity(
                      canAdd ? _ringOpacity.value : _ringOpacity.value * 0.4,
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
                width: 72,
                height: 72,
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
                            color: Colors.greenAccent.withOpacity(0.45),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ]
                      : [],
                ),
                child: Icon(icon, color: Colors.white, size: 34),
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
    final sinStock = _previewMaxQty <= 0;
    final nombreProducto = ProductoPosRules.nombreParaMostrar(producto);
    final existenciaStr = producto.existencia % 1 == 0
        ? producto.existencia.toInt().toString()
        : producto.existencia.toStringAsFixed(2);

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.52),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: sinStock
              ? AppColors.warning.withOpacity(0.7)
              : Colors.white.withOpacity(0.18),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
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
            sinStock
                ? Icons.warning_amber_rounded
                : Icons.qr_code_2_outlined,
            color: sinStock ? AppColors.warning : Colors.greenAccent,
            size: 20,
          ),
          const SizedBox(width: 8),
          // Nombre del producto
          Expanded(
            child: Text(
              nombreProducto,
              style: const TextStyle(
                color: Colors.white,
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
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          // Existencia
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: sinStock
                  ? AppColors.warning.withOpacity(0.2)
                  : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 11,
                  color: sinStock ? AppColors.warning : Colors.white70,
                ),
                const SizedBox(width: 3),
                Text(
                  existenciaStr,
                  style: TextStyle(
                    color: sinStock ? AppColors.warning : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

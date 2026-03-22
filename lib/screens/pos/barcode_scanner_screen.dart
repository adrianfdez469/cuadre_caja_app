import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/utils/producto_pos_rules.dart';
import '../../providers/productos_provider.dart';
import '../../providers/cart_provider.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen>
    with TickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  late final AnimationController _ringController;
  late final Animation<double> _ringScale;
  late final Animation<double> _ringOpacity;

  // true mientras esperamos que la cámara capture un código
  bool _readyToScan = false;
  // true mientras procesamos el código detectado
  bool _isProcessing = false;

  Timer? _scanTimeout;

  @override
  void initState() {
    super.initState();

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

  @override
  void dispose() {
    _scanTimeout?.cancel();
    _pulseController.dispose();
    _ringController.dispose();
    _controller.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Generación de tono PCM/WAV en memoria — no requiere archivos de audio
  // ---------------------------------------------------------------------------

  Uint8List _generateTone({
    required double frequency,
    required double durationSeconds,
    int sampleRate = 22050,
    double amplitude = 0.85,
  }) {
    final numSamples = (sampleRate * durationSeconds).round();
    final buffer = ByteData(44 + numSamples * 2);

    void writeStr(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        buffer.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    // RIFF / WAVE header
    writeStr(0, 'RIFF');
    buffer.setUint32(4, 36 + numSamples * 2, Endian.little);
    writeStr(8, 'WAVE');

    // fmt sub-chunk
    writeStr(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little);  // tamaño del sub-chunk
    buffer.setUint16(20, 1, Endian.little);   // PCM
    buffer.setUint16(22, 1, Endian.little);   // mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // byteRate
    buffer.setUint16(32, 2, Endian.little);   // blockAlign
    buffer.setUint16(34, 16, Endian.little);  // bitsPerSample

    // data sub-chunk
    writeStr(36, 'data');
    buffer.setUint32(40, numSamples * 2, Endian.little);

    final maxAmp = (32767 * amplitude).round();
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Envolvente senoidal suaviza el ataque y la caída evitando clicks
      final envelope = math.sin(math.pi * t / durationSeconds);
      final sample = (envelope * maxAmp * math.sin(2 * math.pi * frequency * t))
          .round()
          .clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, sample, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  /// Dos pitidos cortos ascendentes: escaneo exitoso
  Future<void> _playSuccess() async {
    try {
      await _audioPlayer.play(
        BytesSource(_generateTone(frequency: 880.0, durationSeconds: 0.1)),
      );
      await Future.delayed(const Duration(milliseconds: 75));
      await _audioPlayer.play(
        BytesSource(_generateTone(frequency: 1320.0, durationSeconds: 0.14)),
      );
    } catch (_) {
      // El audio es complementario — si falla en algún dispositivo no afecta el flujo
    }
  }

  /// Un tono bajo y largo: escaneo fallido o producto no encontrado
  Future<void> _playError() async {
    try {
      await _audioPlayer.play(
        BytesSource(_generateTone(frequency: 210.0, durationSeconds: 0.45)),
      );
    } catch (_) {
      // El audio es complementario — si falla en algún dispositivo no afecta el flujo
    }
  }

  // ---------------------------------------------------------------------------
  // Lógica de escaneo
  // ---------------------------------------------------------------------------

  void _onScanButtonPressed() {
    if (_isProcessing || _readyToScan) return;
    _scanTimeout?.cancel();
    setState(() => _readyToScan = true);
    // Si en 4 segundos no se detecta nada, volvemos al estado idle
    _scanTimeout = Timer(const Duration(seconds: 4), () {
      if (mounted && _readyToScan) {
        setState(() => _readyToScan = false);
      }
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_readyToScan || _isProcessing) return;
    if (capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue?.trim();
    if (code == null || code.isEmpty) return;

    _scanTimeout?.cancel();
    setState(() {
      _readyToScan = false;
      _isProcessing = true;
    });

    final productosProvider = context.read<ProductosProvider>();
    final producto = productosProvider.findProductByCodigo(code);
    if (!mounted) return;

    if (producto == null) {
      _playError();
      AppSnackBar.show(
        context,
        content: Text('Producto no encontrado para el código: $code'),
        backgroundColor: AppColors.error,
      );
      _resetAfterDelay();
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

    if (maxDisp <= 0) {
      _playError();
      AppSnackBar.show(
        context,
        content: const Text('Sin stock disponible'),
        backgroundColor: AppColors.warning,
      );
      _resetAfterDelay();
      return;
    }

    final qty = maxDisp >= 1 ? 1.0 : (producto.permiteDecimal ? 0.1 : 1.0);
    context.read<CartProvider>().addToCart(
      producto,
      cantidad: qty,
      allProductos: productosProvider.allProductos,
    ).then((ok) {
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

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear código'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
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
          Positioned(
            bottom: 52,
            left: 0,
            right: 0,
            child: _buildScanButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildScanOverlay() {
    final frameColor = _readyToScan
        ? Colors.greenAccent
        : Colors.white.withOpacity(0.75);
    final frameWidth = _readyToScan ? 3.0 : 2.0;

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
        const SizedBox(height: 20),
        Text(
          _isProcessing
              ? 'Procesando...'
              : _readyToScan
                  ? 'Buscando código...'
                  : 'Encuadra el código y presiona el botón',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            shadows: [
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

  Widget _buildScanButton() {
    if (_isProcessing) {
      return Center(
        child: Container(
          width: 80,
          height: 80,
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

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Aro expansivo que llama la atención del usuario
          AnimatedBuilder(
            animation: _ringController,
            builder: (_, __) => Transform.scale(
              scale: _ringScale.value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (_readyToScan ? Colors.greenAccent : AppColors.primary)
                        .withOpacity(_ringOpacity.value),
                    width: 3,
                  ),
                ),
              ),
            ),
          ),

          // Botón principal con pulsación suave
          AnimatedBuilder(
            animation: _pulseScale,
            builder: (_, child) => Transform.scale(
              scale: _readyToScan ? 0.96 : _pulseScale.value,
              child: child,
            ),
            child: GestureDetector(
              onTap: _onScanButtonPressed,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _readyToScan
                        ? [Colors.greenAccent.shade700, Colors.green.shade800]
                        : [AppColors.primary, AppColors.primary.withOpacity(0.8)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_readyToScan
                              ? Colors.greenAccent
                              : AppColors.primary)
                          .withOpacity(0.55),
                      blurRadius: 24,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: Icon(
                  _readyToScan
                      ? Icons.center_focus_strong
                      : Icons.qr_code_scanner,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

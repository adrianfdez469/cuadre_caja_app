import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/barcode_scan_processor.dart';

const _hardwareScanIdleMs = 100;

/// Escucha teclas HID globales (pistola BT/USB) mientras el POS está activo.
///
/// El handler de `HardwareKeyboard` es global de proceso, así que sigue vivo
/// aunque le empujen rutas encima a la pantalla que monta este widget. Para
/// que un escaneo no modifique el carrito de forma invisible desde otra
/// pantalla, el listener solo actúa mientras **su propia ruta está al frente**
/// (ver [_esRutaActual]). Una pantalla que quiera soportar la pistola se
/// apunta montando este widget; el resto queda protegido por defecto.
class HardwareScannerListener extends StatefulWidget {
  const HardwareScannerListener({
    super.key,
    required this.enabled,
    required this.child,
    this.onScanOverride,
  });

  final bool enabled;
  final Widget child;

  /// Solo para tests: reemplaza el procesamiento del código escaneado, que en
  /// producción necesita los providers y la DI completos.
  final void Function(BuildContext context, String code)? onScanOverride;

  @override
  State<HardwareScannerListener> createState() => _HardwareScannerListenerState();
}

class _HardwareScannerListenerState extends State<HardwareScannerListener> {
  final StringBuffer _buffer = StringBuffer();
  Timer? _idleTimer;

  /// Ruta que contiene a este listener. Se toma en [didChangeDependencies]
  /// porque `ModalRoute.of` registra una dependencia y no puede llamarse desde
  /// el handler de teclas.
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  /// `false` en cuanto hay cualquier ruta encima: otra pantalla, un
  /// `showModalBottomSheet`, un `showDialog` o un menú emergente.
  bool get _esRutaActual => _route?.isCurrent ?? true;

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _idleTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(HardwareScannerListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _clearBuffer();
  }

  void _clearBuffer() {
    _buffer.clear();
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void _scheduleFlush() {
    _idleTimer?.cancel();
    _idleTimer = Timer(
      const Duration(milliseconds: _hardwareScanIdleMs),
      _flushBuffer,
    );
  }

  void _flushBuffer() {
    final code = _buffer.toString().trim();
    _clearBuffer();
    if (code.isEmpty || !mounted || !widget.enabled) return;
    if (!_esRutaActual) return;

    final override = widget.onScanOverride;
    if (override != null) {
      override(context, code);
      return;
    }
    unawaited(BarcodeScanProcessor.processHardwareScan(context, code));
  }

  bool _isEditableFocused() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || !focus.hasFocus) return false;

    final focusContext = focus.context;
    if (focusContext == null) return false;

    final editable =
        focusContext.findAncestorWidgetOfExactType<EditableText>();
    if (editable == null) return false;
    if (editable.readOnly) return false;

    return true;
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!widget.enabled || !_esRutaActual) {
      _clearBuffer();
      return false;
    }

    if (_isEditableFocused()) {
      _clearBuffer();
      return false;
    }

    if (event is! KeyDownEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_buffer.isNotEmpty) {
        _flushBuffer();
        return true;
      }
      return false;
    }

    final char = event.character;
    if (char == null || char.length != 1) return false;

    _buffer.write(char);
    _scheduleFlush();
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

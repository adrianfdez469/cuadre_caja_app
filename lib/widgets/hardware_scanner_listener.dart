import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/barcode_scan_processor.dart';
import '../services/hardware_scanner_gate.dart';

const _hardwareScanIdleMs = 100;

/// Escucha teclas HID globales (pistola BT/USB) mientras el POS está activo.
class HardwareScannerListener extends StatefulWidget {
  const HardwareScannerListener({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<HardwareScannerListener> createState() => _HardwareScannerListenerState();
}

class _HardwareScannerListenerState extends State<HardwareScannerListener> {
  final StringBuffer _buffer = StringBuffer();
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

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
    if (!HardwareScannerGate.instance.isEnabled) return;

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
    if (!widget.enabled || !HardwareScannerGate.instance.isEnabled) {
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

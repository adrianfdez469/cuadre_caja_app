import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Feedback de escaneo (éxito / error): tono generado sin archivos de audio
/// **más vibración**.
///
/// Las dos señales van juntas a propósito. Se llama desde ~15 sitios entre
/// `barcode_scanner_screen.dart` y `barcode_scan_processor.dart`; si la
/// vibración se sembrara en cada llamada, tarde o temprano alguna sonaría sin
/// vibrar. En un local ruidoso el tono se pierde y la vibración es lo único que
/// le queda al cajero para saber si el escaneo entró.
class ScanFeedbackService {
  ScanFeedbackService._();

  static final ScanFeedbackService instance = ScanFeedbackService._();

  final AudioPlayer _player = AudioPlayer();

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

    writeStr(0, 'RIFF');
    buffer.setUint32(4, 36 + numSamples * 2, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little);
    buffer.setUint16(22, 1, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);
    writeStr(36, 'data');
    buffer.setUint32(40, numSamples * 2, Endian.little);

    final maxAmp = (32767 * amplitude).round();
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final envelope = math.sin(math.pi * t / durationSeconds);
      final sample = (envelope * maxAmp * math.sin(2 * math.pi * frequency * t))
          .round()
          .clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, sample, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  Future<void> playSuccess() async {
    try {
      // Un toque corto: el escaneo entró y el cajero sigue.
      await HapticFeedback.lightImpact();
      await _player.play(
        BytesSource(_generateTone(frequency: 880.0, durationSeconds: 0.1)),
      );
      await Future.delayed(const Duration(milliseconds: 75));
      await _player.play(
        BytesSource(_generateTone(frequency: 1320.0, durationSeconds: 0.14)),
      );
    } catch (_) {}
  }

  Future<void> playError() async {
    try {
      // Más fuerte que el éxito: hay que parar y mirar la pantalla.
      await HapticFeedback.heavyImpact();
      await _player.play(
        BytesSource(_generateTone(frequency: 210.0, durationSeconds: 0.45)),
      );
    } catch (_) {}
  }
}

import 'package:flutter/services.dart';

/// Solo permite la parte entera; ignora dígitos después del separador decimal.
class CashAmountInputFormatter extends TextInputFormatter {
  const CashAmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final dot = newValue.text.indexOf('.');
    final intPart = dot >= 0 ? newValue.text.substring(0, dot) : newValue.text;
    final digits = intPart.replaceAll(RegExp(r'[^\d]'), '');
    if (digits == newValue.text) return newValue;

    final offset = newValue.selection.baseOffset.clamp(0, digits.length);
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// Texto del campo de efectivo (solo enteros, sin decimales).
String formatCashDisplay(double value) {
  if (value <= 0) return '';
  return value.truncate().toInt().toString();
}

/// Parsea el texto del campo de efectivo (solo enteros).
double parseCashAmount(String value) {
  final dot = value.indexOf('.');
  final intPart = dot >= 0 ? value.substring(0, dot) : value;
  if (intPart.isEmpty) return 0;
  return (int.tryParse(intPart) ?? 0).toDouble();
}

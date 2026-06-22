import 'package:intl/intl.dart';

class Formatters {
  // Formatear moneda
  static String formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'es_CO',
      symbol: '\$',
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }
  
  // Formatear fecha
  static String formatDate(DateTime date) {
    final formatter = DateFormat('dd/MM/yyyy', 'es');
    return formatter.format(date);
  }
  
  // Formatear fecha y hora
  static String formatDateTime(DateTime date) {
    final formatter = DateFormat('dd/MM/yyyy HH:mm', 'es');
    return formatter.format(date);
  }
  
  // Formatear solo hora
  static String formatTime(DateTime date) {
    final formatter = DateFormat('HH:mm', 'es');
    return formatter.format(date);
  }
  
  // Formatear número con decimales
  static String formatNumber(double number, {int decimals = 2}) {
    return number.toStringAsFixed(decimals);
  }

  /// Monto con símbolo de moneda o código (ej. US$10.00 o 10.00 EUR).
  static String formatMonedaAmount(
    double amount, {
    String? simbolo,
    String? code,
    int decimals = 2,
  }) {
    final formatted = formatNumber(amount, decimals: decimals);
    if (simbolo != null && simbolo.isNotEmpty) return '$simbolo$formatted';
    if (code != null && code.isNotEmpty) return '$formatted $code';
    return formatCurrency(amount);
  }
}


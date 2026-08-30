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
    // Sin locale: el patrón es puramente numérico y se ve igual en cualquiera,
    // mientras que fijar 'es' obliga a `initializeDateFormatting` y revienta en
    // cualquier contexto que no sea el arranque de la app (tests incluidos).
    final formatter = DateFormat('HH:mm');
    return formatter.format(date);
  }
  
  // Formatear número con decimales
  static String formatNumber(double number, {int decimals = 2}) {
    return number.toStringAsFixed(decimals);
  }

  /// Unidades del carrito con su sustantivo: "1 artículo", "12 artículos",
  /// "1.5 artículos" (hay productos que se venden por peso o fracción).
  ///
  /// Cuenta unidades reales, no líneas: 3 × un mismo producto son "3 artículos".
  static String formatUnidades(double unidades) {
    final cantidad = unidades == unidades.roundToDouble()
        ? unidades.toInt().toString()
        : unidades.toStringAsFixed(1);
    return '$cantidad ${unidades == 1 ? 'artículo' : 'artículos'}';
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


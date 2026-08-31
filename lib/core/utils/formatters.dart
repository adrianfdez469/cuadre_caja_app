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

  /// Cantidad de producto: entera cuando lo es, con decimales cuando hace falta.
  ///
  /// "3", no "3.00"; "1.5" para lo que se vende por peso o fracción. La regla
  /// estaba copiada en cuatro pantallas —y en dos versiones incompatibles
  /// dentro de una misma— así que vive aquí.
  ///
  /// [permiteDecimal] es la bandera del producto: cuando el producto no admite
  /// fracciones la cantidad se muestra entera aunque el dato venga sucio.
  static String formatCantidad(double cantidad, {bool permiteDecimal = true}) {
    if (!permiteDecimal) return cantidad.round().toString();
    if (cantidad == cantidad.roundToDouble()) {
      return cantidad.toInt().toString();
    }
    return cantidad.toStringAsFixed(2);
  }

  /// Encabezado de un grupo de día: "HOY", "AYER" o "MAR 26 AGO".
  ///
  /// En una lista de un solo período casi todo es de hoy, así que repetir
  /// `dd/MM/yyyy` en cada fila era ruido: la fecha sube al encabezado del grupo
  /// y la fila se queda con la hora, que es lo que distingue una venta de otra.
  static String formatDiaRelativo(DateTime fecha, {DateTime? ahora}) {
    final hoy = ahora ?? DateTime.now();
    final dia = DateTime(fecha.year, fecha.month, fecha.day);
    final diaHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final diff = diaHoy.difference(dia).inDays;
    if (diff == 0) return 'HOY';
    if (diff == 1) return 'AYER';
    return DateFormat('EEE d MMM', 'es').format(fecha).toUpperCase();
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

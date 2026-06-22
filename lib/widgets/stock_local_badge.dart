import 'package:flutter/material.dart';

/// Estilos compartidos para productos sin stock local (modo offline).
class SinStockLocalStyles {
  SinStockLocalStyles._();

  static const Color accent = Color(0xFFC45C00);
  static const Color surface = Color(0xFFFFFAF5);
  static const Color border = Color(0xFFFFD8A8);
  static const Color badgeBg = Color(0xFFFFF0E0);

  static ShapeBorder cardShape({required bool sinStockLocal}) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: sinStockLocal
          ? const BorderSide(color: border, width: 1)
          : BorderSide.none,
    );
  }

  static Color? cardColor({required bool sinStockLocal}) {
    return sinStockLocal ? surface : null;
  }
}

/// Badge para productos sin stock local (solo modo offline).
class StockLocalBadge extends StatelessWidget {
  final bool compact;

  const StockLocalBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final label = compact ? 'Sin stock local' : 'SIN STOCK LOCAL';
    final iconSize = compact ? 11.0 : 14.0;
    final fontSize = compact ? 10.0 : 11.0;
    final hPad = compact ? 6.0 : 8.0;
    final vPad = compact ? 2.0 : 3.0;

    return Container(
      constraints: const BoxConstraints(maxWidth: double.infinity),
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: SinStockLocalStyles.badgeBg,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        border: Border.all(color: SinStockLocalStyles.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: iconSize,
            color: SinStockLocalStyles.accent,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: SinStockLocalStyles.accent,
                letterSpacing: compact ? 0 : 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

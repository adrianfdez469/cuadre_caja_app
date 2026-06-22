import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/utils/formatters.dart';

/// Desglose de billetes por denominación (equivalente a BillBreakdownDynamic en web).
class BillBreakdownInput extends StatefulWidget {
  final List<double> denominations;
  final double? targetAmount;
  final ValueChanged<double> onChange;
  final ValueChanged<Map<double, int>>? onCountsChange;
  final Map<double, int>? initialCounts;
  final int resetKey;

  const BillBreakdownInput({
    super.key,
    required this.denominations,
    this.targetAmount,
    required this.onChange,
    this.onCountsChange,
    this.initialCounts,
    this.resetKey = 0,
  });

  @override
  State<BillBreakdownInput> createState() => _BillBreakdownInputState();
}

class _BillBreakdownInputState extends State<BillBreakdownInput> {
  final Map<double, int> _counts = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialCounts != null) {
      _counts.addAll(widget.initialCounts!);
    }
  }

  @override
  void didUpdateWidget(BillBreakdownInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) {
      _counts.clear();
      widget.onCountsChange?.call(const {});
      _notifyTotal();
    }
  }

  double get _total => widget.denominations.fold<double>(
        0,
        (sum, d) => sum + d * (_counts[d] ?? 0),
      );

  void _notifyTotal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChange(_total);
    });
  }

  void _setCount(double denomination, int count) {
    setState(() {
      final next = count.clamp(0, 9999);
      if (next == 0) {
        _counts.remove(denomination);
      } else {
        _counts[denomination] = next;
      }
    });
    widget.onCountsChange?.call(Map<double, int>.from(_counts));
    widget.onChange(_total);
  }

  @override
  Widget build(BuildContext context) {
    final diff = widget.targetAmount != null ? _total - widget.targetAmount! : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...widget.denominations.map((d) {
          final count = _counts[d] ?? 0;
          final subtotal = d * count;
          final highlighted = count > 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Material(
              color: highlighted
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(
                        Formatters.formatNumber(d, decimals: d == d.roundToDouble() ? 0 : 2),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('×', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      visualDensity: VisualDensity.compact,
                      onPressed: count > 0 ? () => _setCount(d, count - 1) : null,
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '$count',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: highlighted ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _setCount(d, count + 1),
                    ),
                    const Spacer(),
                    Text(
                      Formatters.formatNumber(subtotal),
                      style: TextStyle(
                        fontWeight: highlighted ? FontWeight.w600 : FontWeight.normal,
                        color: highlighted ? AppColors.textPrimary : AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const Divider(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total: ${Formatters.formatNumber(_total)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (diff != null && _total > 0)
              Text(
                diff == 0
                    ? 'Exacto ✓'
                    : diff > 0
                        ? 'Sobra: ${Formatters.formatNumber(diff)}'
                        : 'Faltan: ${Formatters.formatNumber(diff.abs())}',
                style: TextStyle(
                  color: diff >= 0 ? AppColors.success : AppColors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

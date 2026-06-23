import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const int _maxCount = 9999;

  final Map<double, int> _counts = {};
  final Map<double, TextEditingController> _countControllers = {};

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void dispose() {
    for (final controller in _countControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(BillBreakdownInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) {
      _counts.clear();
      _resetControllerTexts();
      widget.onCountsChange?.call(const {});
      _notifyTotal();
    }
  }

  void _initControllers() {
    for (final d in widget.denominations) {
      final count = widget.initialCounts?[d] ?? 0;
      if (count > 0) _counts[d] = count;
      _countControllers[d] = TextEditingController(
        text: count > 0 ? '$count' : '',
      );
    }
  }

  void _resetControllerTexts() {
    for (final d in widget.denominations) {
      _countControllers[d]?.text = '';
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

  String _countText(int count) => count > 0 ? '$count' : '';

  void _syncCountController(double denomination, int count) {
    final controller = _countControllers[denomination];
    if (controller == null) return;
    final text = _countText(count);
    if (controller.text != text) {
      controller.text = text;
    }
  }

  void _setCount(
    double denomination,
    int count, {
    bool syncController = true,
  }) {
    final next = count.clamp(0, _maxCount);
    setState(() {
      if (next == 0) {
        _counts.remove(denomination);
      } else {
        _counts[denomination] = next;
      }
      if (syncController) {
        _syncCountController(denomination, next);
      }
    });
    widget.onCountsChange?.call(Map<double, int>.from(_counts));
    widget.onChange(_total);
  }

  void _onCountManualEdit(double denomination, String value) {
    if (value.isEmpty) {
      _setCount(denomination, 0, syncController: false);
      return;
    }
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    _setCount(denomination, parsed, syncController: false);
  }

  void _formatCountField(double denomination) {
    final count = _counts[denomination] ?? 0;
    _syncCountController(denomination, count);
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
                      width: 56,
                      child: TextField(
                        controller: _countControllers[d],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 4,
                        style: TextStyle(
                          fontWeight: highlighted ? FontWeight.bold : FontWeight.normal,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          counterText: '',
                          hintText: '0',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onTap: () {
                          final controller = _countControllers[d];
                          if (controller == null) return;
                          controller.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: controller.text.length,
                          );
                        },
                        onEditingComplete: () => _formatCountField(d),
                        onTapOutside: (_) => _formatCountField(d),
                        onChanged: (value) => _onCountManualEdit(d, value),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      visualDensity: VisualDensity.compact,
                      onPressed: count < _maxCount ? () => _setCount(d, count + 1) : null,
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

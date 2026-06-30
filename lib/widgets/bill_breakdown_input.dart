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
  static const double _denomWidth = 36;
  static const double _stepBtnWidth = 24;
  static const double _inputWidth = 40;
  static const double _inputHeight = 28;

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

  Widget _stepButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: _stepBtnWidth,
      height: _stepBtnWidth,
      child: IconButton(
        icon: Icon(icon, size: 17),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildDenomRow(double d) {
    final count = _counts[d] ?? 0;
    final subtotal = d * count;
    final highlighted = count > 0;

    return Material(
      color: highlighted
          ? AppColors.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: _denomWidth,
                  child: Text(
                    Formatters.formatNumber(
                      d,
                      decimals: d == d.roundToDouble() ? 0 : 2,
                    ),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _stepButton(
                  icon: Icons.remove_circle_outline,
                  onPressed: count > 0 ? () => _setCount(d, count - 1) : null,
                ),
                SizedBox(
                  width: _inputWidth,
                  height: _inputHeight,
                  child: TextField(
                    controller: _countControllers[d],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 4,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          highlighted ? FontWeight.bold : FontWeight.normal,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      counterText: '',
                      hintText: '0',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 2, vertical: 5),
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
                _stepButton(
                  icon: Icons.add_circle_outline,
                  onPressed:
                      count < _maxCount ? () => _setCount(d, count + 1) : null,
                ),
              ],
            ),
            if (highlighted)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '= ${Formatters.formatNumber(subtotal)}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDenomGrid() {
    final denoms = widget.denominations;
    final rows = <Widget>[];

    for (var i = 0; i < denoms.length; i += 2) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildDenomRow(denoms[i])),
              if (i + 1 < denoms.length) ...[
                const SizedBox(width: 2),
                Expanded(child: _buildDenomRow(denoms[i + 1])),
              ] else
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      );
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final diff = widget.targetAmount != null ? _total - widget.targetAmount! : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._buildDenomGrid(),
        const Divider(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total: ${Formatters.formatNumber(_total)}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            if (diff != null && _total > 0)
              Text(
                diff == 0
                    ? 'Exacto ✓'
                    : diff > 0
                        ? 'Sobra: ${Formatters.formatNumber(diff)}'
                        : 'Faltan: ${Formatters.formatNumber(diff.abs())}',
                style: TextStyle(
                  fontSize: 13,
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

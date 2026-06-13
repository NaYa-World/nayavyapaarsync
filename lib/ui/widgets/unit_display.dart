import 'package:flutter/material.dart';
import '../../core/utils/indian_format.dart';

class UnitDisplay extends StatelessWidget {
  final double qty;
  final String unit; // 'BAG' or 'BOX'
  final double? bagWeightKg;
  final double? boxWeightKg;
  final TextStyle? primaryStyle;
  final TextStyle? secondaryStyle;
  final CrossAxisAlignment crossAxisAlignment;

  const UnitDisplay({
    super.key,
    required this.qty,
    required this.unit,
    this.bagWeightKg,
    this.boxWeightKg,
    this.primaryStyle,
    this.secondaryStyle,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    // Generate primary text: e.g. "2.5 BAGS"
    final String primaryText = IndianFormatUtils.formatQtyWithUnit(
      qty: qty,
      unit: unit,
    );

    // Check if secondary weight display is applicable
    double? conversionWeight;
    if (unit.toUpperCase() == 'BAG') {
      conversionWeight = bagWeightKg;
    } else if (unit.toUpperCase() == 'BOX') {
      conversionWeight = boxWeightKg;
    }

    final double? totalWeight = conversionWeight != null ? (qty * conversionWeight) : null;

    final theme = Theme.of(context);
    final TextStyle defaultPrimary = theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ) ??
        const TextStyle(fontWeight: FontWeight.bold);

    final TextStyle defaultSecondary = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
        ) ??
        const TextStyle(color: Colors.grey, fontSize: 11);

    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          primaryText,
          style: primaryStyle ?? defaultPrimary,
        ),
        if (totalWeight != null && totalWeight > 0) ...[
          const SizedBox(height: 2),
          Text(
            '(${IndianFormatUtils.formatNumber(totalWeight)} kg)',
            style: secondaryStyle ?? defaultSecondary,
          ),
        ],
      ],
    );
  }
}

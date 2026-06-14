import 'package:flutter/material.dart';
import '../../core/utils/indian_format.dart';

class GstRow extends StatelessWidget {
  final double subtotal;
  final double cgst;
  final double sgst;
  final double igst;
  final double grandTotal;

  const GstRow({
    super.key,
    required this.subtotal,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.grandTotal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIntraState = cgst > 0 || sgst > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRow('Subtotal', subtotal, theme),
        const SizedBox(height: 6),
        if (isIntraState) ...[
          _buildRow('CGST (Central GST)', cgst, theme, isSubRow: true),
          const SizedBox(height: 4),
          _buildRow('SGST (State GST)', sgst, theme, isSubRow: true),
        ] else if (igst > 0) ...[
          _buildRow('IGST (Integrated GST)', igst, theme, isSubRow: true),
        ],
        const SizedBox(height: 8),
        const Divider(height: 1, thickness: 1),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Grand Total',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            Text(
              IndianFormatUtils.formatCurrency(grandTotal),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRow(String label, double amount, ThemeData theme, {bool isSubRow = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isSubRow
              ? theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  fontSize: 13,
                )
              : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        Text(
          IndianFormatUtils.formatCurrency(amount),
          style: isSubRow
              ? theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  fontSize: 13,
                )
              : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

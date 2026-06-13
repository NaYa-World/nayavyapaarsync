import 'package:flutter/material.dart';
import '../../core/utils/indian_format.dart';
import '../../data/models/party.dart';

class PartyBalanceCard extends StatelessWidget {
  final Party party;
  final double balance;
  final String balanceType; // 'DR' or 'CR'
  final VoidCallback? onTap;

  const PartyBalanceCard({
    super.key,
    required this.party,
    required this.balance,
    required this.balanceType,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCustomer = party.type == 'CUSTOMER';

    // UI semantic colors
    // Customer DR = receivable (positive assets, green)
    // Customer CR = advance received (liability, amber)
    // Supplier CR = payable (liability, amber)
    // Supplier DR = advance paid (asset, green)
    final bool isReceivable = (isCustomer && balanceType == 'DR') || (!isCustomer && balanceType == 'DR');
    final Color indicatorColor = isReceivable ? Colors.green : Colors.amber.shade800;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar with party type abbreviation
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                radius: 24,
                child: Text(
                  party.name.trim().isNotEmpty ? party.name.substring(0, 1).toUpperCase() : 'P',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              const SizedBox(width: 16),
              // Party info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      party.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      party.phone,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      party.type == 'CUSTOMER' ? 'Customer' : 'Supplier',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Outstanding Balance
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    IndianFormatUtils.formatCurrency(balance),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: indicatorColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: indicatorColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      balanceType == 'DR' ? 'DR (Receivable)' : 'CR (Payable)',
                      style: TextStyle(
                        color: indicatorColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

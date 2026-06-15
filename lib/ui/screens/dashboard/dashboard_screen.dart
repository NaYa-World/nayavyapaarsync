import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/indian_format.dart';
import '../../../providers/backup_provider.dart';
import '../../../providers/item_provider.dart';
import '../../../providers/party_provider.dart';
import '../../../providers/transaction_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../widgets/offline_badge.dart';
import '../../widgets/va_logo.dart';
import '../audit/audit_log_screen.dart';
import '../backup/backup_settings_screen.dart';
import '../party/party_ledger_screen.dart';
import '../purchase/purchase_entry_screen.dart';
import '../recycle_bin/recycle_bin_screen.dart';
import '../reports/reports_screen.dart';
import '../sale/sale_entry_screen.dart';
import '../settings/settings_screen.dart';
import '../stock/stock_register_screen.dart';
import '../expense/expense_list_screen.dart';
import '../reports/gst_report_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // 1. Listen to state providers
    final transactionState = ref.watch(transactionProvider);
    final partyState = ref.watch(partyProvider);
    final lowStockItems = ref.watch(lowStockItemsProvider);
    final backupState = ref.watch(backupProvider);
    final settings = ref.watch(settingsProvider);
    final String companyName = (settings != null && settings.firmName.trim().isNotEmpty)
        ? settings.firmName
        : 'Telangana Seed & Fertiliser';

    // 2. Calculations for Metrics
    // Today's Sales
    final String todayDateStr = AppDateUtils.formatDate(DateTime.now());
    final double todaySales = transactionState.sales
        .where((s) => AppDateUtils.formatDate(s.date) == todayDateStr)
        .fold(0.0, (sum, s) => sum + s.grandTotal);

    // Pending Receivables (DR customer balances)
    double pendingReceivables = 0.0;
    // Pending Payables (CR supplier balances)
    double pendingPayables = 0.0;

    partyState.whenData((list) {
      for (final partyWithBal in list) {
        if (partyWithBal.party.type == 'CUSTOMER') {
          if (partyWithBal.balanceType == 'DR') {
            pendingReceivables += partyWithBal.outstandingBalance;
          } else {
            pendingReceivables -= partyWithBal.outstandingBalance; // Advances subtract
          }
        } else {
          if (partyWithBal.balanceType == 'CR') {
            pendingPayables += partyWithBal.outstandingBalance;
          } else {
            pendingPayables -= partyWithBal.outstandingBalance; // Advances subtract
          }
        }
      }
    });

    // 3. Compile Recent Day Book Transactions (Last 5 transactions: sales, purchases, payments)
    final List<Map<String, dynamic>> recentTransactions = [];
    
    for (final sale in transactionState.sales) {
      recentTransactions.add({
        'type': 'SALE',
        'narration': 'Invoice: ${sale.invoiceNo}',
        'date': sale.date,
        'amount': sale.grandTotal,
        'original': sale,
      });
    }
    for (final purchase in transactionState.purchases) {
      recentTransactions.add({
        'type': 'PURCHASE',
        'narration': 'Invoice: ${purchase.invoiceNo}',
        'date': purchase.date,
        'amount': purchase.grandTotal,
        'original': purchase,
      });
    }
    for (final payment in transactionState.payments) {
      final String action = payment.direction == 'RECEIVED' ? 'Receipt' : 'Payment';
      recentTransactions.add({
        'type': payment.direction == 'RECEIVED' ? 'PAYMENT_RECEIVED' : 'PAYMENT_PAID',
        'narration': '$action: ${payment.mode} (${payment.notes ?? 'No details'})',
        'date': payment.date,
        'amount': payment.amount,
        'original': payment,
      });
    }

    recentTransactions.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    final displayTransactions = recentTransactions.take(5).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'విత్తన & ఎరువుల గోదాం',
          style: TextStyle(fontFamily: 'Telugu', fontWeight: FontWeight.bold),
        ),
        actions: const [
          OfflineBadge(),
        ],
      ),
      drawer: _buildDrawer(context, backupState.hasUnsyncedChanges),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(transactionProvider.notifier).loadAllTransactions();
          await ref.read(partyProvider.notifier).loadParties();
          await ref.read(itemProvider.notifier).loadItems();
          await ref.read(backupProvider.notifier).initBackupState();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tally Gateway Header (Current Period & Company Name)
              _buildTallyHeader(context, companyName),
              const SizedBox(height: 16),
              // Backup Sync status banner
              _buildBackupBanner(context, ref, backupState),
              const SizedBox(height: 16),

              // Metrics Grid
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.9,
                children: [
                  _buildMetricCard(
                    context,
                    "Today's Sales",
                    IndianFormatUtils.formatCurrencyNoDecimals(todaySales),
                    Colors.green,
                    Icons.trending_up_rounded,
                  ),
                  _buildMetricCard(
                    context,
                    'Receivables',
                    IndianFormatUtils.formatCurrencyNoDecimals(pendingReceivables),
                    Colors.green.shade800,
                    Icons.call_received_rounded,
                  ),
                  _buildMetricCard(
                    context,
                    'Payables',
                    IndianFormatUtils.formatCurrencyNoDecimals(pendingPayables),
                    Colors.amber.shade900,
                    Icons.call_made_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Quick Actions Grid
              Text(
                'QUICK ACTIONS',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 12),
              _buildQuickActionsGrid(context),
              const SizedBox(height: 24),

              // Low Stock Alarms
              if (lowStockItems.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'LOW STOCK ALERTS',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        '${lowStockItems.length} Items',
                        style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  color: Colors.red.withValues(alpha: 0.03),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.red.withValues(alpha: 0.2)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: lowStockItems.take(3).length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = lowStockItems[index];
                      return ListTile(
                        leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
                        title: Text(item.item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Category: ${item.item.category}'),
                        trailing: Text(
                          'Stock: ${IndianFormatUtils.formatNumber(item.currentStock)} ${item.item.primaryUnit.toLowerCase()}s',
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Day Book Summary
              Text(
                'DAY BOOK SUMMARY (RECENT 5)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 12),
              if (displayTransactions.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No transactions recorded yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    ),
                  ),
                )
              else
                Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: displayTransactions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final tx = displayTransactions[index];
                      final type = tx['type'] as String;
                      final double amount = tx['amount'] as double;
                      final DateTime date = tx['date'] as DateTime;

                      IconData icon;
                      Color color;
                      if (type == 'SALE' || type == 'PAYMENT_RECEIVED') {
                        icon = type == 'SALE' ? Icons.arrow_downward_rounded : Icons.account_balance_wallet_rounded;
                        color = Colors.green;
                      } else {
                        icon = type == 'PURCHASE' ? Icons.arrow_upward_rounded : Icons.payment_rounded;
                        color = Colors.orange.shade800;
                      }

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.12),
                          foregroundColor: color,
                          child: Icon(icon, size: 20),
                        ),
                        title: Text(tx['narration'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(DateFormat('dd-MMM-yyyy').format(date)),
                        trailing: Text(
                          IndianFormatUtils.formatCurrency(amount),
                          style: TextStyle(fontWeight: FontWeight.bold, color: color),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTallyHeader(BuildContext context, String companyName) {
    final theme = Theme.of(context);
    final fyRange = AppDateUtils.getFinancialYearRange(DateTime.now());
    final String fyStartStr = DateFormat('dd-MMM-yyyy').format(fyRange.start);
    final String fyEndStr = DateFormat('dd-MMM-yyyy').format(fyRange.end);
    final String periodStr = '$fyStartStr to $fyEndStr';
    final String currentDateStr = DateFormat('EEEE, dd-MMM-yyyy').format(DateTime.now());

    return Card(
      elevation: 2,
      shadowColor: theme.colorScheme.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
              theme.colorScheme.surface,
            ],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CURRENT PERIOD',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.secondary,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      periodStr,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'CURRENT DATE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.secondary,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentDateStr,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24, thickness: 1),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NAME OF COMPANY',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.secondary,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  companyName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showCategorySelectionDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Select Category / వర్గాన్ని ఎంచుకోండి',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose category to load corresponding products.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.pop(context, 'SEED'),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3), width: 1.5),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.spa_rounded, color: Colors.green, size: 32),
                              SizedBox(height: 8),
                              Text(
                                'Seeds',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green),
                              ),
                              Text(
                                'విత్తనాలు',
                                style: TextStyle(fontFamily: 'Telugu', fontSize: 10, color: Colors.green),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.pop(context, 'FERTILISER'),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.3), width: 1.5),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.science_rounded, color: Colors.orange.shade800, size: 32),
                              const SizedBox(height: 8),
                              Text(
                                'Fertilizers/Pest',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange.shade900),
                              ),
                              Text(
                                'ఎరువులు/మందులు',
                                style: TextStyle(fontFamily: 'Telugu', fontSize: 10, color: Colors.orange.shade900),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _navigateToEntry(BuildContext context, bool isSale) async {
    final category = await _showCategorySelectionDialog(context);
    if (category == null) return;
    if (context.mounted) {
      if (isSale) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => SaleEntryScreen(category: category)));
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseEntryScreen(category: category)));
      }
    }
  }

  Widget _buildBackupBanner(BuildContext context, WidgetRef ref, BackupState state) {
    final theme = Theme.of(context);
    final String lastBackupStr = state.lastBackup != null
        ? DateFormat('dd-MMM-yyyy HH:mm').format(state.lastBackup!.timestamp)
        : 'Never';

    Color badgeColor = Colors.grey;
    String badgeText = 'No Backup';
    if (state.lastBackup != null) {
      if (state.lastBackup!.status == 'SUCCESS') {
        badgeColor = Colors.green;
        badgeText = 'Synced';
      } else {
        badgeColor = Colors.red;
        badgeText = 'Failed';
      }
    }

    if (state.hasUnsyncedChanges) {
      badgeColor = Colors.amber.shade800;
      badgeText = 'Backup Pending';
    }

    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.backup_rounded, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last Backup: $lastBackupStr',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 1),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(BuildContext context, String title, String value, Color color, IconData icon) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              foregroundColor: color,
              radius: 16,
              child: Icon(icon, size: 16),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 9,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsGrid(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: [
        _buildActionTile(
          context,
          'Sale Entry',
          'అమ్మకం బిల్',
          Icons.shopping_cart_rounded,
          Colors.green,
          () => _navigateToEntry(context, true),
        ),
        _buildActionTile(
          context,
          'Purchase Entry',
          'కొనుగోలు బిల్',
          Icons.shopping_bag_rounded,
          Colors.orange.shade800,
          () => _navigateToEntry(context, false),
        ),
        _buildActionTile(
          context,
          'Stock Register',
          'సరుకు నిల్వలు',
          Icons.inventory_2_rounded,
          Colors.blue.shade800,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockRegisterScreen())),
        ),
        _buildActionTile(
          context,
          'Party Ledger',
          'ఖాతాల పుస్తకం',
          Icons.people_alt_rounded,
          Colors.teal.shade800,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PartyLedgerScreen())),
        ),
        _buildActionTile(
          context,
          'Expenses',
          'ఖర్చులు',
          Icons.account_balance_wallet_rounded,
          Colors.red.shade800,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseListScreen())),
        ),
        _buildActionTile(
          context,
          'GST Returns',
          'జి.ఎస్.టి రిటర్న్స్',
          Icons.receipt_long_rounded,
          Colors.indigo.shade800,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GSTReportScreen())),
        ),
      ],
    );
  }

  Widget _buildActionTile(
    BuildContext context,
    String title,
    String subtitleTel,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                foregroundColor: color,
                radius: 20,
                child: Icon(icon, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitleTel,
                      style: const TextStyle(
                        fontFamily: 'Telugu',
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, bool hasUnsynced) {
    return Drawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Color(0xFF0F5132),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const VALogo(size: 48),
                const SizedBox(height: 8),
                const Text(
                  'Distributor Console',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Telangana Seed & Fertiliser',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                  leading: const Icon(Icons.dashboard_rounded),
                  title: const Text('Dashboard'),
                  onTap: () => Navigator.pop(context),
                ),
                ListTile(
                  leading: const Icon(Icons.shopping_cart_rounded),
                  title: const Text('Sale Entry'),
                  onTap: () {
                    Navigator.pop(context);
                    _navigateToEntry(context, true);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.shopping_bag_rounded),
                  title: const Text('Purchase Entry'),
                  onTap: () {
                    Navigator.pop(context);
                    _navigateToEntry(context, false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2_rounded),
                  title: const Text('Stock Register'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const StockRegisterScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.people_alt_rounded),
                  title: const Text('Party Ledger'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const PartyLedgerScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.analytics_rounded),
                  title: const Text('Reports & Registers'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_rounded),
                  title: const Text('Expenses'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseListScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_long_rounded),
                  title: const Text('GST Returns Report'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const GSTReportScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history_toggle_off_rounded),
                  title: const Text('Audit Logs'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditLogScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_rounded),
                  title: const Text('Recycle Bin'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const RecycleBinScreen()));
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.backup_rounded),
                  title: Row(
                    children: [
                      const Text('Backup Settings'),
                      if (hasUnsynced) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                        ),
                      ],
                    ],
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupSettingsScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.settings_rounded),
                  title: const Text('Business Profile'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen(isFirstLaunch: false)));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

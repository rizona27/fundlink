import 'package:flutter/cupertino.dart';
import '../models/transaction_record.dart';
import '../services/data_manager.dart';

class TransactionHistoryDialog extends StatefulWidget {
  final String clientId;
  final String fundCode;
  final String fundName;

  const TransactionHistoryDialog({
    super.key,
    required this.clientId,
    required this.fundCode,
    required this.fundName,
  });

  @override
  State<TransactionHistoryDialog> createState() => _TransactionHistoryDialogState();
}

class _TransactionHistoryDialogState extends State<TransactionHistoryDialog> {
  late DataManager _dataManager;
  List<TransactionRecord> _transactions = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _loadTransactions();
  }

  void _loadTransactions() {
    setState(() {
      _transactions = _dataManager.getTransactionHistory(
        widget.clientId,
        widget.fundCode,
      );
    });
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Color _getTypeColor(TransactionType type) {
    return type == TransactionType.buy 
        ? const Color(0xFF34C759)
        : const Color(0xFFFF3B30);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDarkMode ? const Color(0xFF2C2C2E) : CupertinoColors.white;
    final textColor = isDarkMode ? CupertinoColors.white : const Color(0xFF1C1C1E);
    final secondaryTextColor = isDarkMode 
        ? CupertinoColors.white.withOpacity(0.6)
        : const Color(0xFF8E8E93);

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: CupertinoPopupSurface(
          isSurfacePainted: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.fundName} - 交易记录',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? CupertinoColors.systemGrey.withOpacity(0.3)
                              : CupertinoColors.systemGrey.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.xmark,
                          size: 16,
                          color: textColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Flexible(
                child: _transactions.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.doc_text,
                              size: 48,
                              color: isDarkMode 
                                  ? CupertinoColors.white.withOpacity(0.3)
                                  : CupertinoColors.systemGrey3,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '暂无交易记录',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDarkMode 
                                    ? CupertinoColors.white.withOpacity(0.5)
                                    : CupertinoColors.systemGrey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _transactions.length,
                        itemBuilder: (context, index) {
                          final tx = _transactions[index];
                          return _buildTransactionCard(tx, isDarkMode, textColor, secondaryTextColor);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(TransactionRecord tx, bool isDarkMode, Color textColor, Color secondaryTextColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1C1C1E) : CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(10),
        border: tx.isPending 
            ? Border.all(color: CupertinoColors.systemOrange.withOpacity(0.3), width: 1)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getTypeColor(tx.type).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tx.type.displayName,
                  style: TextStyle(
                    color: _getTypeColor(tx.type),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (tx.isPending) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemOrange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.clock,
                        size: 10,
                        color: CupertinoColors.systemOrange,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '未生效',
                        style: TextStyle(
                          color: CupertinoColors.systemOrange,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              Text(
                _formatDate(tx.tradeDate),
                style: TextStyle(
                  fontSize: 12,
                  color: secondaryTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '金额',
                      style: TextStyle(fontSize: 10, color: secondaryTextColor),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tx.amount.toStringAsFixed(2)}元',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '份额',
                      style: TextStyle(fontSize: 10, color: secondaryTextColor),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tx.shares.toStringAsFixed(2)}份',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '净值',
                      style: TextStyle(fontSize: 10, color: secondaryTextColor),
                    ),
                    const SizedBox(height: 2),
                    if (tx.isPending)
                      Text(
                        '待确认',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.systemOrange,
                        ),
                      )
                    else
                      Text(
                        (tx.confirmedNav ?? tx.nav)?.toStringAsFixed(4) ?? '-',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

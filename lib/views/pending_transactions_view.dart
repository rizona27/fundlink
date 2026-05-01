import 'package:flutter/cupertino.dart';
import '../models/transaction_record.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../widgets/toast.dart';
import '../widgets/adaptive_top_bar.dart';

class PendingTransactionsView extends StatefulWidget {
  const PendingTransactionsView({super.key});

  @override
  State<PendingTransactionsView> createState() => _PendingTransactionsViewState();
}

class _PendingTransactionsViewState extends State<PendingTransactionsView> {
  late DataManager _dataManager;
  late FundService _fundService;
  List<TransactionRecord> _pendingTransactions = [];
  bool _isLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _fundService = FundService(_dataManager);
    _loadPendingTransactions();
  }

  void _loadPendingTransactions() {
    setState(() {
      _pendingTransactions = _dataManager.getPendingTransactions();
    });
  }

  Future<void> _refreshAndConfirm() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final confirmedCount = await _dataManager.autoConfirmPendingTransactions(_fundService);
      
      if (mounted) {
        _loadPendingTransactions();
        if (confirmedCount > 0) {
          context.showToast('成功确认 $confirmedCount 笔交易');
        } else {
          context.showToast('暂无可确认的交易');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showToast('确认失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  DateTime _getExpectedConfirmDate(TransactionRecord tx) {
    return DataManager.calculateConfirmDate(tx.tradeDate, tx.isAfter1500);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final textColor = isDarkMode ? CupertinoColors.white : const Color(0xFF1C1C1E);
    final secondaryTextColor = isDarkMode 
        ? CupertinoColors.white.withOpacity(0.6)
        : const Color(0xFF8E8E93);

    return Container(
      color: bgColor,
      child: SafeArea(
        child: Column(
          children: [
            AdaptiveTopBar(
              scrollOffset: 0,
              showBack: true,
              onBack: () => Navigator.of(context).pop(),
              showRefresh: true,
              onRefresh: _isLoading ? null : _refreshAndConfirm,
              showExpandCollapse: false,
              showSearch: false,
              showReset: false,
              showFilter: false,
              showSort: false,
              backgroundColor: const Color(0x00000000),
              iconColor: CupertinoTheme.of(context).primaryColor,
              iconSize: 24,
              buttonSpacing: 12,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2C2C2E) : CupertinoColors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '待确认交易',
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_pendingTransactions.length} 笔',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '净值将在T+1或T+2日自动确认',
                      style: TextStyle(
                        fontSize: 11,
                        color: secondaryTextColor,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: _pendingTransactions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.checkmark_seal,
                            size: 56,
                            color: isDarkMode 
                                ? CupertinoColors.white.withOpacity(0.3)
                                : CupertinoColors.systemGrey3,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '暂无待确认交易',
                            style: TextStyle(
                              fontSize: 15,
                              color: secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _pendingTransactions.length,
                      itemBuilder: (context, index) {
                        final tx = _pendingTransactions[index];
                        return _buildTransactionCard(tx, isDarkMode, textColor, secondaryTextColor);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(TransactionRecord tx, bool isDarkMode, Color textColor, Color secondaryTextColor) {
    final typeColor = tx.type == TransactionType.buy 
        ? const Color(0xFF34C759)
        : const Color(0xFFFF3B30);
    
    final expectedConfirmDate = _getExpectedConfirmDate(tx);
    final now = DateTime.now();
    final canConfirm = !now.isBefore(expectedConfirmDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2C2C2E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CupertinoColors.systemOrange.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tx.type.displayName,
                  style: TextStyle(
                    color: typeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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
                    const SizedBox(width: 2),
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
              const Spacer(),
              Text(
                _formatDate(tx.tradeDate),
                style: TextStyle(fontSize: 11, color: secondaryTextColor),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          Text(
            tx.fundName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          Text(
            '${tx.fundCode}',
            style: TextStyle(fontSize: 11, color: secondaryTextColor),
          ),
          
          const SizedBox(height: 8),
          
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('金额', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                    const SizedBox(height: 2),
                    Text(
                      '${tx.amount.toStringAsFixed(2)}元',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('份额', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                    const SizedBox(height: 2),
                    Text(
                      tx.shares > 0 
                          ? '${tx.shares.toStringAsFixed(2)}份'
                          : '待计算',
                      style: TextStyle(
                        fontSize: 13, 
                        fontWeight: FontWeight.w600, 
                        color: tx.shares > 0 ? textColor : CupertinoColors.systemOrange,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('预计确认', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(expectedConfirmDate),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: canConfirm 
                            ? const Color(0xFF34C759)
                            : CupertinoColors.systemOrange,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 6),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: canConfirm
                  ? const Color(0xFF34C759).withOpacity(0.1)
                  : CupertinoColors.systemOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  canConfirm 
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.info_circle_fill,
                  size: 12,
                  color: canConfirm 
                      ? const Color(0xFF34C759)
                      : CupertinoColors.systemOrange,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    canConfirm
                        ? '已到达确认时间'
                        : '等待净值公布中...',
                    style: TextStyle(
                      fontSize: 10,
                      color: canConfirm 
                          ? const Color(0xFF34C759)
                          : CupertinoColors.systemOrange,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

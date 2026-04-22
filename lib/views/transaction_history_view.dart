import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Divider;
import '../models/transaction_record.dart';
import '../services/data_manager.dart';
import '../widgets/toast.dart';
import 'add_holding_view.dart';

class TransactionHistoryView extends StatefulWidget {
  final String clientId;
  final String fundCode;
  final String fundName;

  const TransactionHistoryView({
    super.key,
    required this.clientId,
    required this.fundCode,
    required this.fundName,
  });

  @override
  State<TransactionHistoryView> createState() => _TransactionHistoryViewState();
}

class _TransactionHistoryViewState extends State<TransactionHistoryView> {
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

  Future<void> _showSellDialog() async {
    final sharesController = TextEditingController();
    final amountController = TextEditingController();
    DateTime sellDate = DateTime.now();
    bool sharesError = false;
    bool amountError = false;

    await showCupertinoDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return CupertinoAlertDialog(
            title: const Text('添加卖出交易'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '基金: ${widget.fundName}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: sharesController,
                  placeholder: '卖出份额',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [AmountInputFormatter()],
                  onChanged: (value) {
                    final trimmed = value.trim();
                    bool error = false;
                    if (trimmed.isNotEmpty) {
                      final shares = double.tryParse(trimmed);
                      error = shares == null || shares <= 0;
                    } else {
                      error = true;
                    }
                    setDialogState(() => sharesError = error);
                  },
                ),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: amountController,
                  placeholder: '卖出金额（选填）',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [AmountInputFormatter()],
                  onChanged: (value) {
                    final trimmed = value.trim();
                    bool error = false;
                    if (trimmed.isNotEmpty) {
                      final amount = double.tryParse(trimmed);
                      error = amount == null || amount <= 0;
                    }
                    setDialogState(() => amountError = error);
                  },
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final picked = await showCupertinoModalPopup<DateTime>(
                      context: context,
                      builder: (context) => Container(
                        height: 250,
                        color: CupertinoColors.systemBackground.resolveFrom(context),
                        child: CupertinoDatePicker(
                          initialDateTime: sellDate,
                          maximumDate: DateTime.now(),
                          mode: CupertinoDatePickerMode.date,
                          onDateTimeChanged: (date) => sellDate = date,
                        ),
                      ),
                    );
                    if (picked != null) {
                      setDialogState(() => sellDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGrey6.resolveFrom(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${sellDate.year}-${sellDate.month.toString().padLeft(2, '0')}-${sellDate.day.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const Spacer(),
                        const Icon(CupertinoIcons.calendar, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('取消'),
                onPressed: () => Navigator.pop(context),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () async {
                  final sharesText = sharesController.text.trim();
                  final amountText = amountController.text.trim();
                  
                  if (sharesText.isEmpty) {
                    context.showToast('请输入卖出份额');
                    return;
                  }
                  
                  final shares = double.tryParse(sharesText);
                  if (shares == null || shares <= 0) {
                    context.showToast('请输入有效的份额');
                    return;
                  }
                  
                  // 检查持仓是否足够
                  final holding = _dataManager.holdings
                      .firstWhere(
                        (h) => h.clientId == widget.clientId && h.fundCode == widget.fundCode,
                        orElse: () => throw Exception('未找到持仓'),
                      );
                  
                  if (shares > holding.totalShares) {
                    context.showToast('卖出份额不能超过持有份额(${holding.totalShares.toStringAsFixed(2)})');
                    return;
                  }
                  
                  double? amount;
                  if (amountText.isNotEmpty) {
                    amount = double.tryParse(amountText);
                    if (amount == null || amount <= 0) {
                      context.showToast('请输入有效的金额');
                      return;
                    }
                  }
                  
                  Navigator.pop(context);
                  
                  try {
                    // 获取客户姓名
                    final holding = _dataManager.holdings
                        .firstWhere(
                          (h) => h.clientId == widget.clientId && h.fundCode == widget.fundCode,
                        );
                    
                    final transaction = TransactionRecord(
                      clientId: widget.clientId,
                      clientName: holding.clientName,
                      fundCode: widget.fundCode,
                      fundName: widget.fundName,
                      type: TransactionType.sell,
                      amount: amount ?? 0, // 如果没填金额，默认为0
                      shares: shares,
                      tradeDate: sellDate,
                      remarks: '',
                    );
                    
                    await _dataManager.addTransaction(transaction);
                    _loadTransactions();
                    context.showToast('卖出成功');
                  } catch (e) {
                    context.showToast('卖出失败: $e');
                  }
                },
                child: const Text('确认'),
              ),
            ],
          );
        },
      ),
    );
    
    sharesController.dispose();
    amountController.dispose();
  }

  Future<void> _confirmDeleteTransaction(TransactionRecord tx) async {
    // 检查是否为第一笔买入交易
    final allTransactions = _dataManager.getTransactionHistory(
      widget.clientId,
      widget.fundCode,
    );
    
    // 找到最早的买入交易（按日期排序）
    final buyTransactions = allTransactions
        .where((t) => t.type == TransactionType.buy)
        .toList();
    buyTransactions.sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    
    if (buyTransactions.isNotEmpty && buyTransactions.first.id == tx.id) {
      // 这是第一笔买入交易，不允许删除
      await showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('无法删除'),
          content: const Text(
            '这是该持仓的第一笔买入交易（基石交易），\n'
            '不能直接删除。\n\n'
            '如需删除，请前往“管理持仓”页面\n'
            '删除整个持仓记录。',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('知道了'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }
    
    // 其他交易可以正常删除
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认删除'),
        content: Text(
          '确定要删除这条${tx.type.displayName}记录吗？\n'
          '金额：${tx.amount.toStringAsFixed(2)}元\n'
          '份额：${tx.shares.toStringAsFixed(2)}份',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('删除'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _dataManager.deleteTransaction(tx.id);
        _loadTransactions();
        context.showToast('删除成功');
      } catch (e) {
        context.showToast('删除失败: $e');
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Color _getTypeColor(TransactionType type) {
    return type == TransactionType.buy 
        ? const Color(0xFF34C759)  // 绿色-买入
        : const Color(0xFFFF3B30);  // 红色-卖出
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    return CupertinoPageScaffold(
      backgroundColor: backgroundColor,
      navigationBar: CupertinoNavigationBar(
        middle: Text('${widget.fundName} - 交易记录'),
        backgroundColor: Colors.transparent,
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _showSellDialog(),
          child: const Icon(CupertinoIcons.arrow_down_circle_fill, size: 24),
        ),
      ),
      child: SafeArea(
        child: _transactions.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.doc_text,
                      size: 64,
                      color: isDarkMode 
                          ? CupertinoColors.white.withOpacity(0.3)
                          : CupertinoColors.systemGrey3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '暂无交易记录',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDarkMode 
                            ? CupertinoColors.white.withOpacity(0.5)
                            : CupertinoColors.systemGrey,
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _transactions.length,
                itemBuilder: (context, index) {
                  final tx = _transactions[index];
                  return _buildTransactionCard(tx, isDarkMode);
                },
              ),
      ),
    );
  }

  Widget _buildTransactionCard(TransactionRecord tx, bool isDarkMode) {
    final cardColor = isDarkMode 
        ? const Color(0xFF2C2C2E)
        : CupertinoColors.white;
    final textColor = isDarkMode 
        ? CupertinoColors.white
        : const Color(0xFF1C1C1E);
    final secondaryTextColor = isDarkMode 
        ? CupertinoColors.white.withOpacity(0.6)
        : const Color(0xFF8E8E93);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getTypeColor(tx.type).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tx.type.displayName,
                    style: TextStyle(
                      color: _getTypeColor(tx.type),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(tx.tradeDate),
                  style: TextStyle(
                    fontSize: 13,
                    color: secondaryTextColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '交易金额',
                        style: TextStyle(
                          fontSize: 11,
                          color: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${tx.amount.toStringAsFixed(2)}元',
                        style: TextStyle(
                          fontSize: 16,
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
                        '交易份额',
                        style: TextStyle(
                          fontSize: 11,
                          color: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${tx.shares.toStringAsFixed(2)}份',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (tx.nav != null || tx.fee != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (tx.nav != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '成交净值',
                            style: TextStyle(
                              fontSize: 11,
                              color: secondaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tx.nav!.toStringAsFixed(4),
                            style: TextStyle(
                              fontSize: 13,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (tx.fee != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '手续费',
                            style: TextStyle(
                              fontSize: 11,
                              color: secondaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${tx.fee!.toStringAsFixed(2)}元',
                            style: TextStyle(
                              fontSize: 13,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            if (tx.remarks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '备注: ${tx.remarks}',
                style: TextStyle(
                  fontSize: 11,
                  color: secondaryTextColor,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: () => _confirmDeleteTransaction(tx),
                  child: Text(
                    '删除',
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.systemRed,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

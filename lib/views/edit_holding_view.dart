import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Divider;
import '../models/fund_holding.dart';
import '../models/transaction_record.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../widgets/toast.dart';
import '../widgets/add_transaction_dialog.dart';
import '../widgets/adaptive_top_bar.dart';

class EditHoldingView extends StatefulWidget {
  final FundHolding holding;

  const EditHoldingView({super.key, required this.holding});

  @override
  State<EditHoldingView> createState() => _EditHoldingViewState();
}

class _EditHoldingViewState extends State<EditHoldingView> {
  late DataManager _dataManager;
  late FundService _fundService;
  List<TransactionRecord> _transactions = [];
  bool _isLoading = false;
  FundHolding? _currentHolding; // 当前持仓（动态更新）

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _fundService = FundService(_dataManager);
    _loadTransactions();
    _updateCurrentHolding(); // 初始化当前持仓
  }

  void _updateCurrentHolding() {
    // 从DataManager中获取最新的持仓信息
    final holding = _dataManager.holdings.firstWhere(
      (h) => h.clientId == widget.holding.clientId && h.fundCode == widget.holding.fundCode,
      orElse: () => widget.holding, // 如果找不到，使用传入的holding
    );
    setState(() => _currentHolding = holding);
  }

  void _loadTransactions() {
    _updateCurrentHolding(); // 加载交易时也更新持仓
    setState(() {
      _transactions = _dataManager.getTransactionHistory(
        widget.holding.clientId,
        widget.holding.fundCode,
      );
    });
  }

  Future<void> _showAddTransactionDialog(TransactionType type) async {
    await showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AddTransactionDialog(
        clientId: widget.holding.clientId,
        clientName: widget.holding.clientName,
        fundCode: widget.holding.fundCode,
        fundName: widget.holding.fundName,
        type: type,
        currentNav: _currentHolding?.currentNav != null && _currentHolding!.currentNav > 0 
            ? _currentHolding!.currentNav 
            : null,
        currentShares: _currentHolding?.totalShares ?? widget.holding.totalShares,
        onTransactionAdded: () {
          _loadTransactions(); // 重新加载交易记录
          _dataManager.notifyListeners(); // 触发全局刷新
        },
      ),
    );
  }

  Future<void> _confirmDeleteTransaction(TransactionRecord tx) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: true, // 允许点击外部关闭
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

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardColor = isDarkMode ? const Color(0xFF2C2C2E) : CupertinoColors.white;
    final textColor = isDarkMode ? CupertinoColors.white : const Color(0xFF1C1C1E);
    final secondaryTextColor = isDarkMode 
        ? CupertinoColors.white.withOpacity(0.6)
        : const Color(0xFF8E8E93);

    // 使用最新的持仓信息
    final holding = _currentHolding ?? widget.holding;

    return CupertinoPageScaffold(
      backgroundColor: Colors.transparent,
      child: Container(
        color: backgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              AdaptiveTopBar(
                scrollOffset: 0,
                showBack: true,
                onBack: () => Navigator.of(context).pop(),
                showRefresh: false,
                showExpandCollapse: false,
                showSearch: false,
                showReset: false,
                showFilter: false,
                showSort: false,
                backgroundColor: Colors.transparent,
                iconColor: CupertinoTheme.of(context).primaryColor,
                iconSize: 24,
                buttonSpacing: 12,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              Expanded(
                child: Column(
                  children: [
                    // 持仓信息卡片
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          holding.fundName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                      Text(
                        '(${holding.fundCode})',
                        style: TextStyle(
                          fontSize: 14,
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
                            Text('客户', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                            const SizedBox(height: 4),
                            Text(holding.clientName, 
                                style: TextStyle(
                                  fontSize: 13, 
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                )),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('客户号', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                            const SizedBox(height: 4),
                            Text(holding.clientId.isNotEmpty ? holding.clientId : '-', 
                                style: TextStyle(
                                  fontSize: 13, 
                                  color: secondaryTextColor.withOpacity(0.7),
                                )),
                          ],
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
                            Text('累计投入', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                            const SizedBox(height: 4),
                            Text('${holding.totalCost.toStringAsFixed(2)}元', 
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textColor)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('持有份额', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                            const SizedBox(height: 4),
                            Text('${holding.totalShares.toStringAsFixed(2)}份', 
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textColor)),
                          ],
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
                            Text('平均成本', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                            const SizedBox(height: 4),
                            Text(holding.averageCost.toStringAsFixed(4), 
                                style: TextStyle(fontSize: 13, color: textColor)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('当前净值', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                            const SizedBox(height: 4),
                            Text(holding.currentNav.toStringAsFixed(4), 
                                style: TextStyle(fontSize: 13, color: textColor)),
                          ],
                        ),
                      ),
                    ],
                  ),
                        ],
                      ),
                    ),

                    // 操作按钮
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF34C759).withOpacity(0.8),
                                const Color(0xFF34C759).withOpacity(0.6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF34C759).withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => _showAddTransactionDialog(TransactionType.buy),
                            child: const Text(
                              '加仓',
                              style: TextStyle(
                                color: CupertinoColors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFFF3B30).withOpacity(0.8),
                                const Color(0xFFFF3B30).withOpacity(0.6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFFF3B30).withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => _showAddTransactionDialog(TransactionType.sell),
                            child: const Text(
                              '减仓',
                              style: TextStyle(
                                color: CupertinoColors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 交易历史标题
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Row(
                children: [
                  Text('交易记录', 
                      style: TextStyle(
                        fontSize: 16, 
                        fontWeight: FontWeight.w600, 
                        color: textColor,
                      )),
                  const Spacer(),
                  Text('${_transactions.length}条', 
                      style: TextStyle(
                        fontSize: 12, 
                        color: secondaryTextColor,
                      )),
                ],
                      ),
                    ),

                    // 交易历史列表
                    Expanded(
                      child: _transactions.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    CupertinoIcons.doc_text,
                                    size: 48,
                                    color: secondaryTextColor,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '暂无交易记录',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: secondaryTextColor,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(TransactionRecord tx, bool isDarkMode, Color textColor, Color secondaryTextColor) {
    final typeColor = tx.type == TransactionType.buy 
        ? const Color(0xFF34C759)
        : const Color(0xFFFF3B30);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2C2C2E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDarkMode 
              ? CupertinoColors.white.withOpacity(0.05)
              : CupertinoColors.black.withOpacity(0.05),
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
              const Spacer(),
              Text(
                _formatDate(tx.tradeDate),
                style: TextStyle(fontSize: 11, color: secondaryTextColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('金额', style: TextStyle(fontSize: 9, color: secondaryTextColor)),
                    const SizedBox(height: 2),
                    Text('${tx.amount.toStringAsFixed(2)}元', 
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('份额', style: TextStyle(fontSize: 9, color: secondaryTextColor)),
                    const SizedBox(height: 2),
                    Text('${tx.shares.toStringAsFixed(2)}份', 
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                  ],
                ),
              ),
              if (tx.nav != null) ...[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('净值', style: TextStyle(fontSize: 9, color: secondaryTextColor)),
                      const SizedBox(height: 2),
                      Text(tx.nav!.toStringAsFixed(4), 
                          style: TextStyle(fontSize: 13, color: textColor)),
                    ],
                  ),
                ),
              ],
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                onPressed: () => _confirmDeleteTransaction(tx),
                child: Icon(
                  CupertinoIcons.delete,
                  size: 18,
                  color: CupertinoColors.systemRed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

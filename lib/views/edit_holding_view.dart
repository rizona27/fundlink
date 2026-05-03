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
import '../widgets/glass_button.dart';
import '../utils/input_formatters.dart';
import 'add_holding_view.dart';

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
  FundHolding? _currentHolding; 

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _fundService = FundService(_dataManager);
    _loadTransactions();
    _updateCurrentHolding(); 
  }

  void _updateCurrentHolding() {
    final holding = _dataManager.holdings.firstWhere(
      (h) => h.clientId == widget.holding.clientId && h.fundCode == widget.holding.fundCode,
      orElse: () => widget.holding, 
    );
    setState(() => _currentHolding = holding);
  }

  void _loadTransactions() {
    _updateCurrentHolding(); 
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
          _loadTransactions(); 
          _dataManager.notifyListeners(); 
        },
      ),
    );
  }

  Future<void> _confirmDeleteTransaction(TransactionRecord tx) async {
    // 检查是否是基石交易(该基金的第一笔买入交易)
    // _transactions按日期降序排列,last是最早的交易
    final buyTransactions = _transactions.where((t) => t.type == TransactionType.buy).toList();
    final isFoundationBuy = buyTransactions.isNotEmpty && 
                            tx.id == buyTransactions.last.id;  // last是时间最早的买入
    
    if (isFoundationBuy) {
      await showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('无法删除'),
          content: const Text('第一笔买入交易是基石交易\n不能编辑或删除，以保障持仓数据完整性'),
          actions: [
            CupertinoDialogAction(
              child: const Text('知道了'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }
    
    // 非基石交易的待确认交易可以删除
    if (tx.isPending) {
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('删除待确认交易'),
          content: const Text('此交易尚未确认净值\n删除后将无法恢复，是否继续？'),
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
      
      if (confirmed != true) return;
    } else {
      // 已确认交易需要二次确认
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        barrierDismissible: true, 
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
      
      if (confirmed != true) return;
    }

    if (mounted) {
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
  
  String _maskClientName(String name) {
    if (name.isEmpty) return '';
    if (name.length == 1) return '*';
    if (name.length == 2) return '${name[0]}*';
    return '${name[0]}${'*' * (name.length - 2)}${name[name.length - 1]}';
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
                            Row(
                              children: [
                                Text(
                                  _dataManager.isPrivacyMode 
                                      ? _maskClientName(holding.clientName)
                                      : holding.clientName, 
                                    style: TextStyle(
                                      fontSize: 13, 
                                      fontWeight: FontWeight.w500,
                                      color: textColor,
                                    )),
                                if (holding.clientId.isNotEmpty && !_dataManager.isPrivacyMode) ...[
                                  const SizedBox(width: 4),
                                  Text('(${holding.clientId})', 
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: secondaryTextColor.withOpacity(0.7),
                                      )),
                                ],
                              ],
                            ),
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
                            Row(
                              children: [
                                Text('当前净值', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                                if (holding.navDate != null)
                                  Text(
                                    ' (${holding.navDate!.month.toString().padLeft(2, '0')}-${holding.navDate!.day.toString().padLeft(2, '0')})',
                                    style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                  ),
                              ],
                            ),
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

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: '加仓',
                      onPressed: () => _showAddTransactionDialog(TransactionType.buy),
                      isPrimary: true,
                      height: 48,
                      borderRadius: 12,
                      backgroundColorOverride: const Color(0xFFFF3B30).withOpacity(0.15),
                      textColorOverride: const Color(0xFFFF3B30),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassButton(
                      label: '减仓',
                      onPressed: () => _showAddTransactionDialog(TransactionType.sell),
                      isPrimary: true,
                      height: 48,
                      borderRadius: 12,
                      backgroundColorOverride: const Color(0xFF34C759).withOpacity(0.15),
                      textColorOverride: const Color(0xFF34C759),
                    ),
                  ),
                ],
              ),
            ),

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
                                return _buildTransactionCard(tx, index, isDarkMode, textColor, secondaryTextColor);
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

  Widget _buildTransactionCard(TransactionRecord tx, int index, bool isDarkMode, Color textColor, Color secondaryTextColor) {
    final typeColor = tx.type == TransactionType.buy 
        ? const Color(0xFFFF3B30) 
        : const Color(0xFF34C759); 
    
    final buyTransactions = _transactions
        .where((t) => t.type == TransactionType.buy)
        .toList()
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    
    final isFoundationBuy = buyTransactions.isNotEmpty && 
                            tx.id == buyTransactions.first.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2C2C2E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
        border: tx.isPending
            ? Border.all(color: CupertinoColors.systemOrange.withOpacity(0.3), width: 1)
            : Border.all(
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('净值', style: TextStyle(fontSize: 9, color: secondaryTextColor)),
                    const SizedBox(height: 2),
                    if (tx.isPending)
                      Text('待确认', 
                          style: TextStyle(
                            fontSize: 13, 
                            fontWeight: FontWeight.w600,
                            color: CupertinoColors.systemOrange,
                          ))
                    else
                      Text((tx.confirmedNav ?? tx.nav)?.toStringAsFixed(4) ?? '-', 
                          style: TextStyle(fontSize: 13, color: textColor)),
                  ],
                ),
              ),
              if (!isFoundationBuy) ...[
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: () => _editTransaction(tx),
                  child: Icon(
                    CupertinoIcons.pencil,
                    size: 18,
                    color: isDarkMode ? CupertinoColors.activeBlue : CupertinoColors.systemBlue,
                  ),
                ),
                const SizedBox(width: 8),
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
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editTransaction(TransactionRecord tx) async {
    // 检查是否是基石交易(时间上最早的那笔买入交易)
    // 注意:_transactions是按日期降序排列的,所以last才是最早的
    final buyTransactions = _transactions.where((t) => t.type == TransactionType.buy).toList();
    final isFoundationBuy = buyTransactions.isNotEmpty && 
                            tx.id == buyTransactions.last.id;  // last是最早的交易
    
    if (isFoundationBuy) {
      await showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('无法编辑'),
          content: const Text('第一笔买入交易是基石交易\n不能编辑或删除，以保障持仓数据完整性'),
          actions: [
            CupertinoDialogAction(
              child: const Text('知道了'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }
    
    // 非基石交易的待确认交易可以编辑
    if (tx.isPending) {
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('编辑待确认交易'),
          content: const Text('此交易尚未确认净值\n修改后将重新计算，是否继续？'),
          actions: [
            CupertinoDialogAction(
              child: const Text('取消'),
              onPressed: () => Navigator.pop(context, false),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('继续'),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      
      if (confirmed != true) return;
    }
    
    final sharesController = TextEditingController(text: tx.shares.toStringAsFixed(2));
    final amountController = TextEditingController(text: tx.amount.toStringAsFixed(2));
    DateTime tradeDate = tx.tradeDate;
    bool sharesError = false;
    bool amountError = false;

    await showCupertinoModalPopup(
      context: context,
      builder: (context) => GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            constraints: const BoxConstraints(maxWidth: 400),
            child: StatefulBuilder(
              builder: (context, setDialogState) {
              final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
              final textColor = isDark ? CupertinoColors.white : const Color(0xFF1C1C1E);
              final secondaryTextColor = isDark 
                  ? CupertinoColors.white.withOpacity(0.6)
                  : const Color(0xFF8E8E93);
              
              return CupertinoPopupSurface(
                isSurfacePainted: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '编辑${tx.type.displayName}交易',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark
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
                    const Divider(height: 1),
                    Container(
                      color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '交易份额',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            CupertinoTextField(
                              controller: sharesController,
                              placeholder: '请输入份额',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [AmountInputFormatter()],
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7),
                                borderRadius: BorderRadius.circular(10),
                              ),
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
                            if (sharesError)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '请输入有效的份额',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFFFF3B30)),
                                ),
                              ),
                            const SizedBox(height: 16),
                            
                            Text(
                              '交易金额',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            CupertinoTextField(
                              controller: amountController,
                              placeholder: '请输入金额',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [AmountInputFormatter()],
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7),
                                borderRadius: BorderRadius.circular(10),
                              ),
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
                            if (amountError)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '请输入有效的金额',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFFFF3B30)),
                                ),
                              ),
                            const SizedBox(height: 16),
                            
                            Text(
                              '交易日期',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () async {
                                await showCupertinoModalPopup(
                                  context: context,
                                  builder: (pickerContext) => _DatePickerModal(
                                    initialDate: tradeDate,
                                    onConfirm: (selectedDate) {
                                      if (context.mounted) {
                                        setDialogState(() => tradeDate = selectedDate);
                                      }
                                    },
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(CupertinoIcons.calendar, size: 18, color: secondaryTextColor),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${tradeDate.year}-${tradeDate.month.toString().padLeft(2, '0')}-${tradeDate.day.toString().padLeft(2, '0')}',
                                      style: TextStyle(fontSize: 15, color: textColor, fontWeight: FontWeight.w500),
                                    ),
                                    const Spacer(),
                                    Icon(CupertinoIcons.chevron_right, size: 16, color: secondaryTextColor),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GlassButton(
                              label: '取消',
                              onPressed: () => Navigator.pop(context),
                              isPrimary: false,
                              height: 44,
                              borderRadius: 30,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GlassButton(
                              label: '保存',
                              onPressed: () async {
                                final sharesText = sharesController.text.trim();
                                final amountText = amountController.text.trim();
                                
                                if (sharesText.isEmpty) {
                                  context.showToast('请输入份额');
                                  return;
                                }
                                
                                final shares = double.tryParse(sharesText);
                                if (shares == null || shares <= 0) {
                                  context.showToast('请输入有效的份额');
                                  return;
                                }
                                
                                final amount = double.tryParse(amountText);
                                if (amount == null || amount <= 0) {
                                  context.showToast('请输入有效的金额');
                                  return;
                                }
                                
                                Navigator.pop(context);
                                
                                try {
                                  final updatedTx = TransactionRecord(
                                    id: tx.id,
                                    clientId: tx.clientId,
                                    clientName: tx.clientName,
                                    fundCode: tx.fundCode,
                                    fundName: tx.fundName,
                                    type: tx.type,
                                    amount: amount,
                                    shares: shares,
                                    tradeDate: tradeDate,
                                    nav: tx.nav,
                                    fee: tx.fee,
                                    remarks: tx.remarks,
                                    isAfter1500: tx.isAfter1500,
                                    isPending: tx.isPending,
                                    confirmedNav: tx.confirmedNav,
                                  );
                                  
                                  await _dataManager.deleteTransaction(tx.id);
                                  await _dataManager.addTransaction(updatedTx);
                                  
                                  _loadTransactions();
                                  context.showToast('修改成功');
                                } catch (e) {
                                  context.showToast('修改失败: $e');
                                }
                              },
                              isPrimary: true,
                              height: 44,
                              borderRadius: 30,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
    );
  }
}

class _DatePickerModal extends StatefulWidget {
  final DateTime initialDate;
  final ValueChanged<DateTime> onConfirm;

  const _DatePickerModal({
    required this.initialDate,
    required this.onConfirm,
  });

  @override
  State<_DatePickerModal> createState() => _DatePickerModalState();
}

class _DatePickerModalState extends State<_DatePickerModal> {
  late DateTime _tempDate;

  @override
  void initState() {
    super.initState();
    _tempDate = widget.initialDate;
  }

  void _updateTempDate({int? year, int? month, int? day}) {
    setState(() {
      int y = year ?? _tempDate.year;
      int m = month ?? _tempDate.month;
      int d = day ?? _tempDate.day;
      int maxDays = DateTime(y, m + 1, 0).day;
      if (d > maxDays) d = maxDays;
      _tempDate = DateTime(y, m, d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final now = DateTime.now();
    final years = List.generate(10, (i) => now.year - 5 + i);
    final months = List.generate(12, (i) => i + 1);
    final days = List.generate(
      DateTime(_tempDate.year, _tempDate.month + 1, 0).day,
      (i) => i + 1,
    );

    final panelBgColor = isDarkMode ? const Color(0xFF1C1C1E) : CupertinoColors.white;
    final textColor = isDarkMode ? CupertinoColors.white : CupertinoColors.label;
    final selectionOverlay = CupertinoPickerDefaultSelectionOverlay(
      background: isDarkMode
          ? CupertinoColors.white.withOpacity(0.05)
          : CupertinoColors.black.withOpacity(0.03),
    );

    return CupertinoPopupSurface(
      child: Container(
        height: 280,
        decoration: BoxDecoration(
          color: panelBgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  _buildPickerColumn(
                    years,
                    years.indexOf(_tempDate.year),
                    '年',
                    (i) => _updateTempDate(year: years[i]),
                    panelBgColor,
                    textColor,
                    selectionOverlay,
                  ),
                  _buildPickerColumn(
                    months,
                    _tempDate.month - 1,
                    '月',
                    (i) => _updateTempDate(month: i + 1),
                    panelBgColor,
                    textColor,
                    selectionOverlay,
                  ),
                  _buildPickerColumn(
                    days,
                    _tempDate.day - 1,
                    '日',
                    (i) => _updateTempDate(day: i + 1),
                    panelBgColor,
                    textColor,
                    selectionOverlay,
                  ),
                ],
              ),
            ),
            Container(
              height: 0.5,
              color: isDarkMode
                  ? CupertinoColors.separator
                  : CupertinoColors.opaqueSeparator,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GlassButton(
                    label: '取消',
                    onPressed: () => Navigator.pop(context),
                    isPrimary: false,
                    height: 44,
                    borderRadius: 30,
                  ),
                  const SizedBox(width: 12),
                  GlassButton(
                    label: '完成',
                    onPressed: () {
                      widget.onConfirm(_tempDate);
                      Navigator.pop(context);
                    },
                    isPrimary: true,
                    height: 44,
                    borderRadius: 30,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerColumn(
    List<int> items,
    int initial,
    String unit,
    ValueChanged<int> onChanged,
    Color bgColor,
    Color textColor,
    Widget overlay,
  ) {
    return Expanded(
      child: CupertinoPicker(
        scrollController: FixedExtentScrollController(initialItem: initial),
        itemExtent: 40,
        backgroundColor: bgColor,
        selectionOverlay: overlay,
        onSelectedItemChanged: onChanged,
        children: items.map((item) => Center(
          child: Text('$item$unit', style: TextStyle(color: textColor, fontSize: 16)),
        )).toList(),
      ),
    );
  }
}

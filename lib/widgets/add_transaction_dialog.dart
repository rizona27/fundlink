import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import '../models/transaction_record.dart';
import '../models/net_worth_point.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../widgets/toast.dart';
import '../widgets/glass_button.dart';

class AddTransactionDialog extends StatefulWidget {
  final String clientId;
  final String clientName;
  final String fundCode;
  final String fundName;
  final TransactionType type;
  final double? currentNav;
  final double currentShares;
  final VoidCallback onTransactionAdded;

  const AddTransactionDialog({
    super.key,
    required this.clientId,
    required this.clientName,
    required this.fundCode,
    required this.fundName,
    required this.type,
    this.currentNav,
    required this.currentShares,
    required this.onTransactionAdded,
  });

  @override
  State<AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<AddTransactionDialog> {
  late DataManager _dataManager;
  
  final TextEditingController _sharesController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _navController = TextEditingController();
  final TextEditingController _feeController = TextEditingController();
  
  DateTime _tradeDate = DateTime.now();
  bool _isLoading = false;
  String? _timeHint;
  double? _estimatedShares; // 预估份额
  bool _hasManuallyEditedShares = false; // 用户是否手动编辑过份额
  bool _hasManuallyEditedAmount = false; // 用户是否手动编辑过金额
  bool _isFetchingNav = false; // 是否正在获取净值
  bool _isAfter1500 = false; // 是否15:00后交易
  bool _isPendingTransaction = false; // 是否为待确认交易
  
  // 缓存待确认提示的 Future，避免重复计算
  Future<String>? _pendingHintFuture;
  
  // 判断是否为待确认交易(基于净值日期)
  bool get _isTodayTransaction {
    return _isPendingTransaction;
  }
  
  // 更新待确认交易状态（异步）
  Future<void> _updatePendingStatus() async {
    final isPending = await DataManager.isTransactionPendingAsync(_tradeDate, _isAfter1500);
    if (mounted) {
      setState(() {
        _isPendingTransaction = isPending;
      });
    }
  }
  
  // 构建待确认交易的提示文本（异步版本，考虑节假日）
  Future<String> _getPendingTransactionHint() async {
    if (!_isTodayTransaction) return '';
    
    final confirmDate = await DataManager.calculateConfirmDateAsync(_tradeDate, _isAfter1500);
    
    // 显示具体日期：待确认-MM-DD日自动更新
    return '待确认-${confirmDate.month.toString().padLeft(2, '0')}-${confirmDate.day.toString().padLeft(2, '0')}日自动更新';
  }
  
  // 获取或创建待确认提示的 Future
  Future<String> _getOrCreatePendingHintFuture() {
    if (_pendingHintFuture == null) {
      _pendingHintFuture = _getPendingTransactionHint();
    }
    return _pendingHintFuture!;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _updatePendingStatus().then((_) {
      if (mounted) {
        _checkTimeAndSetNav();
        _fetchCurrentNavIfNeeded(); // 首次打开时自动获取净值
      }
    });
  }

  Future<void> _fetchCurrentNavIfNeeded() async {
    // 如果是待确认交易，不自动填充净值
    if (_isTodayTransaction) {
      setState(() => _isFetchingNav = false);
      return;
    }
    
    // 总是尝试获取最新净值，无论是否有缓存
    setState(() => _isFetchingNav = true);
    try {
      final fundService = FundService(_dataManager);
      final fundInfo = await fundService.fetchFundInfo(widget.fundCode);
      if (fundInfo['isValid'] == true && fundInfo['currentNav'] > 0) {
        if (mounted) {
          setState(() {
            _navController.text = fundInfo['currentNav'].toStringAsFixed(4);
          });
        }
      } else if (widget.currentNav != null && widget.currentNav! > 0) {
        // 如果API获取失败，但有传入的净值，使用传入的值
        if (mounted) {
          setState(() {
            _navController.text = widget.currentNav!.toStringAsFixed(4);
          });
        }
      }
    } catch (e) {
      // 如果API失败，但有传入的净值，使用传入的值
      if (widget.currentNav != null && widget.currentNav! > 0) {
        if (mounted) {
          setState(() {
            _navController.text = widget.currentNav!.toStringAsFixed(4);
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingNav = false);
      }
    }
  }

  void _checkTimeAndSetNav() {
    if (!mounted) return; // 检查是否已销毁
    
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    
    // 判断是否接近15:00
    if (hour == 14 && minute >= 50) {
      setState(() {
        _timeHint = '即将收盘，注意区分15:00前后净值';
      });
    } else if (hour == 15 && minute <= 10) {
      setState(() {
        _timeHint = '刚过15:00，今日净值尚未更新';
      });
    }

    // 只有在非待确认交易时才自动填充净值
    if (!_isTodayTransaction) {
      if (widget.currentNav != null && widget.currentNav! > 0) {
        _navController.text = widget.currentNav!.toStringAsFixed(4);
      }
    } else {
    }
  }

  @override
  void dispose() {
    _sharesController.dispose();
    _amountController.dispose();
    _navController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  // 计算预估份额（买入）或预估金额（卖出）
  void _calculateEstimated() {
    // 如果是待确认交易，不自动计算份额
    if (_isTodayTransaction) {
      return;
    }
    
    final amountText = _amountController.text.trim();
    final navText = _navController.text.trim();
    final feeText = _feeController.text.trim();
    final sharesText = _sharesController.text.trim();
    
    if (widget.type == TransactionType.buy) {
      // 买入：根据金额、净值、手续费率计算份额
      if (amountText.isEmpty || navText.isEmpty) {
        setState(() => _estimatedShares = null);
        return;
      }
      
      final amount = double.tryParse(amountText);
      final nav = double.tryParse(navText);
      final feeRate = feeText.isEmpty ? 0.0 : double.tryParse(feeText) ?? 0.0;
      
      if (amount == null || nav == null || nav <= 0) {
        setState(() => _estimatedShares = null);
        return;
      }
      
      // 预估份额 = 金额 / (1 + 费率%) / 净值
      final estimatedShares = amount / (1 + feeRate / 100) / nav;
      setState(() => _estimatedShares = estimatedShares > 0 ? estimatedShares : null);
      
      // 只在用户未手动编辑时才自动填充
      if (!_hasManuallyEditedShares && estimatedShares > 0) {
        _sharesController.text = estimatedShares.toStringAsFixed(2);
      }
    } else {
      // 卖出：根据份额、净值、费率计算金额
      if (sharesText.isEmpty || navText.isEmpty) {
        setState(() => _estimatedShares = null);
        return;
      }
      
      final shares = double.tryParse(sharesText);
      final nav = double.tryParse(navText);
      final feeRate = feeText.isEmpty ? 0.0 : double.tryParse(feeText) ?? 0.0;
      
      if (shares == null || nav == null || nav <= 0) {
        setState(() => _estimatedShares = null);
        return;
      }
      
      // 预估金额 = 份额 * 净值 * (1 - 费率%)
      final estimatedAmount = shares * nav * (1 - feeRate / 100);
      setState(() => _estimatedShares = estimatedAmount > 0 ? estimatedAmount : null);
      
      // 只在用户未手动编辑时才自动填充
      if (!_hasManuallyEditedAmount && estimatedAmount > 0) {
        _amountController.text = estimatedAmount.toStringAsFixed(2);
      }
    }
  }

  Future<void> _selectDate() async {
    await showCupertinoModalPopup(
      context: context,
      builder: (context) => _TransactionDatePickerModal(
        initialDate: _tradeDate,
        onConfirm: (date) {
          setState(() {
            _tradeDate = date;
            // 清空提示缓存，让它重新计算
            _pendingHintFuture = null;
          });
          // 更新待确认状态
          _updatePendingStatus().then((_) {
            // 日期改变后，重新获取净值
            _fetchNavByDate().then((_) {
              // 净值更新后，重新计算预估份额/金额
              if (!_isTodayTransaction && mounted) {
                _calculateEstimated();
              }
            });
          });
        },
      ),
    );
  }
  
  // 根据日期获取基金净值
  Future<void> _fetchNavByDate() async {
    try {
      final fundService = FundService(_dataManager);
      
      // 计算应该使用的净值日期（使用异步方法，考虑节假日）
      final targetNavDate = await DataManager.calculateNavDateForTradeAsync(_tradeDate, _isAfter1500);
      final isPending = DataManager.isTransactionPending(_tradeDate, _isAfter1500);
      
      // 如果是待确认交易(今天或未来),不自动填充净值
      if (isPending) {
        // 不清空用户手动输入的净值，只是不自动填充
        if (_navController.text.isEmpty) {
          setState(() {
            _navController.clear();
          });
        }
        return;
      }
      
      final trendData = await fundService.fetchNetWorthTrend(widget.fundCode);
      if (trendData.isEmpty) return;
      
      // 查找策略：精确匹配 > 下一交易日 > 最接近（3天内）
      NetWorthPoint? exactPoint;
      NetWorthPoint? nextPoint;
      NetWorthPoint? closestPoint;
      int minDiff = 999999;
      
      for (final point in trendData) {
        final diff = point.date.difference(targetNavDate).inDays;
        
        if (diff == 0) {
          exactPoint = point;
          break;
        }
        
        if (diff > 0 && (nextPoint == null || diff < nextPoint!.date.difference(targetNavDate).inDays)) {
          nextPoint = point;
        }
        
        final absDiff = diff.abs();
        if (absDiff < minDiff) {
          minDiff = absDiff;
          closestPoint = point;
        }
      }
      
      NetWorthPoint? selectedPoint;
      if (exactPoint != null) {
        selectedPoint = exactPoint;
      } else if (nextPoint != null && nextPoint!.date.difference(targetNavDate).inDays <= 3) {
        selectedPoint = nextPoint;
      } else if (closestPoint != null && minDiff <= 3) {
        selectedPoint = closestPoint;
      }
      
      if (selectedPoint != null && mounted) {
        setState(() {
          _navController.text = selectedPoint!.nav.toStringAsFixed(4);
        });
        
        // 净值变化后，自动重新计算预估份额/金额
        if (!_isTodayTransaction) {
          _calculateEstimated();
        }
      }
    } catch (e) {
    }
  }

  Future<void> _submit() async {
    if (_isLoading) return;

    final sharesText = _sharesController.text.trim();
    final amountText = _amountController.text.trim();
    final navText = _navController.text.trim();
    final feeText = _feeController.text.trim();

    if (sharesText.isEmpty && amountText.isEmpty) {
      context.showToast('请至少输入份额或金额');
      return;
    }

    double? shares;
    double? amount;
    double? nav;
    double feeRate = 0.0; // 费率百分比

    // 解析输入
    if (sharesText.isNotEmpty) {
      shares = double.tryParse(sharesText);
      if (shares == null || shares <= 0) {
        context.showToast('请输入有效的份额');
        return;
      }
    }

    if (amountText.isNotEmpty) {
      amount = double.tryParse(amountText);
      if (amount == null || amount <= 0) {
        context.showToast('请输入有效的金额');
        return;
      }
    }

    if (navText.isNotEmpty) {
      nav = double.tryParse(navText);
      if (nav == null || nav <= 0) {
        context.showToast('请输入有效的净值');
        return;
      }
    }

    if (feeText.isNotEmpty) {
      feeRate = double.tryParse(feeText) ?? 0.0;
      if (feeRate < 0) {
        context.showToast('费率不能为负数');
        return;
      }
    }

    // 如果只输入了金额且有净值，计算份额（买入时考虑手续费率）
    if (shares == null && amount != null && nav != null && nav > 0) {
      if (widget.type == TransactionType.buy) {
        // 份额 = 金额 / (1 + 费率%) / 净值
        shares = amount / (1 + feeRate / 100) / nav;
      } else {
        shares = amount / nav;
      }
    }

    // 如果只输入了份额且有净值，计算金额（买入时加上手续费率）
    if (amount == null && shares != null && nav != null && nav > 0) {
      if (widget.type == TransactionType.buy) {
        // 金额 = 份额 * 净值 * (1 + 费率%)
        amount = shares * nav * (1 + feeRate / 100);
      } else {
        // 金额 = 份额 * 净值 * (1 - 费率%)
        amount = shares * nav * (1 - feeRate / 100);
      }
    }

    // 最终验证
    // 对于待确认交易，根据买入/卖出有不同的处理
    if (widget.type == TransactionType.buy) {
      // 买入：待确认时可以只输入金额，份额等待确认时计算
      if (shares == null || shares <= 0) {
        if (_isTodayTransaction && amount != null && amount > 0) {
          shares = 0; // 待确认买入时份额可以为0
        } else {
          context.showToast('无法计算份额，请输入净值或份额');
          return;
        }
      }
    } else {
      // 卖出：待确认时必须输入份额，金额可以等待确认时计算
      if (shares == null || shares <= 0) {
        context.showToast('卖出时必须输入份额');
        return;
      }
    }

    // 金额验证
    if (amount == null || amount <= 0) {
      // 对于待确认的卖出交易，金额可以为0，等待确认时计算
      if (widget.type == TransactionType.sell && _isTodayTransaction) {
        amount = 0; // 待确认卖出时金额可以为0
      } else {
        context.showToast('无法计算金额，请输入净值或金额');
        return;
      }
    }

    // 卖出时检查份额
    if (widget.type == TransactionType.sell && shares > widget.currentShares) {
      context.showToast('卖出份额不能超过持有份额(${widget.currentShares.toStringAsFixed(2)})');
      return;
    }

    // 判断是否为待确认交易(今天或未来的交易)
    final isPending = DataManager.isTransactionPending(_tradeDate, _isAfter1500);
    double? confirmedNav;
    
    if (isPending) {
      confirmedNav = null;
    }

    setState(() => _isLoading = true);

    try {
      final transaction = TransactionRecord(
        clientId: widget.clientId,
        clientName: widget.clientName,
        fundCode: widget.fundCode,
        fundName: widget.fundName,
        type: widget.type,
        amount: amount,
        shares: shares,
        tradeDate: _tradeDate,
        nav: nav,
        fee: feeRate > 0 ? feeRate : null,
        remarks: '',
        isAfter1500: _isAfter1500,
        isPending: isPending,
        confirmedNav: confirmedNav,
      );

      await _dataManager.addTransaction(transaction);
      widget.onTransactionAdded();
      
      if (mounted) {
        Navigator.pop(context);
        if (isPending) {
          final confirmDays = _isAfter1500 ? 'T+2' : 'T+1';
          context.showToast('${widget.type == TransactionType.buy ? "加仓" : "减仓"}成功\n净值待${confirmDays}确认后生效');
        } else {
          context.showToast('${widget.type == TransactionType.buy ? "加仓" : "减仓"}成功');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showToast('操作失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white;
    final textColor = isDark ? CupertinoColors.white : CupertinoColors.label;
    final secondaryColor = isDark 
        ? CupertinoColors.white.withOpacity(0.6)
        : CupertinoColors.systemGrey;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        constraints: const BoxConstraints(maxWidth: 400),
        child: CupertinoPopupSurface(
          isSurfacePainted: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
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
                      widget.type == TransactionType.buy ? '加仓' : '减仓',
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

              // 内容区 - 支持滚动
              Container(
                padding: const EdgeInsets.all(16),
                color: bgColor,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    // 基金信息
                    Text(
                      widget.fundName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '代码: ${widget.fundCode}',
                      style: TextStyle(fontSize: 12, color: secondaryColor),
                    ),
                    
                    if (_timeHint != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: CupertinoColors.systemOrange.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.exclamationmark_triangle_fill,
                              size: 14,
                              color: CupertinoColors.systemOrange,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _timeHint!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: CupertinoColors.systemOrange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 持仓信息
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '持有份额',
                                style: TextStyle(fontSize: 12, color: secondaryColor),
                              ),
                              Text(
                                '${widget.currentShares.toStringAsFixed(2)}份',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '持仓市值',
                                style: TextStyle(fontSize: 12, color: secondaryColor),
                              ),
                              Text(
                                widget.currentNav != null && widget.currentNav! > 0
                                    ? '¥${(widget.currentShares * widget.currentNav!).toStringAsFixed(2)}'
                                    : '-',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '累计收益',
                                style: TextStyle(fontSize: 12, color: secondaryColor),
                              ),
                              Builder(
                                builder: (context) {
                                  final transactions = _dataManager.getTransactionHistory(
                                    widget.clientId,
                                    widget.fundCode,
                                  );
                                  if (transactions.isEmpty || widget.currentNav == null || widget.currentNav! <= 0) {
                                    return Text('-', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor));
                                  }
                                  
                                  // 计算累计投入成本
                                  double totalCost = 0;
                                  for (final tx in transactions) {
                                    if (tx.isBuy) {
                                      totalCost += tx.amount;
                                    } else if (tx.isSell) {
                                      totalCost -= tx.amount;
                                    }
                                  }
                                  
                                  final marketValue = widget.currentShares * widget.currentNav!;
                                  final profit = marketValue - totalCost;
                                  // 中国股市习惯：红涨绿跌
                                  final profitColor = profit >= 0 ? const Color(0xFFFF3B30) : const Color(0xFF34C759);
                                  
                                  return Text(
                                    '${profit >= 0 ? '+' : ''}¥${profit.toStringAsFixed(2)}',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: profitColor),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 日期选择
                    GestureDetector(
                      onTap: _selectDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '交易日期',
                              style: TextStyle(fontSize: 13, color: secondaryColor),
                            ),
                            const Spacer(),
                            Text(
                              '${_tradeDate.year}-${_tradeDate.month.toString().padLeft(2, '0')}-${_tradeDate.day.toString().padLeft(2, '0')}',
                              style: TextStyle(fontSize: 14, color: textColor),
                            ),
                            const SizedBox(width: 8),
                            Icon(CupertinoIcons.calendar, size: 16, color: secondaryColor),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // 交易时间选择（15:00前/后）
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isAfter1500 = false;
                                  // 清空提示缓存，让它重新计算
                                  _pendingHintFuture = null;
                                });
                                // 更新待确认状态
                                _updatePendingStatus().then((_) {
                                  _fetchNavByDate(); // 重新获取净值
                                  _calculateEstimated(); // 重新计算份额/金额
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: !_isAfter1500 ? const Color(0xFF007AFF) : CupertinoColors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '15:00前',
                                  style: TextStyle(
                                    color: !_isAfter1500 ? CupertinoColors.white : secondaryColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isAfter1500 = true;
                                  // 清空提示缓存，让它重新计算
                                  _pendingHintFuture = null;
                                });
                                // 更新待确认状态
                                _updatePendingStatus().then((_) {
                                  _fetchNavByDate(); // 重新获取净值
                                  _calculateEstimated(); // 重新计算份额/金额
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _isAfter1500 ? const Color(0xFF007AFF) : CupertinoColors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '15:00后',
                                  style: TextStyle(
                                    color: _isAfter1500 ? CupertinoColors.white : secondaryColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 输入框 - 买入模式
                    if (widget.type == TransactionType.buy) ...[
                      _buildInputField(
                        label: '交易金额',
                        controller: _amountController,
                        hint: '请输入买入金额',
                        suffix: '元',
                        onChanged: (value) => _calculateEstimated(),
                      ),
                      const SizedBox(height: 12),
                      
                      // 成交净值输入框
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '成交净值',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? CupertinoColors.white.withOpacity(0.8) : textColor,
                                ),
                              ),
                              if (_isTodayTransaction)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemOrange.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '待确认',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: CupertinoColors.systemOrange,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          // 显示预计使用的净值日期
                          if (_isTodayTransaction) ...[
                            const SizedBox(height: 4),
                            FutureBuilder<String>(
                              future: _getOrCreatePendingHintFuture(),
                              builder: (context, snapshot) {
                                final hint = snapshot.data ?? '加载中...';
                                return Text(
                                  hint,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: secondaryColor,
                                  ),
                                );
                              },
                            ),
                          ],
                          const SizedBox(height: 6),
                          _buildInputField(
                            label: '',
                            controller: _navController,
                            hint: _isTodayTransaction 
                                ? ''
                                : (_isFetchingNav ? '加载中...' : '用于计算份额'),
                            suffix: '',
                            onChanged: (value) => _calculateEstimated(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      _buildInputField(
                        label: '交易费率',
                        controller: _feeController,
                        hint: '选填，默认0',
                        suffix: '%',
                        onChanged: (value) => _calculateEstimated(),
                      ),
                      
                      if (_estimatedShares != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.info_circle_fill,
                                size: 14,
                                color: CupertinoColors.systemBlue,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '预估份额: ${_estimatedShares!.toStringAsFixed(2)}份',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: CupertinoColors.systemBlue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 12),
                      _buildInputField(
                        label: '确认份额',
                        controller: _sharesController,
                        hint: '可手动修改',
                        suffix: '份',
                        onChanged: (value) {
                          setState(() => _hasManuallyEditedShares = true);
                        },
                      ),
                    ] else ...[
                      // 输入框 - 卖出模式
                      _buildInputField(
                        label: '交易份额',
                        controller: _sharesController,
                        hint: '请输入卖出份额',
                        suffix: '份',
                        onChanged: (value) => _calculateEstimated(),
                      ),
                      const SizedBox(height: 12),
                      
                      // 成交净值输入框（卖出模式）
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '成交净值',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? CupertinoColors.white.withOpacity(0.8) : textColor,
                                ),
                              ),
                              if (_isTodayTransaction)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemOrange.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '待确认',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: CupertinoColors.systemOrange,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          // 显示预计使用的净值日期
                          if (_isTodayTransaction) ...[
                            const SizedBox(height: 4),
                            FutureBuilder<String>(
                              future: _getOrCreatePendingHintFuture(),
                              builder: (context, snapshot) {
                                final hint = snapshot.data ?? '加载中...';
                                return Text(
                                  hint,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: secondaryColor,
                                  ),
                                );
                              },
                            ),
                          ],
                          const SizedBox(height: 6),
                          _buildInputField(
                            label: '',
                            controller: _navController,
                            hint: _isTodayTransaction 
                                ? ''
                                : (_isFetchingNav ? '加载中...' : '用于计算金额'),
                            suffix: '',
                            onChanged: (value) => _calculateEstimated(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      _buildInputField(
                        label: '交易费率',
                        controller: _feeController,
                        hint: '选填，默认0',
                        suffix: '%',
                        onChanged: (value) => _calculateEstimated(),
                      ),
                      
                      if (_estimatedShares != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemOrange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.info_circle_fill,
                                size: 14,
                                color: CupertinoColors.systemOrange,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '预估金额: ¥${_estimatedShares!.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: CupertinoColors.systemOrange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 12),
                      _buildInputField(
                        label: '确认金额',
                        controller: _amountController,
                        hint: '可手动修改',
                        suffix: '元',
                        onChanged: (value) {
                          setState(() => _hasManuallyEditedAmount = true);
                        },
                      ),
                    ],

                    const SizedBox(height: 20),

                    // 提交按钮
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: CupertinoButton(
                        color: widget.type == TransactionType.buy 
                            ? const Color(0xFFFF3B30) // 红色 - 加仓
                            : const Color(0xFF34C759), // 绿色 - 减仓
                        borderRadius: BorderRadius.circular(12),
                        onPressed: _isLoading ? null : _submit,
                        padding: EdgeInsets.zero,
                        child: _isLoading
                            ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                            : Text(
                                widget.type == TransactionType.buy ? '确认加仓' : '确认减仓',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: CupertinoColors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ), // SingleChildScrollView Column
              ), // SingleChildScrollView
            ), // Container (内容区)
          ], // Column children
        ), // Column
      ), // CupertinoPopupSurface
    ), // Container (外层)
    ); // Center
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required String suffix,
    ValueChanged<String>? onChanged,
  }) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final textColor = isDark ? CupertinoColors.white : CupertinoColors.label;
    final placeholderColor = isDark 
        ? CupertinoColors.white.withOpacity(0.5)
        : CupertinoColors.systemGrey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark ? CupertinoColors.white.withOpacity(0.8) : CupertinoColors.label,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
            borderRadius: BorderRadius.circular(10),
          ),
          child: CupertinoTextField(
            controller: controller,
            placeholder: hint,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            style: TextStyle(color: textColor, fontSize: 15),
            placeholderStyle: TextStyle(color: placeholderColor),
            onChanged: onChanged,
            suffix: suffix.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(suffix, style: TextStyle(color: placeholderColor)),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

// 自定义日期选择器（使用数字月份）
class _TransactionDatePickerModal extends StatefulWidget {
  final DateTime initialDate;
  final ValueChanged<DateTime> onConfirm;

  const _TransactionDatePickerModal({
    required this.initialDate,
    required this.onConfirm,
  });

  @override
  State<_TransactionDatePickerModal> createState() => _TransactionDatePickerModalState();
}

class _TransactionDatePickerModalState extends State<_TransactionDatePickerModal> {
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
                      label: '确定',
                      onPressed: () {
                        widget.onConfirm(_tempDate);
                        Navigator.pop(context);
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

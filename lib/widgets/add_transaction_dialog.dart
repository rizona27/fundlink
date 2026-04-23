import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import '../models/transaction_record.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _checkTimeAndSetNav();
    _fetchCurrentNavIfNeeded(); // 首次打开时自动获取净值
  }

  Future<void> _fetchCurrentNavIfNeeded() async {
    // 如果当前净值为0或null，尝试从API获取
    if (widget.currentNav == null || widget.currentNav! <= 0) {
      setState(() => _isFetchingNav = true);
      try {
        final fundService = FundService(_dataManager);
        final fundInfo = await fundService.fetchFundInfo(widget.fundCode);
        if (fundInfo['isValid'] == true && fundInfo['currentNav'] > 0) {
          setState(() {
            _navController.text = fundInfo['currentNav'].toStringAsFixed(4);
          });
        }
      } catch (e) {
        debugPrint('获取基金净值失败: $e');
      } finally {
        if (mounted) {
          setState(() => _isFetchingNav = false);
        }
      }
    }
  }

  void _checkTimeAndSetNav() {
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

    // 如果有当前净值，自动填充
    if (widget.currentNav != null && widget.currentNav! > 0) {
      _navController.text = widget.currentNav!.toStringAsFixed(4);
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
        onConfirm: (date) => setState(() => _tradeDate = date),
      ),
    );
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
    if (shares == null || shares <= 0) {
      context.showToast('无法计算份额，请输入净值或份额');
      return;
    }

    if (amount == null || amount <= 0) {
      context.showToast('无法计算金额，请输入净值或金额');
      return;
    }

    // 卖出时检查份额
    if (widget.type == TransactionType.sell && shares > widget.currentShares) {
      context.showToast('卖出份额不能超过持有份额(${widget.currentShares.toStringAsFixed(2)})');
      return;
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
        remarks: '',
      );

      await _dataManager.addTransaction(transaction);
      widget.onTransactionAdded();
      
      if (mounted) {
        Navigator.pop(context);
        context.showToast('${widget.type == TransactionType.buy ? "加仓" : "减仓"}成功');
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
                                  final profitColor = profit >= 0 ? const Color(0xFF34C759) : const Color(0xFFFF3B30);
                                  
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
                    _buildInputField(
                      label: '成交净值',
                      controller: _navController,
                      hint: _isFetchingNav ? '加载中...' : '用于计算份额',
                      suffix: '',
                      onChanged: (value) => _calculateEstimated(),
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
                      
                      _buildInputField(
                        label: '成交净值',
                        controller: _navController,
                        hint: _isFetchingNav ? '加载中...' : '用于计算金额',
                        suffix: '',
                        onChanged: (value) => _calculateEstimated(),
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
                            ? const Color(0xFF34C759)
                            : const Color(0xFFFF3B30),
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
            ), // Container
          ], // Column children
        ), // Column
      ), // CupertinoPopupSurface
      ), // Container
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

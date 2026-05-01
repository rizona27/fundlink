import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/transaction_record.dart';
import '../models/log_entry.dart';
import '../models/net_worth_point.dart';
import '../widgets/toast.dart';
import '../widgets/glass_button.dart';

class AmountInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    String filtered = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');
    final parts = filtered.split('.');
    if (parts.length > 2) {
      filtered = parts[0] + '.' + parts[1];
    }
    if (filtered.startsWith('.')) {
      filtered = '0$filtered';
    }
    final newParts = filtered.split('.');
    String integerPart = newParts[0];
    String decimalPart = newParts.length > 1 ? newParts[1] : '';
    if (integerPart.length > 9) {
      integerPart = integerPart.substring(0, 9);
    }
    if (decimalPart.length > 2) {
      decimalPart = decimalPart.substring(0, 2);
    }
    String formatted;
    if (decimalPart.isEmpty) {
      formatted = integerPart;
    } else {
      formatted = '$integerPart.$decimalPart';
    }
    if (filtered.endsWith('.') && decimalPart.isEmpty && integerPart.isNotEmpty) {
      formatted = '$integerPart.';
    }
    if (formatted != newValue.text) {
      final cursorPos = formatted.length;
      return newValue.copyWith(
        text: formatted,
        selection: TextSelection.collapsed(offset: cursorPos),
      );
    }
    return newValue;
  }
}

class ClientNameInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final allowedPattern = RegExp(r'[a-zA-Z0-9\u4e00-\u9fa5 ]');
    String filtered = newValue.text
        .split('')
        .where((c) => allowedPattern.hasMatch(c))
        .join('');
    filtered = filtered.replaceAll(RegExp(r' +'), ' ');
    final spaceCount = filtered.split('').where((c) => c == ' ').length;
    if (spaceCount > 1) {
      final firstSpaceIndex = filtered.indexOf(' ');
      if (firstSpaceIndex != -1) {
        filtered = filtered.substring(0, firstSpaceIndex + 1) +
            filtered.substring(firstSpaceIndex + 1).replaceAll(' ', '');
      }
    }
    if (filtered != newValue.text) {
      final cursorPos = filtered.length;
      return newValue.copyWith(
        text: filtered,
        selection: TextSelection.collapsed(offset: cursorPos),
      );
    }
    return newValue;
  }
}

class ClientIdInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final filtered = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limited = filtered.length > 12 ? filtered.substring(0, 12) : filtered;
    if (limited != newValue.text) {
      return newValue.copyWith(
        text: limited,
        selection: TextSelection.collapsed(offset: limited.length),
      );
    }
    return newValue;
  }
}

class AddHoldingView extends StatefulWidget {
  const AddHoldingView({super.key});

  @override
  State<AddHoldingView> createState() => _AddHoldingViewState();
}

class _AddHoldingViewState extends State<AddHoldingView> {
  late DataManager _dataManager;
  late FundService _fundService;

  final TextEditingController _clientNameController = TextEditingController();
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _fundCodeController = TextEditingController();
  final TextEditingController _purchaseAmountController = TextEditingController();
  final TextEditingController _purchaseSharesController = TextEditingController();
  final TextEditingController _feeRateController = TextEditingController();
  final TextEditingController _confirmNavController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  bool _clientNameError = false;
  bool _fundCodeError = false;
  bool _amountError = false;
  bool _sharesError = false;

  String _fundName = '';
  double? _currentNav;
  DateTime? _navDate;
  double? _confirmNav;
  List<NetWorthPoint>? _cachedTrendData;

  DateTime _purchaseDate = DateTime.now();
  bool _isAfter1500 = false;
  bool _isSaving = false;
  bool _isPendingTransaction = false; // 是否为待确认交易
  
  // 缓存待确认提示的 Future，避免 FutureBuilder 重复执行
  Future<String>? _pendingHintFuture;
  
  // 判断是否为待确认交易(基于净值日期)
  // 注意：这是一个同步 getter，使用缓存的状态变量
  bool get _isTodayTransaction {
    return _isPendingTransaction;
  }
  
  // 更新待确认交易状态（异步）
  Future<void> _updatePendingStatus() async {
    final isPending = await DataManager.isTransactionPendingAsync(_purchaseDate, _isAfter1500);
    if (mounted) {
      setState(() {
        _isPendingTransaction = isPending;
      });
    }
  }
  
  // 计算待确认交易的提示文本
  // 构建待确认交易的提示文本（异步版本，考虑节假日）
  Future<String> _getPendingTransactionHint() async {
    if (!_isTodayTransaction) return '可修改，默认当前净值';
    
    final confirmDate = await DataManager.calculateConfirmDateAsync(_purchaseDate, _isAfter1500);
    
    // 显示具体日期：待确认-MM-DD日自动更新
    return '待确认-${confirmDate.month.toString().padLeft(2, '0')}-${confirmDate.day.toString().padLeft(2, '0')}日自动更新';
  }
  
  // 获取或创建待确认提示的 Future
  Future<String> _getOrCreatePendingHintFuture() {
    // 如果 Future 不存在或者参数变化了，重新创建
    if (_pendingHintFuture == null) {
      _pendingHintFuture = _getPendingTransactionHint();
    }
    return _pendingHintFuture!;
  }
  
  // 构建历史交易的净值日期提示
  Future<String> _buildNavDateHintAsync() async {
    // 计算预期的净值日期和确认日期（使用新的异步方法，考虑节假日）
    final expectedNavDate = await DataManager.calculateNavDateForTradeAsync(_purchaseDate, _isAfter1500);
    final confirmDate = DataManager.calculateConfirmDate(_purchaseDate, _isAfter1500);
    
    // 检查净值日期是否是今天或未来（净值还未公布）
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final navDateNotAvailable = !expectedNavDate.isBefore(today);
    
    if (navDateNotAvailable) {
      // 待确认交易：显示预计使用的净值日期和确认日期
      return '预计使用 ${expectedNavDate.month}月${expectedNavDate.day}日 净值，${confirmDate.month}月${confirmDate.day}日 确认';
    }
    
    // 如果已经有净值数据，显示实际净值日期
    if (_navDate != null) {
      return '使用 ${_navDate!.month}月${_navDate!.day}日 净值';
    }
    
    // 默认显示
    return '预计使用 ${expectedNavDate.month}月${expectedNavDate.day}日 净值';
  }
  
  // 保留旧方法用于向后兼容（同步版本）
  String _buildNavDateHint() {
    // 计算预期的净值日期和确认日期
    final expectedNavDate = DataManager.calculateNavDateForTrade(_purchaseDate, _isAfter1500);
    final confirmDate = DataManager.calculateConfirmDate(_purchaseDate, _isAfter1500);
    
    // 检查净值日期是否是今天或未来（净值还未公布）
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final navDateNotAvailable = !expectedNavDate.isBefore(today);
    
    if (navDateNotAvailable) {
      // 待确认交易：显示预计使用的净值日期和确认日期
      return '预计使用 ${expectedNavDate.month}月${expectedNavDate.day}日 净值，${confirmDate.month}月${confirmDate.day}日 确认';
    }
    
    // 如果已经有净值数据，显示实际净值日期
    if (_navDate != null) {
      return '使用 ${_navDate!.month}月${_navDate!.day}日 净值';
    }
    
    // 默认显示
    return '预计使用 ${expectedNavDate.month}月${expectedNavDate.day}日 净值';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _fundService = FundService(_dataManager);
    // 初始化待确认状态
    _updatePendingStatus();
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    _clientIdController.dispose();
    _fundCodeController.dispose();
    _purchaseAmountController.dispose();
    _purchaseSharesController.dispose();
    _feeRateController.dispose();
    _confirmNavController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    // 如果是待确认交易，只需要客户姓名、基金代码和交易金额
    if (_isTodayTransaction) {
      return !_clientNameError &&
          !_fundCodeError &&
          !_amountError &&
          _clientNameController.text.trim().isNotEmpty &&
          _fundCodeController.text.trim().isNotEmpty &&
          _purchaseAmountController.text.trim().isNotEmpty;
    }
    // 如果不是待确认交易，所有字段都是必填的
    return !_clientNameError &&
        !_fundCodeError &&
        !_amountError &&
        !_sharesError &&
        _clientNameController.text.trim().isNotEmpty &&
        _fundCodeController.text.trim().isNotEmpty &&
        _purchaseAmountController.text.trim().isNotEmpty &&
        _purchaseSharesController.text.trim().isNotEmpty;
  }

  void _validateClientName(String value) {
    final trimmed = value.trim();
    setState(() {
      _clientNameError = trimmed.isEmpty || trimmed.length > 20;
    });
  }

  void _validateFundCode(String value) {
    final trimmed = value.trim();
    setState(() {
      _fundCodeError = trimmed.isEmpty || !RegExp(r'^\d{6}$').hasMatch(trimmed);
    });
  }

  void _validateAmount(String value) {
    final trimmed = value.trim();
    bool error = false;
    if (trimmed.isNotEmpty) {
      final amount = double.tryParse(trimmed);
      error = amount == null || amount <= 0;
    } else {
      error = true;
    }
    setState(() => _amountError = error);
  }

  void _validateShares(String value) {
    // 如果是待确认交易，份额不是必填项
    if (_isTodayTransaction) {
      setState(() => _sharesError = false);
      return;
    }
    
    final trimmed = value.trim();
    bool error = false;
    if (trimmed.isNotEmpty) {
      final shares = double.tryParse(trimmed);
      error = shares == null || shares <= 0;
    } else {
      error = true;
    }
    setState(() => _sharesError = error);
  }

  void _onFundCodeChanged(String value) {
    final filtered = value.replaceAll(RegExp(r'[^0-9]'), '');
    final newValue = filtered.length > 6 ? filtered.substring(0, 6) : filtered;
    if (newValue != _fundCodeController.text) {
      final cursor = _fundCodeController.selection.baseOffset;
      _fundCodeController.text = newValue;
      _fundCodeController.selection = TextSelection.collapsed(
        offset: cursor.clamp(0, newValue.length),
      );
    }
    _validateFundCode(newValue);
    
    // 当输入完整的6位基金代码时，查询基金信息
    if (newValue.length == 6) {
      // 先更新待确认状态，再获取基金信息
      _updatePendingStatus().then((_) {
        _fetchFundInfo(newValue);
      });
    } else {
      setState(() {
        _fundName = '';
        _currentNav = null;
        _confirmNav = null;
      });
    }
  }
  
  Future<void> _fetchFundInfo(String fundCode) async {
    try {
      final fundInfo = await _fundService.fetchFundInfo(fundCode);
      if (mounted) {
        setState(() {
          _fundName = fundInfo['fundName'] as String? ?? '';
          _currentNav = fundInfo['currentNav'] as double?;
          _navDate = fundInfo['navDate'] as DateTime?;
          
          // 只有在非待确认交易时才自动填充净值
          if (!_isTodayTransaction) {
            _confirmNav = _currentNav;
            
            // 更新确认净值输入框
            if (_confirmNav != null && _confirmNav! > 0) {
              _confirmNavController.text = _confirmNav!.toStringAsFixed(4);
            }
          } else {
            // 待确认交易时，不自动填充净值
            _confirmNav = null;
            _confirmNavController.clear();
          }
        });
        
        // 后台缓存净值趋势数据，用于后续根据日期查找
        // 缓存完成后，检查并更新为最新的净值
        await _cacheTrendDataAndUpdateLatest(fundCode);
      }
    } catch (e) {
      // 获取基金信息失败，静默处理
    }
  }
  
  // 缓存净值趋势数据
  Future<void> _cacheTrendData(String fundCode) async {
    try {
      final trendData = await _fundService.fetchNetWorthTrend(fundCode);
      if (mounted) {
        setState(() {
          _cachedTrendData = trendData;
        });
      }
    } catch (e) {
      // 缓存净值趋势数据失败，静默处理
    }
  }
  
  // 缓存净值趋势数据并更新最新净值
  Future<void> _cacheTrendDataAndUpdateLatest(String fundCode) async {
    try {
      final trendData = await _fundService.fetchNetWorthTrend(fundCode);
      if (mounted && trendData.isNotEmpty) {
        // 获取最新的净值点（列表最后一个）
        final latestPoint = trendData.last;
        
        setState(() {
          _cachedTrendData = trendData;
          
          // 如果 API 返回的净值日期早于缓存中的最新净值日期，则更新
          if (_navDate == null || latestPoint.date.isAfter(_navDate!)) {
            _currentNav = latestPoint.nav;
            _navDate = latestPoint.date;
            
            // 如果是非待确认交易，也更新确认净值
            if (!_isTodayTransaction) {
              _confirmNav = latestPoint.nav;
              if (_confirmNav != null && _confirmNav! > 0) {
                _confirmNavController.text = _confirmNav!.toStringAsFixed(4);
              }
            }
          }
        });
      }
    } catch (e) {
      // 缓存净值趋势数据失败，静默处理
    }
  }
  
  // 根据金额、费率、确认净值计算份额
  void _calculateShares() {
    // 如果是待确认交易，不自动计算份额
    if (_isTodayTransaction) {
      return;
    }
    
    final amountText = _purchaseAmountController.text.trim();
    final feeRateText = _feeRateController.text.trim();
    
    if (amountText.isEmpty || _confirmNav == null || _confirmNav! <= 0) {
      return;
    }
    
    final amount = double.tryParse(amountText);
    // 交易费率默认为0，输入的是百分比值（如1.5表示1.5%）
    final feeRate = feeRateText.isEmpty ? 0.0 : (double.tryParse(feeRateText) ?? 0.0);
    
    if (amount == null || amount <= 0) {
      return;
    }
    
    // 内扣法计算：
    // 净申购金额 = 申购金额 / (1 + 费率)
    // 确认份额 = 净申购金额 / 确认净值
    // 例如：500000 / (1 + 0.015) / 2.2366 = 220249.86
    final shares = amount / (1 + feeRate / 100) / _confirmNav!;
    
    if (shares > 0) {
      // 始终更新份额，确保与金额同步
      _purchaseSharesController.text = shares.toStringAsFixed(2);
    }
  }
  
  // 根据份额、金额、费率倒推净值
  void _calculateNavFromShares() {
    final amountText = _purchaseAmountController.text.trim();
    final sharesText = _purchaseSharesController.text.trim();
    final feeRateText = _feeRateController.text.trim();
    
    if (amountText.isEmpty || sharesText.isEmpty) {
      return;
    }
    
    final amount = double.tryParse(amountText);
    final shares = double.tryParse(sharesText);
    final feeRate = feeRateText.isEmpty ? 0.0 : (double.tryParse(feeRateText) ?? 0.0);
    
    if (amount == null || amount <= 0 || shares == null || shares <= 0) {
      return;
    }
    
    // 净值 = 金额 / (1 + 费率%) / 份额
    final nav = amount / (1 + feeRate / 100) / shares;
    
    if (nav > 0) {
      setState(() {
        _confirmNav = nav;
        // 更新确认净值输入框的文本
        _confirmNavController.text = nav.toStringAsFixed(4);
      });
    }
  }

  Future<void> _saveHolding() async {
    if (_isSaving) return;
    if (!_isFormValid) return;

    // 验证交易日期是否为交易日
    final isTradingDay = await DataManager.isTradingDay(_purchaseDate);
    if (!isTradingDay) {
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('非交易日提示'),
          content: Text(
            '您选择的日期（${_purchaseDate.year}年${_purchaseDate.month}月${_purchaseDate.day}日）不是 A 股交易日。\n'
            '\n'
            '基金交易只能在交易日进行，是否继续？\n'
            '\n'
            '• 继续：系统会自动顺延至下一个交易日处理\n'
            '• 取消：重新选择交易日期',
          ),
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
      
      if (confirmed != true) {
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });

    final amountText = _purchaseAmountController.text.trim();
    final sharesText = _purchaseSharesController.text.trim();
    
    // 金额必须有值
    if (amountText.isEmpty) {
      context.showToast('请输入买入金额');
      setState(() => _isSaving = false);
      return;
    }
    
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      context.showToast('请输入有效的金额');
      setState(() => _isSaving = false);
      return;
    }
    
    // 份额可以为空（待确认交易）
    double shares = 0;
    if (sharesText.isNotEmpty) {
      shares = double.tryParse(sharesText) ?? 0;
    }
    final fundCode = _fundCodeController.text.trim().toUpperCase();
    final clientId = _clientIdController.text.trim();
    final clientName = _clientNameController.text.trim();
    // 获取费率（百分比值，如1.5表示1.5%）
    final feeRateText = _feeRateController.text.trim();
    final feeRate = feeRateText.isEmpty ? 0.0 : (double.tryParse(feeRateText) ?? 0.0);

    try {
      final clientId = _clientIdController.text.trim();
      final clientName = _clientNameController.text.trim();
      
      // 检查是否已存在该客户+基金的持仓
      // 规则：1. 如果客户号相同，则一定是同一客户
      //       2. 如果客户号为空但用户名相同，需要进一步判断
      List<FundHolding> existingHoldings = [];
      bool isSameClientId = false;
      bool isSameClientName = false;
      bool shouldMerge = false;
      
      if (clientId.isNotEmpty) {
        // 有客户号，优先按客户号匹配
        existingHoldings = _dataManager.holdings
            .where((h) => h.clientId == clientId && h.fundCode == fundCode)
            .toList();
        
        if (existingHoldings.isNotEmpty) {
          isSameClientId = true;
        }
      }
      
      // 如果没找到相同客户号的，再按用户名查找
      if (existingHoldings.isEmpty) {
        existingHoldings = _dataManager.holdings
            .where((h) => h.clientName == clientName && h.fundCode == fundCode)
            .toList();
        
        if (existingHoldings.isNotEmpty) {
          // 只有当当前输入的客户号为空，且找到的持仓也没有客户号时，才认为是同名客户
          // 如果找到的持仓有客户号，而当前输入没有，说明是不同的客户
          final existingHolding = existingHoldings.first;
          if (clientId.isEmpty && existingHolding.clientId.isEmpty) {
            // 两者都没有客户号，可能是同一客户
            isSameClientName = true;
          } else if (clientId.isEmpty && existingHolding.clientId.isNotEmpty) {
            // 当前无客户号，但已有持仓有客户号，说明是不同客户，直接创建新持仓
            // 不设置 isSameClientName，继续执行
          } else if (clientId.isNotEmpty && existingHolding.clientId.isEmpty) {
            // 当前有客户号，但已有持仓没有，说明是不同客户，直接创建新持仓
            // 不设置 isSameClientName，继续执行
          }
        }
      }

      if (existingHoldings.isNotEmpty) {
        final existingHolding = existingHoldings.first;
        
        if (isSameClientId) {
          // 客户号相同，直接提示合并
          final confirmed = await showCupertinoDialog<bool>(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text('检测到重复持仓'),
              content: Text(
                '客户 "$clientName" ($clientId) 已持有基金 "$fundCode"\n'
                '当前持有：${existingHolding.totalShares.toStringAsFixed(2)}份\n'
                '\n是否将本次交易合并到该持仓？',
              ),
              actions: [
                CupertinoDialogAction(
                  child: const Text('取消'),
                  onPressed: () => Navigator.pop(context, false),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  child: const Text('合并'),
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          );

          if (confirmed != true) {
            setState(() => _isSaving = false);
            return;
          }
          shouldMerge = true;
        } else if (isSameClientName) {
          // 用户名相同但客户号不同，提示可能存在同名客户
          final confirmed = await showCupertinoDialog<bool>(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text('检测到同名客户'),
              content: Text(
                '发现同名客户 "$clientName" 已持有基金 "$fundCode"\n'
                '原客户号：${existingHolding.clientId.isEmpty ? "无" : existingHolding.clientId}\n'
                '当前客户号：${clientId.isEmpty ? "无" : clientId}\n'
                '原持有份额：${existingHolding.totalShares.toStringAsFixed(2)}份\n'
                '\n是否为同一客户？\n'
                '• 是，合并：将本次交易合并到现有持仓（使用原客户号）\n'
                '• 否，创建新持仓：为当前客户号创建独立的持仓记录',
              ),
              actions: [
                CupertinoDialogAction(
                  child: const Text('取消'),
                  onPressed: () => Navigator.pop(context, null),
                ),
                CupertinoDialogAction(
                  child: const Text('否，创建新持仓'),
                  onPressed: () => Navigator.pop(context, false),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  child: const Text('是，合并'),
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          );

          // 用户点击取消
          if (confirmed == null) {
            setState(() => _isSaving = false);
            return;
          }

          if (confirmed != true) {
            // 用户选择创建新持仓，继续执行
          } else {
            // 用户选择合并
            shouldMerge = true;
          }
        }
      }

      // 获取基金信息
      final fundInfo = await _fundService.fetchFundInfo(fundCode);
      final fundName = fundInfo['fundName'] as String? ?? '待加载';
      final currentNav = fundInfo['currentNav'] as double? ?? 0;
      final navDate = fundInfo['navDate'] as DateTime? ?? DateTime.now();
      final isValid = fundInfo['isValid'] as bool? ?? false;
      
      // 判断是否为待确认交易(基于净值日期)
      final isPending = DataManager.isTransactionPending(_purchaseDate, _isAfter1500);
      double? confirmedNav;
      double transactionShares = shares;
      
      if (isPending) {
        confirmedNav = null;
        // 待确认交易：如果用户没有输入份额，则设为0，等待后续确认时计算
        if (sharesText.isEmpty) {
          transactionShares = 0;
        }
      }

      // 创建交易记录（买入）- 使用确认净值
      final transaction = TransactionRecord(
        clientId: clientId,
        clientName: clientName,
        fundCode: fundCode,
        fundName: fundName,
        type: TransactionType.buy,
        amount: amount,
        shares: transactionShares,
        tradeDate: _purchaseDate,
        nav: _confirmNav != null && _confirmNav! > 0 ? _confirmNav : (currentNav > 0 ? currentNav : null),
        fee: feeRate,
        remarks: _remarksController.text.trim(),
        isAfter1500: _isAfter1500,
        isPending: isPending,
        confirmedNav: confirmedNav,
      );

      // 添加交易记录（会自动重建持仓）
      await _dataManager.addTransaction(transaction);
      
      if (mounted) {
        if (isPending) {
          final hint = await _getPendingTransactionHint();
          context.showToast(shouldMerge ? '已合并到现有持仓\n$hint' : '添加成功\n$hint');
        } else {
          context.showToast(shouldMerge ? '已合并到现有持仓' : '添加成功');
        }
        // 延迟一下再关闭页面，确保Toast显示和DataManager通知完成
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          Navigator.of(context).pop();
          return; // pop后直接返回，不执行finally中的setState
        }
      }
    } catch (e) {
      await _dataManager.addLog('添加交易失败: $e', type: LogType.error);
      context.showToast('添加失败: $e');
    } finally {
      // 只有在页面仍然挂载的情况下才更新状态
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showDatePickerModal() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => _DatePickerModal(
        initialDate: _purchaseDate,
        onConfirm: (newDate) async {
          setState(() {
            _purchaseDate = newDate;
            // 清空提示缓存，让它重新计算
            _pendingHintFuture = null;
          });
          // 更新待确认状态
          await _updatePendingStatus();
          
          // 选择日期后，尝试获取该日期的净值
          if (_fundCodeController.text.trim().length == 6) {
            await _fetchNavByDate(_fundCodeController.text.trim(), newDate);
            // 净值更新后，重新计算份额
            if (!_isTodayTransaction) {
              _calculateShares();
            }
          }
        },
      ),
    );
  }
  
  // 根据日期获取基金净值
  Future<void> _fetchNavByDate(String fundCode, DateTime targetDate) async {
    try {
      List<NetWorthPoint> trendData;
      
      // 计算应该使用的净值日期（使用异步方法，考虑节假日）
      final targetNavDate = await DataManager.calculateNavDateForTradeAsync(targetDate, _isAfter1500);
      
      // 检查净值日期是否是未来日期或今天（没有净值数据）
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // 净值日期是今天或未来，说明净值还未公布
      final navDateNotAvailable = !targetNavDate.isBefore(today);
      
      // 关键修复：只检查净值日期是否可用，不检查交易是否待确认
      // 即使是待确认交易，如果净值日期是过去（已有净值），也应该填充
      if (navDateNotAvailable) {
        setState(() {
          _confirmNavController.clear();
          _confirmNav = null;
        });
        return;
      }
      
      // 优先使用缓存的数据
      if (_cachedTrendData != null && _cachedTrendData!.isNotEmpty) {
        trendData = _cachedTrendData!;
      } else {
        // 如果没有缓存，则重新获取
        trendData = await _fundService.fetchNetWorthTrend(fundCode);
        if (mounted) {
          setState(() {
            _cachedTrendData = trendData;
          });
        }
      }
      
      if (trendData.isEmpty) return;
      
      // 查找策略：
      // 1. 首先查找等于目标净值日期的净值
      // 2. 如果找不到，查找晚于目标净值日期的第一个净值
      // 3. 如果都找不到，查找最接近的净值（前后3天内）
      
      NetWorthPoint? exactPoint;
      NetWorthPoint? nextPoint;
      NetWorthPoint? closestPoint;
      int minDiff = 999999;
      
      for (final point in trendData) {
        final diff = point.date.difference(targetNavDate).inDays;
        
        // 精确匹配
        if (diff == 0) {
          exactPoint = point;
          break;
        }
        
        // 查找下一个交易日（晚于目标净值日期的第一个）
        if (diff > 0 && (nextPoint == null || diff < nextPoint!.date.difference(targetNavDate).inDays)) {
          nextPoint = point;
        }
        
        // 查找最接近的（用于兜底）
        final absDiff = diff.abs();
        if (absDiff < minDiff) {
          minDiff = absDiff;
          closestPoint = point;
        }
      }
      
      // 优先级：精确匹配 > 下一个交易日 > 最接近（3天内）
      NetWorthPoint? selectedPoint;
      String matchType = '';
      
      if (exactPoint != null) {
        selectedPoint = exactPoint;
        matchType = '精确匹配';
      } else if (nextPoint != null && nextPoint!.date.difference(targetNavDate).inDays <= 3) {
        selectedPoint = nextPoint;
        matchType = '下一交易日';
      } else if (closestPoint != null && minDiff <= 3) {
        selectedPoint = closestPoint;
        matchType = '最接近';
      }
      
      if (selectedPoint != null) {
        setState(() {
          _confirmNav = selectedPoint!.nav;
          _navDate = selectedPoint!.date;  // 更新净值日期，用于显示
          _confirmNavController.text = selectedPoint!.nav.toStringAsFixed(4);
          // 更新基金代码下方显示的净值信息，使其与选择的交易日期一致
          _currentNav = selectedPoint!.nav;
        });
        final timeLabel = _isAfter1500 ? '15:00后' : '15:00前';
        
        // 净值变化后，自动重新计算份额
        if (!_isTodayTransaction) {
          _calculateShares();
        }
      } else {
      }
    } catch (e) {
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final frostedBgColor = isDarkMode
        ? const Color(0xFF2C2C2E).withValues(alpha: 0.85)
        : CupertinoColors.white.withValues(alpha: 0.85);
    final inputBgColor = isDarkMode ? CupertinoColors.systemGrey6 : CupertinoColors.white;
    final textColor = isDarkMode ? CupertinoColors.white : CupertinoColors.label;
    final placeholderColor = isDarkMode
        ? CupertinoColors.white.withValues(alpha: 0.5)
        : CupertinoColors.systemGrey;

    return CupertinoPageScaffold(
      child: SafeArea(
        child: GestureDetector(
          onTap: () {
            // 点击外部时收起键盘
            FocusScope.of(context).unfocus();
          },
          behavior: HitTestBehavior.translucent,
          child: _isSaving
              ? const Center(child: CupertinoActivityIndicator(radius: 20))
              : SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFrostedSection(
                title: '',  // 去掉"必填信息"标题
                isDarkMode: isDarkMode,
                frostedBgColor: frostedBgColor,
                children: [
                  _buildRowField(
                    label: '客户姓名',
                    required: true,
                    child: _buildTextField(
                      controller: _clientNameController,
                      hint: '请输入客户姓名',
                      error: _clientNameError,
                      onChanged: _validateClientName,
                      inputBgColor: inputBgColor,
                      textColor: textColor,
                      placeholderColor: placeholderColor,
                      inputFormatters: [ClientNameInputFormatter()],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRowField(
                    label: '基金代码',
                    required: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTextField(
                          controller: _fundCodeController,
                          hint: '请输入6位基金代码',
                          error: _fundCodeError,
                          onChanged: _onFundCodeChanged,
                          inputBgColor: inputBgColor,
                          textColor: textColor,
                          placeholderColor: placeholderColor,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                        ),
                        if (_fundName.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDarkMode 
                                  ? const Color(0xFF007AFF).withValues(alpha: 0.1)
                                  : const Color(0xFF007AFF).withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _fundName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: isDarkMode 
                                          ? CupertinoColors.systemBlue
                                          : const Color(0xFF007AFF),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_currentNav != null && _currentNav! > 0 && _navDate != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    '${_currentNav!.toStringAsFixed(4)}(${_navDate!.month.toString().padLeft(2, '0')}-${_navDate!.day.toString().padLeft(2, '0')})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDarkMode 
                                          ? CupertinoColors.white.withOpacity(0.7)
                                          : const Color(0xFF8E8E93),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRowField(
                    label: '购买日期',
                    required: true,
                    child: _buildDatePickerField(
                      purchaseDate: _purchaseDate,
                      onTap: _showDatePickerModal,
                      isDarkMode: isDarkMode,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRowField(
                    label: '交易时间',
                    required: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTimeSegmentField(
                          isAfter1500: _isAfter1500,
                          onChanged: (value) async {
                            setState(() {
                              _isAfter1500 = value;
                              // 清空提示缓存，让它重新计算
                              _pendingHintFuture = null;
                            });
                            // 更新待确认状态
                            await _updatePendingStatus();
                            // 重新获取净值
                            if (_fundCodeController.text.trim().length == 6) {
                              await _fetchNavByDate(_fundCodeController.text.trim(), _purchaseDate);
                              // 净值更新后，重新计算份额
                              _calculateShares();
                            }
                          },
                          isDarkMode: isDarkMode,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRowField(
                    label: '交易金额',
                    required: true,
                    child: _buildAmountField(
                      controller: _purchaseAmountController,
                      hint: '请输入买入金额',
                      error: _amountError,
                      onChanged: (value) {
                        _validateAmount(value);
                        _calculateShares();
                      },
                      inputBgColor: inputBgColor,
                      textColor: textColor,
                      placeholderColor: placeholderColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRowField(
                    label: '交易费率',
                    required: false,
                    child: _buildAmountField(
                      controller: _feeRateController,
                      hint: '',
                      error: false,
                      onChanged: (value) => _calculateShares(),
                      inputBgColor: inputBgColor,
                      textColor: textColor,
                      placeholderColor: placeholderColor,
                      suffix: '%',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRowField(
                    label: '确认净值',
                    required: !_isTodayTransaction,
                    child: FutureBuilder<String>(
                      future: _getOrCreatePendingHintFuture(),
                      builder: (context, snapshot) {
                        // 如果是待确认交易，始终显示待确认净值提示
                        final hint = _isTodayTransaction 
                            ? (snapshot.data ?? '加载中...')
                            : '可修改，默认当前净值';
                        return _buildAmountField(
                          controller: _confirmNavController,
                          hint: hint,
                          error: false,
                          onChanged: (value) {
                            final nav = double.tryParse(value.trim());
                            if (nav != null && nav > 0) {
                              setState(() => _confirmNav = nav);
                              // 只有非待确认交易才自动计算份额
                              if (!_isTodayTransaction) {
                                _calculateShares();
                              }
                            }
                          },
                          inputBgColor: inputBgColor,
                          textColor: textColor,
                          placeholderColor: placeholderColor,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRowField(
                    label: '交易份额',
                    required: !_isTodayTransaction,
                    child: _buildAmountField(
                      controller: _purchaseSharesController,
                      hint: _isTodayTransaction ? '选填，待确认后可自动计算' : '请输入买入份额',
                      error: _sharesError,
                      onChanged: (value) {
                        _validateShares(value);
                        // 只有非待确认交易才根据份额反推净值
                        if (!_isTodayTransaction) {
                          _calculateNavFromShares();
                        }
                      },
                      inputBgColor: inputBgColor,
                      textColor: textColor,
                      placeholderColor: placeholderColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildFrostedSection(
                title: '',  // 去掉"选填信息"标题
                isDarkMode: isDarkMode,
                frostedBgColor: frostedBgColor,
                children: [
                  _buildRowField(
                    label: '客户号',
                    required: false,
                    child: _buildTextField(
                      controller: _clientIdController,
                      hint: '选填，最多12位数字',
                      onChanged: (_) {},
                      inputBgColor: inputBgColor,
                      textColor: textColor,
                      placeholderColor: placeholderColor,
                      inputFormatters: [ClientIdInputFormatter()],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRowField(
                    label: '备注',
                    required: false,
                    child: _buildTextField(
                      controller: _remarksController,
                      hint: '选填，最多30个字符',
                      onChanged: (v) {
                        if (v.length > 30) {
                          final cursor = _remarksController.selection.baseOffset;
                          _remarksController.text = v.substring(0, 30);
                          _remarksController.selection = TextSelection.collapsed(
                            offset: cursor.clamp(0, 30),
                          );
                        }
                      },
                      inputBgColor: inputBgColor,
                      textColor: textColor,
                      placeholderColor: placeholderColor,
                      maxLength: 30,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: '取消',
                      onPressed: () => Navigator.of(context).pop(),
                      isPrimary: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassButton(
                      label: '保存',
                      onPressed: _isFormValid ? _saveHolding : null,
                      isPrimary: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildFrostedSection({
    required String title,
    required bool isDarkMode,
    required Color frostedBgColor,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 只有当title不为空时才显示标题
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
              ),
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              decoration: BoxDecoration(
                color: frostedBgColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: children),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRowField({
    required String label,
    required bool required,
    required Widget child,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          flex: 0,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 70,
              maxWidth: 85,
            ),
            child: Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (required)
                  const Text(' *', style: TextStyle(color: CupertinoColors.systemRed)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required Function(String) onChanged,
    required Color inputBgColor,
    required Color textColor,
    required Color placeholderColor,
    bool error = false,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    TextInputType? keyboardType,
  }) {
    Color bottomBorderColor;
    if (error) {
      bottomBorderColor = CupertinoColors.systemRed;
    } else if (controller.text.trim().isNotEmpty && !error) {
      bottomBorderColor = CupertinoColors.activeBlue;
    } else {
      bottomBorderColor = CupertinoColors.systemGrey.withValues(alpha: 0.3);
    }

    return Container(
      decoration: BoxDecoration(
        color: inputBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          bottom: BorderSide(
            color: bottomBorderColor,
            width: 1.5,
          ),
        ),
      ),
      child: CupertinoTextField(
        controller: controller,
        placeholder: hint,
        onChanged: onChanged,
        keyboardType: keyboardType,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        style: TextStyle(color: textColor),
        placeholderStyle: TextStyle(color: placeholderColor),
        inputFormatters: inputFormatters,
        maxLength: maxLength,
      ),
    );
  }

  Widget _buildAmountField({
    required TextEditingController controller,
    required String hint,
    required Function(String) onChanged,
    required Color inputBgColor,
    required Color textColor,
    required Color placeholderColor,
    bool error = false,
    String? suffix,
  }) {
    Color bottomBorderColor;
    if (error) {
      bottomBorderColor = CupertinoColors.systemRed;
    } else if (controller.text.trim().isNotEmpty && !error) {
      bottomBorderColor = CupertinoColors.activeBlue;
    } else {
      bottomBorderColor = CupertinoColors.systemGrey.withValues(alpha: 0.3);
    }

    return Container(
      decoration: BoxDecoration(
        color: inputBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          bottom: BorderSide(
            color: bottomBorderColor,
            width: 1.5,
          ),
        ),
      ),
      child: CupertinoTextField(
        controller: controller,
        placeholder: hint,
        onChanged: onChanged,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        style: TextStyle(color: textColor),
        placeholderStyle: TextStyle(color: placeholderColor),
        inputFormatters: [AmountInputFormatter()],
        suffix: suffix != null
            ? Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(suffix, style: TextStyle(color: placeholderColor)),
              )
            : null,
      ),
    );
  }

  Widget _buildDatePickerField({
    required DateTime purchaseDate,
    required VoidCallback onTap,
    required bool isDarkMode,
  }) {
    final bgColor = isDarkMode ? const Color(0xFF3A3A3C) : CupertinoColors.white;
    final textColor = isDarkMode ? CupertinoColors.white : CupertinoColors.label;
    final iconColor = isDarkMode
        ? CupertinoColors.systemGrey
        : CupertinoColors.inactiveGray;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: const Border(
            bottom: BorderSide(color: CupertinoColors.systemGrey, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Text(
              '${purchaseDate.year}-${purchaseDate.month.toString().padLeft(2, '0')}-${purchaseDate.day.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 16, color: textColor),
            ),
            const Spacer(),
            Icon(
              CupertinoIcons.calendar,
              size: 16,
              color: iconColor,
            ),
          ],
        ),
      ),
    );
  }
  
  // 交易时间选择器（15:00前/后）
  Widget _buildTimeSegmentField({
    required bool isAfter1500,
    required ValueChanged<bool> onChanged,
    required bool isDarkMode,
  }) {
    final bgColor = isDarkMode ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6;
    final selectedColor = const Color(0xFF007AFF);
    final unselectedTextColor = isDarkMode 
        ? CupertinoColors.white.withValues(alpha: 0.6)
        : CupertinoColors.systemGrey;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(false),
              child: Container(
                decoration: BoxDecoration(
                  color: !isAfter1500 ? selectedColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  '15:00前',
                  style: TextStyle(
                    color: !isAfter1500 ? CupertinoColors.white : unselectedTextColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(true),
              child: Container(
                decoration: BoxDecoration(
                  color: isAfter1500 ? selectedColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  '15:00后',
                  style: TextStyle(
                    color: isAfter1500 ? CupertinoColors.white : unselectedTextColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // 基金代码输入框（左右分栏显示）
  Widget _buildFundCodeField({
    required TextEditingController controller,
    required String fundName,
    required bool error,
    required Function(String) onChanged,
    required Color inputBgColor,
    required Color textColor,
    required Color placeholderColor,
    required bool isDarkMode,
  }) {
    Color bottomBorderColor;
    if (error) {
      bottomBorderColor = CupertinoColors.systemRed;
    } else if (controller.text.trim().isNotEmpty && !error) {
      bottomBorderColor = CupertinoColors.activeBlue;
    } else {
      bottomBorderColor = CupertinoColors.systemGrey.withValues(alpha: 0.3);
    }

    // 构建右侧显示的文本：基金名称(截断) + 净值(日期)
    String rightText = '';
    if (fundName.isNotEmpty) {
      // 基金名称最多6个汉字，后面加省略号
      String displayName = fundName;
      if (displayName.length > 6) {
        displayName = displayName.substring(0, 6) + '...';
      }
      
      // 如果有净值，添加净值信息
      if (_currentNav != null && _currentNav! > 0 && _navDate != null) {
        final navDateStr = '${_navDate!.month.toString().padLeft(2, '0')}-${_navDate!.day.toString().padLeft(2, '0')}';
        rightText = '$displayName ${_currentNav!.toStringAsFixed(4)}($navDateStr)';
      } else {
        rightText = displayName;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: inputBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          bottom: BorderSide(
            color: bottomBorderColor,
            width: 1.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 左侧：基金代码输入框
          Expanded(
            flex: 2,
            child: CupertinoTextField(
              controller: controller,
              placeholder: '请输入6位基金代码',
              onChanged: onChanged,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
              placeholderStyle: TextStyle(color: placeholderColor),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              keyboardType: TextInputType.number,
              decoration: null,
            ),
          ),
          if (rightText.isNotEmpty)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  rightText,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDarkMode 
                        ? CupertinoColors.systemBlue
                        : const Color(0xFF007AFF),
                    overflow: TextOverflow.ellipsis,
                  ),
                  maxLines: 1,
                ),
              ),
            ),
        ],
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
          ? CupertinoColors.white.withValues(alpha: 0.05)
          : CupertinoColors.black.withValues(alpha: 0.03),
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
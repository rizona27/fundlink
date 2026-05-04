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
import '../utils/input_formatters.dart';

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
  bool _isPendingTransaction = false; 
  
  Future<String>? _pendingHintFuture;
  
  bool get _isTodayTransaction {
    return _isPendingTransaction;
  }
  
  Future<void> _updatePendingStatus() async {
    final isPending = await DataManager.isTransactionPendingAsync(_purchaseDate, _isAfter1500);
    if (mounted) {
      setState(() {
        _isPendingTransaction = isPending;
      });
    }
  }
  
  Future<String> _getPendingTransactionHint() async {
    if (!_isTodayTransaction) return '可修改，默认当前净值';
    
    final confirmDate = await DataManager.calculateConfirmDateAsync(_purchaseDate, _isAfter1500);
    
    return '待确认-${confirmDate.month.toString().padLeft(2, '0')}-${confirmDate.day.toString().padLeft(2, '0')}日自动更新';
  }
  
  Future<String> _getOrCreatePendingHintFuture() {
    if (_pendingHintFuture == null) {
      _pendingHintFuture = _getPendingTransactionHint();
    }
    return _pendingHintFuture!;
  }
  
  Future<String> _buildNavDateHintAsync() async {
    final expectedNavDate = await DataManager.calculateNavDateForTradeAsync(_purchaseDate, _isAfter1500);
    final confirmDate = DataManager.calculateConfirmDate(_purchaseDate, _isAfter1500);
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final navDateNotAvailable = !expectedNavDate.isBefore(today);
    
    if (navDateNotAvailable) {
      return '预计使用 ${expectedNavDate.month}月${expectedNavDate.day}日 净值，${confirmDate.month}月${confirmDate.day}日 确认';
    }
    
    if (_navDate != null) {
      return '使用 ${_navDate!.month}月${_navDate!.day}日 净值';
    }
    
    return '预计使用 ${expectedNavDate.month}月${expectedNavDate.day}日 净值';
  }
  
  String _buildNavDateHint() {
    final expectedNavDate = DataManager.calculateNavDateForTrade(_purchaseDate, _isAfter1500);
    final confirmDate = DataManager.calculateConfirmDate(_purchaseDate, _isAfter1500);
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final navDateNotAvailable = !expectedNavDate.isBefore(today);
    
    if (navDateNotAvailable) {
      return '预计使用 ${expectedNavDate.month}月${expectedNavDate.day}日 净值，${confirmDate.month}月${confirmDate.day}日 确认';
    }
    
    if (_navDate != null) {
      return '使用 ${_navDate!.month}月${_navDate!.day}日 净值';
    }
    
    return '预计使用 ${expectedNavDate.month}月${expectedNavDate.day}日 净值';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _fundService = FundService(_dataManager);
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
    if (_isTodayTransaction) {
      return !_clientNameError &&
          !_fundCodeError &&
          !_amountError &&
          _clientNameController.text.trim().isNotEmpty &&
          _fundCodeController.text.trim().isNotEmpty &&
          _purchaseAmountController.text.trim().isNotEmpty;
    }
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
    
    if (newValue.length == 6) {
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
          
          if (!_isTodayTransaction) {
            _confirmNav = _currentNav;
            
            if (_confirmNav != null && _confirmNav! > 0) {
              _confirmNavController.text = _confirmNav!.toStringAsFixed(4);
            }
          } else {
            _confirmNav = null;
            _confirmNavController.clear();
          }
        });
        
        await _cacheTrendDataAndUpdateLatest(fundCode);
      }
    } catch (e) {
      debugPrint('加载基金信息失败 ($fundCode): $e');
      // 静默失败，不影响用户输入
    }
  }
  
  Future<void> _cacheTrendData(String fundCode) async {
    try {
      final trendData = await _fundService.fetchNetWorthTrend(fundCode);
      if (mounted) {
        setState(() {
          _cachedTrendData = trendData;
        });
      }
    } catch (e) {
      debugPrint('缓存基金趋势数据失败 ($fundCode): $e');
      // 静默失败，不影响主要功能
    }
  }
  
  Future<void> _cacheTrendDataAndUpdateLatest(String fundCode) async {
    try {
      final trendData = await _fundService.fetchNetWorthTrend(fundCode);
      if (mounted && trendData.isNotEmpty) {
        final latestPoint = trendData.last;
        
        if (mounted) {  // ✅ 添加 mounted 检查
          setState(() {
            _cachedTrendData = trendData;
            
            if (_navDate == null || latestPoint.date.isAfter(_navDate!)) {
              _currentNav = latestPoint.nav;
              _navDate = latestPoint.date;
              
              if (!_isTodayTransaction) {
                _confirmNav = latestPoint.nav;
                if (_confirmNav != null && _confirmNav! > 0) {
                  _confirmNavController.text = _confirmNav!.toStringAsFixed(4);
                }
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint('更新最新净值失败 ($fundCode): $e');
      // 静默失败，使用已有数据
    }
  }
  
  void _calculateShares() {
    if (_isTodayTransaction) {
      return;
    }
    
    final amountText = _purchaseAmountController.text.trim();
    final feeRateText = _feeRateController.text.trim();
    
    if (amountText.isEmpty || _confirmNav == null || _confirmNav! <= 0) {
      return;
    }
    
    final amount = double.tryParse(amountText);
    final feeRate = feeRateText.isEmpty ? 0.0 : (double.tryParse(feeRateText) ?? 0.0);
    
    if (amount == null || amount <= 0) {
      return;
    }
    
    final shares = amount / (1 + feeRate / 100) / _confirmNav!;
    
    if (shares > 0) {
      _purchaseSharesController.text = shares.toStringAsFixed(2);
    }
  }
  
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
    
    final nav = amount / (1 + feeRate / 100) / shares;
    
    if (nav > 0) {
      setState(() {
        _confirmNav = nav;
        _confirmNavController.text = nav.toStringAsFixed(4);
      });
    }
  }

  Future<void> _saveHolding() async {
    if (_isSaving) return;
    if (!_isFormValid) return;

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
    
    double shares = 0;
    if (sharesText.isNotEmpty) {
      shares = double.tryParse(sharesText) ?? 0;
    }
    final fundCode = _fundCodeController.text.trim().toUpperCase();
    final clientId = _clientIdController.text.trim();
    final clientName = _clientNameController.text.trim();
    final feeRateText = _feeRateController.text.trim();
    final feeRate = feeRateText.isEmpty ? 0.0 : (double.tryParse(feeRateText) ?? 0.0);

    try {
      final clientId = _clientIdController.text.trim();
      final clientName = _clientNameController.text.trim();
      
      List<FundHolding> existingHoldings = [];
      bool isSameClientId = false;
      bool isSameClientName = false;
      bool shouldMerge = false;
      
      if (clientId.isNotEmpty) {
        existingHoldings = _dataManager.holdings
            .where((h) => h.clientId == clientId && h.fundCode == fundCode)
            .toList();
        
        if (existingHoldings.isNotEmpty) {
          isSameClientId = true;
        }
      }
      
      if (existingHoldings.isEmpty) {
        existingHoldings = _dataManager.holdings
            .where((h) => h.clientName == clientName && h.fundCode == fundCode)
            .toList();
        
        if (existingHoldings.isNotEmpty) {
          final existingHolding = existingHoldings.first;
          if (clientId.isEmpty && existingHolding.clientId.isEmpty) {
            isSameClientName = true;
          } else if (clientId.isEmpty && existingHolding.clientId.isNotEmpty) {
          } else if (clientId.isNotEmpty && existingHolding.clientId.isEmpty) {
          }
        }
      }

      if (existingHoldings.isNotEmpty) {
        final existingHolding = existingHoldings.first;
        
        if (isSameClientId) {
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

          if (confirmed == null) {
            setState(() => _isSaving = false);
            return;
          }

          if (confirmed != true) {
          } else {
            shouldMerge = true;
          }
        }
      }

      final fundInfo = await _fundService.fetchFundInfo(fundCode);
      final fundName = fundInfo['fundName'] as String? ?? '待加载';
      final currentNav = fundInfo['currentNav'] as double? ?? 0;
      final navDate = fundInfo['navDate'] as DateTime? ?? DateTime.now();
      final isValid = fundInfo['isValid'] as bool? ?? false;
      
      final isPending = DataManager.isTransactionPending(_purchaseDate, _isAfter1500);
      double? confirmedNav;
      double transactionShares = shares;
      
      if (isPending) {
        confirmedNav = null;
        if (sharesText.isEmpty) {
          transactionShares = 0;
        }
      }

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

      await _dataManager.addTransaction(transaction);
      
      if (mounted) {
        if (isPending) {
          final hint = await _getPendingTransactionHint();
          context.showToast(shouldMerge ? '已合并到现有持仓\n$hint' : '添加成功\n$hint');
        } else {
          context.showToast(shouldMerge ? '已合并到现有持仓' : '添加成功');
        }
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          Navigator.of(context).pop();
          return; 
        }
      }
    } catch (e) {
      await _dataManager.addLog('添加交易失败: $e', type: LogType.error);
      context.showToast('添加失败: $e');
    } finally {
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
          if (mounted) {  // ✅ 添加 mounted 检查
            setState(() {
              _purchaseDate = newDate;
              _pendingHintFuture = null;
            });
          }
          await _updatePendingStatus();
          
          if (_fundCodeController.text.trim().length == 6) {
            await _fetchNavByDate(_fundCodeController.text.trim(), newDate);
            if (!_isTodayTransaction) {
              _calculateShares();
            }
          }
        },
      ),
    );
  }
  
  Future<void> _fetchNavByDate(String fundCode, DateTime targetDate) async {
    try {
      List<NetWorthPoint> trendData;
      
      final targetNavDate = await DataManager.calculateNavDateForTradeAsync(targetDate, _isAfter1500);
      
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final navDateNotAvailable = !targetNavDate.isBefore(today);
      
      if (navDateNotAvailable) {
        if (mounted) {  // ✅ 添加 mounted 检查
          setState(() {
            _confirmNavController.clear();
            _confirmNav = null;
          });
        }
        return;
      }
      
      if (_cachedTrendData != null && _cachedTrendData!.isNotEmpty) {
        trendData = _cachedTrendData!;
      } else {
        trendData = await _fundService.fetchNetWorthTrend(fundCode);
        if (mounted) {
          setState(() {
            _cachedTrendData = trendData;
          });
        }
      }
      
      if (trendData.isEmpty) return;
      
      
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
          _navDate = selectedPoint!.date;  
          _confirmNavController.text = selectedPoint!.nav.toStringAsFixed(4);
          _currentNav = selectedPoint!.nav;
        });
        final timeLabel = _isAfter1500 ? '15:00后' : '15:00前';
        
        if (!_isTodayTransaction) {
          _calculateShares();
        }
      } else {
        debugPrint('未找到 $fundCode 在 ${targetDate.year}-${targetDate.month}-${targetDate.day} 的净值数据');
      }
    } catch (e) {
      debugPrint('根据日期获取净值失败 ($fundCode): $e');
      // 静默失败，用户可以手动输入
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
                title: '',  
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
                            if (mounted) {  // ✅ 添加 mounted 检查
                              setState(() {
                                _isAfter1500 = value;
                                _pendingHintFuture = null;
                              });
                            }
                            await _updatePendingStatus();
                            if (_fundCodeController.text.trim().length == 6) {
                              await _fetchNavByDate(_fundCodeController.text.trim(), _purchaseDate);
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
                title: '',  
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

    String rightText = '';
    if (fundName.isNotEmpty) {
      String displayName = fundName;
      if (displayName.length > 6) {
        displayName = displayName.substring(0, 6) + '...';
      }
      
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
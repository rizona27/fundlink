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
  final TextEditingController _feeRateController = TextEditingController(); // 交易费率
  final TextEditingController _confirmNavController = TextEditingController(); // 确认净值
  final TextEditingController _remarksController = TextEditingController();

  bool _clientNameError = false;
  bool _fundCodeError = false;
  bool _amountError = false;
  bool _sharesError = false;

  String _fundName = ''; // 基金名称
  double? _currentNav; // 当前净值（从API获取）
  DateTime? _navDate; // 净值日期
  double? _confirmNav; // 确认净值（用户可修改）
  List<NetWorthPoint>? _cachedTrendData; // 缓存的净值趋势数据

  DateTime _purchaseDate = DateTime.now();
  bool _isAfter1500 = false; // 是否15:00后交易
  bool _isSaving = false;
  
  // 判断是否为待确认交易(今天或未来)
  bool get _isTodayTransaction {
    return DataManager.isTransactionPending(_purchaseDate);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _fundService = FundService(_dataManager);
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
      _fetchFundInfo(newValue);
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
          _confirmNav = _currentNav; // 默认使用API返回的净值作为确认净值
          
          // 更新确认净值输入框
          if (_confirmNav != null && _confirmNav! > 0) {
            _confirmNavController.text = _confirmNav!.toStringAsFixed(4);
          }
          
          // 调试信息
          print('基金代码: $fundCode');
          print('基金名称: $_fundName');
          print('当前净值: $_currentNav');
          print('确认净值: $_confirmNav');
          print('净值日期: $_navDate');
        });
        
        // 后台缓存净值趋势数据，用于后续根据日期查找
        _cacheTrendData(fundCode);
      }
    } catch (e) {
      print('获取基金信息失败: $e');
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
        print('已缓存 ${trendData.length} 条净值数据');
      }
    } catch (e) {
      print('缓存净值趋势数据失败: $e');
    }
  }
  
  // 根据金额、费率、确认净值计算份额
  void _calculateShares() {
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

    setState(() {
      _isSaving = true;
    });

    final amount = double.parse(_purchaseAmountController.text.trim());
    final shares = double.parse(_purchaseSharesController.text.trim());
    final fundCode = _fundCodeController.text.trim().toUpperCase();
    final clientId = _clientIdController.text.trim();
    final clientName = _clientNameController.text.trim();

    try {
      final clientId = _clientIdController.text.trim();
      final clientName = _clientNameController.text.trim();
      
      // 检查是否已存在该客户+基金的持仓
      // 规则：1. 如果客户号相同，则一定是同一客户
      //       2. 如果客户号为空但用户名相同，可能是同名客户，需要二次确认
      List<FundHolding> existingHoldings = [];
      bool isSameClientId = false;
      bool isSameClientName = false;
      bool shouldMerge = false; // 是否应该合并
      
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
          isSameClientName = true;
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
          shouldMerge = true; // 标记为需要合并
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
            shouldMerge = true; // 标记为需要合并
          }
        }
      }

      // 获取基金信息
      final fundInfo = await _fundService.fetchFundInfo(fundCode);
      final fundName = fundInfo['fundName'] as String? ?? '待加载';
      final currentNav = fundInfo['currentNav'] as double? ?? 0;
      final navDate = fundInfo['navDate'] as DateTime? ?? DateTime.now();
      final isValid = fundInfo['isValid'] as bool? ?? false;
      
      // 判断是否为待确认交易(今天或未来的交易)
      final isPending = DataManager.isTransactionPending(_purchaseDate);
      double? confirmedNav;
      
      if (isPending) {
        confirmedNav = null;
        print('创建待确认交易(新增持仓): 今天或未来日期');
      }

      // 创建交易记录（买入）- 使用确认净值
      final transaction = TransactionRecord(
        clientId: clientId,
        clientName: clientName,
        fundCode: fundCode,
        fundName: fundName,
        type: TransactionType.buy,
        amount: amount,
        shares: shares,
        tradeDate: _purchaseDate,
        nav: _confirmNav != null && _confirmNav! > 0 ? _confirmNav : (currentNav > 0 ? currentNav : null),
        fee: null,
        remarks: _remarksController.text.trim(),
        isAfter1500: _isAfter1500,
        isPending: isPending,
        confirmedNav: confirmedNav,
      );

      // 添加交易记录（会自动重建持仓）
      await _dataManager.addTransaction(transaction);
      
      if (mounted) {
        if (isPending) {
          context.showToast(shouldMerge ? '已合并到现有持仓\n净值待T+1确认后生效' : '添加成功\n净值待T+1确认后生效');
        } else {
          context.showToast(shouldMerge ? '已合并到现有持仓' : '添加成功');
        }
        Navigator.of(context).pop();
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
          setState(() {
            _purchaseDate = newDate;
          });
          
          // 选择日期后，尝试获取该日期的净值
          if (_fundCodeController.text.trim().length == 6) {
            await _fetchNavByDate(_fundCodeController.text.trim(), newDate);
          }
        },
      ),
    );
  }
  
  // 根据日期获取基金净值
  Future<void> _fetchNavByDate(String fundCode, DateTime targetDate) async {
    try {
      List<NetWorthPoint> trendData;
      
      // 计算应该使用的净值日期
      final targetNavDate = DataManager.calculateNavDateForTrade(targetDate, _isAfter1500);
      final isPending = DataManager.isTransactionPending(targetDate);
      
      // 如果是待确认交易(今天或未来),不自动填充净值
      if (isPending) {
        print('待确认交易(今天或未来日期),不自动填充净值');
        setState(() {
          _confirmNavController.clear();
          _confirmNav = null;
        });
        return;
      }
      
      // 优先使用缓存的数据
      if (_cachedTrendData != null && _cachedTrendData!.isNotEmpty) {
        trendData = _cachedTrendData!;
        print('使用缓存的净值数据');
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
      
      NetWorthPoint? exactPoint; // 精确匹配
      NetWorthPoint? nextPoint;  // 下一个交易日
      NetWorthPoint? closestPoint; // 最接近
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
          _navDate = selectedPoint!.date;
          _confirmNavController.text = selectedPoint!.nav.toStringAsFixed(4);
        });
        final timeLabel = _isAfter1500 ? '15:00后' : '15:00前';
        print('$timeLabel交易 - $matchType - 选择日期: $targetDate, 使用净值日期: ${selectedPoint!.date}, 净值: ${selectedPoint!.nav}');
      } else {
        print('未找到 $targetNavDate 附近的净值数据（最近的是 ${closestPoint?.date}，相差${minDiff}天）');
      }
    } catch (e) {
      print('获取历史净值失败: $e');
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
        child: _isSaving
            ? const Center(child: CupertinoActivityIndicator(radius: 20))
            : SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFrostedSection(
                title: '必填信息',
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
                    child: _buildTimeSegmentField(
                      isAfter1500: _isAfter1500,
                      onChanged: (value) async {
                        setState(() {
                          _isAfter1500 = value;
                        });
                        // 重新获取净值
                        if (_fundCodeController.text.trim().length == 6) {
                          await _fetchNavByDate(_fundCodeController.text.trim(), _purchaseDate);
                          // 净值更新后，重新计算份额
                          print('切换15:00前后，重新计算份额。当前确认净值: $_confirmNav, 金额: ${_purchaseAmountController.text}, 费率: ${_feeRateController.text}');
                          _calculateShares();
                          print('计算后份额: ${_purchaseSharesController.text}');
                        }
                      },
                      isDarkMode: isDarkMode,
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
                        _calculateShares(); // 自动计算份额
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
                      hint: '', // 无提示文字
                      error: false,
                      onChanged: (value) => _calculateShares(), // 自动计算份额
                      inputBgColor: inputBgColor,
                      textColor: textColor,
                      placeholderColor: placeholderColor,
                      suffix: '%',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRowField(
                    label: '确认净值',
                    required: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isTodayTransaction)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemOrange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: CupertinoColors.systemOrange.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.clock,
                                  size: 12,
                                  color: CupertinoColors.systemOrange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '待确认 - T+1日自动更新',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: CupertinoColors.systemOrange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        _buildAmountField(
                          controller: _confirmNavController,
                          hint: _isTodayTransaction ? 'T+1日自动更新' : '可修改，默认当前净值',
                          error: false,
                          onChanged: (value) {
                            final nav = double.tryParse(value.trim());
                            if (nav != null && nav > 0) {
                              setState(() => _confirmNav = nav);
                              _calculateShares(); // 重新计算份额
                            }
                          },
                          inputBgColor: inputBgColor,
                          textColor: textColor,
                          placeholderColor: placeholderColor,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRowField(
                    label: '交易份额',
                    required: true,
                    child: _buildAmountField(
                      controller: _purchaseSharesController,
                      hint: '请输入买入份额',
                      error: _sharesError,
                      onChanged: (value) {
                        _validateShares(value);
                        _calculateNavFromShares(); // 根据份额反推净值
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
                title: '选填信息',
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
              decoration: null, // 移除默认装饰
            ),
          ),
          // 右侧：基金名称和净值显示
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
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_constants.dart';
import '../models/client_mapping.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../models/net_worth_point.dart';
import '../models/transaction_record.dart';
import '../services/client_mapping_service.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../services/transaction_utils.dart';
import '../utils/input_formatters.dart';
import '../widgets/glass_button.dart';
import '../widgets/toast.dart';

class AddHoldingView extends StatefulWidget {
  const AddHoldingView({super.key});

  @override
  State<AddHoldingView> createState() => _AddHoldingViewState();
}

class _AddHoldingViewState extends State<AddHoldingView> {
  late DataManager _dataManager;
  late FundService _fundService;
  final ClientMappingService _mappingService = ClientMappingService();

  final TextEditingController _clientNameController = TextEditingController();
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _fundCodeController = TextEditingController();
  final TextEditingController _purchaseAmountController = TextEditingController();
  final TextEditingController _purchaseSharesController = TextEditingController();
  final TextEditingController _feeRateController = TextEditingController();
  final TextEditingController _confirmNavController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  Timer? _mappingCheckTimer;

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
    final isPending =
        await TransactionUtils.isTransactionPendingAsync(_purchaseDate, _isAfter1500);
    if (mounted) {
      setState(() {
        _isPendingTransaction = isPending;
      });
    }
  }

  Future<String> _getPendingTransactionHint() async {
    if (!_isTodayTransaction) return '可修改，默认当前净值';

    final confirmDate =
        await TransactionUtils.calculateConfirmDateAsync(_purchaseDate, _isAfter1500);

    return '待确认-${confirmDate.month.toString().padLeft(2, '0')}-${confirmDate.day.toString().padLeft(2, '0')}日自动更新';
  }

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
    _mappingCheckTimer?.cancel();
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
      _clientNameError =
          trimmed.isEmpty || trimmed.length > AppConstants.maxClientNameLength;
    });
  }

  void _validateFundCode(String value) {
    final trimmed = value.trim();
    setState(() {
      _fundCodeError =
          trimmed.isEmpty || !RegExp(AppConstants.fundCodePattern).hasMatch(trimmed);
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

  Future<void> _checkClientMapping(String clientId) async {
    if (clientId.isEmpty) return;

    try {
      final mappedName = await _mappingService.getClientNameByClientId(clientId);

      if (mappedName != null && mounted) {
        final currentName = _clientNameController.text.trim();

        if (currentName.isNotEmpty && currentName != mappedName) {
          final choice = await showCupertinoDialog<int>(
            context: context,
            barrierDismissible: true,
            builder: (context) => CupertinoAlertDialog(
              title: const Text('检测到客户号映射'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('客户号 "$clientId" 在映射词典中有记录：'),
                  const SizedBox(height: 8),
                  Text(
                    '词典姓名：$mappedName',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '当前输入：$currentName',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  const Text('请选择使用哪个姓名：'),
                ],
              ),
              actions: [
                CupertinoDialogAction(
                  child: Text('使用词典 [$mappedName]'),
                  onPressed: () => Navigator.pop(context, 1),
                ),
                CupertinoDialogAction(
                  child: Text('使用输入 [$currentName]'),
                  onPressed: () => Navigator.pop(context, 2),
                ),
              ],
            ),
          );

          if (choice == 1 && mounted) {
            _clientNameController.text = mappedName;
            context.showToast('已自动填充词典姓名');
          }
        } else if (currentName.isEmpty) {
          _clientNameController.text = mappedName;
          if (mounted) {
            setState(() => _clientNameError = false);
            context.showToast('已自动填充词典姓名');
          }
        }
      }
    } catch (e) {
      // silently ignore mapping lookup failures
    }
  }

  Future<void> _checkClientMappingByName(String clientName) async {
    if (clientName.isEmpty) return;

    try {
      final mappings = await _mappingService.getMappingsByClientName(clientName);

      if (mappings.isNotEmpty && mounted) {
        final currentClientId = _clientIdController.text.trim();

        if (mappings.length > 1) {
          final selectedMapping = await showCupertinoDialog<ClientMapping>(
            context: context,
            barrierDismissible: true,
            builder: (context) => CupertinoAlertDialog(
              title: const Text('检测到同名客户'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('发现 ${mappings.length} 个同名客户 "$clientName" 的映射记录'),
                  const SizedBox(height: 12),
                  ...mappings.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: CupertinoDialogAction(
                      child: Text('客户号: ${m.clientId}'),
                      onPressed: () => Navigator.pop(context, m),
                    ),
                  )),
                ],
              ),
              actions: [
                CupertinoDialogAction(
                  child: const Text('取消'),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          );

          if (selectedMapping != null && mounted) {
            _clientIdController.text = selectedMapping.clientId;
            context.showToast('已自动填充客户号');
          }
        } else if (currentClientId.isEmpty) {
          _clientIdController.text = mappings.first.clientId;
          context.showToast('已自动填充客户号');
        }
      }
    } catch (e) {
      // silently ignore
    }
  }

  Future<void> _onFundCodeChanged(String value) async {
    _validateFundCode(value);
    final code = value.trim().toUpperCase();
    if (code.length == 6 && RegExp(AppConstants.fundCodePattern).hasMatch(code)) {
      try {
        final fundInfo = await _fundService.fetchFundInfo(code);
        if (fundInfo['isValid'] == true && mounted) {
          setState(() {
            _fundName = fundInfo['fundName'] as String? ?? '';
            _currentNav = fundInfo['currentNav'] as double?;
            _navDate = fundInfo['navDate'] as DateTime?;
          });
          // Auto-fill confirm nav if non-pending date
          if (!_isTodayTransaction && _currentNav != null && _currentNav! > 0) {
            _confirmNavController.text = _currentNav!.toStringAsFixed(4);
            _confirmNav = _currentNav;
            _calculateShares();
          }
        }
      } catch (e) {
        // silently ignore fetch failures
      }
    } else {
      if (mounted) {
        setState(() {
          _fundName = '';
          _currentNav = null;
          _navDate = null;
        });
      }
    }
    _calculateShares();
  }

  Future<void> _fetchNavByDate(String code, DateTime date) async {
    if (_isTodayTransaction) {
      setState(() {
        _confirmNavController.clear();
        _confirmNav = null;
      });
      return;
    }

    try {
      List<NetWorthPoint> trendData;
      final targetNavDate =
          await TransactionUtils.calculateNavDateForTradeAsync(date, _isAfter1500);

      trendData = await _fundService.fetchNetWorthTrend(code);
      if (trendData.isEmpty) return;

      _cachedTrendData = trendData;

      NetWorthPoint? exactPoint;
      NetWorthPoint? closestPoint;
      int minDiff = 999999;
      NetWorthPoint? nextPoint;

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
          _confirmNavController.text = selectedPoint!.nav.toStringAsFixed(4);
          _confirmNav = selectedPoint!.nav;
        });
        _calculateShares();
      }
    } catch (e) {
      // silently ignore
    }
  }

  void _calculateShares() {
    if (_isTodayTransaction) return;

    final amountText = _purchaseAmountController.text.trim();
    final nav = _confirmNav;

    if (amountText.isEmpty || nav == null || nav <= 0) return;

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) return;

    final feeRateText = _feeRateController.text.trim();
    final feeRate = feeRateText.isEmpty ? 0.0 : (double.tryParse(feeRateText) ?? 0.0);
    if (feeRate <= AppConstants.feeRateMinValue) return;

    final shares = amount / (1 + feeRate / 100) / nav;

    _purchaseSharesController.text = shares.toStringAsFixed(2);
  }

  void _calculateNavFromShares() {
    if (_isTodayTransaction) return;

    final amountText = _purchaseAmountController.text.trim();
    final sharesText = _purchaseSharesController.text.trim();
    final feeRateText = _feeRateController.text.trim();

    final amount = double.tryParse(amountText);
    final shares = double.tryParse(sharesText);
    final feeRate = feeRateText.isEmpty ? 0.0 : (double.tryParse(feeRateText) ?? 0.0);

    if (amount == null || amount <= 0 || shares == null || shares <= 0) return;
    if (feeRate <= AppConstants.feeRateMinValue) return;

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

    final isTradingDay = await TransactionUtils.isTradingDay(_purchaseDate);
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

      if (confirmed != true) return;
    }

    setState(() => _isSaving = true);

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
    final feeRateText = _feeRateController.text.trim();
    final feeRate = feeRateText.isEmpty ? 0.0 : (double.tryParse(feeRateText) ?? 0.0);
    if (feeRate <= AppConstants.feeRateMinValue) {
      context.showToast('费率不能小于等于${AppConstants.feeRateMinValue.abs().toStringAsFixed(0)}%');
      setState(() => _isSaving = false);
      return;
    }
    if (feeRate > AppConstants.feeRateMaxValue) {
      context.showToast('费率不能超过${AppConstants.feeRateMaxValue.toStringAsFixed(0)}%');
      setState(() => _isSaving = false);
      return;
    }

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
        isSameClientId = existingHoldings.isNotEmpty;
      }

      if (existingHoldings.isEmpty) {
        existingHoldings = _dataManager.holdings
            .where((h) => h.clientName == clientName && h.fundCode == fundCode)
            .toList();
        if (existingHoldings.isNotEmpty) {
          final first = existingHoldings.first;
          if (clientId.isEmpty && first.clientId.isEmpty) {
            isSameClientName = true;
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
          shouldMerge = confirmed == true;
        }
      }

      final isPending = TransactionUtils.isTransactionPending(_purchaseDate, _isAfter1500);
      double? confirmedNav;
      if (!isPending) {
        final navText = _confirmNavController.text.trim();
        if (navText.isNotEmpty) {
          confirmedNav = double.tryParse(navText);
        }
        final effectiveNav = confirmedNav ?? _currentNav;
        if (shares == 0 && effectiveNav != null && effectiveNav > 0) {
          shares = amount / (1 + feeRate / 100) / effectiveNav;
        }
      } else {
        if (shares == 0) {
          final defaultNav = _confirmNav ?? _currentNav;
          if (defaultNav != null && defaultNav > 0) {
            shares = amount / (1 + feeRate / 100) / defaultNav;
          }
        }
      }

      final transaction = TransactionRecord(
        clientId: clientId,
        clientName: clientName,
        fundCode: fundCode,
        fundName: _fundName.isNotEmpty ? _fundName : '未知基金',
        type: TransactionType.buy,
        amount: amount,
        shares: shares,
        tradeDate: _purchaseDate,
        nav: confirmedNav,
        fee: feeRate > 0 ? feeRate : null,
        remarks: _remarksController.text.trim(),
        isAfter1500: _isAfter1500,
        isPending: isPending,
        confirmedNav: confirmedNav,
      );

      if (shouldMerge) {
        final existingHolding = existingHoldings.first;
        final holdingIndex =
            _dataManager.holdings.indexWhere((h) => h.id == existingHolding.id);
        if (holdingIndex != -1) {
          final updatedHolding = _dataManager.holdings[holdingIndex];
          await _dataManager.addTransaction(transaction);
          _dataManager.addLog(
            '合并加仓: ${transaction.fundCode} - ${transaction.clientName}',
            type: LogType.success,
          );
          if (mounted) {
            Navigator.pop(context);
            context.showToast('合并加仓成功');
          }
          return;
        }
      }

      await _dataManager.addTransaction(transaction);
      _dataManager.addLog(
        '新增持仓: ${transaction.fundCode} - ${transaction.clientName}',
        type: LogType.success,
      );

      if (mounted) {
        Navigator.pop(context);
        if (isPending) {
          final confirmDays = _isAfter1500 ? 'T+2' : 'T+1';
          context.showToast('新增持仓成功\n净值待${confirmDays}确认后生效');
        } else {
          context.showToast('新增持仓成功');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showToast('保存失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _selectDate() async {
    await showCupertinoModalPopup(
      context: context,
      builder: (context) => _DatePickerModal(
        initialDate: _purchaseDate,
        onConfirm: (date) {
          if (mounted) {
            setState(() {
              _purchaseDate = date;
              _pendingHintFuture = null;
            });
            _updatePendingStatus().then((_) {
              if (_fundCodeController.text.trim().length == 6) {
                _fetchNavByDate(_fundCodeController.text.trim(), _purchaseDate);
                _calculateShares();
              }
            });
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white;
    final textColor = isDark ? CupertinoColors.white : CupertinoColors.label;
    final secondaryColor = isDark
        ? CupertinoColors.white.withValues(alpha: 0.6)
        : CupertinoColors.systemGrey;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          constraints: const BoxConstraints(maxWidth: 400),
          child: CupertinoPopupSurface(
            isSurfacePainted: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ──
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF3A3A3C)
                        : CupertinoColors.systemGrey6,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '新增持仓',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: textColor),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDark
                                ? CupertinoColors.systemGrey
                                    .withValues(alpha: 0.3)
                                : CupertinoColors.systemGrey
                                    .withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(CupertinoIcons.xmark,
                              size: 16, color: textColor),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Scrollable body ──
                Container(
                  padding: const EdgeInsets.all(16),
                  color: bgColor,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.7,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Client name
                        _buildLabel('客户姓名', required: true),
                        const SizedBox(height: 6),
                        _buildTextField(
                          controller: _clientNameController,
                          hint: '请输入客户姓名',
                          error: _clientNameError,
                          onChanged: (value) {
                            _validateClientName(value);
                            _mappingCheckTimer?.cancel();
                            _mappingCheckTimer =
                                Timer(const Duration(milliseconds: 500), () {
                              final trimmedName = value.trim();
                              if (trimmedName.isNotEmpty) {
                                _checkClientMappingByName(trimmedName);
                              }
                            });
                          },
                          inputFormatters: [ClientNameInputFormatter()],
                        ),
                        const SizedBox(height: 12),

                        // Fund code
                        _buildLabel('基金代码', required: true),
                        const SizedBox(height: 6),
                        _buildTextField(
                          controller: _fundCodeController,
                          hint: '请输入6位基金代码',
                          error: _fundCodeError,
                          onChanged: _onFundCodeChanged,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                        ),
                        // Fund info — fixed-height display bar (avoids height jump)
                        const SizedBox(height: 12),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          alignment: Alignment.topCenter,
                          child: _fundName.isNotEmpty
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF007AFF)
                                            .withValues(alpha: 0.1)
                                        : const Color(0xFF007AFF)
                                            .withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _fundName,
                                          style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? CupertinoColors.systemBlue
                                                  : const Color(0xFF007AFF)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (_currentNav != null &&
                                          _currentNav! > 0 &&
                                          _navDate != null) ...[
                                        const SizedBox(width: 12),
                                        Text(
                                          '净值 ${_currentNav!.toStringAsFixed(4)}',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: textColor),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${_navDate!.month.toString().padLeft(2, '0')}-${_navDate!.day.toString().padLeft(2, '0')}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: secondaryColor),
                                        ),
                                      ],
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 14),

                        // Row 4: Date + Time side by side
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('购买日期', required: true),
                                  const SizedBox(height: 6),
                                  GestureDetector(
                                    onTap: _selectDate,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF3A3A3C)
                                            : CupertinoColors.systemGrey6,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            '${_purchaseDate.year}-${_purchaseDate.month.toString().padLeft(2, '0')}-${_purchaseDate.day.toString().padLeft(2, '0')}',
                                            style: TextStyle(
                                                fontSize: 15,
                                                color: textColor),
                                          ),
                                          const Spacer(),
                                          Icon(CupertinoIcons.calendar,
                                              size: 16,
                                              color: secondaryColor),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('交易时间', required: true),
                                  const SizedBox(height: 6),
                                  Container(
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF3A3A3C)
                                          : CupertinoColors.systemGrey6,
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => _setTime(false),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: !_isAfter1500
                                                    ? const Color(0xFF007AFF)
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                '15:00前',
                                                style: TextStyle(
                                                  color: !_isAfter1500
                                                      ? CupertinoColors.white
                                                      : secondaryColor,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => _setTime(true),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: _isAfter1500
                                                    ? const Color(0xFF007AFF)
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                '15:00后',
                                                style: TextStyle(
                                                  color: _isAfter1500
                                                      ? CupertinoColors.white
                                                      : secondaryColor,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Row 5: Amount + Fee side by side
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('交易金额', required: true),
                                  const SizedBox(height: 6),
                                  _buildAmountField(
                                    controller: _purchaseAmountController,
                                    hint: '请输入买入金额',
                                    error: _amountError,
                                    suffix: '元',
                                    onChanged: (value) {
                                      _validateAmount(value);
                                      _calculateShares();
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('费率', required: false),
                                  const SizedBox(height: 6),
                                  _buildFeeRateField(
                                    controller: _feeRateController,
                                    hint: '0',
                                    onChanged: (value) => _calculateShares(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Row 6: Confirm NAV (full width)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                _buildLabel('成交净值',
                                    required: !_isTodayTransaction),
                                if (_isTodayTransaction)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: CupertinoColors.systemOrange
                                          .withValues(alpha: 0.15),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: const Text(
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
                            if (_isTodayTransaction) ...[
                              const SizedBox(height: 4),
                              FutureBuilder<String>(
                                future: _getOrCreatePendingHintFuture(),
                                builder: (context, snapshot) {
                                  return Text(
                                    snapshot.data ?? '加载中...',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: secondaryColor),
                                  );
                                },
                              ),
                            ],
                            const SizedBox(height: 6),
                            _buildAmountField(
                              controller: _confirmNavController,
                              hint: _isTodayTransaction
                                  ? ''
                                  : '可修改，默认当前净值',
                              error: false,
                              suffix: '',
                              onChanged: (value) {
                                final nav =
                                    double.tryParse(value.trim());
                                if (nav != null && nav > 0) {
                                  setState(() => _confirmNav = nav);
                                  if (!_isTodayTransaction) {
                                    _calculateShares();
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Row 7: Shares (full width)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('交易份额',
                                required: !_isTodayTransaction),
                            const SizedBox(height: 6),
                            _buildAmountField(
                              controller: _purchaseSharesController,
                              hint: _isTodayTransaction
                                  ? '选填，待净值确认后可自动计算'
                                  : '请输入买入份额',
                              error: _sharesError,
                              suffix: '份',
                              onChanged: (value) {
                                _validateShares(value);
                                if (!_isTodayTransaction) {
                                  _calculateNavFromShares();
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Row 8: Client ID (full width)
                        _buildLabel('客户号', required: false),
                        const SizedBox(height: 6),
                        _buildTextField(
                          controller: _clientIdController,
                          hint: '选填，最多12位数字',
                          onChanged: (value) {
                            _mappingCheckTimer?.cancel();
                            _mappingCheckTimer = Timer(
                                const Duration(milliseconds: 500), () {
                              final trimmed = value.trim();
                              if (trimmed.isNotEmpty &&
                                  RegExp(r'^\d{1,12}$')
                                      .hasMatch(trimmed)) {
                                _checkClientMapping(trimmed);
                              }
                            });
                          },
                          inputFormatters: [ClientIdInputFormatter()],
                        ),
                        const SizedBox(height: 14),

                        // Row 9: Remarks (full width)
                        _buildLabel('备注', required: false),
                        const SizedBox(height: 6),
                        _buildTextField(
                          controller: _remarksController,
                          hint: '选填，最多30个字符',
                          onChanged: (v) {
                            if (v.length > 30) {
                              final cursor =
                                  _remarksController.selection.baseOffset;
                              _remarksController.text =
                                  v.substring(0, 30);
                              _remarksController.selection =
                                  TextSelection.collapsed(
                                offset: cursor.clamp(0, 30),
                              );
                            }
                          },
                          maxLength: 30,
                        ),
                        const SizedBox(height: 24),

                        // Submit button
                        GlassButton(
                          label: _isSaving ? '保存中...' : '确认新增',
                          onPressed: _isFormValid && !_isSaving
                              ? _saveHolding
                              : null,
                          isPrimary: true,
                          height: 44,
                          borderRadius: 12,
                          expand: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setTime(bool isAfter1500) async {
    if (mounted) {
      setState(() {
        _isAfter1500 = isAfter1500;
        _pendingHintFuture = null;
      });
    }
    await _updatePendingStatus();
    if (_fundCodeController.text.trim().length == 6) {
      await _fetchNavByDate(_fundCodeController.text.trim(), _purchaseDate);
      _calculateShares();
    }
  }

  // ─── Reusable field builders ───

  Widget _buildLabel(String text, {required bool required}) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color:
                isDark ? CupertinoColors.white.withValues(alpha: 0.8) : CupertinoColors.label,
          ),
        ),
        if (required)
          const Text(' *',
              style:
                  TextStyle(color: CupertinoColors.systemRed, fontSize: 12)),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
    bool error = false,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    TextInputType? keyboardType,
  }) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final textColor = isDark ? CupertinoColors.white : CupertinoColors.label;
    final placeholderColor = isDark
        ? CupertinoColors.white.withValues(alpha: 0.5)
        : CupertinoColors.systemGrey;
    final inputBgColor =
        isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6;

    Color bottomBorderColor;
    if (error) {
      bottomBorderColor = CupertinoColors.systemRed;
    } else if (controller.text.trim().isNotEmpty && !error) {
      bottomBorderColor = CupertinoColors.activeBlue;
    } else {
      bottomBorderColor =
          CupertinoColors.systemGrey.withValues(alpha: 0.3);
    }

    return Container(
      decoration: BoxDecoration(
        color: inputBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          bottom: BorderSide(color: bottomBorderColor, width: 1.5),
        ),
      ),
      child: CupertinoTextField(
        controller: controller,
        placeholder: hint,
        onChanged: onChanged,
        keyboardType: keyboardType,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        style: TextStyle(fontSize: 15, color: textColor),
        placeholderStyle: TextStyle(fontSize: 14, color: placeholderColor),
        inputFormatters: inputFormatters,
        maxLength: maxLength,
      ),
    );
  }

  Widget _buildAmountField({
    required TextEditingController controller,
    required String hint,
    required bool error,
    required String suffix,
    required ValueChanged<String> onChanged,
  }) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final textColor = isDark ? CupertinoColors.white : CupertinoColors.label;
    final placeholderColor = isDark
        ? CupertinoColors.white.withValues(alpha: 0.5)
        : CupertinoColors.systemGrey;
    final inputBgColor =
        isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6;

    Color bottomBorderColor;
    if (error) {
      bottomBorderColor = CupertinoColors.systemRed;
    } else if (controller.text.trim().isNotEmpty && !error) {
      bottomBorderColor = CupertinoColors.activeBlue;
    } else {
      bottomBorderColor =
          CupertinoColors.systemGrey.withValues(alpha: 0.3);
    }

    return Container(
      decoration: BoxDecoration(
        color: inputBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          bottom: BorderSide(color: bottomBorderColor, width: 1.5),
        ),
      ),
      child: CupertinoTextField(
        controller: controller,
        placeholder: hint,
        onChanged: onChanged,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        style: TextStyle(fontSize: 15, color: textColor),
        placeholderStyle: TextStyle(fontSize: 13, color: placeholderColor),
        inputFormatters: [AmountInputFormatter()],
        suffix: suffix.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(right: 10),
                child:
                    Text(suffix, style: TextStyle(color: placeholderColor)),
              )
            : null,
      ),
    );
  }

  Widget _buildFeeRateField({
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final textColor = isDark ? CupertinoColors.white : CupertinoColors.label;
    final placeholderColor = isDark
        ? CupertinoColors.white.withValues(alpha: 0.5)
        : CupertinoColors.systemGrey;
    final inputBgColor =
        isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6;

    return Container(
      decoration: BoxDecoration(
        color: inputBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          bottom: BorderSide(
              color: CupertinoColors.systemGrey.withValues(alpha: 0.3),
              width: 1.5),
        ),
      ),
      child: CupertinoTextField(
        controller: controller,
        placeholder: hint,
        onChanged: onChanged,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        style: TextStyle(fontSize: 15, color: textColor),
        placeholderStyle: TextStyle(fontSize: 13, color: placeholderColor),
        inputFormatters: [FeeRateInputFormatter()],
        suffix: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Text('%', style: TextStyle(color: placeholderColor)),
        ),
      ),
    );
  }
}

// ─── Date Picker Modal ───

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
  final List<FixedExtentScrollController> _pickerControllers = [];

  @override
  void initState() {
    super.initState();
    _tempDate = widget.initialDate;
  }

  @override
  void dispose() {
    for (final c in _pickerControllers) {
      c.dispose();
    }
    _pickerControllers.clear();
    super.dispose();
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

    final panelBgColor =
        isDarkMode ? const Color(0xFF1C1C1E) : CupertinoColors.white;
    final textColor =
        isDarkMode ? CupertinoColors.white : CupertinoColors.label;
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
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(12)),
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
                    months.indexOf(_tempDate.month),
                    '月',
                    (i) => _updateTempDate(month: months[i]),
                    panelBgColor,
                    textColor,
                    selectionOverlay,
                  ),
                  _buildPickerColumn(
                    days,
                    days.indexOf(_tempDate.day),
                    '日',
                    (i) => _updateTempDate(day: days[i]),
                    panelBgColor,
                    textColor,
                    selectionOverlay,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GlassButton(
                  label: '取消',
                  onPressed: () => Navigator.pop(context),
                  isPrimary: false,
                  height: 44,
                  borderRadius: 30,
                ),
                const SizedBox(width: 16),
                GlassButton(
                  label: '确定',
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
    final controller = FixedExtentScrollController(initialItem: initial);
    _pickerControllers.add(controller);
    return Expanded(
      child: CupertinoPicker(
        scrollController: controller,
        itemExtent: 40,
        backgroundColor: bgColor,
        selectionOverlay: overlay,
        onSelectedItemChanged: onChanged,
        children: items.map((item) => Center(
          child: Text('$item$unit',
              style: TextStyle(color: textColor, fontSize: 16)),
        )).toList(),
      ),
    );
  }
}

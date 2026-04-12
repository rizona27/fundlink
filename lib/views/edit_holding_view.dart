import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import '../providers/data_manager_provider.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../widgets/toast.dart';

class EditHoldingView extends StatefulWidget {
  final FundHolding holding;

  const EditHoldingView({super.key, required this.holding});

  @override
  State<EditHoldingView> createState() => _EditHoldingViewState();
}

class _EditHoldingViewState extends State<EditHoldingView> {
  late DataManager _dataManager;
  late FundService _fundService;

  late TextEditingController _clientNameController;
  late TextEditingController _clientIdController;
  late TextEditingController _fundCodeController;
  late TextEditingController _purchaseAmountController;
  late TextEditingController _purchaseSharesController;
  late TextEditingController _remarksController;

  String? _clientNameError;
  String? _fundCodeError;
  String? _amountError;
  String? _sharesError;

  bool _showDatePicker = false;
  late DateTime _purchaseDate;
  late DateTime _tempPurchaseDate;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _clientNameController = TextEditingController(text: widget.holding.clientName);
    _clientIdController = TextEditingController(text: widget.holding.clientId);
    _fundCodeController = TextEditingController(text: widget.holding.fundCode);
    _purchaseAmountController = TextEditingController(text: widget.holding.purchaseAmount.toStringAsFixed(2));
    _purchaseSharesController = TextEditingController(text: widget.holding.purchaseShares.toStringAsFixed(2));
    _remarksController = TextEditingController(text: widget.holding.remarks);
    _purchaseDate = widget.holding.purchaseDate;
    _tempPurchaseDate = widget.holding.purchaseDate;
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
    _remarksController.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    return _clientNameError == null &&
        _fundCodeError == null &&
        _amountError == null &&
        _sharesError == null &&
        _clientNameController.text.trim().isNotEmpty &&
        _fundCodeController.text.trim().isNotEmpty &&
        _purchaseAmountController.text.trim().isNotEmpty &&
        _purchaseSharesController.text.trim().isNotEmpty;
  }

  void _validateClientName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() => _clientNameError = '姓名不能为空');
    } else if (trimmed.length > 20) {
      setState(() => _clientNameError = '姓名不能超过20个字符');
    } else {
      setState(() => _clientNameError = null);
    }
  }

  void _validateFundCode(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() => _fundCodeError = '基金代码不能为空');
    } else if (!RegExp(r'^\d{6}$').hasMatch(trimmed)) {
      setState(() => _fundCodeError = '基金代码必须是6位数字');
    } else {
      setState(() => _fundCodeError = null);
    }
  }

  void _validateAmount(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() => _amountError = '购买金额不能为空');
    } else {
      final amount = double.tryParse(trimmed);
      if (amount == null || amount <= 0) {
        setState(() => _amountError = '请输入有效的正数金额');
      } else {
        setState(() => _amountError = null);
      }
    }
  }

  void _validateShares(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() => _sharesError = '购买份额不能为空');
    } else {
      final shares = double.tryParse(trimmed);
      if (shares == null || shares <= 0) {
        setState(() => _sharesError = '请输入有效的正数份额');
      } else {
        setState(() => _sharesError = null);
      }
    }
  }

  void _onFundCodeChanged(String value) {
    final filtered = value.replaceAll(RegExp(r'[^0-9]'), '');
    final newValue = filtered.length > 6 ? filtered.substring(0, 6) : filtered;
    if (newValue != _fundCodeController.text) {
      final cursorPosition = _fundCodeController.selection.baseOffset;
      _fundCodeController.text = newValue;
      if (cursorPosition <= newValue.length) {
        _fundCodeController.selection = TextSelection.collapsed(offset: cursorPosition);
      }
      _validateFundCode(newValue);
    }
  }

  void _onAmountChanged(String value) {
    final filtered = value.replaceAll(RegExp(r'[^0-9.]'), '');
    final dotCount = filtered.split('.').length - 1;
    if (dotCount > 1) return;
    final parts = filtered.split('.');
    String integerPart = parts[0];
    if (integerPart.length > 9) {
      integerPart = integerPart.substring(0, 9);
    }
    String decimalPart = parts.length > 1 ? parts[1] : '';
    if (decimalPart.length > 2) {
      decimalPart = decimalPart.substring(0, 2);
    }
    final newValue = decimalPart.isEmpty ? integerPart : '$integerPart.$decimalPart';
    if (newValue != _purchaseAmountController.text) {
      final cursorPosition = _purchaseAmountController.selection.baseOffset;
      _purchaseAmountController.text = newValue;
      if (cursorPosition <= newValue.length) {
        _purchaseAmountController.selection = TextSelection.collapsed(offset: cursorPosition);
      }
      _validateAmount(newValue);
    }
  }

  void _onSharesChanged(String value) {
    final filtered = value.replaceAll(RegExp(r'[^0-9.]'), '');
    final dotCount = filtered.split('.').length - 1;
    if (dotCount > 1) return;
    final parts = filtered.split('.');
    String integerPart = parts[0];
    if (integerPart.length > 9) {
      integerPart = integerPart.substring(0, 9);
    }
    String decimalPart = parts.length > 1 ? parts[1] : '';
    if (decimalPart.length > 2) {
      decimalPart = decimalPart.substring(0, 2);
    }
    final newValue = decimalPart.isEmpty ? integerPart : '$integerPart.$decimalPart';
    if (newValue != _purchaseSharesController.text) {
      final cursorPosition = _purchaseSharesController.selection.baseOffset;
      _purchaseSharesController.text = newValue;
      if (cursorPosition <= newValue.length) {
        _purchaseSharesController.selection = TextSelection.collapsed(offset: cursorPosition);
      }
      _validateShares(newValue);
    }
  }

  Future<void> _saveChanges() async {
    if (!_isFormValid) return;

    setState(() => _isLoading = true);

    final amount = double.parse(_purchaseAmountController.text.trim());
    final shares = double.parse(_purchaseSharesController.text.trim());
    final newFundCode = _fundCodeController.text.trim().toUpperCase();
    final fundCodeChanged = newFundCode != widget.holding.fundCode;

    final updatedHolding = widget.holding.copyWith(
      clientName: _clientNameController.text.trim(),
      clientId: _clientIdController.text.trim(),
      fundCode: newFundCode,
      purchaseAmount: amount,
      purchaseShares: shares,
      purchaseDate: _purchaseDate,
      remarks: _remarksController.text.trim(),
      fundName: fundCodeChanged ? '待加载' : widget.holding.fundName,
      currentNav: fundCodeChanged ? 0 : widget.holding.currentNav,
      navDate: fundCodeChanged ? DateTime.now() : widget.holding.navDate,
      isValid: fundCodeChanged ? false : widget.holding.isValid,
    );

    try {
      await _dataManager.updateHolding(updatedHolding);
      await _dataManager.addLog('更新持仓: ${updatedHolding.fundCode} - ${updatedHolding.clientName}', type: LogType.success);
      context.showToast('保存成功');

      if (fundCodeChanged || !updatedHolding.isValid) {
        final fundInfo = await _fundService.fetchFundInfo(updatedHolding.fundCode);
        final finalHolding = updatedHolding.copyWith(
          fundName: fundInfo['fundName'] as String? ?? '待加载',
          currentNav: fundInfo['currentNav'] as double? ?? 0,
          navDate: fundInfo['navDate'] as DateTime? ?? DateTime.now(),
          isValid: fundInfo['isValid'] as bool? ?? false,
        );
        await _dataManager.updateHolding(finalHolding);
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      await _dataManager.addLog('更新持仓失败: $e', type: LogType.error);
      context.showToast('保存失败');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    // 修复：删除未使用的 backgroundColor, textColor, secondaryTextColor
    // 这些变量在后续代码中并未使用，直接移除

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: const Text('编辑持仓'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.back, size: 24),
        ),
      ),
      child: SafeArea(
        child: _isLoading
            ? const Center(child: CupertinoActivityIndicator(radius: 20))
            : SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSection(
                title: '必填信息',
                isDarkMode: isDarkMode,
                children: [
                  _buildTextField(
                    title: '客户姓名',
                    required: true,
                    hint: '请输入客户姓名',
                    controller: _clientNameController,
                    error: _clientNameError,
                    icon: CupertinoIcons.person,
                    isDarkMode: isDarkMode,
                    onChanged: _validateClientName,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    title: '基金代码',
                    required: true,
                    hint: '请输入6位基金代码',
                    controller: _fundCodeController,
                    error: _fundCodeError,
                    icon: CupertinoIcons.number,
                    keyboardType: TextInputType.number,
                    isDarkMode: isDarkMode,
                    onChanged: _onFundCodeChanged,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    title: '购买金额',
                    required: true,
                    hint: '请输入购买金额',
                    controller: _purchaseAmountController,
                    error: _amountError,
                    icon: CupertinoIcons.money_dollar,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    isDarkMode: isDarkMode,
                    onChanged: _onAmountChanged,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    title: '购买份额',
                    required: true,
                    hint: '请输入购买份额',
                    controller: _purchaseSharesController,
                    error: _sharesError,
                    icon: CupertinoIcons.chart_pie,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    isDarkMode: isDarkMode,
                    onChanged: _onSharesChanged,
                  ),
                  const SizedBox(height: 12),
                  _buildDatePicker(isDarkMode),
                ],
              ),
              const SizedBox(height: 24),
              _buildSection(
                title: '选填信息',
                isDarkMode: isDarkMode,
                children: [
                  _buildTextField(
                    title: '客户号',
                    required: false,
                    hint: '选填，最多12位数字',
                    controller: _clientIdController,
                    icon: CupertinoIcons.creditcard,
                    keyboardType: TextInputType.number,
                    isDarkMode: isDarkMode,
                    onChanged: (v) {
                      final filtered = v.replaceAll(RegExp(r'[^0-9]'), '');
                      final newValue = filtered.length > 12 ? filtered.substring(0, 12) : filtered;
                      if (newValue != _clientIdController.text) {
                        final cursor = _clientIdController.selection.baseOffset;
                        _clientIdController.text = newValue;
                        if (cursor <= newValue.length) {
                          _clientIdController.selection = TextSelection.collapsed(offset: cursor);
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    title: '备注',
                    required: false,
                    hint: '选填，最多30个字符',
                    controller: _remarksController,
                    icon: CupertinoIcons.text_bubble,
                    isDarkMode: isDarkMode,
                    onChanged: (v) {
                      if (v.length > 30) {
                        final cursor = _remarksController.selection.baseOffset;
                        _remarksController.text = v.substring(0, 30);
                        if (cursor <= 30) {
                          _remarksController.selection = TextSelection.collapsed(offset: cursor);
                        }
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      onPressed: () => Navigator.of(context).pop(),
                      color: isDarkMode ? CupertinoColors.systemGrey : CupertinoColors.systemGrey,
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      onPressed: _isFormValid ? _saveChanges : null,
                      color: CupertinoColors.activeBlue,
                      child: const Text('保存修改'),
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

  Widget _buildSection({
    required String title,
    required bool isDarkMode,
    required List<Widget> children,
  }) {
    final textColor = isDarkMode ? CupertinoColors.white : CupertinoColors.label;
    final backgroundColor = isDarkMode ? CupertinoColors.systemGrey6.withOpacity(0.3) : CupertinoColors.systemGrey6;

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
              color: textColor,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String title,
    required bool required,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    required Function(String) onChanged,
    required bool isDarkMode,
    String? error,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final textColor = isDarkMode ? CupertinoColors.white : CupertinoColors.label;
    final secondaryTextColor = isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey;
    final backgroundColor = isDarkMode ? CupertinoColors.systemGrey6 : CupertinoColors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4FACFE), Color(0xFF00F2FE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 14, color: CupertinoColors.white),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            if (required)
              Text(' *', style: TextStyle(color: CupertinoColors.systemRed)),
          ],
        ),
        const SizedBox(height: 8),
        CupertinoTextField(
          placeholder: hint,
          controller: controller,
          onChanged: onChanged,
          keyboardType: keyboardType,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
          ),
          style: TextStyle(color: textColor),
          placeholderStyle: TextStyle(color: secondaryTextColor),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(CupertinoIcons.exclamationmark_triangle, size: 12, color: CupertinoColors.systemRed),
                const SizedBox(width: 4),
                Text(error, style: const TextStyle(fontSize: 12, color: CupertinoColors.systemRed)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDatePicker(bool isDarkMode) {
    final now = DateTime.now();
    final years = List.generate(10, (i) => now.year - 5 + i);
    final months = List.generate(12, (i) => i + 1);
    final days = List.generate(
      DateTime(_tempPurchaseDate.year, _tempPurchaseDate.month + 1, 0).day,
          (i) => i + 1,
    );

    int selectedYearIndex = years.indexOf(_tempPurchaseDate.year);
    int selectedMonthIndex = _tempPurchaseDate.month - 1;
    int selectedDayIndex = _tempPurchaseDate.day - 1;

    final textColor = isDarkMode ? CupertinoColors.white : CupertinoColors.label;
    final backgroundColor = isDarkMode ? CupertinoColors.systemGrey6 : CupertinoColors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFD746C), Color(0xFFFF9068)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(CupertinoIcons.calendar, size: 14, color: CupertinoColors.white),
            ),
            const SizedBox(width: 8),
            Text(
              '购买日期 *',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        CupertinoButton(
          onPressed: () {
            setState(() {
              _tempPurchaseDate = _purchaseDate;
              _showDatePicker = true;
            });
          },
          padding: EdgeInsets.zero,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text(
                  '${_purchaseDate.year}-${_purchaseDate.month.toString().padLeft(2, '0')}-${_purchaseDate.day.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 16, color: textColor),
                ),
                const Spacer(),
                Icon(
                  CupertinoIcons.chevron_down,
                  size: 16,
                  color: CupertinoColors.systemGrey,
                ),
              ],
            ),
          ),
        ),
        if (_showDatePicker)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 200,
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(initialItem: selectedYearIndex),
                          itemExtent: 40,
                          onSelectedItemChanged: (index) {
                            setState(() {
                              final newYear = years[index];
                              final newDate = DateTime(
                                newYear,
                                _tempPurchaseDate.month,
                                _tempPurchaseDate.day.clamp(1, DateTime(newYear, _tempPurchaseDate.month + 1, 0).day),
                              );
                              _tempPurchaseDate = newDate;
                            });
                          },
                          children: years.map((year) => Center(child: Text('$year年', style: TextStyle(color: textColor)))).toList(),
                        ),
                      ),
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(initialItem: selectedMonthIndex),
                          itemExtent: 40,
                          onSelectedItemChanged: (index) {
                            setState(() {
                              final newMonth = index + 1;
                              final maxDay = DateTime(_tempPurchaseDate.year, newMonth + 1, 0).day;
                              final newDay = _tempPurchaseDate.day.clamp(1, maxDay);
                              _tempPurchaseDate = DateTime(_tempPurchaseDate.year, newMonth, newDay);
                            });
                          },
                          children: months.map((month) => Center(child: Text('$month月', style: TextStyle(color: textColor)))).toList(),
                        ),
                      ),
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(initialItem: selectedDayIndex),
                          itemExtent: 40,
                          onSelectedItemChanged: (index) {
                            setState(() {
                              final newDay = index + 1;
                              _tempPurchaseDate = DateTime(_tempPurchaseDate.year, _tempPurchaseDate.month, newDay);
                            });
                          },
                          children: days.map((day) => Center(child: Text('$day日', style: TextStyle(color: textColor)))).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        onPressed: () => setState(() => _showDatePicker = false),
                        color: CupertinoColors.systemGrey,
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton(
                        onPressed: () {
                          setState(() {
                            _purchaseDate = _tempPurchaseDate;
                            _showDatePicker = false;
                          });
                        },
                        color: CupertinoColors.activeBlue,
                        child: const Text('完成'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
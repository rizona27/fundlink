import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../widgets/toast.dart';
import '../widgets/glass_button.dart';

/// 金额/份额输入格式化器：支持小数点输入，整数最多9位，小数最多2位，只能一个小数点
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

/// 客户姓名输入格式化器：只允许中文、英文、数字、最多一个空格
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

/// 客户号输入格式化器：只允许数字，最多12位
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
  final TextEditingController _remarksController = TextEditingController();

  bool _clientNameError = false;
  bool _fundCodeError = false;
  bool _amountError = false;
  bool _sharesError = false;

  DateTime _purchaseDate = DateTime.now();
  bool _isLoading = false;
  bool _isSaving = false;

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
  }

  Future<void> _saveHolding() async {
    if (_isSaving) return;
    if (!_isFormValid) return;

    setState(() {
      _isLoading = true;
      _isSaving = true;
    });

    final amount = double.parse(_purchaseAmountController.text.trim());
    final shares = double.parse(_purchaseSharesController.text.trim());

    final newHolding = FundHolding(
      clientName: _clientNameController.text.trim(),
      clientId: _clientIdController.text.trim(),
      fundCode: _fundCodeController.text.trim().toUpperCase(),
      fundName: '待加载',
      purchaseAmount: amount,
      purchaseShares: shares,
      purchaseDate: _purchaseDate,
      navDate: DateTime.now(),
      currentNav: 0,
      isValid: false,
      remarks: _remarksController.text.trim(),
    );

    try {
      await _dataManager.addHolding(newHolding);
      await _dataManager.addLog('新增持仓: ${newHolding.fundCode} - ${newHolding.clientName}', type: LogType.success);
      context.showToast('添加成功');

      final fundInfo = await _fundService.fetchFundInfo(newHolding.fundCode);
      final updatedHolding = newHolding.copyWith(
        fundName: fundInfo['fundName'] as String? ?? '待加载',
        currentNav: fundInfo['currentNav'] as double? ?? 0,
        navDate: fundInfo['navDate'] as DateTime? ?? DateTime.now(),
        isValid: fundInfo['isValid'] as bool? ?? false,
      );
      await _dataManager.updateHolding(updatedHolding);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      await _dataManager.addLog('添加持仓失败: $e', type: LogType.error);
      context.showToast('添加失败');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
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
        onConfirm: (newDate) {
          setState(() {
            _purchaseDate = newDate;
          });
        },
      ),
    );
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
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: const SizedBox(),
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
                    child: _buildTextField(
                      controller: _fundCodeController,
                      hint: '请输入6位基金代码',
                      error: _fundCodeError,
                      onChanged: _onFundCodeChanged,
                      inputBgColor: inputBgColor,
                      textColor: textColor,
                      placeholderColor: placeholderColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRowField(
                    label: '购买金额',
                    required: true,
                    child: _buildAmountField(
                      controller: _purchaseAmountController,
                      hint: '请输入购买金额',
                      error: _amountError,
                      onChanged: _validateAmount,
                      inputBgColor: inputBgColor,
                      textColor: textColor,
                      placeholderColor: placeholderColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRowField(
                    label: '购买份额',
                    required: true,
                    child: _buildAmountField(
                      controller: _purchaseSharesController,
                      hint: '请输入购买份额',
                      error: _sharesError,
                      onChanged: _validateShares,
                      inputBgColor: inputBgColor,
                      textColor: textColor,
                      placeholderColor: placeholderColor,
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

  // 磨玻璃质感区块（带 BackdropFilter）
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
        SizedBox(
          width: 80,
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              if (required)
                const Text(' *', style: TextStyle(color: CupertinoColors.systemRed)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }

  // 输入框：极细底边，无实体边框
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
}

// 模态日期选择器（复用 GlassButton）
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
            // 修改点：移除 Expanded，改用 Row 右对齐，按钮宽度自适应
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
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';
import '../providers/data_manager_provider.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../widgets/toast.dart';

/// 金额/份额输入格式化器：支持小数点输入，整数最多9位，小数最多2位，只能一个小数点
class AmountInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    // 只允许数字和小数点
    String filtered = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');

    // 限制最多一个小数点
    final parts = filtered.split('.');
    if (parts.length > 2) {
      filtered = parts[0] + '.' + parts[1];
    }

    // 处理以小数点开头的情况（例如 ".5" -> "0.5"）
    if (filtered.startsWith('.')) {
      filtered = '0$filtered';
    }

    // 分离整数和小数部分
    final newParts = filtered.split('.');
    String integerPart = newParts[0];
    String decimalPart = newParts.length > 1 ? newParts[1] : '';

    // 整数部分最多9位
    if (integerPart.length > 9) {
      integerPart = integerPart.substring(0, 9);
    }
    // 小数部分最多2位
    if (decimalPart.length > 2) {
      decimalPart = decimalPart.substring(0, 2);
    }

    // 格式化结果
    String formatted;
    if (decimalPart.isEmpty) {
      formatted = integerPart;
    } else {
      formatted = '$integerPart.$decimalPart';
    }

    // 如果用户输入了小数点但没有小数部分，保留小数点（例如 "123."）
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
    // 允许的字符：字母、数字、中文、空格
    final allowedPattern = RegExp(r'[a-zA-Z0-9\u4e00-\u9fa5 ]');
    String filtered = newValue.text.split('').where((c) => allowedPattern.hasMatch(c)).join('');

    // 限制最多一个空格：将多个连续空格替换为单个空格，并限制空格总数不超过1
    filtered = filtered.replaceAll(RegExp(r' +'), ' ');
    final spaceCount = filtered.split('').where((c) => c == ' ').length;
    if (spaceCount > 1) {
      // 移除多余的空格，保留第一个
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

  // 错误状态（用于控制边框颜色）
  bool _clientNameError = false;
  bool _fundCodeError = false;
  bool _amountError = false;
  bool _sharesError = false;

  // 日期选择器
  bool _showDatePicker = false;
  DateTime _purchaseDate = DateTime.now();
  DateTime _tempPurchaseDate = DateTime.now();

  bool _isLoading = false;

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

  // 表单整体有效性
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

  // 验证客户姓名
  void _validateClientName(String value) {
    final trimmed = value.trim();
    setState(() {
      _clientNameError = trimmed.isEmpty || trimmed.length > 20;
    });
  }

  // 验证基金代码
  void _validateFundCode(String value) {
    final trimmed = value.trim();
    setState(() {
      _fundCodeError = trimmed.isEmpty || !RegExp(r'^\d{6}$').hasMatch(trimmed);
    });
  }

  // 验证购买金额
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

  // 验证购买份额
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

  // 基金代码输入过滤（只允许数字，最多6位）
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

  // 保存持仓
  Future<void> _saveHolding() async {
    if (!_isFormValid) return;

    setState(() => _isLoading = true);

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

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      await _dataManager.addLog('添加持仓失败: $e', type: LogType.error);
      context.showToast('添加失败');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    // 磨玻璃背景色：深色模式深灰半透，浅色模式白半透
    final frostedBgColor = isDarkMode
        ? const Color(0xFF2C2C2E).withOpacity(0.85)
        : CupertinoColors.white.withOpacity(0.85);
    // 输入框背景色：深色模式深灰，浅色模式白
    final inputBgColor = isDarkMode ? CupertinoColors.systemGrey6 : CupertinoColors.white;
    // 文字颜色
    final textColor = isDarkMode ? CupertinoColors.white : CupertinoColors.label;
    // 次要文字颜色（占位符等）
    final placeholderColor = isDarkMode
        ? CupertinoColors.white.withOpacity(0.5)
        : CupertinoColors.systemGrey;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        heroTag: 'add_holding_view_nav',
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
              // 必填信息区块
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
                      onTap: () {
                        setState(() {
                          _tempPurchaseDate = _purchaseDate;
                          _showDatePicker = true;
                        });
                      },
                      isDarkMode: isDarkMode,
                    ),
                  ),
                  // 日期选择器面板
                  if (_showDatePicker) _buildDatePickerPanel(isDarkMode),
                ],
              ),
              const SizedBox(height: 24),
              // 选填信息区块
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
              // 底部按钮（统一磨玻璃质感）
              Row(
                children: [
                  Expanded(
                    child: _buildGlassButton(
                      label: '取消',
                      onPressed: () => Navigator.of(context).pop(),
                      isDarkMode: isDarkMode,
                      isPrimary: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildGlassButton(
                      label: '保存',
                      onPressed: _isFormValid ? _saveHolding : null,
                      isDarkMode: isDarkMode,
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

  // 磨玻璃质感区块
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
        Container(
          decoration: BoxDecoration(
            color: frostedBgColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.08),
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
      ],
    );
  }

  // 标签 + 输入框同行（垂直居中）
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

  // 普通输入框（边框颜色反馈，支持深色模式）
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
    Color borderColor;
    if (error) {
      borderColor = CupertinoColors.systemRed;
    } else if (controller.text.trim().isNotEmpty && !error) {
      borderColor = CupertinoColors.activeBlue.withOpacity(0.5);
    } else {
      borderColor = CupertinoColors.systemGrey.withOpacity(0.4);
    }

    return CupertinoTextField(
      controller: controller,
      placeholder: hint,
      onChanged: onChanged,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: inputBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      style: TextStyle(color: textColor),
      placeholderStyle: TextStyle(color: placeholderColor),
      inputFormatters: inputFormatters,
      maxLength: maxLength,
    );
  }

  // 金额/份额输入框（使用自定义格式化器）
  Widget _buildAmountField({
    required TextEditingController controller,
    required String hint,
    required Function(String) onChanged,
    required Color inputBgColor,
    required Color textColor,
    required Color placeholderColor,
    bool error = false,
  }) {
    Color borderColor;
    if (error) {
      borderColor = CupertinoColors.systemRed;
    } else if (controller.text.trim().isNotEmpty && !error) {
      borderColor = CupertinoColors.activeBlue.withOpacity(0.5);
    } else {
      borderColor = CupertinoColors.systemGrey.withOpacity(0.4);
    }

    return CupertinoTextField(
      controller: controller,
      placeholder: hint,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: inputBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      style: TextStyle(color: textColor),
      placeholderStyle: TextStyle(color: placeholderColor),
      inputFormatters: [AmountInputFormatter()],
    );
  }

  // ==================== 日期选择器核心修复 ====================

  /// 修复：购买日期显示框（未点击时）深色模式完美适配
  Widget _buildDatePickerField({
    required DateTime purchaseDate,
    required VoidCallback onTap,
    required bool isDarkMode,
  }) {
    // 核心修复：深色模式下使用比背景稍微亮一点的深灰色，浅色模式下用纯白
    final bgColor = isDarkMode ? const Color(0xFF3A3A3C) : CupertinoColors.white;
    final textColor = isDarkMode ? CupertinoColors.white : CupertinoColors.label;
    final borderColor = isDarkMode
        ? CupertinoColors.systemGrey.withOpacity(0.2)
        : CupertinoColors.systemGrey.withOpacity(0.4);
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
          border: Border.all(color: borderColor, width: 1.5),
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

  /// 修复：日期选择器面板（深色模式完整适配，消除白灰色遮罩）
  Widget _buildDatePickerPanel(bool isDarkMode) {
    final now = DateTime.now();
    final years = List.generate(10, (i) => now.year - 5 + i);
    final months = List.generate(12, (i) => i + 1);
    final days = List.generate(
      DateTime(_tempPurchaseDate.year, _tempPurchaseDate.month + 1, 0).day,
          (i) => i + 1,
    );

    // 严格适配 iOS 深色二级背景
    final Color panelBgColor = isDarkMode ? const Color(0xFF1C1C1E) : CupertinoColors.white;
    final Color textColor = isDarkMode ? CupertinoColors.white : CupertinoColors.label;

    // 彻底修复：使用系统专门的 Overlay 组件，并设置背景色
    final selectionOverlay = CupertinoPickerDefaultSelectionOverlay(
      background: isDarkMode
          ? CupertinoColors.white.withOpacity(0.05)
          : CupertinoColors.black.withOpacity(0.03),
    );

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelBgColor,
        borderRadius: BorderRadius.circular(12),
        border: isDarkMode ? Border.all(color: Colors.white10) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDarkMode ? 0.4 : 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: Row(
              children: [
                _buildColumn(
                  years,
                  years.indexOf(_tempPurchaseDate.year),
                  '年',
                      (i) => _updateTempDate(year: years[i]),
                  panelBgColor,
                  textColor,
                  selectionOverlay,
                ),
                _buildColumn(
                  months,
                  _tempPurchaseDate.month - 1,
                  '月',
                      (i) => _updateTempDate(month: i + 1),
                  panelBgColor,
                  textColor,
                  selectionOverlay,
                ),
                _buildColumn(
                  days,
                  _tempPurchaseDate.day - 1,
                  '日',
                      (i) => _updateTempDate(day: i + 1),
                  panelBgColor,
                  textColor,
                  selectionOverlay,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildGlassButton(
                  label: '取消',
                  onPressed: () => setState(() => _showDatePicker = false),
                  isDarkMode: isDarkMode,
                  isPrimary: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildGlassButton(
                  label: '完成',
                  onPressed: () {
                    setState(() {
                      _purchaseDate = _tempPurchaseDate;
                      _showDatePicker = false;
                    });
                  },
                  isDarkMode: isDarkMode,
                  isPrimary: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 提取的列构建方法，确保每个滚轮都应用了 selectionOverlay
  Widget _buildColumn(
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

  /// 辅助方法：更新日期并处理 2.29/2.30 等溢出逻辑
  void _updateTempDate({int? year, int? month, int? day}) {
    setState(() {
      int y = year ?? _tempPurchaseDate.year;
      int m = month ?? _tempPurchaseDate.month;
      int d = day ?? _tempPurchaseDate.day;
      int maxDays = DateTime(y, m + 1, 0).day;
      if (d > maxDays) d = maxDays;
      _tempPurchaseDate = DateTime(y, m, d);
    });
  }

  // 统一磨玻璃质感按钮（适用于底部按钮和日期选择器按钮）
  Widget _buildGlassButton({
    required String label,
    required VoidCallback? onPressed,
    required bool isDarkMode,
    required bool isPrimary,
  }) {
    // 背景色：深色模式深灰半透，浅色模式白半透
    final bgColor = isDarkMode
        ? const Color(0xFF2C2C2E).withOpacity(0.85)
        : CupertinoColors.white.withOpacity(0.85);
    // 主要按钮（保存）使用淡蓝色背景（毛玻璃效果），次要按钮使用半透背景
    Color? backgroundColor;
    if (isPrimary && onPressed != null) {
      backgroundColor = CupertinoColors.activeBlue.withOpacity(0.15);
    } else if (!isPrimary && onPressed != null) {
      backgroundColor = bgColor;
    }
    // 文字颜色：主要按钮蓝色，次要按钮根据主题自动
    final textColor = isPrimary
        ? CupertinoColors.activeBlue
        : (isDarkMode ? CupertinoColors.white : CupertinoColors.label);
    final disabledColor = isDarkMode ? CupertinoColors.systemGrey : CupertinoColors.systemGrey5;

    Widget button = Container(
      decoration: BoxDecoration(
        color: onPressed != null ? backgroundColor : disabledColor,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: CupertinoButton(
        onPressed: onPressed,
        padding: const EdgeInsets.symmetric(vertical: 12),
        borderRadius: BorderRadius.circular(30),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: onPressed != null ? textColor : textColor.withOpacity(0.5),
          ),
        ),
      ),
    );

    if (onPressed == null) {
      button = Opacity(opacity: 0.6, child: button);
    }
    return button;
  }
}
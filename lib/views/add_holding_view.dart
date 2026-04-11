import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import '../providers/data_manager_provider.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../widgets/toast.dart';

class AddHoldingView extends StatefulWidget {
  const AddHoldingView({super.key});

  @override
  State<AddHoldingView> createState() => _AddHoldingViewState();
}

class _AddHoldingViewState extends State<AddHoldingView> {
  late DataManager _dataManager;
  late FundService _fundService;

  // 使用 TextEditingController
  final TextEditingController _clientNameController = TextEditingController();
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _fundCodeController = TextEditingController();
  final TextEditingController _purchaseAmountController = TextEditingController();
  final TextEditingController _purchaseSharesController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  // 错误信息
  String? _clientNameError;
  String? _fundCodeError;
  String? _amountError;
  String? _sharesError;

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

  // 修复输入框光标问题：使用 controller.text 并手动设置
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

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      await _dataManager.addLog('添加持仓失败: $e', type: LogType.error);
      context.showToast('添加失败');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('新增持仓'),
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
                children: [
                  _buildTextField(
                    title: '客户姓名',
                    required: true,
                    hint: '请输入客户姓名',
                    controller: _clientNameController,
                    error: _clientNameError,
                    icon: CupertinoIcons.person,
                    onChanged: (v) {
                      _validateClientName(v);
                    },
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
                    onChanged: _onSharesChanged,
                  ),
                  const SizedBox(height: 12),
                  _buildDatePicker(),
                ],
              ),
              const SizedBox(height: 24),
              _buildSection(
                title: '选填信息',
                children: [
                  _buildTextField(
                    title: '客户号',
                    required: false,
                    hint: '选填，最多12位数字',
                    controller: _clientIdController,
                    icon: CupertinoIcons.creditcard,
                    keyboardType: TextInputType.number,
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
                      color: CupertinoColors.systemGrey,
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      onPressed: _isFormValid ? _saveHolding : null,
                      color: CupertinoColors.activeBlue,
                      child: const Text('保存'),
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
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.label,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey6,
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
    String? error,
    TextInputType keyboardType = TextInputType.text,
  }) {
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
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (required)
              const Text(' *', style: TextStyle(color: CupertinoColors.systemRed)),
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
            color: CupertinoColors.white,
            borderRadius: BorderRadius.circular(10),
          ),
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

  Widget _buildDatePicker() {
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
            const Text('购买日期 *', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
              color: CupertinoColors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text(
                  '${_purchaseDate.year}-${_purchaseDate.month.toString().padLeft(2, '0')}-${_purchaseDate.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 16),
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
              color: CupertinoColors.white,
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
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: _tempPurchaseDate,
                    maximumDate: DateTime.now(),
                    onDateTimeChanged: (date) {
                      _tempPurchaseDate = date;
                    },
                  ),
                ),
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
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

  String _formatDecimalInput(String input, int maxDigits) {
    final parts = input.split('.');
    String result = parts[0];
    if (result.length > maxDigits) {
      result = result.substring(0, maxDigits);
    }
    if (parts.length > 1) {
      result += '.' + parts[1].substring(0, parts[1].length > 2 ? 2 : parts[1].length);
    }
    return result;
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
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
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
                children: [
                  _buildTextField(
                    title: '客户姓名',
                    required: true,
                    hint: '请输入客户姓名',
                    controller: _clientNameController,
                    error: _clientNameError,
                    icon: CupertinoIcons.person,
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
                    maxLength: 6,
                    onChanged: (v) {
                      final filtered = v.replaceAll(RegExp(r'[^0-9]'), '');
                      _fundCodeController.text = filtered.length > 6 ? filtered.substring(0, 6) : filtered;
                      _validateFundCode(_fundCodeController.text);
                    },
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
                    onChanged: (v) {
                      final filtered = v.replaceAll(RegExp(r'[^0-9.]'), '');
                      final dotCount = filtered.split('.').length - 1;
                      if (dotCount > 1) return;
                      _purchaseAmountController.text = _formatDecimalInput(filtered, 9);
                      _validateAmount(_purchaseAmountController.text);
                    },
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
                    onChanged: (v) {
                      final filtered = v.replaceAll(RegExp(r'[^0-9.]'), '');
                      final dotCount = filtered.split('.').length - 1;
                      if (dotCount > 1) return;
                      _purchaseSharesController.text = _formatDecimalInput(filtered, 9);
                      _validateShares(_purchaseSharesController.text);
                    },
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
                    maxLength: 12,
                    onChanged: (v) {
                      final filtered = v.replaceAll(RegExp(r'[^0-9]'), '');
                      _clientIdController.text = filtered.length > 12 ? filtered.substring(0, 12) : filtered;
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    title: '备注',
                    required: false,
                    hint: '选填，最多30个字符',
                    controller: _remarksController,
                    icon: CupertinoIcons.text_bubble,
                    maxLength: 30,
                    onChanged: (v) {
                      if (v.length > 30) {
                        _remarksController.text = v.substring(0, 30);
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
    int? maxLength,
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
          maxLength: maxLength,
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
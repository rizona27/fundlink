import 'package:flutter/cupertino.dart';
import '../services/fund_service.dart';
import '../widgets/glass_button.dart';
import '../utils/input_formatters.dart';

class CustomFundConfigDialog extends StatefulWidget {
  final String currentCode;
  final Function(String) onConfirm;

  const CustomFundConfigDialog({
    super.key,
    required this.currentCode,
    required this.onConfirm,
  });

  @override
  State<CustomFundConfigDialog> createState() => _CustomFundConfigDialogState();
}

class _CustomFundConfigDialogState extends State<CustomFundConfigDialog> {
  late TextEditingController _codeController;
  bool _isValidating = false;
  String? _validationError;
  bool _fundExists = false;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.currentCode);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _validateFundCode() async {
    final code = _codeController.text.trim();
    
    if (code.length != 6 || !RegExp(r'^\d{6}$').hasMatch(code)) {
      if (mounted) setState(() {
        _validationError = '请输入6位数字';
        _fundExists = false;
      });
      return;
    }

    if (mounted) setState(() {
      _isValidating = true;
      _validationError = null;
      _fundExists = false;
    });

    try {
      final fundService = FundService();
      final data = await fundService.fetchNetWorthTrend(code);
      
      if (data.isNotEmpty) {
        if (mounted) setState(() {
          _fundExists = true;
          _validationError = null;
        });
      } else {
        if (mounted) setState(() {
          _fundExists = false;
          _validationError = '未找到该基金数据';
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _fundExists = false;
        _validationError = '基金不存在或网络错误';
      });
    } finally {
      if (mounted) setState(() {
        _isValidating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: CupertinoPopupSurface(
          isSurfacePainted: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey6,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '配置自定义基金',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        size: 24,
                        color: isDark 
                            ? CupertinoColors.white.withOpacity(0.6)
                            : CupertinoColors.systemGrey,
                      ),
                    ),
                  ],
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '基金代码',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: CupertinoTextField(
                            controller: _codeController,
                            placeholder: '输入6位基金代码',
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            inputFormatters: [IntegerInputFormatter(maxLength: 6)],
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            onChanged: (_) {
                              if (_validationError != null || _fundExists) {
                                if (mounted) setState(() {
                                  _validationError = null;
                                  _fundExists = false;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        GlassButton(
                          label: _isValidating ? '验证中' : '验证',
                          onPressed: _isValidating ? null : _validateFundCode,
                          isPrimary: false,
                          height: 40,
                          width: 70,
                        ),
                      ],
                    ),
                    
                    if (_validationError != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.exclamationmark_circle,
                            size: 16,
                            color: CupertinoColors.systemRed,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _validationError!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.systemRed,
                            ),
                          ),
                        ],
                      ),
                    ] else if (_fundExists) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.checkmark_circle,
                            size: 16,
                            color: CupertinoColors.systemGreen,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '基金存在，可以保存',
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.systemGreen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey6,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        label: '取消',
                        onPressed: () => Navigator.of(context).pop(),
                        isPrimary: false,
                        height: 44,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassButton(
                        label: '保存',
                        onPressed: _fundExists && !_isValidating
                            ? () {
                                widget.onConfirm(_codeController.text.trim());
                                Navigator.of(context).pop();
                              }
                            : null,
                        isPrimary: true,
                        height: 44,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

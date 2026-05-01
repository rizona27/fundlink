import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Divider;
import '../services/alert_service.dart';
import '../services/fund_service.dart';
import '../services/data_manager.dart';
import '../models/valuation_alert.dart';
import '../widgets/glass_button.dart';

/// 估值预警规则管理弹窗
class AlertEditDialog extends StatefulWidget {
  final ValuationAlert? alert; // null 表示新建

  const AlertEditDialog({super.key, this.alert});

  @override
  State<AlertEditDialog> createState() => _AlertEditDialogState();
}

class _AlertEditDialogState extends State<AlertEditDialog> {
  late DataManager _dataManager;
  late AlertService _alertService;
  
  final _fundCodeController = TextEditingController();
  String _fundName = '';
  final _thresholdUpController = TextEditingController();
  final _thresholdDownController = TextEditingController();
  
  bool _isEnabled = true;
  bool _isSubmitting = false;
  bool _isLoadingFundInfo = false;
  List<ValuationAlert> _alerts = [];
  String? _overwriteAlertId; // 用于存储要覆盖的规则ID

  @override
  void initState() {
    super.initState();
    if (widget.alert != null) {
      _fundCodeController.text = widget.alert!.fundCode;
      _fundName = widget.alert!.fundName;
      _thresholdUpController.text = widget.alert!.thresholdUp?.abs().toString() ?? '';
      _thresholdDownController.text = widget.alert!.thresholdDown?.abs().toString() ?? '';
      _isEnabled = widget.alert!.isEnabled;
    }
    
    // 添加监听器，当输入变化时更新UI
    _fundCodeController.addListener(_onFieldChanged);
    _thresholdUpController.addListener(_onFieldChanged);
    _thresholdDownController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) {
      setState(() {}); // 触发重建，更新按钮状态
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    final fundService = FundService(_dataManager);
    _alertService = AlertService(fundService);
    _alertService.initialize();
    _loadAlerts();
  }

  @override
  void dispose() {
    _fundCodeController.removeListener(_onFieldChanged);
    _thresholdUpController.removeListener(_onFieldChanged);
    _thresholdDownController.removeListener(_onFieldChanged);
    _fundCodeController.dispose();
    _thresholdUpController.dispose();
    _thresholdDownController.dispose();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    final alerts = await _alertService.getAllAlerts();
    if (mounted) {
      // 按基金代码从小到大排序
      alerts.sort((a, b) => a.fundCode.compareTo(b.fundCode));
      setState(() => _alerts = alerts);
    }
  }

  Future<void> _fetchFundName(String code) async {
    if (code.isEmpty || code.length < 6) {
      if (mounted) setState(() => _fundName = '');
      return;
    }

    if (mounted) setState(() => _isLoadingFundInfo = true);

    try {
      final fundService = FundService(_dataManager);
      final info = await fundService.fetchFundInfo(code);
      print('查询基金信息: $code, 结果: $info'); // 调试日志
      if (mounted && info.isNotEmpty) {
        setState(() {
          // API返回的字段是 fundName 而不是 name
          _fundName = info['fundName'] ?? info['name'] ?? '';
          _isLoadingFundInfo = false;
        });
        print('基金名称: $_fundName'); // 调试日志
      } else {
        if (mounted) {
          setState(() {
            _fundName = '';
            _isLoadingFundInfo = false;
          });
        }
      }
    } catch (e) {
      print('查询基金信息失败: $e'); // 调试日志
      if (mounted) {
        setState(() {
          _fundName = '';
          _isLoadingFundInfo = false;
        });
      }
    }
  }

  String? _validateThreshold(String? value) {
    if (value == null || value.isEmpty) return null;
    final num = double.tryParse(value);
    if (num == null) return '请输入有效数字';
    if (num <= 0 || num > 10) return '范围: 0.1-10';
    if (value.contains('.') && value.split('.')[1].length > 1) {
      return '最多一位小数';
    }
    return null;
  }

  Future<void> _deleteAlert(String id) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除规则'),
        content: const Text('确定要删除此预警规则吗？'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('删除'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _alertService.deleteAlert(id);
      await _loadAlerts();
    }
  }

  Future<void> _toggleAlert(ValuationAlert alert) async {
    await _alertService.toggleAlert(alert.id, !alert.isEnabled);
    await _loadAlerts();
  }

  /// 格式化基金显示：名称(代码)，名称超过6个汉字截断
  String _formatFundDisplay(String fundName, String fundCode) {
    if (fundName.isEmpty) return fundCode;
    
    // 计算汉字数量
    int chineseCharCount = 0;
    int cutIndex = 0;
    
    for (int i = 0; i < fundName.length; i++) {
      final char = fundName[i];
      // 判断是否为汉字
      if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(char)) {
        chineseCharCount++;
      }
      cutIndex = i + 1;
      
      // 当汉字数量达到6时，记录位置并继续检查是否还有更多汉字
      if (chineseCharCount == 6) {
        // 继续往后看是否还有汉字
        for (int j = i + 1; j < fundName.length; j++) {
          if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(fundName[j])) {
            // 还有第7个汉字，需要截断
            return '${fundName.substring(0, cutIndex)}...($fundCode)';
          }
        }
        // 没有更多汉字，不需要截断
        break;
      }
    }
    
    // 不超过6个汉字，直接显示
    return '$fundName($fundCode)';
  }

  Future<void> _save() async {
    // 验证基金代码
    if (_fundCodeController.text.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('提示'),
          content: const Text('请输入基金代码'),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }

    // 验证上涨阈值（必输）
    if (_thresholdUpController.text.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('提示'),
          content: const Text('请输入上涨阈值'),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }

    // 验证下跌阈值（必输）
    if (_thresholdDownController.text.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('提示'),
          content: const Text('请输入下跌阈值'),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }

    final upError = _validateThreshold(_thresholdUpController.text);
    final downError = _validateThreshold(_thresholdDownController.text);
    
    if (upError != null || downError != null) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('输入错误'),
          content: Text(upError ?? downError ?? ''),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }

    // 检查是否已存在相同基金代码的规则（新增时检查）
    if (widget.alert == null && _overwriteAlertId == null) {
      final existingAlert = _alerts.firstWhere(
        (alert) => alert.fundCode == _fundCodeController.text.trim(),
        orElse: () => ValuationAlert.empty(),
      );
      
      if (existingAlert.id.isNotEmpty) {
        // 提示用户是否覆盖
        final shouldOverwrite = await showCupertinoDialog<bool>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('规则已存在'),
            content: Text('基金 ${existingAlert.fundName.isNotEmpty ? existingAlert.fundName : existingAlert.fundCode} 已存在预警规则，是否覆盖？'),
            actions: [
              CupertinoDialogAction(
                child: const Text('取消'),
                onPressed: () => Navigator.pop(context, false),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                child: const Text('覆盖'),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        );
        
        if (shouldOverwrite != true) {
          return; // 用户取消，不继续
        }
        
        // 用户选择覆盖，记录要更新的ID
        _overwriteAlertId = existingAlert.id;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final thresholdUp = double.tryParse(_thresholdUpController.text);
      final thresholdDownRaw = double.tryParse(_thresholdDownController.text);
      // 下跌阈值自动转为负数
      final thresholdDown = thresholdDownRaw != null && thresholdDownRaw > 0
          ? -thresholdDownRaw
          : thresholdDownRaw;

      final alert = ValuationAlert(
        id: widget.alert?.id ?? _overwriteAlertId, // 使用覆盖ID或原有ID
        fundCode: _fundCodeController.text.trim(),
        fundName: _fundName,
        thresholdUp: thresholdUp,
        thresholdDown: thresholdDown,
        isEnabled: _isEnabled,
      );

      if (widget.alert != null || _overwriteAlertId != null) {
        // 更新已有规则（包括覆盖的情况）
        await _alertService.updateAlert(alert);
      } else {
        // 新增规则
        await _alertService.addAlert(alert);
      }
      
      // 添加完成后不关闭窗口，清空表单并刷新列表
      if (mounted) {
        setState(() {
          _fundCodeController.clear();
          _fundName = '';
          _thresholdUpController.clear();
          _thresholdDownController.clear();
          _isEnabled = true;
          _overwriteAlertId = null; // 重置覆盖ID
        });
        await _loadAlerts();
      }
    } catch (e) {
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('错误'),
            content: Text('保存失败: $e'),
            actions: [
              CupertinoDialogAction(
                child: const Text('确定'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white;
    final textColor = isDark ? CupertinoColors.white : CupertinoColors.label;
    final secondaryColor = isDark 
        ? CupertinoColors.white.withOpacity(0.6)
        : CupertinoColors.systemGrey;

    // 响应式布局：移动端使用垂直布局，桌面端使用左右分栏
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Center(
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 24, 
          vertical: isMobile ? 20 : 40,
        ),
        constraints: BoxConstraints(
          maxWidth: isMobile ? double.infinity : 600,
          maxHeight: isMobile ? 650 : 450, // 减小高度
        ),
        child: CupertinoPopupSurface(
          isSurfacePainted: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '估值预警管理',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    GestureDetector(
                      onTap: _isSubmitting ? null : () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? CupertinoColors.systemGrey.withOpacity(0.3)
                              : CupertinoColors.systemGrey.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.xmark,
                          size: 16,
                          color: textColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 内容区域
              Flexible(
                child: isMobile
                    ? _buildMobileLayout(isDark, textColor, secondaryColor)
                    : _buildDesktopLayout(isDark, textColor, secondaryColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 移动端垂直布局
  Widget _buildMobileLayout(bool isDark, Color textColor, Color secondaryColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAddForm(isDark, textColor, secondaryColor),
          const SizedBox(height: 20),
          _buildAlertList(isDark, textColor, secondaryColor),
        ],
      ),
    );
  }

  /// 桌面端左右分栏布局
  Widget _buildDesktopLayout(bool isDark, Color textColor, Color secondaryColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：添加规则表单
        Expanded(
          flex: 5,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: secondaryColor.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: SingleChildScrollView(
              child: _buildAddForm(isDark, textColor, secondaryColor),
            ),
          ),
        ),

        // 右侧：已添加的规则列表
        Expanded(
          flex: 6,
          child: Container(
            padding: const EdgeInsets.all(16),
            child: _buildAlertList(isDark, textColor, secondaryColor),
          ),
        ),
      ],
    );
  }

  /// 构建添加规则表单
  Widget _buildAddForm(bool isDark, Color textColor, Color secondaryColor) {
    // 检查是否可以提交（三个必填项都有值）
    final canSubmit = _fundCodeController.text.isNotEmpty &&
        _thresholdUpController.text.isNotEmpty &&
        _thresholdDownController.text.isNotEmpty;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题，与右侧对齐（移除额外padding，让Container的padding生效）
        Text(
          '添加规则',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 12),

        // 基金代码
        Row(
          children: [
            SizedBox(
              width: 60,
              child: Text('基金代码', 
                style: TextStyle(fontSize: 12, color: secondaryColor),
              ),
            ),
            Expanded(
              child: CupertinoTextField(
                controller: _fundCodeController,
                placeholder: '000001',
                placeholderStyle: TextStyle(color: secondaryColor, fontSize: 13),
                style: TextStyle(fontSize: 14, color: textColor),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                enabled: !_isSubmitting,
                onChanged: (value) {
                  if (value.length >= 6) _fetchFundName(value);
                },
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 10),

        // 基金名称反显
        Row(
          children: [
            SizedBox(
              width: 60,
              child: Text('基金名称', 
                style: TextStyle(fontSize: 12, color: secondaryColor),
              ),
            ),
            Expanded(
              child: Container(
                height: 32,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _isLoadingFundInfo
                    ? const SizedBox(width: 14, height: 14, child: CupertinoActivityIndicator(radius: 7))
                    : Text(
                        _fundName.isNotEmpty ? _fundName : '自动反显',
                        style: TextStyle(
                          fontSize: 13, 
                          color: _fundName.isNotEmpty ? textColor : secondaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 10),

        // 上涨阈值
        Row(
          children: [
            SizedBox(
              width: 60,
              child: Text('上涨%', 
                style: TextStyle(fontSize: 12, color: secondaryColor),
              ),
            ),
            Expanded(
              child: CupertinoTextField(
                controller: _thresholdUpController,
                placeholder: '3.0',
                placeholderStyle: TextStyle(color: secondaryColor, fontSize: 13),
                style: TextStyle(fontSize: 14, color: textColor),
                prefix: Icon(CupertinoIcons.arrow_up_right, size: 14, color: CupertinoColors.systemGreen),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                enabled: !_isSubmitting,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 10),

        // 下跌阈值
        Row(
          children: [
            SizedBox(
              width: 60,
              child: Text('下跌%', 
                style: TextStyle(fontSize: 12, color: secondaryColor),
              ),
            ),
            Expanded(
              child: CupertinoTextField(
                controller: _thresholdDownController,
                placeholder: '2.0',
                placeholderStyle: TextStyle(color: secondaryColor, fontSize: 13),
                style: TextStyle(fontSize: 14, color: textColor),
                prefix: Icon(CupertinoIcons.arrow_down_right, size: 14, color: CupertinoColors.systemRed),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                enabled: !_isSubmitting,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 12),

        // 启用开关
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.checkmark_seal_fill, 
                size: 16, 
                color: _isEnabled ? CupertinoColors.systemGreen : secondaryColor,
              ),
              const SizedBox(width: 6),
              Text('启用', style: TextStyle(fontSize: 13, color: textColor)),
              const Spacer(),
              CupertinoSwitch(
                value: _isEnabled,
                onChanged: _isSubmitting ? null : (value) => setState(() => _isEnabled = value),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 14),

        // 保存按钮（三个必填项都填写后才可点击）
        GlassButton(
          label: _isSubmitting ? '保存中...' : '添加规则',
          onPressed: (!_isSubmitting && canSubmit) ? _save : null,
          isPrimary: true,
          height: 38,
        ),
      ],
    );
  }

  /// 构建规则列表
  Widget _buildAlertList(bool isDark, Color textColor, Color secondaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题（外层Container已有padding，这里只需bottom间距）
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '已添加规则 (${_alerts.length})',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
        
        Expanded(
          child: _alerts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.bell_slash,
                        size: 48,
                        color: secondaryColor.withOpacity(0.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '暂无预警规则',
                        style: TextStyle(
                          fontSize: 14,
                          color: secondaryColor,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _alerts.length,
                  itemBuilder: (context, index) {
                    final alert = _alerts[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _formatFundDisplay(alert.fundName, alert.fundCode),
                                      style: TextStyle(
                                        fontSize: 13, 
                                        fontWeight: FontWeight.w500, 
                                        color: textColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              CupertinoSwitch(
                                value: alert.isEnabled,
                                onChanged: (value) => _toggleAlert(alert),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => _deleteAlert(alert.id),
                                child: Icon(
                                  CupertinoIcons.trash, 
                                  size: 16, 
                                  color: CupertinoColors.systemRed,
                                ),
                              ),
                            ],
                          ),
                          if (alert.thresholdUp != null || alert.thresholdDown != null) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: [
                                if (alert.thresholdUp != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: CupertinoColors.systemRed.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '涨 ${alert.thresholdUp}%',
                                      style: const TextStyle(
                                        color: CupertinoColors.systemRed, 
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                if (alert.thresholdDown != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: CupertinoColors.systemGreen.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '跌 ${alert.thresholdDown!.abs()}%',
                                      style: const TextStyle(
                                        color: CupertinoColors.systemGreen, 
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

import 'package:flutter/cupertino.dart';
import '../services/data_manager.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../widgets/toast.dart';
import '../widgets/glass_button.dart';
import '../utils/input_formatters.dart';

class BatchRenameDialog extends StatefulWidget {
  final String clientKey;
  final String currentName;
  final List<FundHolding> holdings;

  const BatchRenameDialog({
    super.key,
    required this.clientKey,
    required this.currentName,
    required this.holdings,
  });

  @override
  State<BatchRenameDialog> createState() => _BatchRenameDialogState();
}

class _BatchRenameDialogState extends State<BatchRenameDialog> {
  late DataManager _dataManager;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.currentName;
    _idController.text = widget.holdings.first.clientId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  Future<void> _handleRename() async {
    final newName = _nameController.text.trim();
    final newId = _idController.text.trim();
    
    if (newName.isEmpty) {
      context.showToast('客户姓名不能为空');
      return;
    }

    if (newName == widget.currentName && newId == widget.holdings.first.clientId) {
      context.showToast('信息未发生变化');
      return;
    }

    // 检查是否有其他客户使用相同的名称
    final allClientNames = _dataManager.holdings
        .map((h) => h.clientName)
        .where((name) => name != widget.currentName)
        .toSet();
    
    if (allClientNames.contains(newName)) {
      // 找到使用该名称的所有持仓（排除当前正在重命名的这些持仓）
      final currentHoldingIds = widget.holdings.map((h) => h.id).toSet();
      final existingHoldings = _dataManager.holdings
          .where((h) => h.clientName == newName && !currentHoldingIds.contains(h.id))
          .toList();
      
      if (existingHoldings.isNotEmpty) {
        final shouldMerge = await _showMergeConfirmDialog(newName, existingHoldings);
        if (shouldMerge != true) {
          return; // 用户取消或选择不合并
        }
      }
    }

    setState(() => _isProcessing = true);

    try {
      int updatedCount = 0;
      for (final holding in widget.holdings) {
        final updated = holding.copyWith(
          clientName: newName,
          clientId: newId,
        );
        await _dataManager.updateHolding(updated);
        updatedCount++;
      }

      await _dataManager.addLog(
        '批量编辑客户: ${widget.currentName} -> $newName (共$updatedCount条记录)',
        type: LogType.info,
      );

      if (mounted) {
        context.showToast('已成功修改 $updatedCount 条记录');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        context.showToast('重命名失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<bool?> _showMergeConfirmDialog(String newName, List<FundHolding> existingHoldings) async {
    final existingClientIds = existingHoldings.map((h) => h.clientId).toSet();
    final existingClientId = existingClientIds.length == 1 ? existingClientIds.first : '';
    
    return await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('检测到同名客户'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '客户 "$newName" 已存在',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (existingClientId.isNotEmpty) ...[
              Text(
                '原客户号: $existingClientId',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              '现有持仓: ${existingHoldings.length} 条记录',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              '当前操作将把 ${widget.holdings.length} 条记录的客户名也改为 "$newName"。\n\n' 
              '这会导致两个不同客户的持仓在显示上合并（但客户号不同，数据仍独立）。\n\n' 
              '是否继续？',
              style: TextStyle(fontSize: 12),
            ),
          ],
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
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white;
    final textColor = isDark ? CupertinoColors.white : CupertinoColors.label;
    final secondaryColor = isDark 
        ? CupertinoColors.white.withOpacity(0.6)
        : CupertinoColors.systemGrey;

    return GestureDetector(
      onTap: () {
        // 点击空白处收起键盘
        FocusScope.of(context).unfocus();
      },
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            // ✅ 添加键盘避让
            padding: MediaQuery.of(context).viewInsets,
            child: CupertinoPopupSurface(
              isSurfacePainted: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题栏
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '编辑',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? CupertinoColors.systemGrey.withOpacity(0.3)
                                  : CupertinoColors.systemGrey.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.xmark,
                              size: 14,
                              color: textColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 内容区域
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: bgColor,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 影响范围提示
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.info_circle_fill,
                                color: CupertinoColors.activeBlue,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '影响范围: ${widget.holdings.length} 条持仓记录',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CupertinoColors.activeBlue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 客户姓名输入框
                        Text(
                          '客户姓名',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: secondaryColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: CupertinoTextField(
                            controller: _nameController,
                            placeholder: '请输入客户姓名',
                            placeholderStyle: TextStyle(
                              color: secondaryColor,
                              fontSize: 14,
                            ),
                            style: TextStyle(
                              fontSize: 15,
                              color: textColor,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            autofocus: true,
                            clearButtonMode: OverlayVisibilityMode.editing,
                            inputFormatters: [ClientNameInputFormatter()],
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 客户号输入框
                        Text(
                          '客户号（选填）',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: secondaryColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: CupertinoTextField(
                            controller: _idController,
                            placeholder: '请输入客户号',
                            placeholderStyle: TextStyle(
                              color: secondaryColor,
                              fontSize: 14,
                            ),
                            style: TextStyle(
                              fontSize: 15,
                              color: textColor,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            clearButtonMode: OverlayVisibilityMode.editing,
                            keyboardType: TextInputType.number,
                            inputFormatters: [ClientIdInputFormatter()],
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 确认按钮 - 横向排列
                        Row(
                          children: [
                            Expanded(
                              child: GlassButton(
                                label: '取消',
                                onPressed: _isProcessing ? null : () => Navigator.pop(context),
                                isPrimary: false,
                                height: 40,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GlassButton(
                                label: _isProcessing ? '处理中...' : '确认修改',
                                onPressed: _isProcessing ? null : _handleRename,
                                isPrimary: true,
                                height: 40,
                              ),
                            ),
                          ],
                        ),
                  ],
                ),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

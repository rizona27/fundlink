import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Divider, Scrollbar;
import '../services/data_manager.dart';
import '../models/log_entry.dart';
import '../widgets/adaptive_top_bar.dart';

class LogView extends StatefulWidget {
  const LogView({super.key});

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> with SingleTickerProviderStateMixin {
  late DataManager _dataManager;
  Set<LogType> _selectedLogTypes = {};
  late AnimationController _fadeController;

  double _scrollOffset = 0;

  // 滚动控制器
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..forward();
    // 默认全选
    _selectedLogTypes = LogType.values.toSet();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 获取所有筛选后的日志（按时间倒序）
  List<LogEntry> get _filteredLogs {
    if (_selectedLogTypes.isEmpty) return [];
    return _dataManager.logs
        .where((log) => _selectedLogTypes.contains(log.type))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  bool get _isAllSelected => _selectedLogTypes.length == LogType.values.length;

  void _toggleAllSelection() {
    setState(() {
      if (_isAllSelected) {
        _selectedLogTypes.clear();
      } else {
        _selectedLogTypes = LogType.values.toSet();
      }
    });
  }

  void _clearAllLogs() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('清空日志'),
        content: const Text('确定要清空所有日志吗？此操作不可撤销。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            isDestructiveAction: true,
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _dataManager.clearAllLogs();
      setState(() {});
    }
  }

  void _toggleLogType(LogType type) {
    setState(() {
      if (_selectedLogTypes.contains(type)) {
        _selectedLogTypes.remove(type);
      } else {
        _selectedLogTypes.add(type);
      }
    });
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  Color _getLogTextColor(LogType type, bool isDarkMode) {
    switch (type) {
      case LogType.success:
        return const Color(0xFF34C759);
      case LogType.error:
        return const Color(0xFFFF3B30);
      case LogType.warning:
        return const Color(0xFFFF9500);
      case LogType.info:
        return isDarkMode ? CupertinoColors.white : CupertinoColors.label;
      case LogType.network:
        return const Color(0xFF5856D6);
      case LogType.cache:
        return const Color(0xFFFF2D55);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    return CupertinoPageScaffold(
      backgroundColor: Colors.transparent,
      child: Container(
        color: backgroundColor,
        child: SafeArea(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
                setState(() {
                  _scrollOffset = notification.metrics.pixels;
                });
              }
              return false;
            },
            child: Column(
              children: [
                AdaptiveTopBar(
                  scrollOffset: _scrollOffset,
                  showBack: true,
                  onBack: () => Navigator.of(context).pop(),
                  showRefresh: false,
                  showExpandCollapse: false,
                  showSearch: false,
                  showReset: false,
                  showFilter: false,
                  showSort: false,
                  isAllExpanded: false,
                  searchText: '',
                  dataManager: _dataManager,
                  fundService: null,
                  onToggleExpandAll: null,
                  onSearchChanged: null,
                  onSearchClear: null,
                  backgroundColor: Colors.transparent,
                  iconColor: CupertinoTheme.of(context).primaryColor,
                  iconSize: 24,
                  buttonSpacing: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeController,
                    child: Column(
                      children: [
                        _buildFilterSection(isDarkMode),
                        Expanded(
                          child: _buildContent(isDarkMode),
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

  Widget _buildFilterSection(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode
            ? CupertinoColors.systemGrey6.withOpacity(0.4)
            : CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode
              ? CupertinoColors.white.withOpacity(0.1)
              : CupertinoColors.systemGrey4.withOpacity(0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '筛选',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                ),
              ),
              const SizedBox(width: 12),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _toggleAllSelection,
                child: Text(
                  _isAllSelected ? '取消全选' : '全选',
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFF6366F1),
                  ),
                ),
              ),
              const Spacer(),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _clearAllLogs,
                child: Text(
                  '清空日志',
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.systemRed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 第一行：成功、错误、警告 - 三等分但不改变按钮大小
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLogTypeButton(LogType.success, isDarkMode),
              _buildLogTypeButton(LogType.error, isDarkMode),
              _buildLogTypeButton(LogType.warning, isDarkMode),
            ],
          ),
          const SizedBox(height: 6),
          // 第二行：信息、网络、缓存 - 三等分但不改变按钮大小
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLogTypeButton(LogType.info, isDarkMode),
              _buildLogTypeButton(LogType.network, isDarkMode),
              _buildLogTypeButton(LogType.cache, isDarkMode),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogTypeButton(LogType type, bool isDarkMode) {
    final isSelected = _selectedLogTypes.contains(type);
    final color = type.color;

    return GestureDetector(
      onTap: () => _toggleLogType(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(isDarkMode ? 0.25 : 0.12)
              : (isDarkMode ? CupertinoColors.systemGrey5.withOpacity(0.3) : CupertinoColors.systemGrey6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              type.displayName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? color
                    : (isDarkMode ? CupertinoColors.white : CupertinoColors.label),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool isDarkMode) {
    final logs = _filteredLogs;

    if (_dataManager.logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.doc_text,
              size: 64,
              color: isDarkMode
                  ? CupertinoColors.white.withOpacity(0.3)
                  : CupertinoColors.systemGrey.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无日志',
              style: TextStyle(
                fontSize: 16,
                color: isDarkMode
                    ? CupertinoColors.white.withOpacity(0.5)
                    : CupertinoColors.systemGrey,
              ),
            ),
          ],
        ),
      );
    }

    if (_selectedLogTypes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.slider_horizontal_3,
              size: 64,
              color: isDarkMode
                  ? CupertinoColors.white.withOpacity(0.3)
                  : CupertinoColors.systemGrey.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '请至少选择一种日志类型',
              style: TextStyle(
                fontSize: 16,
                color: isDarkMode
                    ? CupertinoColors.white.withOpacity(0.5)
                    : CupertinoColors.systemGrey,
              ),
            ),
          ],
        ),
      );
    }

    if (logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.doc_text,
              size: 64,
              color: isDarkMode
                  ? CupertinoColors.white.withOpacity(0.3)
                  : CupertinoColors.systemGrey.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '没有符合条件的日志',
              style: TextStyle(
                fontSize: 16,
                color: isDarkMode
                    ? CupertinoColors.white.withOpacity(0.5)
                    : CupertinoColors.systemGrey,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode
            ? CupertinoColors.systemGrey6.withOpacity(0.4)
            : CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: CupertinoColors.activeBlue,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '日志记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                  ),
                ),
                const Spacer(),
                Text(
                  '(${logs.length})',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDarkMode
                        ? CupertinoColors.white.withOpacity(0.5)
                        : CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 0, indent: 12, endIndent: 12),
          // 日志列表 - 使用 Expanded 让内容填充可用空间，添加滚动条
          Expanded(
            child: CupertinoScrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: logs.asMap().entries.map((entry) =>
                      _buildLogItem(entry.value, entry.key, logs.length, isDarkMode)
                  ).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(LogEntry log, int index, int totalCount, bool isDarkMode) {
    final textColor = _getLogTextColor(log.type, isDarkMode);
    final timeStr = _formatTimestamp(log.timestamp);
    final typeStr = log.type.displayName;
    final typeColor = log.type.color;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 类型标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  typeStr,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: typeColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 时间戳
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  color: isDarkMode
                      ? CupertinoColors.white.withOpacity(0.4)
                      : CupertinoColors.systemGrey,
                ),
              ),
              const SizedBox(width: 10),
              // 日志内容
              Expanded(
                child: Text(
                  log.message,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: textColor,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // 虚线分割线（最后一条不显示）
        if (index != totalCount - 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Divider(
              height: 0,
              thickness: 0.5,
              color: isDarkMode
                  ? CupertinoColors.white.withOpacity(0.1)
                  : CupertinoColors.systemGrey4.withOpacity(0.5),
            ),
          ),
      ],
    );
  }
}
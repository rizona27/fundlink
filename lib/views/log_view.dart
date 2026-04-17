import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Divider;
import '../services/data_manager.dart';
import '../models/log_entry.dart';
import '../widgets/adaptive_top_bar.dart';

class LogView extends StatefulWidget {
  const LogView({super.key});

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> with TickerProviderStateMixin {
  late DataManager _dataManager;
  Set<LogType> _selectedLogTypes = {};
  late AnimationController _fadeController;

  double _scrollOffset = 0;

  // 分页加载相关
  static const int _pageSize = 20;
  int _displayCount = 20;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  // 滚动控制器
  final ScrollController _scrollController = ScrollController();

  // 存储每个日志项的动画控制器
  final Map<String, AnimationController> _itemControllers = {};

  // 动画队列管理
  bool _isAnimating = false;
  List<LogEntry> _currentDisplayedLogs = [];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..forward();

    _selectedLogTypes = LogType.values.toSet();
    _scrollController.addListener(_onScroll);
    // 延迟初始化，等待 didChangeDependencies
    _currentDisplayedLogs = [];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    // 初始化当前显示的日志
    _currentDisplayedLogs = _getFilteredLogs();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    for (var controller in _itemControllers.values) {
      controller.dispose();
    }
    _itemControllers.clear();
    super.dispose();
  }

  List<LogEntry> _getFilteredLogs() {
    if (_selectedLogTypes.isEmpty) return [];
    final logs = _dataManager.logs
        .where((log) => _selectedLogTypes.contains(log.type))
        .toList();
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return logs.take(_displayCount).toList();
  }

  List<LogEntry> get _allFilteredLogs {
    if (_selectedLogTypes.isEmpty) return [];
    final logs = _dataManager.logs
        .where((log) => _selectedLogTypes.contains(log.type))
        .toList();
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return logs;
  }

  bool get _isAllSelected => _selectedLogTypes.length == LogType.values.length;

  void _toggleAllSelection() async {
    final newSelectedTypes = _isAllSelected
        ? <LogType>{}
        : LogType.values.toSet();
    await _animateLogTypeChange(newSelectedTypes);
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

    if (confirmed == true && mounted) {
      await _dataManager.clearAllLogs();
      if (mounted) {
        setState(() {
          _resetPagination();
          _currentDisplayedLogs = _getFilteredLogs();
        });
      }
    }
  }

  void _toggleLogType(LogType type) async {
    final newSelectedTypes = Set<LogType>.from(_selectedLogTypes);
    if (newSelectedTypes.contains(type)) {
      newSelectedTypes.remove(type);
    } else {
      newSelectedTypes.add(type);
    }
    await _animateLogTypeChange(newSelectedTypes);
  }

  Future<void> _animateLogTypeChange(Set<LogType> newSelectedTypes) async {
    if (_isAnimating) return;
    _isAnimating = true;

    // 获取当前显示的日志和新日志
    final oldLogs = _currentDisplayedLogs;
    final newLogs = _getNewFilteredLogs(newSelectedTypes);

    // 找出需要淡出的日志（在旧列表中但不在新列表中）
    final oldLogIds = oldLogs.map((l) => l.id).toSet();
    final newLogIds = newLogs.map((l) => l.id).toSet();
    final toRemove = oldLogIds.difference(newLogIds);
    final toAdd = newLogIds.difference(oldLogIds);

    // 为需要淡出的日志执行淡出动画
    final fadeOutFutures = <Future>[];
    for (var id in toRemove) {
      if (_itemControllers.containsKey(id)) {
        fadeOutFutures.add(_itemControllers[id]!.reverse().orCancel);
      }
    }

    // 等待淡出动画完成
    if (fadeOutFutures.isNotEmpty) {
      await Future.wait(fadeOutFutures);
    }

    // 更新状态
    setState(() {
      _selectedLogTypes = newSelectedTypes;
      _resetPagination();
      _currentDisplayedLogs = _getFilteredLogs();
    });

    // 清理已移除日志的动画控制器
    final currentLogIds = _currentDisplayedLogs.map((l) => l.id).toSet();
    for (var id in _itemControllers.keys.toList()) {
      if (!currentLogIds.contains(id)) {
        _itemControllers[id]?.dispose();
        _itemControllers.remove(id);
      }
    }

    // 为新增的日志创建动画控制器并淡入
    final fadeInFutures = <Future>[];
    for (var id in toAdd) {
      if (!_itemControllers.containsKey(id)) {
        _itemControllers[id] = AnimationController(
          duration: const Duration(milliseconds: 200),
          vsync: this,
        );
        fadeInFutures.add(_itemControllers[id]!.forward().orCancel);
      }
    }

    // 等待淡入动画完成
    if (fadeInFutures.isNotEmpty) {
      await Future.wait(fadeInFutures);
    }

    _isAnimating = false;
  }

  List<LogEntry> _getNewFilteredLogs(Set<LogType> newTypes) {
    if (newTypes.isEmpty) return [];
    final logs = _dataManager.logs
        .where((log) => newTypes.contains(log.type))
        .toList();
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return logs.take(_displayCount).toList();
  }

  void _resetPagination() {
    _displayCount = _pageSize;
    _hasMore = true;
    _isLoadingMore = false;
  }

  void _loadMore() {
    if (_isLoadingMore || !_hasMore) return;

    final totalCount = _allFilteredLogs.length;
    if (_displayCount >= totalCount) {
      _hasMore = false;
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    Future.microtask(() {
      if (mounted) {
        setState(() {
          _displayCount = (_displayCount + _pageSize).clamp(0, totalCount);
          _currentDisplayedLogs = _getFilteredLogs();
          _isLoadingMore = false;
          _hasMore = _displayCount < totalCount;
        });
      }
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  /// 获取或创建日志项的动画控制器
  AnimationController _getItemController(String logId) {
    if (!_itemControllers.containsKey(logId)) {
      _itemControllers[logId] = AnimationController(
        duration: const Duration(milliseconds: 200),
        vsync: this,
      )..value = 1.0;
    }
    return _itemControllers[logId]!;
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

    final logs = _currentDisplayedLogs;
    final totalCount = _allFilteredLogs.length;

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
                          child: _buildContent(isDarkMode, logs, totalCount),
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
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 85,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _isAllSelected
                          ? [const Color(0xFF6366F1), const Color(0xFF8B5CF6)]
                          : [CupertinoColors.systemGrey5.withOpacity(0.5), CupertinoColors.systemGrey5.withOpacity(0.3)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isAllSelected
                          ? const Color(0xFF6366F1).withOpacity(0.5)
                          : CupertinoColors.systemGrey4.withOpacity(0.5),
                      width: 0.5,
                    ),
                  ),
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    minSize: 0,
                    onPressed: _toggleAllSelection,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isAllSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                          size: 14,
                          color: _isAllSelected ? CupertinoColors.white : CupertinoColors.systemGrey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isAllSelected ? '取消全选' : '全选',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _isAllSelected ? CupertinoColors.white : CupertinoColors.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [CupertinoColors.systemRed.withOpacity(0.15), CupertinoColors.systemRed.withOpacity(0.08)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: CupertinoColors.systemRed.withOpacity(0.3),
                      width: 0.5,
                    ),
                  ),
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    minSize: 0,
                    onPressed: _clearAllLogs,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          CupertinoIcons.trash,
                          size: 14,
                          color: CupertinoColors.systemRed,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '清空日志',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: CupertinoColors.systemRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 50,
            color: isDarkMode
                ? CupertinoColors.white.withOpacity(0.1)
                : CupertinoColors.systemGrey4.withOpacity(0.5),
            margin: const EdgeInsets.symmetric(horizontal: 8),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildLogTypeButton(LogType.success, isDarkMode),
                    _buildLogTypeButton(LogType.error, isDarkMode),
                    _buildLogTypeButton(LogType.warning, isDarkMode),
                  ],
                ),
                const SizedBox(height: 6),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(isDarkMode ? 0.25 : 0.12)
              : (isDarkMode ? CupertinoColors.systemGrey5.withOpacity(0.3) : CupertinoColors.systemGrey6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              type.displayName,
              style: TextStyle(
                fontSize: 12,
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

  Widget _buildContent(bool isDarkMode, List<LogEntry> logs, int totalCount) {
    if (_dataManager.logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.doc_text, size: 64,
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
            Icon(CupertinoIcons.slider_horizontal_3, size: 64,
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
            Icon(CupertinoIcons.doc_text, size: 64,
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: CupertinoColors.activeBlue,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '日志记录',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                  ),
                ),
                const Spacer(),
                Text(
                  '(${totalCount})',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode
                        ? CupertinoColors.white.withOpacity(0.5)
                        : CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 0, indent: 10, endIndent: 10),
          Expanded(
            child: CupertinoScrollbar(
              controller: _scrollController,
              child: ListView.builder(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                itemCount: logs.length + (_isLoadingMore ? 1 : 0) + (!_hasMore && totalCount > _pageSize ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_isLoadingMore && index == logs.length) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CupertinoActivityIndicator()),
                    );
                  }
                  if (!_hasMore && totalCount > _pageSize && index == logs.length) {
                    return Padding(
                      padding: const EdgeInsets.all(10),
                      child: Center(
                        child: Text(
                          '已加载全部 $totalCount 条日志',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDarkMode
                                ? CupertinoColors.white.withOpacity(0.4)
                                : CupertinoColors.systemGrey,
                          ),
                        ),
                      ),
                    );
                  }
                  final log = logs[index];
                  final animationController = _getItemController(log.id);
                  return FadeTransition(
                    opacity: animationController,
                    child: _buildLogItem(log, index, logs.length, isDarkMode),
                  );
                },
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
              const SizedBox(width: 8),
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  color: isDarkMode
                      ? CupertinoColors.white.withOpacity(0.4)
                      : CupertinoColors.systemGrey,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  log.message,
                  style: TextStyle(
                    fontSize: 12,
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
        if (index != totalCount - 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
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
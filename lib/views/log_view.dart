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

class _LogViewState extends State<LogView> {
  late DataManager _dataManager;
  Set<LogType> _selectedLogTypes = {};
  String _searchKeyword = '';

  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 20;
  int _displayCount = 20;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _selectedLogTypes = LogType.values.toSet();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  List<LogEntry> _getFilteredLogs() {
    if (_selectedLogTypes.isEmpty) return [];

    var logs = _dataManager.logs
        .where((log) => _selectedLogTypes.contains(log.type))
        .toList();

    if (_searchKeyword.isNotEmpty) {
      final keyword = _searchKeyword.toLowerCase();
      logs = logs.where((log) =>
      log.message.toLowerCase().contains(keyword) ||
          log.type.displayName.contains(keyword)
      ).toList();
    }

    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return logs;
  }

  List<LogEntry> get _displayedLogs {
    final allLogs = _getFilteredLogs();
    return allLogs.take(_displayCount).toList();
  }

  bool get _hasMore {
    return _displayCount < _getFilteredLogs().length;
  }

  bool get _isAllSelected => _selectedLogTypes.length == LogType.values.length;

  void _toggleAllSelection() {
    setState(() {
      _selectedLogTypes = _isAllSelected ? <LogType>{} : LogType.values.toSet();
      _resetPagination();
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

    if (confirmed == true && mounted) {
      await _dataManager.clearAllLogs();
      if (mounted) {
        setState(() {
          _resetPagination();
        });
      }
    }
  }

  void _toggleLogType(LogType type) {
    setState(() {
      if (_selectedLogTypes.contains(type)) {
        _selectedLogTypes.remove(type);
      } else {
        _selectedLogTypes.add(type);
      }
      _resetPagination();
    });
  }

  void _resetPagination() {
    _displayCount = _pageSize;
    _isLoadingMore = false;
  }

  void _loadMore() {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      setState(() {
        _displayCount += _pageSize;
        _isLoadingMore = false;
      });
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
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
        return isDarkMode ? const Color(0xFFBF5AF2) : const Color(0xFF5856D6); // 深色模式用更亮的紫色
      case LogType.cache:
        return isDarkMode ? const Color(0xFFFF375F) : const Color(0xFFFF2D55); // 深色模式用更亮的红色
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final displayedLogs = _displayedLogs;
    final totalCount = _getFilteredLogs().length;

    return CupertinoPageScaffold(
      backgroundColor: backgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            AdaptiveTopBar(
              scrollOffset: 0,
              showBack: true,
              onBack: () => Navigator.of(context).pop(),
              showRefresh: false,
              showExpandCollapse: false,
              showSearch: true,
              showReset: false,
              showFilter: false,
              showSort: false,
              isAllExpanded: false,
              searchText: _searchKeyword,
              searchPlaceholder: '搜索日志内容或类型',
              dataManager: _dataManager,
              fundService: null,
              onToggleExpandAll: null,
              onSearchChanged: (value) {
                setState(() {
                  _searchKeyword = value;
                  _resetPagination();
                });
              },
              onSearchClear: () {
                setState(() {
                  _searchKeyword = '';
                  _resetPagination();
                });
              },
              backgroundColor: backgroundColor,
              iconColor: CupertinoTheme.of(context).primaryColor,
              iconSize: 24,
              buttonSpacing: 12,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildFilterSection(isDarkMode),
                  ),
                  _buildContent(isDarkMode, displayedLogs, totalCount),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(16),
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
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: LogType.values.map((type) {
                    return _buildLogTypeChip(type, isDarkMode);
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: _isAllSelected
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  label: _isAllSelected ? '取消全选' : '全选',
                  gradient: _isAllSelected
                      ? [const Color(0xFF6366F1), const Color(0xFF8B5CF6)]
                      : null,
                  textColor: _isAllSelected
                      ? CupertinoColors.white
                      : (isDarkMode ? CupertinoColors.white : CupertinoColors.label),
                  onPressed: _toggleAllSelection,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: CupertinoIcons.trash,
                  label: '清空日志',
                  gradient: [
                    CupertinoColors.systemRed.withOpacity(0.15),
                    CupertinoColors.systemRed.withOpacity(0.08)
                  ],
                  textColor: CupertinoColors.systemRed,
                  borderColor: CupertinoColors.systemRed.withOpacity(0.3),
                  onPressed: _clearAllLogs,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogTypeChip(LogType type, bool isDarkMode) {
    final isSelected = _selectedLogTypes.contains(type);
    final color = type.color;

    return GestureDetector(
      onTap: () => _toggleLogType(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(isDarkMode ? 0.25 : 0.12)
              : (isDarkMode
              ? CupertinoColors.systemGrey5.withOpacity(0.3)
              : CupertinoColors.systemGrey6),
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
            const SizedBox(width: 6),
            Text(
              type.displayName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? color
                    : (isDarkMode
                    ? CupertinoColors.white
                    : CupertinoColors.label),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required List<Color>? gradient,
    required Color textColor,
    required VoidCallback onPressed,
    Color? borderColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient != null
            ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        )
            : null,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor ??
              (gradient != null
                  ? gradient.first.withOpacity(0.5)
                  : CupertinoColors.systemGrey4.withOpacity(0.5)),
          width: 0.5,
        ),
      ),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minSize: 0,
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool isDarkMode, List<LogEntry> logs, int totalCount) {
    if (_dataManager.logs.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.doc_text,
                size: 64,
                color: isDarkMode
                    ? CupertinoColors.systemGrey
                    : CupertinoColors.systemGrey3,
              ),
              const SizedBox(height: 16),
              Text(
                '暂无日志',
                style: TextStyle(
                  fontSize: 16,
                  color: isDarkMode
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.systemGrey2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedLogTypes.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.slider_horizontal_3,
                size: 64,
                color: isDarkMode
                    ? CupertinoColors.systemGrey
                    : CupertinoColors.systemGrey3,
              ),
              const SizedBox(height: 16),
              Text(
                '请至少选择一种日志类型',
                style: TextStyle(
                  fontSize: 16,
                  color: isDarkMode
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.systemGrey2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (logs.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.search,
                size: 64,
                color: isDarkMode
                    ? CupertinoColors.systemGrey
                    : CupertinoColors.systemGrey3,
              ),
              const SizedBox(height: 16),
              Text(
                '没有符合条件的日志',
                style: TextStyle(
                  fontSize: 16,
                  color: isDarkMode
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.systemGrey2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          if (index >= logs.length) {
            if (_isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CupertinoActivityIndicator()),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  '已加载全部 $totalCount 条日志',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDarkMode
                        ? CupertinoColors.systemGrey
                        : CupertinoColors.systemGrey2,
                  ),
                ),
              ),
            );
          }

          final log = logs[index];
          return _buildLogItem(log, index, logs.length, isDarkMode);
        },
        childCount: logs.length + (_hasMore || _isLoadingMore ? 1 : 0),
      ),
    );
  }

  Widget _buildLogItem(LogEntry log, int index, int totalCount, bool isDarkMode) {
    final textColor = _getLogTextColor(log.type, isDarkMode);
    final timeStr = _formatTimestamp(log.timestamp);
    final typeStr = log.type.displayName;
    final typeColor = log.type.color;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDarkMode
            ? CupertinoColors.systemGrey6.withOpacity(0.3)
            : CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDarkMode
              ? CupertinoColors.white.withOpacity(0.08)
              : CupertinoColors.systemGrey4.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  typeStr,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: typeColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 11,
                  color: isDarkMode
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.systemGrey2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            log.message,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

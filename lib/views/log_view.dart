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
  late AnimationController _pageFadeController;

  double _scrollOffset = 0;

  static const int _pageSize = 10;
  int _displayCount = 10;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  final ScrollController _scrollController = ScrollController();

  final Map<String, AnimationController> _fadeControllers = {};
  final Map<String, AnimationController> _sizeControllers = {};

  bool _isAnimating = false;
  List<LogEntry> _targetLogs = [];

  static const Duration _fadeDuration = Duration(milliseconds: 200);
  static const Duration _sizeDuration = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    _pageFadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    )..forward();

    _selectedLogTypes = LogType.values.toSet();
    _scrollController.addListener(_onScroll);
    _targetLogs = [];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _targetLogs = _getFilteredLogs();
  }

  @override
  void dispose() {
    _pageFadeController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _disposeAllControllers();
    super.dispose();
  }

  void _disposeAllControllers() {
    for (var controller in _fadeControllers.values) {
      controller.dispose();
    }
    for (var controller in _sizeControllers.values) {
      controller.dispose();
    }
    _fadeControllers.clear();
    _sizeControllers.clear();
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

  void _toggleAllSelection() {
    if (_isAnimating) return;
    final newTypes = _isAllSelected ? <LogType>{} : LogType.values.toSet();
    _startTypeChangeAnimation(newTypes);
  }

  void _clearAllLogs() async {
    if (_isAnimating) return;

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
          _targetLogs = _getFilteredLogs();
        });
        _disposeAllControllers();
      }
    }
  }

  void _toggleLogType(LogType type) {
    if (_isAnimating) return;
    final newTypes = Set<LogType>.from(_selectedLogTypes);
    if (newTypes.contains(type)) {
      newTypes.remove(type);
    } else {
      newTypes.add(type);
    }
    _startTypeChangeAnimation(newTypes);
  }

  void _startTypeChangeAnimation(Set<LogType> newTypes) async {
    if (_isAnimating) return;
    _isAnimating = true;

    final oldLogs = _targetLogs;
    final newLogs = _getNewFilteredLogs(newTypes);

    final oldIds = oldLogs.map((l) => l.id).toSet();
    final newIds = newLogs.map((l) => l.id).toSet();
    final toRemove = oldIds.difference(newIds).toList();
    final toAdd = newIds.difference(oldIds).toList();

    if (toRemove.isNotEmpty) {
      await _animateRemoval(toRemove);
    }

    if (!mounted) return;

    setState(() {
      _selectedLogTypes = newTypes;
      _resetPagination();
      _targetLogs = _getFilteredLogs();
    });

    _cleanupControllers(newIds);

    if (toAdd.isNotEmpty) {
      await _animateAddition(toAdd);
    }

    _isAnimating = false;
  }

  Future<void> _animateRemoval(List<String> ids) async {
    final futures = <Future>[];
    for (var id in ids) {
      final fadeCtrl = _fadeControllers[id];
      if (fadeCtrl != null && fadeCtrl.isAnimating == false) {
        futures.add(fadeCtrl.reverse().orCancel);
      }
      var sizeCtrl = _sizeControllers[id];
      if (sizeCtrl == null) {
        sizeCtrl = AnimationController(
          duration: _sizeDuration,
          vsync: this,
        )..value = 1.0;
        _sizeControllers[id] = sizeCtrl;
      }
      if (sizeCtrl.isAnimating == false) {
        futures.add(sizeCtrl.reverse().orCancel);
      }
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  Future<void> _animateAddition(List<String> ids) async {
    for (var id in ids) {
      if (!_sizeControllers.containsKey(id)) {
        _sizeControllers[id] = AnimationController(
          duration: _sizeDuration,
          vsync: this,
        )..value = 0.0;
      } else {
        _sizeControllers[id]!.value = 0.0;
      }
      if (!_fadeControllers.containsKey(id)) {
        _fadeControllers[id] = AnimationController(
          duration: _fadeDuration,
          vsync: this,
        )..value = 0.0;
      } else {
        _fadeControllers[id]!.value = 0.0;
      }
    }

    await Future.delayed(Duration.zero);

    if (!mounted) return;

    final futures = <Future>[];
    for (var id in ids) {
      final sizeCtrl = _sizeControllers[id];
      if (sizeCtrl != null && sizeCtrl.isAnimating == false) {
        futures.add(sizeCtrl.forward().orCancel);
      }
      final fadeCtrl = _fadeControllers[id];
      if (fadeCtrl != null && fadeCtrl.isAnimating == false) {
        futures.add(fadeCtrl.forward().orCancel);
      }
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  void _cleanupControllers(Set<String> currentIds) {
    final toRemove = <String>[];
    for (var id in _fadeControllers.keys) {
      if (!currentIds.contains(id)) {
        toRemove.add(id);
      }
    }
    for (var id in toRemove) {
      _fadeControllers[id]?.dispose();
      _fadeControllers.remove(id);
      _sizeControllers[id]?.dispose();
      _sizeControllers.remove(id);
    }
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

  void _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isAnimating) return;

    final totalCount = _allFilteredLogs.length;
    if (_displayCount >= totalCount) {
      if (_hasMore) {
        setState(() {
          _hasMore = false;
        });
      }
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    final newCount = (_displayCount + _pageSize).clamp(0, totalCount);
    final newLogs = _getFilteredLogsWithCount(newCount);
    final currentIds = _targetLogs.map((l) => l.id).toSet();
    final newIds = newLogs.map((l) => l.id).toSet();
    final toAdd = newIds.difference(currentIds).toList();

    for (var id in toAdd) {
      if (!_sizeControllers.containsKey(id)) {
        _sizeControllers[id] = AnimationController(
          duration: _sizeDuration,
          vsync: this,
        )..value = 0.0;
      }
      if (!_fadeControllers.containsKey(id)) {
        _fadeControllers[id] = AnimationController(
          duration: _fadeDuration,
          vsync: this,
        )..value = 0.0;
      }
    }

    setState(() {
      _displayCount = newCount;
      _targetLogs = newLogs;
      _isLoadingMore = false;
      _hasMore = _displayCount < totalCount;
    });

    await Future.delayed(Duration.zero);

    if (!mounted) return;

    if (toAdd.isNotEmpty) {
      final futures = <Future>[];
      for (var id in toAdd) {
        final sizeCtrl = _sizeControllers[id];
        if (sizeCtrl != null && sizeCtrl.isAnimating == false) {
          futures.add(sizeCtrl.forward().orCancel);
        }
        final fadeCtrl = _fadeControllers[id];
        if (fadeCtrl != null && fadeCtrl.isAnimating == false) {
          futures.add(fadeCtrl.forward().orCancel);
        }
      }
      if (futures.isNotEmpty) {
        await Future.wait(futures);
      }
    }
  }

  List<LogEntry> _getFilteredLogsWithCount(int count) {
    if (_selectedLogTypes.isEmpty) return [];
    final logs = _dataManager.logs
        .where((log) => _selectedLogTypes.contains(log.type))
        .toList();
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return logs.take(count).toList();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      _loadMore();
    }
  }

  AnimationController _getFadeController(String id) {
    if (!_fadeControllers.containsKey(id)) {
      _fadeControllers[id] = AnimationController(
        duration: _fadeDuration,
        vsync: this,
      )..value = 1.0;
    }
    return _fadeControllers[id]!;
  }

  AnimationController _getSizeController(String id) {
    if (!_sizeControllers.containsKey(id)) {
      _sizeControllers[id] = AnimationController(
        duration: _sizeDuration,
        vsync: this,
      )..value = 1.0;
    }
    return _sizeControllers[id]!;
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

    final logs = _targetLogs;
    final totalCount = _allFilteredLogs.length;

    return CupertinoPageScaffold(
      backgroundColor: Colors.transparent,
      child: Container(
        color: backgroundColor,
        child: SafeArea(
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
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildFilterSection(isDarkMode),
                      _buildContent(isDarkMode, logs, totalCount),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
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
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.doc_text, size: 64),
            SizedBox(height: 16),
            Text('暂无日志'),
          ],
        ),
      );
    }

    if (_selectedLogTypes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.slider_horizontal_3, size: 64),
            SizedBox(height: 16),
            Text('请至少选择一种日志类型'),
          ],
        ),
      );
    }

    if (logs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.doc_text, size: 64),
            SizedBox(height: 16),
            Text('没有符合条件的日志'),
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
        mainAxisSize: MainAxisSize.min,
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
          const Divider(height: 0, indent: 10, endIndent: 10),
          ListView.builder(
            key: ValueKey('log_list_${_selectedLogTypes.hashCode}'),
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            addRepaintBoundaries: true,
            addAutomaticKeepAlives: true,
            shrinkWrap: true,
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
              final fadeController = _getFadeController(log.id);
              final sizeController = _getSizeController(log.id);

              return RepaintBoundary(
                child: SizeTransition(
                  sizeFactor: sizeController,
                  axis: Axis.vertical,
                  child: FadeTransition(
                    opacity: fadeController,
                    child: _buildLogItem(log, index, logs.length, isDarkMode),
                  ),
                ),
              );
            },
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
      mainAxisSize: MainAxisSize.min,
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
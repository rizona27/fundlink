import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Divider;
import '../services/data_manager.dart';
import '../models/log_entry.dart';

class LogView extends StatefulWidget {
  const LogView({super.key});

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> with SingleTickerProviderStateMixin {
  late DataManager _dataManager;
  Set<LogType> _selectedLogTypes = LogType.values.toSet();
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  List<LogEntry> get _filteredLogs {
    if (_selectedLogTypes.isEmpty) return [];
    return _dataManager.logs
        .where((log) => _selectedLogTypes.contains(log.type))
        .toList();
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

  void _toggleLogType(LogType type) {
    setState(() {
      if (_selectedLogTypes.contains(type)) {
        _selectedLogTypes.remove(type);
      } else {
        _selectedLogTypes.add(type);
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

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    return Container(
      color: backgroundColor,
      child: SafeArea(
        child: FadeTransition(
          opacity: _fadeController,
          child: Column(
            children: [
              _buildHeader(isDarkMode),
              Expanded(
                child: _buildContent(isDarkMode),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF1C1C1E).withOpacity(0.98)
            : CupertinoColors.white.withOpacity(0.98),
        border: Border(
          bottom: BorderSide(
            color: isDarkMode
                ? CupertinoColors.white.withOpacity(0.1)
                : CupertinoColors.systemGrey4.withOpacity(0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pop(context),
            child: Icon(
              CupertinoIcons.back,
              size: 24,
              color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '日志',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
              ),
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _clearAllLogs,
            child: Text(
              '清空',
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.systemRed,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isDarkMode) {
    return Column(
      children: [
        _buildFilterSection(isDarkMode),
        Expanded(
          child: _buildLogListSection(isDarkMode),
        ),
      ],
    );
  }

  Widget _buildFilterSection(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode
            ? CupertinoColors.systemGrey6.withOpacity(0.4)
            : CupertinoColors.white,
        border: Border(
          bottom: BorderSide(
            color: isDarkMode
                ? CupertinoColors.white.withOpacity(0.1)
                : CupertinoColors.systemGrey4.withOpacity(0.5),
            width: 0.5,
          ),
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
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                ),
              ),
              const Spacer(),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _toggleAllSelection,
                child: Text(
                  _isAllSelected ? '取消全选' : '全选',
                  style: TextStyle(
                    fontSize: 14,
                    color: const Color(0xFF6366F1),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: LogType.values.map((type) {
              final isSelected = _selectedLogTypes.contains(type);
              return _buildLogTypeChip(type, isSelected, isDarkMode);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLogTypeChip(LogType type, bool isSelected, bool isDarkMode) {
    return GestureDetector(
      onTap: () => _toggleLogType(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? type.color.withOpacity(isDarkMode ? 0.25 : 0.12)
              : (isDarkMode ? CupertinoColors.systemGrey5.withOpacity(0.3) : CupertinoColors.systemGrey6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? type.color : Colors.transparent,
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
                color: type.color,
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
                    ? type.color
                    : (isDarkMode ? CupertinoColors.white : CupertinoColors.label),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogListSection(bool isDarkMode) {
    final logs = _filteredLogs;

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

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final log = logs[logs.length - 1 - index];
        return _buildLogCard(log, isDarkMode);
      },
    );
  }

  Widget _buildLogCard(LogEntry log, bool isDarkMode) {
    final timeStr = '${log.timestamp.year}-${log.timestamp.month.toString().padLeft(2, '0')}-${log.timestamp.day.toString().padLeft(2, '0')} '
        '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDarkMode
            ? CupertinoColors.systemGrey6.withOpacity(0.4)
            : CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: log.type.color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 4, right: 12),
            decoration: BoxDecoration(
              color: log.type.color,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.message,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDarkMode
                        ? CupertinoColors.white.withOpacity(0.5)
                        : CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: log.type.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              log.type.displayName,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: log.type.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
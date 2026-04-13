import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Divider;
import '../services/data_manager.dart';
import '../models/log_entry.dart';
import '../widgets/theme_switch.dart';
import 'add_holding_view.dart';
import 'manage_holdings_view.dart';

class ConfigView extends StatefulWidget {
  const ConfigView({super.key});

  @override
  State<ConfigView> createState() => _ConfigViewState();
}

class _ConfigViewState extends State<ConfigView> {
  late DataManager _dataManager;
  bool _showLogs = false;
  Set<LogType> _selectedLogTypes = LogType.values.toSet();
  // 删除未使用的 _scrollController
  // final ScrollController _scrollController = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _dataManager.addLog('进入设置页面', type: LogType.info);
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

  void _onThemeChanged(ThemeMode mode) {
    _dataManager.setThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: Text('设置'),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSection(
                    title: '通用设置',
                    isDarkMode: isDarkMode,
                    children: [
                      _buildSwitchRow(
                        icon: CupertinoIcons.lock_fill,
                        title: '隐私模式',
                        subtitle: '开启后隐藏客户姓名中的部分字符',
                        value: _dataManager.isPrivacyMode,
                        isDarkMode: isDarkMode,
                        onChanged: (value) async {
                          await _dataManager.togglePrivacyMode();
                          setState(() {});
                        },
                      ),
                      _buildDivider(isDarkMode: isDarkMode),
                      _buildThemeRow(isDarkMode: isDarkMode),
                      _buildDivider(isDarkMode: isDarkMode),
                      _buildMenuRow(
                        icon: CupertinoIcons.doc_text_search,
                        title: '日志查询',
                        subtitle: '查看API请求和操作日志',
                        isDarkMode: isDarkMode,
                        onTap: () {
                          setState(() {
                            _showLogs = !_showLogs;
                          });
                        },
                      ),
                    ],
                  ),

                  if (_showLogs) ...[
                    const SizedBox(height: 20),
                    _buildLogFilterSection(isDarkMode: isDarkMode),
                    const SizedBox(height: 12),
                    _buildLogListSection(isDarkMode: isDarkMode),
                  ],

                  const SizedBox(height: 20),
                  _buildSection(
                    title: '数据管理',
                    isDarkMode: isDarkMode,
                    children: [
                      _buildMenuRow(
                        icon: CupertinoIcons.plus_circle_fill,
                        title: '新增持仓',
                        subtitle: '添加新的基金持仓记录',
                        isDarkMode: isDarkMode,
                        onTap: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (context) => const AddHoldingView(),
                            ),
                          );
                        },
                      ),
                      _buildDivider(isDarkMode: isDarkMode),
                      _buildMenuRow(
                        icon: CupertinoIcons.folder_fill,
                        title: '管理持仓',
                        subtitle: '编辑或删除现有持仓',
                        isDarkMode: isDarkMode,
                        onTap: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (context) => const ManageHoldingsView(),
                            ),
                          );
                        },
                      ),
                      _buildDivider(isDarkMode: isDarkMode),
                      _buildMenuRow(
                        icon: CupertinoIcons.trash_fill,
                        title: '清空所有日志',
                        subtitle: '删除所有操作日志记录',
                        isDarkMode: isDarkMode,
                        onTap: () {
                          _showConfirmDialog(
                            title: '清空日志',
                            message: '确定要清空所有日志吗？此操作不可撤销。',
                            onConfirm: () async {
                              await _dataManager.clearAllLogs();
                              setState(() {});
                            },
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  _buildSection(
                    title: '关于',
                    isDarkMode: isDarkMode,
                    children: [
                      _buildMenuRow(
                        icon: CupertinoIcons.info_circle_fill,
                        title: '版本信息',
                        subtitle: 'v1.0.0',
                        isDarkMode: isDarkMode,
                        onTap: () {
                          _showAboutDialog();
                        },
                      ),
                      _buildDivider(isDarkMode: isDarkMode),
                      _buildMenuRow(
                        icon: CupertinoIcons.heart_fill,
                        title: '开源许可',
                        subtitle: 'MIT License',
                        isDarkMode: isDarkMode,
                        onTap: () {
                          _showNotImplementedToast();
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),
                  Center(
                    child: Text(
                      'Happiness around the corner.',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode
                            ? CupertinoColors.white.withOpacity(0.6)
                            : CupertinoColors.systemGrey.withOpacity(0.6),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeRow({required bool isDarkMode}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: CupertinoColors.systemBlue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(CupertinoIcons.paintbrush_fill, size: 18, color: CupertinoColors.systemBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '主题模式',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '浅色、深色或跟随系统',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          ),
          ThemeSwitch(
            initialMode: _dataManager.themeMode,
            onChanged: _onThemeChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildLogFilterSection({required bool isDarkMode}) {
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? CupertinoColors.systemGrey6.withOpacity(0.3) : CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(
                  '日志筛选',
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
                      fontSize: 13,
                      color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () async {
                    await _dataManager.clearAllLogs();
                    setState(() {});
                  },
                  child: Text(
                    '清空',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDarkMode ? CupertinoColors.systemRed : CupertinoColors.destructiveRed,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 0,
            color: isDarkMode ? CupertinoColors.white.withOpacity(0.1) : CupertinoColors.systemGrey4,
          ),
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
              ? type.color.withOpacity(isDarkMode ? 0.3 : 0.15)
              : (isDarkMode ? CupertinoColors.systemGrey5.withOpacity(0.3) : CupertinoColors.systemGrey5),
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
                fontSize: 12,
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

  Widget _buildLogListSection({required bool isDarkMode}) {
    final logs = _filteredLogs;

    if (logs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: isDarkMode ? CupertinoColors.systemGrey6.withOpacity(0.3) : CupertinoColors.systemGrey6,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                CupertinoIcons.doc_text,
                size: 48,
                color: isDarkMode ? CupertinoColors.white.withOpacity(0.5) : CupertinoColors.systemGrey,
              ),
              const SizedBox(height: 12),
              Text(
                '暂无日志',
                style: TextStyle(
                  color: isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? CupertinoColors.systemGrey6.withOpacity(0.3) : CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '日志列表',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
              ),
            ),
          ),
          Divider(
            height: 0,
            color: isDarkMode ? CupertinoColors.white.withOpacity(0.1) : CupertinoColors.systemGrey4,
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: logs.length,
            separatorBuilder: (_, __) => Divider(
              height: 0,
              indent: 16,
              color: isDarkMode ? CupertinoColors.white.withOpacity(0.1) : CupertinoColors.systemGrey4,
            ),
            itemBuilder: (context, index) {
              final log = logs[index];
              return _buildLogItem(log, isDarkMode);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(LogEntry log, bool isDarkMode) {
    final timeStr = '${log.timestamp.hour.toString().padLeft(2, '0')}:'
        '${log.timestamp.minute.toString().padLeft(2, '0')}:'
        '${log.timestamp.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 10),
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
                    fontSize: 13,
                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDarkMode ? CupertinoColors.white.withOpacity(0.5) : CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required bool isDarkMode,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDarkMode ? CupertinoColors.systemGrey6.withOpacity(0.3) : CupertinoColors.systemGrey6,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required bool isDarkMode,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: CupertinoColors.systemBlue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: CupertinoColors.systemBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: CupertinoColors.systemBlue,
          ),
        ],
      ),
    );
  }

  Widget _buildMenuRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: BorderRadius.zero,
      onPressed: onTap,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: CupertinoColors.systemBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            CupertinoIcons.chevron_forward,
            size: 14,
            color: isDarkMode ? CupertinoColors.white.withOpacity(0.6) : CupertinoColors.systemGrey.withOpacity(0.6),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider({required bool isDarkMode}) {
    return Divider(
      height: 0,
      indent: 60,
      color: isDarkMode ? CupertinoColors.white.withOpacity(0.1) : CupertinoColors.systemGrey4,
    );
  }

  void _showConfirmDialog({
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            isDestructiveAction: true,
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('基金持仓管理'),
        content: const Text(
          '版本: 1.0.0\n\n'
              '一款用于管理基金持仓的Flutter应用\n'
              '支持导入CSV数据、查看收益排行等功能\n\n'
              '使用Flutter Cupertino组件构建',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showNotImplementedToast() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('提示'),
        content: const Text('此功能开发中...'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }
}
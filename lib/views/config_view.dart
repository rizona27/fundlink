import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Divider;
import '../providers/data_manager_provider.dart';
import '../services/data_manager.dart';
import '../models/log_entry.dart';
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
  final ScrollController _scrollController = ScrollController();

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

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
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
                    children: [
                      _buildSwitchRow(
                        icon: CupertinoIcons.lock_fill,
                        title: '隐私模式',
                        subtitle: '开启后隐藏客户姓名中的部分字符',
                        value: _dataManager.isPrivacyMode,
                        onChanged: (value) async {
                          await _dataManager.togglePrivacyMode();
                          setState(() {});
                        },
                      ),
                      _buildDivider(),
                      _buildMenuRow(
                        icon: CupertinoIcons.doc_text_search,
                        title: '日志查询',
                        subtitle: '查看API请求和操作日志',
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
                    _buildLogFilterSection(),
                    const SizedBox(height: 12),
                    _buildLogListSection(),
                  ],

                  const SizedBox(height: 20),
                  _buildSection(
                    title: '数据管理',
                    children: [
                      // 新增持仓
                      _buildMenuRow(
                        icon: CupertinoIcons.plus_circle_fill,
                        title: '新增持仓',
                        subtitle: '添加新的基金持仓记录',
                        onTap: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (context) => const AddHoldingView(),
                            ),
                          );
                        },
                      ),
                      _buildDivider(),
                      // 管理持仓
                      _buildMenuRow(
                        icon: CupertinoIcons.folder_fill,
                        title: '管理持仓',
                        subtitle: '编辑或删除现有持仓',
                        onTap: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (context) => const ManageHoldingsView(),
                            ),
                          );
                        },
                      ),
                      _buildDivider(),
                      // 清空所有日志
                      _buildMenuRow(
                        icon: CupertinoIcons.trash_fill,
                        title: '清空所有日志',
                        subtitle: '删除所有操作日志记录',
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
                    children: [
                      _buildMenuRow(
                        icon: CupertinoIcons.info_circle_fill,
                        title: '版本信息',
                        subtitle: 'v1.0.0',
                        onTap: () {
                          _showAboutDialog();
                        },
                      ),
                      _buildDivider(),
                      _buildMenuRow(
                        icon: CupertinoIcons.heart_fill,
                        title: '开源许可',
                        subtitle: 'MIT License',
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
                        color: CupertinoColors.systemGrey.withOpacity(0.6),
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

  Widget _buildLogFilterSection() {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Text(
                  '日志筛选',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _toggleAllSelection,
                  child: Text(
                    _isAllSelected ? '取消全选' : '全选',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () async {
                    await _dataManager.clearAllLogs();
                    setState(() {});
                  },
                  child: const Text(
                    '清空',
                    style: TextStyle(fontSize: 13, color: CupertinoColors.destructiveRed),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 0),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: LogType.values.map((type) {
              final isSelected = _selectedLogTypes.contains(type);
              return _buildLogTypeChip(type, isSelected);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLogTypeChip(LogType type, bool isSelected) {
    return GestureDetector(
      onTap: () => _toggleLogType(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? type.color.withOpacity(0.15) : CupertinoColors.systemGrey5,
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
                color: isSelected ? type.color : CupertinoColors.label,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogListSection() {
    final logs = _filteredLogs;

    if (logs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey6,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(CupertinoIcons.doc_text, size: 48, color: CupertinoColors.systemGrey),
              SizedBox(height: 12),
              Text('暂无日志', style: TextStyle(color: CupertinoColors.systemGrey)),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '日志列表',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 0),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: logs.length,
            separatorBuilder: (_, __) => const Divider(height: 0, indent: 16),
            itemBuilder: (context, index) {
              final log = logs[index];
              return _buildLogItem(log);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(LogEntry log) {
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
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: const TextStyle(fontSize: 10, color: CupertinoColors.systemGrey),
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
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.systemGrey,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey6,
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey),
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey),
                ),
              ],
            ),
          ),
          Icon(
            CupertinoIcons.chevron_forward,
            size: 14,
            color: CupertinoColors.systemGrey.withOpacity(0.6),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 0,
      indent: 60,
      color: CupertinoColors.systemGrey4,
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
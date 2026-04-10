import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Divider;

class ConfigView extends StatefulWidget {
  const ConfigView({super.key});

  @override
  State<ConfigView> createState() => _ConfigViewState();
}

class _ConfigViewState extends State<ConfigView> {
  bool _isPrivacyMode = true;
  bool _autoRefresh = true;
  String _selectedTheme = '浅色';

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('设置'),
      ),
      child: SafeArea(
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
                  value: _isPrivacyMode,
                  onChanged: (value) {
                    setState(() {
                      _isPrivacyMode = value;
                    });
                  },
                ),
                _buildDivider(),
                _buildSwitchRow(
                  icon: CupertinoIcons.arrow_clockwise,
                  title: '自动刷新',
                  subtitle: '打开应用时自动刷新基金净值',
                  value: _autoRefresh,
                  onChanged: (value) {
                    setState(() {
                      _autoRefresh = value;
                    });
                  },
                ),
                _buildDivider(),
                _buildMenuRow(
                  icon: CupertinoIcons.paintbrush_fill,
                  title: '主题模式',
                  subtitle: _selectedTheme,
                  onTap: () {
                    _showThemePicker();
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSection(
              title: '数据管理',
              children: [
                _buildMenuRow(
                  icon: CupertinoIcons.arrow_up_doc_fill,
                  title: '导入数据',
                  subtitle: '从CSV文件导入持仓',
                  onTap: () {
                    _showNotImplementedToast();
                  },
                ),
                _buildDivider(),
                _buildMenuRow(
                  icon: CupertinoIcons.arrow_down_doc_fill,
                  title: '导出数据',
                  subtitle: '导出持仓到CSV文件',
                  onTap: () {
                    _showNotImplementedToast();
                  },
                ),
                _buildDivider(),
                _buildMenuRow(
                  icon: CupertinoIcons.doc_text_search,
                  title: '日志查询',
                  subtitle: '查看API请求日志',
                  onTap: () {
                    _showNotImplementedToast();
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

  void _showThemePicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择主题'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() {
                _selectedTheme = '浅色';
              });
              Navigator.pop(context);
            },
            child: const Text('浅色模式'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() {
                _selectedTheme = '深色';
              });
              Navigator.pop(context);
            },
            child: const Text('深色模式'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() {
                _selectedTheme = '跟随系统';
              });
              Navigator.pop(context);
            },
            child: const Text('跟随系统'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
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
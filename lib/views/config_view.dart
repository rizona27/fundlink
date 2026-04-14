import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Divider;
import '../services/data_manager.dart';
import '../models/log_entry.dart';
import '../widgets/theme_switch.dart';
import 'add_holding_view.dart';
import 'manage_holdings_view.dart';
import 'log_view.dart';  // 新增导入

class ConfigView extends StatefulWidget {
  const ConfigView({super.key});

  @override
  State<ConfigView> createState() => _ConfigViewState();
}

class _ConfigViewState extends State<ConfigView> with SingleTickerProviderStateMixin {
  late DataManager _dataManager;
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
    _dataManager.addLog('进入设置页面', type: LogType.info);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
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
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildGeneralSection(isDarkMode),
              const SizedBox(height: 16),
              _buildDataSection(isDarkMode),
              const SizedBox(height: 16),
              _buildLogSection(isDarkMode),
              const SizedBox(height: 16),
              _buildAboutSection(isDarkMode),
              const SizedBox(height: 32),
              _buildFooter(isDarkMode),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String icon,
    required bool isDarkMode,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode
            ? CupertinoColors.systemGrey6.withOpacity(0.4)
            : CupertinoColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDarkMode
                ? Colors.black.withOpacity(0.2)
                : Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _getIconGradient(icon),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getIconData(icon),
                    color: CupertinoColors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 0,
            indent: 60,
            endIndent: 16,
            color: isDarkMode
                ? CupertinoColors.white.withOpacity(0.1)
                : CupertinoColors.systemGrey4,
          ),
          ...children,
        ],
      ),
    );
  }

  List<Color> _getIconGradient(String icon) {
    final gradients = {
      '通用': [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
      '数据': [const Color(0xFF10B981), const Color(0xFF34D399)],
      '日志': [const Color(0xFFF59E0B), const Color(0xFFFBBF24)],
      '关于': [const Color(0xFFEC4899), const Color(0xFFF472B6)],
    };
    return gradients[icon] ?? [const Color(0xFF6B7280), const Color(0xFF9CA3AF)];
  }

  IconData _getIconData(String icon) {
    final icons = {
      '通用': CupertinoIcons.slider_horizontal_3,
      '数据': CupertinoIcons.folder,
      '日志': CupertinoIcons.doc_text,
      '关于': CupertinoIcons.info,
    };
    return icons[icon] ?? CupertinoIcons.settings;
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDarkMode,
    required VoidCallback onTap,
    bool isDestructive = false,
    Widget? trailing,
  }) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      borderRadius: BorderRadius.zero,
      onPressed: onTap,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isDestructive
                  ? CupertinoColors.systemRed.withOpacity(0.15)
                  : (isDarkMode
                  ? CupertinoColors.systemGrey5.withOpacity(0.3)
                  : CupertinoColors.systemGrey6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isDestructive
                  ? CupertinoColors.systemRed
                  : (isDarkMode ? CupertinoColors.systemBlue : const Color(0xFF6366F1)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDestructive
                        ? CupertinoColors.systemRed
                        : (isDarkMode ? CupertinoColors.white : CupertinoColors.label),
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode
                          ? CupertinoColors.white.withOpacity(0.6)
                          : CupertinoColors.systemGrey,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing
          else
            Icon(
              CupertinoIcons.chevron_forward,
              size: 14,
              color: isDarkMode
                  ? CupertinoColors.white.withOpacity(0.4)
                  : CupertinoColors.systemGrey.withOpacity(0.6),
            ),
        ],
      ),
    );
  }

  Widget _buildSwitchItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required bool isDarkMode,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isDarkMode
                  ? CupertinoColors.systemGrey5.withOpacity(0.3)
                  : CupertinoColors.systemGrey6,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFF6366F1)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode
                          ? CupertinoColors.white.withOpacity(0.6)
                          : CupertinoColors.systemGrey,
                    ),
                  ),
                ],
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF6366F1),
            trackColor: isDarkMode
                ? CupertinoColors.systemGrey5
                : CupertinoColors.systemGrey4,
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(bool isDarkMode) {
    return Divider(
      height: 0,
      indent: 60,
      color: isDarkMode
          ? CupertinoColors.white.withOpacity(0.08)
          : CupertinoColors.systemGrey4.withOpacity(0.5),
    );
  }

  Widget _buildGeneralSection(bool isDarkMode) {
    return _buildSection(
      title: '通用设置',
      icon: '通用',
      isDarkMode: isDarkMode,
      children: [
        _buildSwitchItem(
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
        _buildDivider(isDarkMode),
        _buildThemeItem(isDarkMode),
      ],
    );
  }

  Widget _buildThemeItem(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isDarkMode
                  ? CupertinoColors.systemGrey5.withOpacity(0.3)
                  : CupertinoColors.systemGrey6,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(CupertinoIcons.paintbrush_fill, size: 16, color: Color(0xFF6366F1)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '主题模式',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '浅色、深色或跟随系统',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode
                        ? CupertinoColors.white.withOpacity(0.6)
                        : CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          ),
          ThemeSwitch(
            initialMode: _dataManager.themeMode,
            onChanged: (mode) => _dataManager.setThemeMode(mode),
          ),
        ],
      ),
    );
  }

  Widget _buildDataSection(bool isDarkMode) {
    return _buildSection(
      title: '数据管理',
      icon: '数据',
      isDarkMode: isDarkMode,
      children: [
        _buildMenuItem(
          icon: CupertinoIcons.plus_circle_fill,
          title: '新增持仓',
          subtitle: '添加新的基金持仓记录',
          isDarkMode: isDarkMode,
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (context) => const AddHoldingView()),
            );
          },
        ),
        _buildDivider(isDarkMode),
        _buildMenuItem(
          icon: CupertinoIcons.folder_fill,
          title: '管理持仓',
          subtitle: '编辑或删除现有持仓',
          isDarkMode: isDarkMode,
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (context) => const ManageHoldingsView()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLogSection(bool isDarkMode) {
    return _buildSection(
      title: '日志',
      icon: '日志',
      isDarkMode: isDarkMode,
      children: [
        _buildMenuItem(
          icon: CupertinoIcons.doc_text_search,
          title: '查看日志',
          subtitle: '查看API请求和操作日志记录',
          isDarkMode: isDarkMode,
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (context) => const LogView()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAboutSection(bool isDarkMode) {
    return _buildSection(
      title: '关于',
      icon: '关于',
      isDarkMode: isDarkMode,
      children: [
        _buildMenuItem(
          icon: CupertinoIcons.info_circle_fill,
          title: '版本信息',
          subtitle: 'v1.0.0',
          isDarkMode: isDarkMode,
          onTap: () => _showAboutDialog(),
        ),
        _buildDivider(isDarkMode),
        _buildMenuItem(
          icon: CupertinoIcons.heart_fill,
          title: '开源许可',
          subtitle: 'MIT License',
          isDarkMode: isDarkMode,
          onTap: () => _showNotImplementedToast(),
        ),
      ],
    );
  }

  Widget _buildFooter(bool isDarkMode) {
    return Center(
      child: Column(
        children: [
          Icon(
            CupertinoIcons.heart_fill,
            size: 16,
            color: isDarkMode
                ? CupertinoColors.white.withOpacity(0.3)
                : CupertinoColors.systemGrey.withOpacity(0.4),
          ),
          const SizedBox(height: 8),
          Text(
            'Happiness around the corner.',
            style: TextStyle(
              fontSize: 12,
              color: isDarkMode
                  ? CupertinoColors.white.withOpacity(0.4)
                  : CupertinoColors.systemGrey.withOpacity(0.5),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
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
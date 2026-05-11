import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart' show Colors, Divider;
import '../services/data_manager.dart';
import '../models/log_entry.dart';
import '../widgets/theme_switch.dart';
import 'add_holding_view.dart';
import 'manage_holdings_view.dart';
import 'log_view.dart';
import 'version_view.dart';
import 'license_view.dart';
import 'import_holding_view.dart';
import 'export_holding_view.dart';
import 'pending_transactions_view.dart';
import 'dart:async';

class ConfigView extends StatefulWidget {
  const ConfigView({super.key});

  @override
  State<ConfigView> createState() => _ConfigViewState();
}

class _ConfigViewState extends State<ConfigView> with AutomaticKeepAliveClientMixin {
  late DataManager _dataManager;
  Brightness? _lastBrightness;
  Timer? _animationTimer;
  double _backgroundOpacity = 1.0; // 背景透明度

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _dataManager = DataManagerProvider.of(context);
        _lastBrightness = CupertinoTheme.brightnessOf(context);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    
    final currentBrightness = CupertinoTheme.brightnessOf(context);
    if (_lastBrightness != null && currentBrightness != _lastBrightness) {
      _lastBrightness = currentBrightness;
      
      // 背景淡出再淡入，文字颜色自动跟随主题变化
      setState(() {
        _backgroundOpacity = 0.0;
      });
      
      // 主题动画完成后立即淡入背景
      _animationTimer?.cancel();
      _animationTimer = Timer(const Duration(milliseconds: 400), () {
        if (mounted) {
          setState(() {
            _backgroundOpacity = 1.0;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    return Container(
      color: backgroundColor, // 底层：固定主题色，避免闪烁
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        color: backgroundColor.withOpacity(_backgroundOpacity), // 上层：透明度控制淡入淡出
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHoldingsManagementSection(isDarkMode),
              const SizedBox(height: 16),
              _buildGeneralSection(isDarkMode),
              const SizedBox(height: 16),
              _buildImportExportSection(isDarkMode),
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

  Widget _buildGeneralSection(bool isDarkMode) {
    final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
    
    return _buildSection(
      title: '基础配置',
      icon: '通用',
      isDarkMode: isDarkMode,
      children: [
        _buildSwitchItem(
          icon: CupertinoIcons.lock_fill,
          title: '隐私模式',
          subtitle: '信息脱敏',
          value: _dataManager.isPrivacyMode,
          isDarkMode: isDarkMode,
          onChanged: (value) async {
            await _dataManager.togglePrivacyMode();
            if (mounted) setState(() {});  // ✅ 添加 mounted 检查
          },
        ),
        _buildDivider(isDarkMode),
        _buildSwitchItem(
          icon: CupertinoIcons.person_fill,
          title: '一览卡片',
          subtitle: '客户显示',
          value: _dataManager.showHoldersOnSummaryCard,
          isDarkMode: isDarkMode,
          onChanged: (value) async {
            await _dataManager.setShowHoldersOnSummaryCard(value);
            if (mounted) setState(() {});  // ✅ 添加 mounted 检查
          },
        ),
        _buildDivider(isDarkMode),
        _buildThemeItem(isDarkMode),
      ],
    );
  }

  Widget _buildHoldingsManagementSection(bool isDarkMode) {
    return _buildSection(
      title: '持仓管理',
      icon: '数据',
      isDarkMode: isDarkMode,
      children: [
        _buildMenuItem(
          icon: CupertinoIcons.plus_circle_fill,
          title: '新增持仓',
          subtitle: '添加基金记录',
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
          icon: CupertinoIcons.pencil,
          title: '编辑持仓',
          subtitle: '修改持仓信息',
          isDarkMode: isDarkMode,
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (context) => const ManageHoldingsView()),
            );
          },
        ),
        _buildDivider(isDarkMode),
        _buildMenuItem(
          icon: CupertinoIcons.clock_fill,
          title: '待确认交易',
          subtitle: '查看和管理待确认交易',
          isDarkMode: isDarkMode,
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (context) => const PendingTransactionsView()),
            );
          },
        ),
        _buildDivider(isDarkMode),
        _buildMenuItem(
          icon: CupertinoIcons.trash,
          title: '清空持仓',
          subtitle: '删除所有数据（不可恢复）',
          isDarkMode: isDarkMode,
          isDestructive: true,
          onTap: () => _showClearAllConfirmDialog(),
        ),
      ],
    );
  }

  Widget _buildImportExportSection(bool isDarkMode) {
    return _buildSection(
      title: '数据迁移',
      icon: '通用',
      isDarkMode: isDarkMode,
      children: [
        _buildMenuItem(
          icon: CupertinoIcons.cloud_download,
          title: '导入数据',
          subtitle: '从文件导入持仓数据',
          isDarkMode: isDarkMode,
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (context) => const ImportHoldingView()),
            );
          },
        ),
        _buildDivider(isDarkMode),
        _buildMenuItem(
          icon: CupertinoIcons.cloud_upload,
          title: '导出数据',
          subtitle: '导出持仓数据到文件',
          isDarkMode: isDarkMode,
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (context) => const ExportHoldingView()),
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
          subtitle: '', // 清空subtitle，我们将自定义显示
          isDarkMode: isDarkMode,
          trailing: null, // 不使用trailing
          customSubtitle: _buildVersionWithBadge(isDarkMode), // 使用自定义subtitle
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (context) => const VersionView()),
            );
          },
        ),
        _buildDivider(isDarkMode),
        _buildMenuItem(
          icon: CupertinoIcons.doc_text_search,
          title: '查看日志',
          subtitle: '系统和操作记录',
          isDarkMode: isDarkMode,
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (context) => const LogView()),
            );
          },
        ),
        _buildDivider(isDarkMode),
        _buildMenuItem(
          icon: CupertinoIcons.heart_fill,
          title: '开源许可',
          subtitle: 'AGPL v3',
          isDarkMode: isDarkMode,
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (context) => const LicenseView()),
            );
          },
        ),
      ],
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
    Widget? customSubtitle, // 自定义subtitle widget
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
                if (customSubtitle != null) ...[
                  const SizedBox(height: 2),
                  customSubtitle,
                ] else if (subtitle.isNotEmpty) ...[
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
            child: const Icon(
              CupertinoIcons.paintbrush_fill,
              size: 16,
              color: Color(0xFF6366F1),
            ),
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
                  '明暗适配',
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
          const SizedBox(width: 12),
          // ✅ 修复：使用 ConstrainedBox 限制最大宽度，避免无限宽度错误
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.4, // 最多占据屏幕宽度的40%
            ),
            child: ThemeSwitch(
              initialMode: _dataManager.themeMode,
              onChanged: (mode) {
                _dataManager.setThemeMode(mode);
                setState(() {});
              },
            ),
          ),
        ],
      ),
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

  /// 构建版本徽章（NEW 或 Latest）
  Widget _buildVersionBadge(bool isDarkMode) {
    final versionInfo = _dataManager.latestVersionInfo;
    
    if (versionInfo == null) {
      // 还在检查中或未获取到信息，不显示徽章
      return const SizedBox.shrink();
    }
    
    final hasUpdate = versionInfo.hasUpdate;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: hasUpdate ? const Color(0xFF007AFF) : const Color(0xFF34C759),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        hasUpdate ? 'NEW' : 'Latest',
        style: const TextStyle(
          color: CupertinoColors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 构建带徽章的版本号（内联显示）
  Widget _buildVersionWithBadge(bool isDarkMode) {
    final versionInfo = _dataManager.latestVersionInfo;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          APP_VERSION,
          style: TextStyle(
            fontSize: 12,
            color: isDarkMode
                ? CupertinoColors.white.withOpacity(0.6)
                : CupertinoColors.systemGrey,
          ),
        ),
        if (versionInfo != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: versionInfo.hasUpdate ? const Color(0xFF007AFF) : const Color(0xFF34C759),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              versionInfo.hasUpdate ? 'NEW' : 'Latest',
              style: const TextStyle(
                color: CupertinoColors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showClearAllConfirmDialog() {
    final holdingCount = _dataManager.holdings.length;
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('清空所有持仓'),
        content: Text('此操作将删除所有持仓数据($holdingCount条)，且不可恢复。确定要继续吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              Navigator.pop(context);
              _showFinalConfirmDialog();
            },
            isDestructiveAction: true,
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
  }

  void _showFinalConfirmDialog() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('最后确认'),
        content: const Text('此操作无法撤销，请再次确认是否清空所有持仓？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _dataManager.clearAllHoldings();
                await _dataManager.addLog('已清空所有持仓', type: LogType.warning);
                if (mounted) {
                  showCupertinoDialog(
                    context: context,
                    builder: (context) => CupertinoAlertDialog(
                      title: const Text('操作成功'),
                      content: const Text('所有持仓数据已清空。'),
                      actions: [
                        CupertinoDialogAction(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  );
                  if (mounted) setState(() {});  // ✅ 添加 mounted 检查
                }
              } catch (e) {
                await _dataManager.addLog('清空持仓失败: $e', type: LogType.error);
                if (mounted) {
                  showCupertinoDialog(
                    context: context,
                    builder: (context) => CupertinoAlertDialog(
                      title: const Text('操作失败'),
                      content: Text('清空数据时出错: $e'),
                      actions: [
                        CupertinoDialogAction(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  );
                }
              }
            },
            isDestructiveAction: true,
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
  }
}
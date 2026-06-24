import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import '../models/log_entry.dart';
import '../services/data_manager.dart';
import '../services/ui_state_service.dart';
import '../utils/animation_config.dart';
import '../widgets/theme_switch.dart';
import 'add_holding_view.dart';
import 'export_holding_view.dart';
import 'import_holding_view.dart';
import 'license_view.dart';
import 'log_view.dart';
import 'manage_holdings_view.dart';
import '../services/client_mapping_service.dart';
import 'mapping_dictionary_view.dart';
import 'pending_transactions_view.dart';
import 'permission_settings_view.dart';
import 'version_view.dart';
import '../widgets/toast.dart';

class ConfigView extends StatefulWidget {
  const ConfigView({super.key});

  @override
  State<ConfigView> createState() => _ConfigViewState();
}

class _ConfigViewState extends State<ConfigView>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  late DataManager _dataManager;
  Brightness? _lastBrightness;
  Timer? _animationTimer;
  double _backgroundOpacity = 1.0;

  bool _isHoldingsManagementExpanded = true;
  bool _isCommonToolsExpanded = false;
  bool _isAppSettingsExpanded = false;
  bool _isAboutExpanded = false;

  Timer? _gradientTimer;
  double _gradientOffset = 0.0;
  static const List<Color> _gradientColors = [
    Color(0xFFD4A5A5),
    Color(0xFFE8B89D),
    Color(0xFFE2C8A0),
    Color(0xFFB5C9B4),
    Color(0xFFA3B8C8),
    Color(0xFF9EA8C4),
    Color(0xFFC4B0D4),
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        _dataManager = DataManagerProvider.of(context);
        _lastBrightness = CupertinoTheme.brightnessOf(context);

        await _loadSectionStates();
        _startGradientAnimation();
      }
    });
  }

  void _startGradientAnimation() {
    _gradientTimer?.cancel();
    WidgetsBinding.instance.addObserver(this);
    _gradientTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _gradientOffset = (_gradientOffset + 0.004) % 1.0;
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _gradientTimer?.cancel();
      _gradientTimer = null;
    } else if (state == AppLifecycleState.resumed && _gradientTimer == null) {
      _gradientTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _gradientOffset = (_gradientOffset + 0.004) % 1.0;
        });
      });
    }
  }

  bool get _allSectionsCollapsed =>
      !_isHoldingsManagementExpanded &&
          !_isCommonToolsExpanded &&
          !_isAppSettingsExpanded &&
          !_isAboutExpanded;

  Future<void> _loadSectionStates() async {
    final uiState = UIStateService();
    if (mounted) {
      final holdingsManagementExpanded = await uiState.getBool('section_holdings_management_expanded');
      final commonToolsExpanded = await uiState.getBool('section_common_tools_expanded');
      final appSettingsExpanded = await uiState.getBool('section_app_settings_expanded');
      final aboutExpanded = await uiState.getBool('section_about_expanded');

      setState(() {
        _isHoldingsManagementExpanded = holdingsManagementExpanded ?? false;
        _isCommonToolsExpanded = commonToolsExpanded ?? false;
        _isAppSettingsExpanded = appSettingsExpanded ?? false;
        _isAboutExpanded = aboutExpanded ?? false;
      });
    }
  }

  void _saveSectionState(String key, bool value) {
    UIStateService().saveBool(key, value);
  }

  void _toggleSection(String key, bool currentValue) {
    setState(() {
      switch (key) {
        case 'holdings':
          _isHoldingsManagementExpanded = !currentValue;
          break;
        case 'common':
          _isCommonToolsExpanded = !currentValue;
          break;
        case 'app':
          _isAppSettingsExpanded = !currentValue;
          break;
        case 'about':
          _isAboutExpanded = !currentValue;
          break;
      }
    });
    _saveSectionState('section_${key}_expanded', !currentValue);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);

    final currentBrightness = CupertinoTheme.brightnessOf(context);
    if (_lastBrightness != null && currentBrightness != _lastBrightness) {
      _lastBrightness = currentBrightness;

      setState(() {
        _backgroundOpacity = 0.0;
      });

      _animationTimer?.cancel();
      _animationTimer = Timer(AnimationConfig.durationSlow, () {
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
    WidgetsBinding.instance.removeObserver(this);
    _animationTimer?.cancel();
    _gradientTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    return Container(
      color: backgroundColor,
      child: AnimatedContainer(
        duration: AnimationConfig.durationSlow,
        curve: AnimationConfig.curveEaseInOutCubic,
        color: backgroundColor.withOpacity(_backgroundOpacity),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHoldingsManagementSection(isDarkMode),
              const SizedBox(height: 16),
              _buildCommonToolsSection(isDarkMode),
              const SizedBox(height: 16),
              _buildAppSettingsSection(isDarkMode),
              const SizedBox(height: 16),
              _buildAboutSection(isDarkMode),
              const SizedBox(height: 32),
              _buildFooter(isDarkMode),
              const SizedBox(height: 24),
              _buildDonationSection(isDarkMode),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommonToolsSection(bool isDarkMode) {
    return _buildSection(
      title: '数据同步',
      icon: '工具',
      isDarkMode: isDarkMode,
      isExpanded: _isCommonToolsExpanded,
      onToggle: () => _toggleSection('common', _isCommonToolsExpanded),
      children: [
        _buildMenuItem(
          icon: CupertinoIcons.book,
          title: '映射索引',
          subtitle: '管理客户与客户号映射关系',
          isDarkMode: isDarkMode,
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (context) => const MappingDictionaryView()),
            );
          },
        ),
        _buildDivider(isDarkMode),
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
        _buildDivider(isDarkMode),
        _buildMenuItem(
          icon: CupertinoIcons.trash,
          title: '清空映射索引',
          subtitle: '删除所有映射数据（不可恢复）',
          isDarkMode: isDarkMode,
          isDestructive: true,
          onTap: () => _showClearMappingsConfirmDialog(),
        ),
      ],
    );
  }

  Widget _buildAppSettingsSection(bool isDarkMode) {
    return _buildSection(
      title: '偏好设置',
      icon: '设置',
      isDarkMode: isDarkMode,
      isExpanded: _isAppSettingsExpanded,
      onToggle: () => _toggleSection('app', _isAppSettingsExpanded),
      children: [
        _buildSwitchItem(
          icon: CupertinoIcons.lock_fill,
          title: '隐私模式',
          subtitle: '客户信息脱敏',
          value: _dataManager.isPrivacyMode,
          isDarkMode: isDarkMode,
          onChanged: (value) async {
            await _dataManager.togglePrivacyMode();
            if (mounted) {
              final toastMsg = value
                  ? '隐私模式开启:隐藏客户名'
                  : '隐私模式关闭:显示客户名';
              context.showToast(toastMsg);
              setState(() {});
            }
          },
        ),
        _buildDivider(isDarkMode),
        _buildSwitchItem(
          icon: CupertinoIcons.person_fill,
          title: '一览卡片',
          subtitle: '是否显示客户',
          value: _dataManager.showHoldersOnSummaryCard,
          isDarkMode: isDarkMode,
          onChanged: (value) async {
            await _dataManager.setShowHoldersOnSummaryCard(value);
            if (mounted) {
              final toastMsg = value
                  ? '基金卡片开启:显示客户'
                  : '基金卡片关闭:隐藏客户';
              context.showToast(toastMsg);
              setState(() {});
            }
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
      icon: '持仓',
      isDarkMode: isDarkMode,
      isExpanded: _isHoldingsManagementExpanded,
      onToggle: () => _toggleSection('holdings', _isHoldingsManagementExpanded),
      children: [
        _buildMenuItem(
          icon: CupertinoIcons.plus_circle_fill,
          title: '新增持仓',
          subtitle: '添加持仓记录',
          isDarkMode: isDarkMode,
          onTap: () {
            showCupertinoDialog(
              context: context,
              barrierDismissible: true,
              builder: (context) => const AddHoldingView(),
            );
          },
        ),
        _buildDivider(isDarkMode),
        _buildMenuItem(
          icon: CupertinoIcons.pencil,
          title: '编辑持仓',
          subtitle: '修改持仓记录',
          isDarkMode: isDarkMode,
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (context) => const ManageHoldingsView()),
            );
          },
        ),
        _buildDivider(isDarkMode),
        _buildMenuItemWithBadge(
          icon: CupertinoIcons.clock_fill,
          title: '待确认交易',
          subtitle: '待确认交易队列查看',
          isDarkMode: isDarkMode,
          badgeCount: _getPendingTransactionCount(),
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
          title: '清空持仓数据',
          subtitle: '删除所有持仓数据（不可恢复）',
          isDarkMode: isDarkMode,
          isDestructive: true,
          onTap: () => _showClearAllConfirmDialog(),
        ),
      ],
    );
  }

  Widget _buildAboutSection(bool isDarkMode) {
    return _buildSection(
      title: '关于程序',
      icon: '关于',
      isDarkMode: isDarkMode,
      isExpanded: _isAboutExpanded,
      onToggle: () => _toggleSection('about', _isAboutExpanded),
      children: [
        _buildMenuItem(
          icon: CupertinoIcons.info_circle_fill,
          title: '版本信息',
          subtitle: '',
          isDarkMode: isDarkMode,
          trailing: null,
          customSubtitle: _buildVersionWithBadge(isDarkMode),
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
          icon: CupertinoIcons.lock_shield_fill,
          title: '权限许可',
          subtitle: '查看和管理应用权限',
          isDarkMode: isDarkMode,
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (context) => const PermissionSettingsView()),
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
    required bool isExpanded,
    required VoidCallback onToggle,
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
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            onPressed: onToggle,
            child: Row(
              children: [
                AnimatedContainer(
                  duration: AnimationConfig.durationVerySlow,
                  curve: Curves.easeInOut,
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isExpanded
                          ? _getIconGradient(icon)
                          : _getGrayscaleGradient(),
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
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: AnimationConfig.durationMedium,
                  curve: AnimationConfig.curveEaseInOutCubic,
                  child: Icon(
                    CupertinoIcons.chevron_down,
                    size: 16,
                    color: isDarkMode
                        ? CupertinoColors.white.withOpacity(0.6)
                        : CupertinoColors.systemGrey.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: AnimationConfig.durationMedium,
            curve: AnimationConfig.curveEaseInOutCubic,
            child: isExpanded
                ? Column(
              children: [
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
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  List<Color> _getIconGradient(String icon) {
    final gradients = {
      '持仓': [const Color(0xFF10B981), const Color(0xFF34D399)],
      '工具': [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
      '设置': [const Color(0xFFF59E0B), const Color(0xFFFBBF24)],
      '关于': [const Color(0xFFEC4899), const Color(0xFFF472B6)],
    };
    return gradients[icon] ?? [const Color(0xFF6B7280), const Color(0xFF9CA3AF)];
  }

  List<Color> _getGrayscaleGradient() {
    return [const Color(0xFFD1D5DB), const Color(0xFF9CA3AF)];
  }

  IconData _getIconData(String icon) {
    final icons = {
      '持仓': CupertinoIcons.square_stack_3d_up,
      '工具': CupertinoIcons.wrench,
      '设置': CupertinoIcons.slider_horizontal_3,
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
    Widget? customSubtitle,
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

  Widget _buildMenuItemWithBadge({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDarkMode,
    required int badgeCount,
    required VoidCallback onTap,
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
              color: isDarkMode
                  ? CupertinoColors.systemGrey5.withOpacity(0.3)
                  : CupertinoColors.systemGrey6,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isDarkMode ? CupertinoColors.systemBlue : const Color(0xFF6366F1),
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
          if (badgeCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: CupertinoColors.systemRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badgeCount',
                style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
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

  int _getPendingTransactionCount() {
    return _dataManager.getPendingTransactions().length;
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

/// Determines the expected brightness based on the theme mode.
///
/// This function takes a ThemeMode parameter and returns the corresponding brightness.
/// For system theme mode, it retrieves the platform's default brightness.
///
/// @param mode The current theme mode (light, dark, or system)
/// @return The expected brightness value (light or dark)
  Brightness _getExpectedBrightness(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:    // When light theme is selected
        return Brightness.light;  // Return light brightness
      case ThemeMode.dark:     // When dark theme is selected
        return Brightness.dark;   // Return dark brightness
      case ThemeMode.system:   // When system theme is selected
        // Get the platform's default brightness from the platform dispatcher
        return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
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
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.4,
            ),
            child: ThemeSwitch(
              initialMode: _dataManager.themeMode,
              onChanged: (mode) {
                _dataManager.setThemeMode(mode);
                final expectedBrightness = _getExpectedBrightness(mode);
                String modeText;
                switch (mode) {
                  case ThemeMode.light:
                    modeText = '浅色';
                    break;
                  case ThemeMode.dark:
                    modeText = '深色';
                    break;
                  case ThemeMode.system:
                    modeText = '跟随系统';
                    break;
                }
                context.showToast('主题模式:$modeText', brightness: expectedBrightness);
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isDarkMode) {
    final isCollapsed = _allSectionsCollapsed;

    final greyColor = isDarkMode
        ? CupertinoColors.white.withOpacity(0.3)
        : CupertinoColors.systemGrey.withOpacity(0.4);

    return Center(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: isCollapsed ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOut,
                child: Icon(
                  CupertinoIcons.heart_fill,
                  size: 16,
                  color: CupertinoColors.systemRed,
                ),
              ),
              AnimatedOpacity(
                opacity: isCollapsed ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOut,
                child: Icon(
                  CupertinoIcons.heart_fill,
                  size: 16,
                  color: greyColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: isCollapsed ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOut,
                child: ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      colors: _gradientColors,
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      transform: GradientRotation(_gradientOffset * 2 * 3.14159),
                    ).createShader(bounds);
                  },
                  child: Text(
                    'Happiness around the corner.',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: CupertinoColors.white,
                    ),
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: isCollapsed ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOut,
                child: Text(
                  'Happiness around the corner.',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: isDarkMode
                        ? CupertinoColors.white.withOpacity(0.4)
                        : CupertinoColors.systemGrey.withOpacity(0.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDonationSection(bool isDarkMode) {
    final textColor = isDarkMode
        ? CupertinoColors.white.withOpacity(0.5)
        : CupertinoColors.systemGrey.withOpacity(0.6);

    return AnimatedOpacity(
      opacity: _allSectionsCollapsed ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        offset: _allSectionsCollapsed ? Offset.zero : const Offset(0, 0.05),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '请我喝杯柠檬水吧~',
                    style: TextStyle(fontSize: 12, color: textColor),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onLongPress: () => _saveDonationQrToGallery(),
              child: RepaintBoundary(
                key: _donationQrKey,
                child: Image.asset(
                  'assets/icon/wx.png',
                  width: 200,
                  height: 200,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '长按二维码保存到相册，微信扫码即可',
              style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7)),
            ),
          ],
        ),
      ),
    );
  }

  final GlobalKey _donationQrKey = GlobalKey();

  Future<void> _saveDonationQrToGallery() async {
    try {
      final boundary = _donationQrKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final imageBytes = byteData.buffer.asUint8List();
      await Gal.putImageBytes(imageBytes, name: 'FundLink_Donate_WeChat');
      if (context.mounted) {
        context.showToast('微信收款码已保存到相册');
      }
    } catch (e) {
      if (context.mounted) {
        context.showToast('保存失败，请检查相册权限');
      }
    }
  }

  Widget _buildVersionBadge(bool isDarkMode) {
    final versionInfo = _dataManager.latestVersionInfo;

    if (versionInfo == null) {
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
                  if (mounted) setState(() {});
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

  void _showClearMappingsConfirmDialog() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('清空映射索引'),
        content: const Text('此操作将删除所有客户映射索引数据，且不可恢复。确定要继续吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              Navigator.pop(context);
              _showClearMappingsFinalConfirmDialog();
            },
            isDestructiveAction: true,
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
  }

  void _showClearMappingsFinalConfirmDialog() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('最后确认'),
        content: const Text('此操作无法撤销，请再次确认是否清空所有映射索引？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ClientMappingService().clearAll();
                await _dataManager.addLog('已清空所有映射索引', type: LogType.warning);
                if (mounted) {
                  showCupertinoDialog(
                    context: context,
                    builder: (context) => CupertinoAlertDialog(
                      title: const Text('操作成功'),
                      content: const Text('所有映射索引数据已清空。'),
                      actions: [
                        CupertinoDialogAction(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  );
                }
              } catch (e) {
                await _dataManager.addLog('清空映射索引失败: $e', type: LogType.error);
                if (mounted) {
                  showCupertinoDialog(
                    context: context,
                    builder: (context) => CupertinoAlertDialog(
                      title: const Text('操作失败'),
                      content: Text('清空映射索引时出错: $e'),
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


import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import '../widgets/adaptive_top_bar.dart';

class VersionView extends StatelessWidget {
  const VersionView({super.key});

  // 版本号统一在这里定义，ConfigView 会通过此常量获取
  static const String appVersion = 'v0.9.9';

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    double scrollOffset = 0;

    return CupertinoPageScaffold(
      backgroundColor: Colors.transparent,
      child: Container(
        color: backgroundColor,
        child: SafeArea(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
                // 不需要更新状态
              }
              return false;
            },
            child: Column(
              children: [
                AdaptiveTopBar(
                  scrollOffset: scrollOffset,
                  showBack: true,
                  onBack: () => Navigator.of(context).pop(),
                  showRefresh: false,
                  showExpandCollapse: false,
                  showSearch: false,
                  showReset: false,
                  showFilter: false,
                  showSort: false,
                  backgroundColor: Colors.transparent,
                  iconColor: CupertinoTheme.of(context).primaryColor,
                  iconSize: 24,
                  buttonSpacing: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 头部区域：图标 + 标题 + 副标题 + 标签 + 版本信息（紧凑一行）
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 图标占位（后续可自定义替换）
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF6366F1),
                                    const Color(0xFF8B5CF6),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                CupertinoIcons.chart_bar_fill,
                                size: 24,
                                color: CupertinoColors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // 标题区域
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'FundLink',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '一基暴富',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isDarkMode
                                              ? CupertinoColors.white.withOpacity(0.6)
                                              : CupertinoColors.systemGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6366F1).withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '基金用户管理系统',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: const Color(0xFF6366F1),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        appVersion,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDarkMode
                                              ? CupertinoColors.white.withOpacity(0.5)
                                              : CupertinoColors.systemGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // 主要功能标题
                        Text(
                          '主要功能',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 主要功能列表（紧凑分行）
                        Wrap(
                          spacing: 16,
                          runSpacing: 10,
                          children: [
                            _buildFeatureItem(CupertinoIcons.doc_plaintext, '基金持仓管理', isDarkMode),
                            _buildFeatureItem(CupertinoIcons.square_grid_2x2, '多维度视图', isDarkMode),
                            _buildFeatureItem(CupertinoIcons.chart_bar, '实时净值估算', isDarkMode),
                            _buildFeatureItem(CupertinoIcons.arrow_clockwise, '基金详情回溯', isDarkMode),
                            _buildFeatureItem(CupertinoIcons.moon_stars, '主题模式', isDarkMode),
                            _buildFeatureItem(CupertinoIcons.lock_fill, '用户隐私模式', isDarkMode),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // 功能待开发标题
                        Text(
                          '功能待开发',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          runSpacing: 10,
                          children: [
                            _buildFeatureItem(CupertinoIcons.cloud_upload, '数据导入及导出', isDarkMode),
                          ],
                        ),
                        const SizedBox(height: 32),
                        // 版权信息
                        Center(
                          child: Text(
                            '© 2026 Rizona',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDarkMode
                                  ? CupertinoColors.white.withOpacity(0.3)
                                  : CupertinoColors.systemGrey.withOpacity(0.5),
                            ),
                          ),
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

  Widget _buildFeatureItem(IconData icon, String label, bool isDarkMode) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: isDarkMode
              ? CupertinoColors.white.withOpacity(0.7)
              : const Color(0xFF6366F1),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDarkMode
                ? CupertinoColors.white.withOpacity(0.85)
                : CupertinoColors.label,
          ),
        ),
      ],
    );
  }
}
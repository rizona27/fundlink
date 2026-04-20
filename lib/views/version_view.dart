import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import '../widgets/adaptive_top_bar.dart';

class VersionView extends StatelessWidget {
  const VersionView({super.key});

  // 版本号统一在这里定义，ConfigView 会通过此常量获取
  static const String appVersion = 'v1.0.0';

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    double scrollOffset = 0;

    // 生成随机邮箱颜色（饱和0.7，亮度0.6，保证可见性）
    final randomEmailColor = HSLColor.fromAHSL(
      1,
      Random().nextDouble() * 360,
      0.7,
      0.6,
    ).toColor();

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
                            // 使用生成的应用图标
                            _buildAppIcon(isDarkMode),
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
                        // 主要功能列表（包含数据导入及导出）
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
                            _buildFeatureItem(CupertinoIcons.cloud_upload, '数据导入及导出', isDarkMode),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // 程序说明区块
                        Text(
                          '程序说明',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInstructionItem('1. 持仓数据可通过主界面/设置-新增持仓/导入添加。', isDarkMode),
                            _buildInstructionItem('2. 实时估值倒计时可长按修改默认间隔', isDarkMode),
                            _buildInstructionItem('3. 主功能页刷新可轻触单独刷新/长按全量刷新', isDarkMode),
                            _buildInstructionItem('4. 筛选及搜索功能支持各字段、维度，添加防抖', isDarkMode),
                            _buildInstructionItem('5. 未公布持仓基金无法获取十大重仓及实时估值。', isDarkMode),
                            _buildInstructionItem('6. 实时估值可能存在偏离度，季报末尤甚，仅供参考。', isDarkMode),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // 联系作者（固定蓝色 + 随机颜色邮箱）
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Mail:',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FontStyle.italic,
                                  color: CupertinoColors.activeBlue,
                                ),
                              ),
                              Text(
                                'rizona.cn@gmail.com',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FontStyle.italic,
                                  color: randomEmailColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 27),
                        // 说明文字（淡灰色，居中）
                        Align(
                          alignment: Alignment.center,
                          child: Text(
                            '仅供个人学习交流使用，数据仅供参考，投资需谨慎。',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDarkMode
                                  ? CupertinoColors.white.withOpacity(0.5)
                                  : CupertinoColors.systemGrey.withOpacity(0.7),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        // 版权信息
                        Center(
                          child: Text(
                            '© 2026 Developed by Rizona.',
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

  // 构建应用图标（使用生成的应用图标）
  Widget _buildAppIcon(bool isDarkMode) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/icon/app_icon.png',
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          // 如果图标加载失败，显示渐变占位符
          return Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF6366F1),
                  Color(0xFF8B5CF6),
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
          );
        },
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

  // 程序说明项（纯文本，带序号，淡灰色）
  Widget _buildInstructionItem(String text, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: isDarkMode
              ? CupertinoColors.white.withOpacity(0.7)
              : CupertinoColors.systemGrey.withOpacity(0.8),
          height: 1.4,
        ),
      ),
    );
  }
}
import 'dart:convert';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import '../widgets/adaptive_top_bar.dart';
import '../services/data_manager.dart';
import '../services/version_check_service.dart';
import '../constants/app_constants.dart';

String APP_VERSION = AppConstants.appVersionWithPrefix;

const List<String> UPDATE_LOGS = [
  'v1.4.1 - 代码整体优化：统一颜色常量、消除重复逻辑、修复空安全问题、架构分层调整',
  'v1.4.0 - 优化了部分已知问题',
  'v1.3.9 - 重构数据中心架构：拆分为门面模式+子通知器，性能优化与漏洞修复',
  'v1.3.8 - 排序切换及顶部菜单栏优化',
  'v1.3.7 - 重构客户组合分析页面：整合持仓盈亏图表、优化风格/行业分布展示',
  'v1.3.6 - 优化加减仓逻辑，DB schema升级持久化完整交易状态',
  'v1.3.5 - 新增业绩走势图片导出及自定义区间测算',
  'v1.3.4 - 新增文件分享导入，优化模板和导入格式',
  'v1.3.3 - 优化Toast提示与主题的适配',
  'v1.3.2 - 优化持仓置顶/回滚顶部按钮，重构日志/设置菜单',
  'v1.3.1 - 新增各数据页返回顶部按钮动画',
  'v1.3.0 - 新增映射索引，自动匹配用户名/用户号对应关系',
  'v1.2.8 - 优化主题切换',
  'v1.2.7 - 优化估值查询逻辑，修复图表显示',
  'v1.2.6 - 修复数据持久化问题，新增应用生命周期管理',
  'v1.2.5 - 新增跨平台内存监控、修复Web端编译问题',
  'v1.2.4 - 数据访问层封装，SQLite 存储，优化TTL 过期和容量限制',
  'v1.2.3 - 安全加固：新增文件大小限制、客户姓名长度限制、错误消息脱敏',
  'v1.2.2 - 估值模块根据交易时间优化，优化股票图在不同网络下的表现',
  'v1.2.1 - 优化版本检测逻辑、多端下载支持',
  'v1.2.0 - 新增版本检测',
  'v1.1.9 - 新增全局常量管理，统一API、缓存，设计冗余逻辑，优化日志系统',
  'v1.1.8 - 新增本地缓存功能，已缓存数据支持离线，体验大幅提升',
  'v1.1.7 - 优化十大重仓股布局，新增股票K线蜡烛图功能，支持查看历史数据',
  'v1.1.6 - 编辑持仓列表性能优化，客户排序优化，深色模式可见性改进',
  'v1.1.5 - iOS端插件引用及请求并发优化，修改了部分UI',
  'v1.1.4 - 文件导入兼容性改进，智能格式检测',
  'v1.1.3 - 优化交易记录编辑体验，精简代码结构',
  'v1.1.2 - 节假日、交易日判断优化、待确认交易提示改进',
  'v1.1.1 - 智能开市检测、市场状态监控、待确认交易优化、视图刷新修复',
  'v1.1.0 - 性能优化：更新机制、LRU缓存、懒加载、排序缓存、预计算',
  'v1.0.9 - 优化工具栏，增加自动收回效果；优化持仓列表逻辑',
  'v1.0.8 - 优化基金对比图表；修复自定义基金模块错误',
  'v1.0.7 - 新增一览展开按钮，跳转基金详情；优化动画效果',
  'v1.0.6 - 新增自定义基金对比；优化图例显示，动态显示/隐藏指标',
  'v1.0.5 - 新增中证500、中证1000指数；优化基金数据源',
  'v1.0.4 - 新增待确认交易队列；支持延时自动确认净值',
  'v1.0.3 - 优化收益计算逻辑；支持绝对与年化收益率',
  'v1.0.2 - 新增导入导出功能；支持模糊匹配',
  'v1.0.1 - 新增实时估值刷新；自定义刷新间隔',
  'v1.0.0 - FundLink 正式版',
];

const String ACKNOWLEDGMENT_LINE_1 = '感谢参与测试的小伙伴：miner2011m、qiu_kw、naniezy、leo_pengtao、JMW0802、yizhixiaozhuti';
const String ACKNOWLEDGMENT_LINE_2 = '愿大家一基暴富～！';

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle textStyle;
  final double velocity;

  const _MarqueeText({
    required this.text,
    required this.textStyle,
    this.velocity = 30.0,
  });

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _VerticalMarqueeText extends StatefulWidget {
  final List<String> items;
  final TextStyle itemTextStyle;
  final double velocity;

  const _VerticalMarqueeText({
    required this.items,
    required this.itemTextStyle,
    this.velocity = 25.0,
  });

  @override
  State<_VerticalMarqueeText> createState() => _VerticalMarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _offset = 0;
  double _containerWidth = 0;
  bool _animationStarted = false;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  void _startAnimation(double containerWidth) {
    if (_animationStarted) return;

    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.textStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final textWidth = textPainter.width;
    _containerWidth = containerWidth;

    final totalDistance = textWidth + containerWidth;
    final duration = Duration(milliseconds: (totalDistance / widget.velocity * 1000).round());

    _controller.duration = duration;
    final animation = Tween<double>(begin: containerWidth, end: -textWidth).animate(_controller);
    animation.addListener(() {
      if (mounted) setState(() => _offset = animation.value);
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _controller.forward(from: 0);
      }
    });

    setState(() {
      _offset = containerWidth;
      _animationStarted = true;
    });
    _controller.forward();
  }

  void _pauseAnimation() {
    if (!_isPaused && _controller.isAnimating) {
      _controller.stop();
      setState(() {
        _isPaused = true;
      });
    }
  }

  void _resumeAnimation() {
    if (_isPaused && !_controller.isAnimating) {
      _controller.forward();
      setState(() {
        _isPaused = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth;

        if (!_animationStarted && containerWidth > 0 && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_animationStarted) _startAnimation(containerWidth);
          });
        }

        if (!_animationStarted) {
          return Center(
            child: Text(
              widget.text,
              style: widget.textStyle,
              maxLines: 1,
              softWrap: false,
            ),
          );
        }

        return MouseRegion(
          onEnter: (_) => _pauseAnimation(),
          onExit: (_) => _resumeAnimation(),
          child: GestureDetector(
            onTapDown: (_) => _pauseAnimation(),
            onTapUp: (_) => _resumeAnimation(),
            onTapCancel: () => _resumeAnimation(),
            child: SizedBox(
              height: double.infinity,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: _offset,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.text,
                        style: widget.textStyle,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VersionUpdateButton extends StatefulWidget {
  final VoidCallback? onSmartNavigate;
  final bool hasUpdate;

  const _VersionUpdateButton({this.onSmartNavigate, this.hasUpdate = false});

  @override
  State<_VersionUpdateButton> createState() => _VersionUpdateButtonState();
}

class _VersionUpdateButtonState extends State<_VersionUpdateButton> {
  bool _isChecking = false;

  Future<void> _handleUpdateTap() async {
    if (_isChecking) return;

    if (mounted) {
      setState(() {
        _isChecking = true;
      });
    }

    try {
      final dataManager = DataManagerProvider.of(context);
      final versionInfo = dataManager.latestVersionInfo;

      if (versionInfo != null) {
        await _showUpdateDialog(versionInfo);
      } else {
        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

        if (mounted) {
          showCupertinoDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const CupertinoAlertDialog(
              content: Row(
                children: [
                  CupertinoActivityIndicator(),
                  SizedBox(width: 16),
                  Text('检查版本中...'),
                ],
              ),
            ),
          );
        }

        final newVersionInfo = await VersionCheckService.checkLatestVersion(currentVersion);

        if (mounted) {
          Navigator.of(context).pop();
        }

        if (newVersionInfo != null && mounted) {
          dataManager.setLatestVersionInfo(newVersionInfo);
          await _showUpdateDialog(newVersionInfo);
        } else {
          await _smartNavigate();
        }
      }
    } catch (e) {
      if (mounted) {
        await _smartNavigate();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _smartNavigate() async {
    if (widget.onSmartNavigate != null) {
      widget.onSmartNavigate?.call();
      return;
    }

    final url = Uri.parse(AppConstants.nasBackendUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showUpdateDialog(VersionInfo versionInfo) async {
    if (!mounted) return;

    if (!versionInfo.hasUpdate) {
      final shouldOpen = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('当前已是最新版本'),
          content: Text('Version: ${versionInfo.version} \n\n是否仍要打开下载页面？'),
          actions: [
            CupertinoDialogAction(
              child: const Text('取消'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('打开'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );

      if (shouldOpen == true && mounted) {
        await _smartNavigate();
      }
    } else {
      final shouldOpen = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('发现新版本'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('最新版本: ${versionInfo.version}'),
              const SizedBox(height: 8),
              if (versionInfo.releaseNotes.isNotEmpty)
                Text('更新内容:\n${versionInfo.releaseNotes}'),
              const SizedBox(height: 8),
              const Text('是否前往下载页面？'),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('稍后'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('前往下载'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );

      if (shouldOpen == true && mounted) {
        await _smartNavigate();
      }
    }
  }

  Future<void> _openProjectUrl() async {
    final versionViewState = context.findAncestorStateOfType<_VersionViewState>();

    if (versionViewState != null) {
      await versionViewState._handleUpdateTap();
      return;
    }

    final url = Uri.parse(AppConstants.nasBackendUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = AppConstants.isDark(context);

    return GestureDetector(
      onTap: _handleUpdateTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _isChecking
              ? (widget.hasUpdate ? AppConstants.warningOrange.withOpacity(0.5) : AppConstants.primaryBlue.withOpacity(0.5))
              : (widget.hasUpdate ? AppConstants.warningOrange : AppConstants.primaryBlue),
          borderRadius: BorderRadius.circular(12),
        ),
        child: _isChecking
            ? const SizedBox(
          width: 14,
          height: 14,
          child: CupertinoActivityIndicator(radius: 7),
        )
            : Text(
          widget.hasUpdate ? 'Update' : 'Homepage',
          style: TextStyle(
            color: CupertinoColors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class VersionView extends StatefulWidget {
  const VersionView({super.key});

  @override
  State<VersionView> createState() => _VersionViewState();
}

class _VersionViewState extends State<VersionView> {
  bool _hasUpdate = false;

  late Color _mailColor;

  @override
  void initState() {
    super.initState();
    _mailColor = HSLColor.fromAHSL(
      1,
      Random().nextDouble() * 360,
      0.7,
      0.6,
    ).toColor();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVersionOnStartup();
    });
  }


  Future<void> _checkVersionOnStartup() async {
    try {
      final dataManager = DataManagerProvider.of(context);
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

      final versionInfo = await VersionCheckService.checkLatestVersion(currentVersion);

      if (mounted && versionInfo != null) {
        dataManager.setLatestVersionInfo(versionInfo);
        setState(() {
          _hasUpdate = versionInfo.hasUpdate;
        });
      }
    } catch (e) {
    }
  }

  Future<void> _handleUpdateTap() async {
    final state = context.findAncestorStateOfType<_VersionUpdateButtonState>();
    if (state != null) {
      await state._handleUpdateTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = AppConstants.isDark(context);
    final backgroundColor = isDarkMode ? AppConstants.darkBackground : AppConstants.lightBackground;
    double scrollOffset = 0;

    return CupertinoPageScaffold(
      backgroundColor: Colors.transparent,
      child: Container(
        color: backgroundColor,
        child: SafeArea(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
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
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildAppIcon(isDarkMode),
                            const SizedBox(width: 12),
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
                                          color: AppConstants.accentIndigo.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '基金持仓管理助手',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: AppConstants.accentIndigo,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        APP_VERSION,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDarkMode
                                              ? CupertinoColors.white.withOpacity(0.5)
                                              : CupertinoColors.systemGrey,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _VersionUpdateButton(
                                        onSmartNavigate: _handleUpdateTap,
                                        hasUpdate: _hasUpdate,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '主要功能',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildFeatureItemWithText(CupertinoIcons.chart_bar_fill, '基金一览：查看基金业绩指标，对比基准', isDarkMode),
                        const SizedBox(height: 8),
                        _buildFeatureItemWithText(CupertinoIcons.person_2_fill, '客户持仓：增删客户持仓情况，分析收益', isDarkMode),
                        const SizedBox(height: 8),
                        _buildFeatureItemWithText(CupertinoIcons.star_fill, '业绩排名：不同维度排序筛选，确定范围', isDarkMode),
                        const SizedBox(height: 8),
                        _buildFeatureItemWithText(CupertinoIcons.cloud_upload, '数据管理：批量进行导入导出，统一维护', isDarkMode),
                        const SizedBox(height: 8),
                        _buildFeatureItemWithText(CupertinoIcons.lock_fill, '个性设定：隐私主题自由设置，适应需求', isDarkMode),
                        const SizedBox(height: 24),
                        _buildUpdateLogMarquee(isDarkMode),
                        const SizedBox(height: 16),
                        // ── Feedback button ──
                        Align(
                          alignment: Alignment.center,
                          child: CupertinoButton(
                            onPressed: () => _showFeedbackDialog(context, isDarkMode),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            color: CupertinoColors.systemGrey.withOpacity(0.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.chat_bubble_text_fill,
                                  size: 16,
                                  color: AppConstants.primaryBlue,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '意见和反馈',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppConstants.primaryBlue,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.center,
                          child: Text(
                            '本项目仅供个人学习与技术交流使用\n数据仅供参考，不构成任何投资建议',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDarkMode
                                  ? CupertinoColors.white.withOpacity(0.5)
                                  : CupertinoColors.systemGrey.withOpacity(0.7),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
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

  Widget _buildAppIcon(bool isDarkMode) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/icon/app_icon.png',
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  AppConstants.accentIndigo,
                  AppConstants.accentPurple,
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

  Widget _buildFeatureItem(IconData icon, String label, bool isDarkMode, [double? fontSize, double? iconSize]) {
    final textSize = fontSize ?? 13.0;
    final iSize = iconSize ?? 14.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: iSize,
          color: isDarkMode
              ? CupertinoColors.white.withOpacity(0.7)
              : AppConstants.accentIndigo,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: textSize,
            color: isDarkMode
                ? CupertinoColors.white.withOpacity(0.85)
                : CupertinoColors.label,
          ),
        ),
      ],
    );
  }

  Widget _buildSimpleText(String text, bool isDarkMode) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        height: 1.4,
        color: isDarkMode
            ? CupertinoColors.white.withOpacity(0.7)
            : CupertinoColors.systemGrey,
      ),
    );
  }

  Widget _buildFeatureItemWithText(IconData icon, String text, bool isDarkMode) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: isDarkMode
              ? CupertinoColors.white.withOpacity(0.6)
              : AppConstants.accentIndigo,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: isDarkMode
                  ? CupertinoColors.white.withOpacity(0.7)
                  : CupertinoColors.systemGrey,
            ),
          ),
        ),
      ],
    );
  }

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

  Widget _buildAcknowledgmentMarquee(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '致谢',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: isDarkMode
                ? AppConstants.darkCardBg.withOpacity(0.6)
                : CupertinoColors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDarkMode
                  ? CupertinoColors.white.withOpacity(0.1)
                  : CupertinoColors.systemGrey.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: _MarqueeText(
              text: '感谢参与测试的小伙伴：miner2011m、qiu_kw、naniezy   |愿大家一基暴富～！',
              textStyle: TextStyle(
                fontSize: 13,
                color: isDarkMode
                    ? CupertinoColors.white.withOpacity(0.8)
                    : CupertinoColors.systemGrey.withOpacity(0.9),
              ),
              velocity: 30.0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUpdateLogMarquee(bool isDarkMode) {
    final recentLogs = UPDATE_LOGS.take(5).toList();
    final hasMoreLogs = UPDATE_LOGS.length > 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '更新历史',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
              ),
            ),
            if (hasMoreLogs)
              GestureDetector(
                onTap: () => _showFullHistoryDialog(context, isDarkMode),
                child: Text(
                  '...更多',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppConstants.primaryBlue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isDarkMode
                ? AppConstants.darkCardBg.withOpacity(0.6)
                : CupertinoColors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDarkMode
                  ? CupertinoColors.white.withOpacity(0.1)
                  : CupertinoColors.systemGrey.withOpacity(0.2),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ACKNOWLEDGMENT_LINE_1,
                style: TextStyle(
                  fontSize: 12,
                  color: isDarkMode
                      ? CupertinoColors.white.withOpacity(0.8)
                      : CupertinoColors.systemGrey.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                ACKNOWLEDGMENT_LINE_2,
                style: TextStyle(
                  fontSize: 12,
                  color: isDarkMode
                      ? CupertinoColors.white.withOpacity(0.8)
                      : CupertinoColors.systemGrey.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 8),
              Divider(
                height: 1,
                color: isDarkMode
                    ? CupertinoColors.white.withOpacity(0.1)
                    : CupertinoColors.systemGrey.withOpacity(0.2),
              ),
              const SizedBox(height: 8),
              ...recentLogs.map((log) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  log,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode
                        ? CupertinoColors.white.withOpacity(0.8)
                        : CupertinoColors.systemGrey.withOpacity(0.9),
                  ),
                ),
              )).toList(),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Mail:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                        color: _mailColor,
                      ),
                    ),
                    Text(
                      ' rizona.cn@gmail.com',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                        color: _mailColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showFullHistoryDialog(BuildContext context, bool isDarkMode) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
              child: GestureDetector(
                onTap: () {},
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? AppConstants.darkBackground
                          : CupertinoColors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isDarkMode
                                    ? CupertinoColors.white.withOpacity(0.1)
                                    : CupertinoColors.systemGrey.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '更新历史',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDarkMode
                                      ? CupertinoColors.white
                                      : CupertinoColors.label,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.of(context).pop(),
                                child: Icon(
                                  CupertinoIcons.xmark_circle_fill,
                                  size: 24,
                                  color: isDarkMode
                                      ? CupertinoColors.white.withOpacity(0.6)
                                      : CupertinoColors.systemGrey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ...UPDATE_LOGS.map((log) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    log,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDarkMode
                                          ? CupertinoColors.white.withOpacity(0.8)
                                          : CupertinoColors.systemGrey.withOpacity(0.9),
                                    ),
                                  ),
                                )).toList(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
    );
  }

  // ── Feedback dialog ──────────────────────────────────────────

  void _showFeedbackDialog(BuildContext context, bool isDarkMode) {
    final nameController = TextEditingController();
    final contentController = TextEditingController();
    final contactValueController = TextEditingController();
    String? contactType;
    bool isSubmitting = false;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: '关闭',
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                constraints: const BoxConstraints(maxWidth: 500),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? AppConstants.darkBackground
                          : CupertinoColors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Title bar ──
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isDarkMode
                                    ? CupertinoColors.white.withOpacity(0.1)
                                    : CupertinoColors.systemGrey.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '意见和反馈',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDarkMode
                                      ? CupertinoColors.white
                                      : CupertinoColors.label,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.of(context).pop(),
                                child: Icon(
                                  CupertinoIcons.xmark_circle_fill,
                                  size: 24,
                                  color: isDarkMode
                                      ? CupertinoColors.white.withOpacity(0.6)
                                      : CupertinoColors.systemGrey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ── Form body ──
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Name field (required) ──
                                Text(
                                  '您的称呼 *',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isDarkMode
                                        ? CupertinoColors.white.withOpacity(0.8)
                                        : CupertinoColors.label,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                CupertinoTextField(
                                  controller: nameController,
                                  placeholder: '请输入您的称呼',
                                  padding: const EdgeInsets.all(12),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? AppConstants.darkCardBg
                                        : CupertinoColors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isDarkMode
                                          ? CupertinoColors.white.withOpacity(0.2)
                                          : CupertinoColors.systemGrey.withOpacity(0.3),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // ── Content field (required) ──
                                Text(
                                  '意见/建议内容 *',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isDarkMode
                                        ? CupertinoColors.white.withOpacity(0.8)
                                        : CupertinoColors.label,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                CupertinoTextField(
                                  controller: contentController,
                                  placeholder: '请输入您的意见或建议（最多300字）',
                                  maxLines: 4,
                                  maxLength: 300,
                                  padding: const EdgeInsets.all(12),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? AppConstants.darkCardBg
                                        : CupertinoColors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isDarkMode
                                          ? CupertinoColors.white.withOpacity(0.2)
                                          : CupertinoColors.systemGrey.withOpacity(0.3),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // ── Contact type selector (optional) ──
                                Text(
                                  '联系方式（选填）',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isDarkMode
                                        ? CupertinoColors.white.withOpacity(0.8)
                                        : CupertinoColors.label,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: ['电话', '微信', '其他'].map((type) {
                                    final isSelected = contactType == type;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: GestureDetector(
                                        onTap: () {
                                          setDialogState(() {
                                            contactType = isSelected ? null : type;
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? AppConstants.primaryBlue.withOpacity(0.15)
                                                : (isDarkMode
                                                    ? AppConstants.darkCardBg
                                                    : CupertinoColors.white),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isSelected
                                                  ? AppConstants.primaryBlue
                                                  : (isDarkMode
                                                      ? CupertinoColors.white.withOpacity(0.2)
                                                      : CupertinoColors.systemGrey.withOpacity(0.3)),
                                            ),
                                          ),
                                          child: Text(
                                            type,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: isSelected
                                                  ? AppConstants.primaryBlue
                                                  : (isDarkMode
                                                      ? CupertinoColors.white.withOpacity(0.7)
                                                      : CupertinoColors.systemGrey),
                                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 8),

                                // ── Contact value field (optional) ──
                                CupertinoTextField(
                                  controller: contactValueController,
                                  placeholder: contactType != null
                                      ? '请输入${contactType}号码（最多20个字符）'
                                      : '请先选择联系方式类型',
                                  maxLength: 20,
                                  enabled: contactType != null,
                                  padding: const EdgeInsets.all(12),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
                                  ),
                                  decoration: BoxDecoration(
                                    color: contactType != null
                                        ? (isDarkMode ? AppConstants.darkCardBg : CupertinoColors.white)
                                        : (isDarkMode
                                            ? AppConstants.darkCardBg.withOpacity(0.4)
                                            : CupertinoColors.white.withOpacity(0.5)),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isDarkMode
                                          ? CupertinoColors.white.withOpacity(0.2)
                                          : CupertinoColors.systemGrey.withOpacity(0.3),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // ── Submit button ──
                                SizedBox(
                                  width: double.infinity,
                                  child: CupertinoButton(
                                    onPressed: isSubmitting
                                        ? null
                                        : () async {
                                            if (nameController.text.trim().isEmpty) {
                                              _showFeedbackToast(context, '请填写您的称呼', isDarkMode);
                                              return;
                                            }
                                            if (contentController.text.trim().isEmpty) {
                                              _showFeedbackToast(context, '请填写意见内容', isDarkMode);
                                              return;
                                            }
                                            setDialogState(() => isSubmitting = true);
                                            try {
                                              await _submitFeedback(
                                                nameController.text.trim(),
                                                contentController.text.trim(),
                                                contactType,
                                                contactValueController.text.trim(),
                                              );
                                              if (context.mounted) {
                                                Navigator.of(context).pop();
                                                _showFeedbackToast(context, '感谢您的反馈！', isDarkMode);
                                              }
                                            } catch (e) {
                                              setDialogState(() => isSubmitting = false);
                                              if (context.mounted) {
                                                _showFeedbackToast(context, '提交失败，请稍后再试', isDarkMode);
                                              }
                                            }
                                          },
                                    color: AppConstants.primaryBlue,
                                    borderRadius: BorderRadius.circular(10),
                                    child: isSubmitting
                                        ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                                        : const Text(
                                            '提交反馈',
                                            style: TextStyle(
                                              color: CupertinoColors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                            ),
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
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _submitFeedback(String name, String content, String? contactType, String? contactValue) async {
    final body = <String, dynamic>{
      'name': name,
      'content': content,
    };
    if (contactType != null && contactValue != null && contactValue.isNotEmpty) {
      body['contact_type'] = contactType;
      body['contact_value'] = contactValue;
    }

    final uri = Uri.parse('${AppConstants.nasBackendUrl}/api/feedback');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': AppConstants.userAgentApp,
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }
  }

  void _showFeedbackToast(BuildContext context, String message, bool isDarkMode) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        content: Text(
          message,
          style: TextStyle(
            color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _VerticalMarqueeTextState extends State<_VerticalMarqueeText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _offset = 0;
  double _containerHeight = 0;
  bool _animationStarted = false;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  void _startAnimation(double containerHeight) {
    if (_animationStarted) return;

    final textPainter = TextPainter(
      text: TextSpan(text: widget.items.join('\n'), style: widget.itemTextStyle),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: 300);
    final totalTextHeight = textPainter.height + (widget.items.length - 1) * 8;

    _containerHeight = containerHeight;
    final totalDistance = totalTextHeight + containerHeight;
    final duration = Duration(milliseconds: (totalDistance / widget.velocity * 1000).round());

    _controller.duration = duration;
    final animation = Tween<double>(begin: containerHeight, end: -totalTextHeight).animate(_controller);
    animation.addListener(() {
      if (mounted) setState(() => _offset = animation.value);
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && !_controller.isAnimating) {
            _controller.forward(from: 0);
          }
        });
      }
    });

    setState(() {
      _offset = containerHeight;
      _animationStarted = true;
    });
    _controller.forward();
  }

  void _pauseAnimation() {
    if (!_isPaused && _controller.isAnimating) {
      _controller.stop();
      setState(() {
        _isPaused = true;
      });
    }
  }

  void _resumeAnimation() {
    if (_isPaused && !_controller.isAnimating) {
      _controller.forward();
      setState(() {
        _isPaused = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerHeight = constraints.maxHeight;

        if (!_animationStarted && containerHeight > 0 && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_animationStarted) _startAnimation(containerHeight);
          });
        }

        if (!_animationStarted) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: widget.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  item,
                  style: widget.itemTextStyle,
                ),
              )).toList(),
            ),
          );
        }

        return MouseRegion(
          onEnter: (_) => _pauseAnimation(),
          onExit: (_) => _resumeAnimation(),
          child: GestureDetector(
            onTapDown: (_) => _pauseAnimation(),
            onTapUp: (_) => _resumeAnimation(),
            onTapCancel: () => _resumeAnimation(),
            child: SizedBox(
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _offset,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: widget.items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                        child: Text(
                          item,
                          style: widget.itemTextStyle,
                        ),
                      )).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
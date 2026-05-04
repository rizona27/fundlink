import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import '../widgets/adaptive_top_bar.dart';
import '../services/data_manager.dart';
import '../services/version_check_service.dart';
import '../constants/app_constants.dart';

const String APP_VERSION = 'v1.2.5';

const List<String> UPDATE_LOGS = [
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

/// 版本更新按钮组件
class _VersionUpdateButton extends StatefulWidget {
  final VoidCallback? onSmartNavigate;
  
  const _VersionUpdateButton({this.onSmartNavigate});

  @override
  State<_VersionUpdateButton> createState() => _VersionUpdateButtonState();
}

class _VersionUpdateButtonState extends State<_VersionUpdateButton> {
  bool _isChecking = false;

  Future<void> _handleUpdateTap() async {
    if (_isChecking) return; // 防止重复点击
    
    if (mounted) {  // ✅ 添加 mounted 检查
      setState(() {
        _isChecking = true;
      });
    }

    try {
      final dataManager = DataManagerProvider.of(context);
      final versionInfo = dataManager.latestVersionInfo;
      
      // 如果已经有版本信息，直接判断
      if (versionInfo != null) {
        await _showUpdateDialog(versionInfo);
      } else {
        // 如果没有版本信息，先检查一次
        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
        
        // 显示加载提示
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
        
        // 关闭加载提示
        if (mounted) {
          Navigator.of(context).pop();
        }
        
        if (newVersionInfo != null && mounted) {
          // 更新缓存的版本信息
          dataManager.setLatestVersionInfo(newVersionInfo);
          await _showUpdateDialog(newVersionInfo);
        } else {
          // 检查失败，使用智能导航
          await _smartNavigate();
        }
      }
    } catch (e) {
      debugPrint('版本检查异常: $e');
      // 异常情况下使用智能导航
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
    // 尝试获取父widget的智能导航回调
    if (widget.onSmartNavigate != null) {
      widget.onSmartNavigate!();
      return;
    }
    
    // 否则默认打开NAS后端
    final url = Uri.parse(AppConstants.nasBackendUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showUpdateDialog(VersionInfo versionInfo) async {
    if (!mounted) return;
    
    if (!versionInfo.hasUpdate) {
      // 当前已是最新版本
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
        // 使用智能导航
        await _smartNavigate();
      }
    } else {
      // 有新版本可用
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
        // 使用智能导航
        await _smartNavigate();
      }
    }
  }

  Future<void> _openProjectUrl() async {
    // 获取父widget的连通性状态
    final versionViewState = context.findAncestorStateOfType<_VersionViewState>();
    
    if (versionViewState != null) {
      // 使用智能导航逻辑
      await versionViewState._handleUpdateTap();
      return;
    }
    
    // Fallback: 默认打开NAS后端
    final url = Uri.parse(AppConstants.nasBackendUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleUpdateTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _isChecking 
              ? const Color(0xFF007AFF).withOpacity(0.5)
              : const Color(0xFF007AFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: _isChecking
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CupertinoActivityIndicator(radius: 7),
              )
            : const Text(
                'Update',
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
  bool _isCheckingConnectivity = false;
  bool? _nasConnected;
  bool? _githubConnected;
  int? _nasLatency;
  int? _githubLatency;

  @override
  void initState() {
    super.initState();
    // 启动时自动检查版本和连通性
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVersionOnStartup();
      // 延迟500ms后检查连通性，避免同时发起太多请求
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _checkConnectivity();
        }
      });
    });
  }

  Future<void> _checkVersionOnStartup() async {
    try {
      final dataManager = DataManagerProvider.of(context);
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      
      // 后台检查版本，不阻塞UI
      final versionInfo = await VersionCheckService.checkLatestVersion(currentVersion);
      
      if (mounted && versionInfo != null) {
        dataManager.setLatestVersionInfo(versionInfo);
      }
    } catch (e) {
      debugPrint('启动时版本检查失败: $e');
    }
  }

  Future<void> _checkConnectivity() async {
    if (_isCheckingConnectivity) return;
    
    setState(() {
      _isCheckingConnectivity = true;
      _nasConnected = null;
      _githubConnected = null;
      _nasLatency = null;
      _githubLatency = null;
    });

    // 同时检查两个连接 - 都使用API端点进行公平比较
    final nasFuture = _testConnection('${AppConstants.nasBackendUrl}/api/version');
    final githubFuture = _testConnection(AppConstants.githubReleaseApiUrl);
    
    final results = await Future.wait([nasFuture, githubFuture]);
    
    if (mounted) {
      setState(() {
        _nasConnected = results[0].connected;
        _nasLatency = results[0].latency;
        _githubConnected = results[1].connected;
        _githubLatency = results[1].latency;
        _isCheckingConnectivity = false;
      });
    }
  }

  Future<({bool connected, int? latency})> _testConnection(String url) async {
    try {
      final startTime = DateTime.now();
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': AppConstants.userAgentApp},
      ).timeout(const Duration(seconds: 5));
      final endTime = DateTime.now();
      
      final latency = endTime.difference(startTime).inMilliseconds;
      return (connected: response.statusCode == 200, latency: latency);
    } catch (e) {
      return (connected: false, latency: null);
    }
  }

  Future<void> _handleUpdateTap() async {
    debugPrint('========== Update按钮点击 ==========');
    debugPrint('_nasConnected: $_nasConnected');
    debugPrint('_githubConnected: $_githubConnected');
    debugPrint('_nasLatency: $_nasLatency');
    debugPrint('_githubLatency: $_githubLatency');
    
    // 如果已经有连通性数据，根据连接状态智能选择
    if (_nasConnected != null || _githubConnected != null) {
      // 优先使用后端服务器，只有后端不可用时才用GitHub
      if (_nasConnected == true) {
        // 后端可用，直接使用后端
        debugPrint('========== 智能导航决策 ==========');
        debugPrint('NAS: 已连接 (${_nasLatency}ms)');
        debugPrint('GitHub: ${_githubConnected == true ? "已连接 (${_githubLatency}ms)" : "连接失败"}');
        debugPrint('选择: NAS (fundlink.cr315.com) - 优先策略');
        debugPrint('=================================');
        
        final uri = Uri.parse(AppConstants.nasBackendUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        return;
      }
      
      // 后端不可用，使用GitHub
      if (_githubConnected == true) {
        debugPrint('========== 智能导航决策 ==========');
        debugPrint('NAS: 连接失败');
        debugPrint('GitHub: 已连接 (${_githubLatency}ms)');
        debugPrint('选择: GitHub Release - 后端不可用');
        debugPrint('=================================');
        
        final uri = Uri.parse(AppConstants.githubReleasePageUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        return;
      }
      
      // 两者都不可用，默认使用GitHub
      debugPrint('========== 智能导航决策 ==========');
      debugPrint('NAS: 连接失败');
      debugPrint('GitHub: 连接失败');
      debugPrint('选择: GitHub Release (默认)');
      debugPrint('=================================');
      
      final uri = Uri.parse(AppConstants.githubReleasePageUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    
    // 否则使用原有逻辑（检查版本后决定）
    final state = context.findAncestorStateOfType<_VersionUpdateButtonState>();
    if (state != null) {
      await state._handleUpdateTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    double scrollOffset = 0;

    final randomColor = HSLColor.fromAHSL(
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
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final screenWidth = constraints.maxWidth;
                            final effectiveWidth = screenWidth > 500 ? 500 : screenWidth; 
                            final crossAxisCount = effectiveWidth > 400 ? 3 : 2;
                            final fontSize = effectiveWidth > 400 ? 13.0 : 11.0;
                            final iconSize = effectiveWidth > 400 ? 16.0 : 12.0;
                            
                            return ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: 500),
                              child: GridView.count(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 8, // 增加垂直间距
                                crossAxisSpacing: 8,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                childAspectRatio: 8.0, // 调整比例，避免文字挤压
                                children: [
                                  _buildFeatureItem(CupertinoIcons.doc_plaintext, '基金持仓管理', isDarkMode, fontSize, iconSize),
                                  _buildFeatureItem(CupertinoIcons.square_grid_2x2, '多维度视图', isDarkMode, fontSize, iconSize),
                                  _buildFeatureItem(CupertinoIcons.chart_bar, '实时净值估算', isDarkMode, fontSize, iconSize),
                                  _buildFeatureItem(CupertinoIcons.arrow_clockwise, '基金详情回溯', isDarkMode, fontSize, iconSize),
                                  _buildFeatureItem(CupertinoIcons.moon_stars, '主题模式切换', isDarkMode, fontSize, iconSize),
                                  _buildFeatureItem(CupertinoIcons.lock_fill, '隐私保护模式', isDarkMode, fontSize, iconSize),
                                  _buildFeatureItem(CupertinoIcons.cloud_upload, '数据导入导出', isDarkMode, fontSize, iconSize),
                                  _buildFeatureItem(CupertinoIcons.clock, '待确认交易管理', isDarkMode, fontSize, iconSize),
                                  _buildFeatureItem(CupertinoIcons.arrow_up_right, '业绩走势对比', isDarkMode, fontSize, iconSize),
                                  _buildFeatureItem(CupertinoIcons.star_fill, '收益排行分析', isDarkMode, fontSize, iconSize),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        _buildConnectivitySection(isDarkMode),
                        const SizedBox(height: 24),
                        _buildUpdateLogMarquee(isDarkMode),
                        const SizedBox(height: 24),
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
                                  color: randomColor, 
                                ),
                              ),
                              Text(
                                'rizona.cn@gmail.com',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FontStyle.italic,
                                  color: randomColor, 
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 27),
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
                        const SizedBox(height: 27),
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
              : const Color(0xFF6366F1),
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

  Widget _buildConnectivitySection(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '连通性',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _checkConnectivity,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isCheckingConnectivity
                      ? const Color(0xFF007AFF).withOpacity(0.5)
                      : const Color(0xFF007AFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isCheckingConnectivity
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CupertinoActivityIndicator(radius: 7),
                      )
                    : const Text(
                        '检查',
                        style: TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final effectiveWidth = screenWidth > 500 ? 500 : screenWidth;
            final fontSize = effectiveWidth > 400 ? 13.0 : 11.0;
            
            return ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 500),
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 2,
                crossAxisSpacing: 8,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 10.0,
                children: [
                  _buildConnectivityItem(
                    '后端服务器:',
                    _nasConnected,
                    _nasLatency,
                    isDarkMode,
                    fontSize,
                  ),
                  _buildConnectivityItem(
                    'Github:',
                    _githubConnected,
                    _githubLatency,
                    isDarkMode,
                    fontSize,
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildConnectivityItem(
    String label,
    bool? connected,
    int? latency,
    bool isDarkMode,
    double fontSize,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            color: isDarkMode
                ? CupertinoColors.white.withOpacity(0.85)
                : CupertinoColors.label,
          ),
        ),
        const SizedBox(width: 6),
        if (connected == null)
          // 未检查状态：灰色空条
          _buildSignalBars(0, isDarkMode)
        else if (connected && latency != null)
          // 连接成功：根据延迟显示信号条
          _buildSignalBars(_calculateSignalLevel(latency), isDarkMode)
        else
          // 连接失败：红色空条
          _buildSignalBars(0, isDarkMode, failed: true),
      ],
    );
  }

  /// 计算信号等级 (0-10)
  int _calculateSignalLevel(int latency) {
    if (latency <= 100) return 10;      // 非常快
    if (latency <= 200) return 9;
    if (latency <= 300) return 8;
    if (latency <= 400) return 7;
    if (latency <= 500) return 6;
    if (latency <= 600) return 5;
    if (latency <= 800) return 4;
    if (latency <= 1000) return 3;
    if (latency <= 1500) return 2;
    if (latency <= 2000) return 1;
    return 0;                            // 非常慢
  }

  /// 构建信号条
  Widget _buildSignalBars(int level, bool isDarkMode, {bool failed = false}) {
    const totalBars = 10;
    const barWidth = 2.0;
    const barHeight = 12.0;
    const spacing = 1.0;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalBars, (index) {
        final isActive = index < level;
        Color barColor;
        
        if (failed) {
          // 失败状态：全红
          barColor = const Color(0xFFFF3B30);
        } else if (!isActive) {
          // 未激活：灰色
          barColor = isDarkMode 
              ? CupertinoColors.systemGrey.withOpacity(0.3)
              : CupertinoColors.systemGrey4;
        } else {
          // 激活状态：根据位置渐变
          final position = index / (totalBars - 1); // 0.0 - 1.0
          if (position < 0.5) {
            // 前半段：橙色到黄色
            final t = position * 2; // 0.0 - 1.0
            barColor = Color.lerp(
              const Color(0xFFFF9500), // 橙色
              const Color(0xFFFFCC00), // 黄色
              t,
            )!;
          } else {
            // 后半段：黄色到绿色
            final t = (position - 0.5) * 2; // 0.0 - 1.0
            barColor = Color.lerp(
              const Color(0xFFFFCC00), // 黄色
              const Color(0xFF34C759), // 绿色
              t,
            )!;
          }
        }
        
        return Container(
          width: barWidth,
          height: barHeight,
          margin: EdgeInsets.only(right: index < totalBars - 1 ? spacing : 0),
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
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
                ? const Color(0xFF2C2C2E).withOpacity(0.6)
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
    final updateLogs = [
      ACKNOWLEDGMENT_LINE_1,  
      ACKNOWLEDGMENT_LINE_2,  
      '',  
      '──────────────────────',  
      '',  
      ...UPDATE_LOGS,  
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '更新记录',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final estimatedHeight = updateLogs.length * 20.0;
            final containerHeight = (estimatedHeight.clamp(120.0, 300.0)) * 0.6; 
            
            return Container(
              height: containerHeight,
              decoration: BoxDecoration(
                color: isDarkMode 
                    ? const Color(0xFF2C2C2E).withOpacity(0.6)
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
                child: _VerticalMarqueeText(
                  items: updateLogs,
                  itemTextStyle: TextStyle(
                    fontSize: 12,
                    color: isDarkMode
                        ? CupertinoColors.white.withOpacity(0.8)
                        : CupertinoColors.systemGrey.withOpacity(0.9),
                  ),
                  velocity: 15.0, 
                ),
              ),
            );
          },
        ),
      ],
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
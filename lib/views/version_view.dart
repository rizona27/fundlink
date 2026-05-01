import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import '../widgets/adaptive_top_bar.dart';

const String APP_VERSION = 'v1.1.8';

const List<String> UPDATE_LOGS = [
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

class VersionView extends StatelessWidget {
  const VersionView({super.key});

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
                                mainAxisSpacing: 2, 
                                crossAxisSpacing: 8,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                childAspectRatio: 5.0, 
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
      ...UPDATE_LOGS,  
      '',  
      '──────────────────────',  
      '',  
      ACKNOWLEDGMENT_LINE_1,  
      ACKNOWLEDGMENT_LINE_2,  
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
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import '../widgets/adaptive_top_bar.dart';

// ==================== 版本信息配置区 ====================
/// 应用版本号
const String APP_VERSION = 'v1.1.2';

/// 更新记录列表（从新到旧）
const List<String> UPDATE_LOGS = [
  'v1.1.2 - 节假日智能识别、交易日判断优化、待确认交易提示改进',
  'v1.1.1 - 智能开市检测、市场状态监控、待确认交易优化、视图刷新修复',
  'v1.1.0 - 性能优化：批量更新机制、LRU缓存系统、列表懒加载、排序缓存、预计算优化',
  'v1.0.9 - 顶部工具栏优化，增加菜单自动收回和淡入淡出效果；优化基金持仓列表排序逻辑',
  'v1.0.8 - 优化基金对比图表，支持渐变填充效果；修复自定义基金配置对话框输入问题',
  'v1.0.7 - 新增SummaryView展开时"更多"按钮，点击跳转基金详情；优化展开/折叠动画效果',
  'v1.0.6 - 新增自定义基金对比功能；优化图例显示规则，支持动态显示/隐藏指标',
  'v1.0.5 - 新增中证500、中证1000指数对比；优化ETF联接基金数据源',
  'v1.0.4 - 新增待确认交易管理功能；支持T+1/T+2自动确认净值',
  'v1.0.3 - 优化持仓收益计算逻辑；支持绝对收益与年化收益率分开计算',
  'v1.0.2 - 新增CSV/Excel导入导出功能；支持模糊智能匹配',
  'v1.0.1 - 新增实时估值倒计时刷新；支持自定义刷新间隔',
  'v1.0.0 - FundLink 正式发布，支持基金持仓管理、多维度视图、实时净值估算',
];

/// 致谢信息
const String ACKNOWLEDGMENT_LINE_1 = '感谢参与测试的小伙伴：miner2011m、qiu_kw、naniezy、leo_pengtao';
const String ACKNOWLEDGMENT_LINE_2 = '愿大家一基暴富～！';
// ======================================================

/// 跑马灯文本组件 - 支持无缝循环滚动、鼠标悬停/触摸暂停
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

/// 垂直跑马灯组件 - 从下往上滚动
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

  /// 启动跑马灯动画
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
  
  /// 暂停动画
  void _pauseAnimation() {
    if (!_isPaused && _controller.isAnimating) {
      _controller.stop();
      setState(() {
        _isPaused = true;
      });
    }
  }
  
  /// 恢复动画
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

    // 生成随机颜色用于“一基暴富”
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
                            // 根据屏幕宽度动态调整列数和字体大小，但限制最大宽度
                            final screenWidth = constraints.maxWidth;
                            final effectiveWidth = screenWidth > 500 ? 500 : screenWidth; // 限制最大宽度为500
                            final crossAxisCount = effectiveWidth > 400 ? 3 : 2;
                            final fontSize = effectiveWidth > 400 ? 13.0 : 11.0;
                            final iconSize = effectiveWidth > 400 ? 16.0 : 12.0;
                            
                            return ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: 500),
                              child: GridView.count(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 2, // 进一步减小行间距
                                crossAxisSpacing: 8,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                childAspectRatio: 5.0, // 增大宽高比，使行高更小
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
                        // 更新记录（从下往上滚动）
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
                                  color: randomColor, // 使用与“一基暴富”相同的随机颜色
                                ),
                              ),
                              Text(
                                'rizona.cn@gmail.com',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FontStyle.italic,
                                  color: randomColor, // 与Mail保持一致的颜色
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
              velocity: 30.0, // 滚动速度（像素/秒）
            ),
          ),
        ),
      ],
    );
  }

  /// 从下往上滚动的更新记录组件
  Widget _buildUpdateLogMarquee(bool isDarkMode) {
    // 构建完整的更新记录列表（包含空行和致谢）
    final updateLogs = [
      ...UPDATE_LOGS,  // 展开更新记录
      '',  // v1.0.0后的空行
      '──────────────────────',  // 分隔符
      '',  // 分隔符后的空行
      ACKNOWLEDGMENT_LINE_1,  // 致谢第一行
      ACKNOWLEDGMENT_LINE_2,  // 致谢第二行
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '更新记录',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? CupertinoColors.white : CupertinoColors.label,
              ),
            ),
            Text(
              '点击暂停',
              style: TextStyle(
                fontSize: 11,
                color: isDarkMode
                    ? CupertinoColors.white.withOpacity(0.4)
                    : CupertinoColors.systemGrey.withOpacity(0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 根据内容数量动态计算高度，最少120，最多300
        LayoutBuilder(
          builder: (context, constraints) {
            // 每行大约20像素高度（文本12px + 间距8px）
            final estimatedHeight = updateLogs.length * 20.0;
            final containerHeight = estimatedHeight.clamp(120.0, 300.0);
            
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
                  velocity: 15.0, // 进一步降低滚动速度
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// 垂直跑马灯状态类 - 从下往上滚动
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

  /// 启动垂直跑马灯动画
  void _startAnimation(double containerHeight) {
    if (_animationStarted) return;
    
    // 计算总高度（所有文本项的高度 + 间距）
    final textPainter = TextPainter(
      text: TextSpan(text: widget.items.join('\n'), style: widget.itemTextStyle),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: 300); // 假设宽度为300
    final totalTextHeight = textPainter.height + (widget.items.length - 1) * 8; // 8是行间距
    
    _containerHeight = containerHeight;
    final totalDistance = totalTextHeight + containerHeight;
    // 降低速度，确保用户可以阅读完所有内容
    final duration = Duration(milliseconds: (totalDistance / widget.velocity * 1000).round());
    
    _controller.duration = duration;
    final animation = Tween<double>(begin: containerHeight, end: -totalTextHeight).animate(_controller);
    animation.addListener(() {
      if (mounted) setState(() => _offset = animation.value);
    });
    
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        // 完成后等待2秒再重新开始，给用户更多时间
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
  
  /// 暂停动画
  void _pauseAnimation() {
    if (!_isPaused && _controller.isAnimating) {
      _controller.stop();
      setState(() {
        _isPaused = true;
      });
    }
  }
  
  /// 恢复动画
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
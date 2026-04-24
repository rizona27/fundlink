import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import '../widgets/adaptive_top_bar.dart';

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

  static const String appVersion = 'v1.0.7';

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    double scrollOffset = 0;

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
                        Text(
                          '主要功能',
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
                        // 致谢跑马灯
                        _buildAcknowledgmentMarquee(isDarkMode),
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
              text: '感谢参与测试的小伙伴：miner2011m、qiu_kw、naniezy  |愿大家一基暴富～！',
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
}
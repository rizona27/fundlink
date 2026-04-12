import 'dart:async';
import 'dart:ui' as ui show Color;
import 'package:flutter/cupertino.dart';

/// 悬浮药丸状底部导航栏（滚动时降低透明度，纯阴影立体感，无边框）
/// 支持每个标签独立渐变色，点击动画：
/// - 未选中时图标顺时针旋转270°再逆时针返回，同时颜色从灰色渐变为激活色
/// - 已选中时图标缩放，颜色先减弱再增强
class FloatingTabBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<BottomNavigationBarItem> items;
  final List<ui.Color>? activeColors;      // 渐变起始色（也用于文字）
  final List<ui.Color>? activeColorsEnd;   // 渐变结束色

  const FloatingTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.activeColors,
    this.activeColorsEnd,
  });

  @override
  State<FloatingTabBar> createState() => FloatingTabBarState();
}

class FloatingTabBarState extends State<FloatingTabBar> with TickerProviderStateMixin {
  late AnimationController _opacityController;
  Timer? _restoreTimer;
  bool _isScrolling = false;

  static const double _normalOpacity = 1.0;
  static const double _scrollingOpacity = 0.5;

  final List<AnimationController> _scaleControllers = [];
  final List<Animation<double>> _scaleAnimations = [];
  final List<AnimationController> _rotateControllers = [];

  @override
  void initState() {
    super.initState();
    _opacityController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    )..value = _normalOpacity;

    for (int i = 0; i < widget.items.length; i++) {
      final scaleCtrl = AnimationController(
        duration: const Duration(milliseconds: 150),
        vsync: this,
      );
      final scaleAnim = Tween<double>(begin: 1.0, end: 0.85).animate(
        CurvedAnimation(parent: scaleCtrl, curve: Curves.easeOut),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) scaleCtrl.reverse();
      });
      _scaleControllers.add(scaleCtrl);
      _scaleAnimations.add(scaleAnim);

      final rotateCtrl = AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      );
      _rotateControllers.add(rotateCtrl);
    }
  }

  void onScroll() {
    if (!_isScrolling) {
      _isScrolling = true;
      if (_opacityController.value != _scrollingOpacity) {
        _opacityController.animateTo(_scrollingOpacity, curve: Curves.easeOut);
      }
    }
    _resetRestoreTimer();
  }

  void _resetRestoreTimer() {
    _restoreTimer?.cancel();
    _restoreTimer = Timer(const Duration(milliseconds: 500), () {
      if (_isScrolling && mounted) {
        _isScrolling = false;
        if (_opacityController.value != _normalOpacity) {
          _opacityController.animateTo(_normalOpacity, curve: Curves.easeOut);
        }
      }
    });
  }

  void restore() {
    _restoreTimer?.cancel();
    _isScrolling = false;
    if (_opacityController.value != _normalOpacity) {
      _opacityController.animateTo(_normalOpacity, curve: Curves.easeOut);
    }
  }

  void _onItemTap(int index) {
    final bool isSelected = (widget.currentIndex == index);
    if (isSelected) {
      if (index < _scaleControllers.length) {
        _scaleControllers[index].forward(from: 0.0);
      }
    } else {
      if (index < _rotateControllers.length) {
        _rotateControllers[index].forward(from: 0.0);
      }
      widget.onTap(index);
    }
    restore();
  }

  @override
  void dispose() {
    _opacityController.dispose();
    for (var c in _scaleControllers) c.dispose();
    for (var c in _rotateControllers) c.dispose();
    _restoreTimer?.cancel();
    super.dispose();
  }

  Color _getActiveColorForIndex(int index, bool isDarkMode) {
    if (widget.activeColors != null && index < widget.activeColors!.length) {
      return widget.activeColors![index];
    }
    return isDarkMode ? const ui.Color(0xFF6D8EAD) : const ui.Color(0xFF8FB4D9);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // 深色模式背景：使用系统深灰色 (#2C2C2E)，接近黑色但柔和
    final Color backgroundColor = isDarkMode
        ? const ui.Color(0xFF2C2C2E).withValues(alpha: 0.95)
        : CupertinoColors.white.withValues(alpha: 0.92);

    final inactiveIconColor = isDarkMode
        ? CupertinoColors.white.withValues(alpha: 0.55)
        : CupertinoColors.systemGrey.withValues(alpha: 0.7);
    final inactiveTextColor = isDarkMode
        ? CupertinoColors.white.withValues(alpha: 0.45)
        : CupertinoColors.secondaryLabel;

    final boxShadow = [
      BoxShadow(
        color: const ui.Color(0xFF000000).withValues(alpha: isDarkMode ? 0.3 : 0.1),
        blurRadius: 20,
        spreadRadius: 0,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: const ui.Color(0xFF000000).withValues(alpha: isDarkMode ? 0.15 : 0.05),
        blurRadius: 10,
        spreadRadius: -2,
        offset: const Offset(0, 3),
      ),
    ];

    const double itemHeight = 60.0;
    const double itemWidth = 70.0;
    const double circleSize = 32.0;
    const double iconSize = 18.0;
    const double spacing = 4.0;
    const double fontSize = 12.0;

    Gradient _getActiveGradient(int index) {
      Color start = _getActiveColorForIndex(index, isDarkMode);
      if (isDarkMode) start = start.withValues(alpha: 0.9);
      Color end = (widget.activeColorsEnd != null && index < widget.activeColorsEnd!.length)
          ? widget.activeColorsEnd![index]
          : start;
      if (isDarkMode) end = end.withValues(alpha: 0.9);
      return LinearGradient(
        colors: [start, end],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }

    return AnimatedBuilder(
      animation: _opacityController,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityController.value,
          child: Container(
            margin: EdgeInsets.only(bottom: bottomPadding + 12),
            constraints: const BoxConstraints(maxWidth: 350),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(30),
              boxShadow: boxShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(widget.items.length, (index) {
                  final item = widget.items[index];
                  final isSelected = widget.currentIndex == index;
                  final Color activeColor = _getActiveColorForIndex(index, isDarkMode);
                  final Color selectedTextColor = isDarkMode ? activeColor.withValues(alpha: 0.9) : activeColor;

                  final ColorTween colorTween = ColorTween(
                    begin: inactiveIconColor,
                    end: activeColor,
                  );
                  final Animation<ui.Color?> colorAnimation = _rotateControllers[index].drive(colorTween);

                  return GestureDetector(
                    onTap: () => _onItemTap(index),
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: itemWidth,
                      height: itemHeight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: Listenable.merge([
                              _scaleAnimations[index],
                              _rotateControllers[index],
                              colorAnimation,
                            ]),
                            builder: (context, child) {
                              // 旋转角度：顺时针 270° 再逆时针返回
                              double t = _rotateControllers[index].value;
                              double angle = 270 * (1 - (2 * t - 1).abs()) * 3.14159 / 180;

                              // 图标颜色处理
                              Color iconColor;
                              if (isSelected) {
                                // 选中状态：缩放动画期间颜色变弱（半透明），否则白色
                                double scaleValue = _scaleAnimations[index].value;
                                if (scaleValue < 1.0) {
                                  iconColor = CupertinoColors.white.withValues(alpha: 0.6);
                                } else {
                                  iconColor = CupertinoColors.white;
                                }
                              } else {
                                // 未选中状态：旋转动画期间使用渐变色，否则非激活色
                                iconColor = (_rotateControllers[index].isAnimating
                                    ? (colorAnimation.value ?? inactiveIconColor)
                                    : inactiveIconColor);
                              }

                              return Transform.scale(
                                scale: _scaleAnimations[index].value,
                                child: Transform.rotate(
                                  angle: angle,
                                  child: Container(
                                    width: circleSize,
                                    height: circleSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: isSelected ? _getActiveGradient(index) : null,
                                      color: isSelected ? null : inactiveIconColor.withValues(alpha: 0.15),
                                    ),
                                    child: Center(
                                      child: IconTheme(
                                        data: IconThemeData(
                                          size: iconSize,
                                          color: iconColor,
                                        ),
                                        child: item.icon,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          SizedBox(height: spacing),
                          Text(
                            item.label ?? '',
                            style: TextStyle(
                              fontSize: fontSize,
                              color: isSelected ? selectedTextColor : inactiveTextColor,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }
}
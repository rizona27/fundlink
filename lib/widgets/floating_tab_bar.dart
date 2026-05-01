import 'dart:async';
import 'dart:ui' as ui show Color;
import 'package:flutter/cupertino.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class FloatingTabBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<BottomNavigationBarItem> items;
  final List<ui.Color>? activeColors;
  final List<ui.Color>? activeColorsEnd;

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
  Timer? _autoFadeTimer; // 自动淡出定时器
  bool _isScrolling = false;
  bool _hasInteracted = false; // 是否有过交互
  bool _isHovered = false; // 鼠标是否悬停

  static const double _normalOpacity = 1.0;
  static const double _scrollingOpacity = 0.6; // 滚动时降到60%
  
  // 判断是否为桌面平台 (Windows/Web)
  bool get _isDesktopPlatform => kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  final List<AnimationController> _scaleControllers = [];
  final List<Animation<double>> _scaleAnimations = [];
  final List<AnimationController> _rotateControllers = [];

  @override
  void initState() {
    super.initState();
    _opacityController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    )..value = _normalOpacity;

    // 启动后2秒自动降低透明度，让背景透出
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _startAutoFade();
      }
    });

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
      _cancelAutoFade(); // 取消自动淡出
      if (_opacityController.value != _scrollingOpacity) {
        _opacityController.animateTo(_scrollingOpacity, curve: Curves.easeOut);
      }
    }
    _resetRestoreTimer();
  }
  
  // 启动自动淡出（2秒后降低透明度）
  void _startAutoFade() {
    _cancelAutoFade();
    _autoFadeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_isScrolling) {
        _opacityController.animateTo(_scrollingOpacity, curve: Curves.easeOut);
      }
    });
  }
  
  // 取消自动淡出
  void _cancelAutoFade() {
    _autoFadeTimer?.cancel();
    _autoFadeTimer = null;
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
      // 恢复完全不透明后，重新启动自动淡出
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_isScrolling && !_isHovered) {
          _startAutoFade();
        }
      });
    }
  }

  void _onItemTap(int index) {
    _cancelAutoFade(); // 点击时取消自动淡出
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
    _autoFadeTimer?.cancel(); // 清理自动淡出定时器
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

    // Windows 优化：滚动时降低不透明度，让背景透出
    final Color backgroundColor = isDarkMode
        ? const ui.Color(0xFF2C2C2E).withValues(alpha: 0.85)  // 默认85%不透明
        : CupertinoColors.white.withValues(alpha: 0.85);      // 默认85%不透明

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

    const double itemHeight = 52.0; // 降低高度，更紧凑
    const double itemWidth = 56.0; // 进一步缩短宽度
    const double circleSize = 28.0; // 缩小图标容器
    const double iconSize = 16.0; // 缩小图标
    const double spacing = 3.0; // 减小间距
    const double fontSize = 11.0; // 缩小字体

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
        // 滚动时整体透明度从1.0降到0.6，让背景更明显
        final double scrollOpacity = _opacityController.value;
        
        Widget tabBarWidget = Opacity(
          opacity: scrollOpacity,
          child: Container(
            margin: EdgeInsets.only(bottom: bottomPadding + 10), // 减小底部边距
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.70, // 从85%缩短到70%，更紧凑
            ),
            decoration: BoxDecoration(
              // 根据滚动状态动态调整背景透明度
              color: backgroundColor.withValues(
                alpha: 0.85 * scrollOpacity, // 滚动时进一步降低透明度
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: boxShadow,
              // 简洁边框，模拟轻微立体感
              border: Border.all(
                color: isDarkMode 
                    ? CupertinoColors.white.withValues(alpha: 0.08 * scrollOpacity)
                    : CupertinoColors.black.withValues(alpha: 0.06 * scrollOpacity),
                width: 0.5,
              ),
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
                    child: Container(
                      width: itemWidth,
                      height: itemHeight,
                      // 移除选中项的矩形背景,保持简洁
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
                              double t = _rotateControllers[index].value;
                              double angle = 270 * (1 - (2 * t - 1).abs()) * 3.14159 / 180;

                              Color iconColor;
                              if (isSelected) {
                                double scaleValue = _scaleAnimations[index].value;
                                if (scaleValue < 1.0) {
                                  iconColor = CupertinoColors.white.withValues(alpha: 0.6);
                                } else {
                                  iconColor = CupertinoColors.white;
                                }
                              } else {
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
                                      // 选中时添加微妙阴影，增强立体感
                                      boxShadow: isSelected ? [
                                        BoxShadow(
                                          color: _getActiveColorForIndex(index, isDarkMode).withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          spreadRadius: 0,
                                          offset: const Offset(0, 2),
                                        ),
                                      ] : null,
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
            ),  // ClipRRect
          ),
        );
        
        // 桌面平台：添加鼠标悬停监听
        if (_isDesktopPlatform) {
          return MouseRegion(
            onEnter: (_) {
              setState(() => _isHovered = true);
              _cancelAutoFade();
              if (_opacityController.value != _normalOpacity) {
                _opacityController.animateTo(_normalOpacity, curve: Curves.easeOut);
              }
            },
            onExit: (_) {
              setState(() => _isHovered = false);
              // 鼠标离开后，如果没有其他交互，立即开始淡出（与移入时的恢复时间对称）
              if (!_isScrolling) {
                // 取消之前的自动淡出定时器
                _cancelAutoFade();
                // 直接启动淡出动画，300ms内从100%降到60%
                if (_opacityController.value != _scrollingOpacity) {
                  _opacityController.animateTo(_scrollingOpacity, curve: Curves.easeOut);
                }
              }
            },
            child: tabBarWidget,
          );
        }
        
        return tabBarWidget;
      },
    );
  }
}
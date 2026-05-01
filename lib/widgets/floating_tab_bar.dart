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
  Timer? _autoFadeTimer; 
  bool _isScrolling = false;
  bool _hasInteracted = false; 
  bool _isHovered = false; 

  static const double _normalOpacity = 1.0;
  static const double _scrollingOpacity = 0.6; 
  
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
      _cancelAutoFade(); 
      if (_opacityController.value != _scrollingOpacity) {
        _opacityController.animateTo(_scrollingOpacity, curve: Curves.easeOut);
      }
    }
    _resetRestoreTimer();
  }
  
  void _startAutoFade() {
    _cancelAutoFade();
    _autoFadeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_isScrolling) {
        _opacityController.animateTo(_scrollingOpacity, curve: Curves.easeOut);
      }
    });
  }
  
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
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_isScrolling && !_isHovered) {
          _startAutoFade();
        }
      });
    }
  }

  void _onItemTap(int index) {
    _cancelAutoFade(); 
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
    _autoFadeTimer?.cancel(); 
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

    final Color backgroundColor = isDarkMode
        ? const ui.Color(0xFF2C2C2E).withValues(alpha: 0.85)  
        : CupertinoColors.white.withValues(alpha: 0.85);      

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

    const double itemHeight = 52.0; 
    const double itemWidth = 56.0; 
    const double circleSize = 28.0; 
    const double iconSize = 16.0; 
    const double spacing = 3.0; 
    const double fontSize = 11.0; 

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
        final double scrollOpacity = _opacityController.value;
        
        Widget tabBarWidget = Opacity(
          opacity: scrollOpacity,
          child: Container(
            margin: EdgeInsets.only(bottom: bottomPadding + 10), 
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.70, 
            ),
            decoration: BoxDecoration(
              color: backgroundColor.withValues(
                alpha: 0.85 * scrollOpacity, 
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: boxShadow,
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
            ),  
          ),
        );
        
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
              if (!_isScrolling) {
                _cancelAutoFade();
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
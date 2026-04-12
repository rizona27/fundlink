import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

/// 悬浮药丸状底部导航栏（滚动时降低透明度，纯阴影立体感，无边框）
/// 整个导航栏（背景+图标+文字+阴影）整体透明度同步变化，平滑渐变
class FloatingTabBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<BottomNavigationBarItem> items;

  const FloatingTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  State<FloatingTabBar> createState() => FloatingTabBarState();
}

class FloatingTabBarState extends State<FloatingTabBar> with TickerProviderStateMixin {
  late AnimationController _opacityController;
  Timer? _restoreTimer;
  bool _isScrolling = false;

  static const double _normalOpacity = 1.0;      // 默认完全不透明
  static const double _scrollingOpacity = 0.5;   // 滚动时 50% 透明度

  @override
  void initState() {
    super.initState();
    _opacityController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    )..value = _normalOpacity;
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

  @override
  void dispose() {
    _opacityController.dispose();
    _restoreTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // 背景色直接使用 CupertinoColors，它们本身就是 Color 类型
    final Color backgroundColor = isDarkMode ? CupertinoColors.black : CupertinoColors.white;
    final Color activeColor = CupertinoColors.activeBlue;
    // 非激活色：暗色模式下为白色 60% 透明度，亮色模式下为系统灰 60% 透明度
    final Color inactiveColor = (isDarkMode
        ? CupertinoColors.white
        : CupertinoColors.systemGrey).withValues(alpha: 0.6);

    final boxShadow = [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDarkMode ? 0.4 : 0.15),
        blurRadius: 20,
        spreadRadius: 0,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.08),
        blurRadius: 10,
        spreadRadius: -2,
        offset: const Offset(0, 3),
      ),
    ];

    const double itemHeight = 44.0;
    const double iconSize = 22.0;
    const double fontSize = 12.0;

    return AnimatedBuilder(
      animation: _opacityController,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityController.value,
          child: Container(
            margin: EdgeInsets.only(bottom: bottomPadding + 12),
            constraints: const BoxConstraints(maxWidth: 260),
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
                  final Color color = isSelected ? activeColor : inactiveColor;

                  return GestureDetector(
                    onTap: () {
                      widget.onTap(index);
                      restore();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      height: itemHeight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconTheme(
                            data: IconThemeData(
                              size: iconSize,
                              color: color,
                            ),
                            child: item.icon,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.label ?? '',
                            style: TextStyle(
                              fontSize: fontSize,
                              color: color,
                              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                            ),
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
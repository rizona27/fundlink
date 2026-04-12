import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

/// 悬浮药丸状底部导航栏（滚动时降低透明度，纯阴影立体感，无边框）
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

  static const double _normalOpacity = 0.5;
  static const double _scrollingOpacity = 0.05;

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
      _opacityController.animateTo(_scrollingOpacity);
    }
    _resetRestoreTimer();
  }

  void _resetRestoreTimer() {
    _restoreTimer?.cancel();
    _restoreTimer = Timer(const Duration(milliseconds: 500), () {
      if (_isScrolling && mounted) {
        _isScrolling = false;
        _opacityController.animateTo(_normalOpacity);
      }
    });
  }

  void restore() {
    _restoreTimer?.cancel();
    _isScrolling = false;
    _opacityController.animateTo(_normalOpacity);
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

    final backgroundColor = isDarkMode
        ? CupertinoColors.black
        : CupertinoColors.white;

    final boxShadow = [
      BoxShadow(
        color: Colors.black.withOpacity(isDarkMode ? 0.4 : 0.15),
        blurRadius: 20,
        spreadRadius: 0,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.08),
        blurRadius: 10,
        spreadRadius: -2,
        offset: const Offset(0, 3),
      ),
    ];

    return AnimatedBuilder(
      animation: _opacityController,
      builder: (context, child) {
        return Container(
          margin: EdgeInsets.only(bottom: bottomPadding + 12),
          width: 260,
          height: 56,
          decoration: BoxDecoration(
            color: backgroundColor.withOpacity(_opacityController.value),
            borderRadius: BorderRadius.circular(30),
            boxShadow: boxShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: CupertinoTabBar(
              currentIndex: widget.currentIndex,
              onTap: (index) {
                widget.onTap(index);
                restore();
              },
              items: widget.items,
              backgroundColor: Colors.transparent,
              activeColor: CupertinoColors.activeBlue,
              inactiveColor: isDarkMode
                  ? CupertinoColors.white.withOpacity(0.6)
                  : CupertinoColors.systemGrey,
              iconSize: 22,
              height: 56,
            ),
          ),
        );
      },
    );
  }
}
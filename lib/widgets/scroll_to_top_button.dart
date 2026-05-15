import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, MediaQuery, OverlayEntry, Overlay;

/// ScrollToTopButton 助手类
/// 使用 Overlay 方式添加返回顶部按钮，无需修改页面结构
class ScrollToTopButton {
  // ✅ 使用 Map 存储每个 ScrollController 对应的 OverlayEntry
  static final Map<ScrollController, OverlayEntry> _overlayEntries = {};

  /// 显示返回顶部按钮
  static void show({
    required BuildContext context,
    required ScrollController scrollController,
    double showThreshold = 100.0,
    double rightMargin = 16.0,
  }) {
    // ✅ 如果该 ScrollController 已经存在，先移除旧的
    hide(scrollController: scrollController);

    final overlayEntry = OverlayEntry(
      builder: (context) => _ScrollToTopOverlay(
        scrollController: scrollController,
        showThreshold: showThreshold,
        rightMargin: rightMargin,
      ),
    );

    _overlayEntries[scrollController] = overlayEntry;
    Overlay.of(context).insert(overlayEntry);
  }

  /// 隐藏返回顶部按钮
  static void hide({ScrollController? scrollController}) {
    if (scrollController != null) {
      // ✅ 移除指定 ScrollController 的 OverlayEntry
      _overlayEntries[scrollController]?.remove();
      _overlayEntries.remove(scrollController);
    } else {
      // ✅ 如果没有指定，移除所有 OverlayEntry
      _overlayEntries.forEach((_, entry) => entry.remove());
      _overlayEntries.clear();
    }
  }
}

/// Overlay 中的返回顶部按钮
class _ScrollToTopOverlay extends StatefulWidget {
  final ScrollController scrollController;
  final double showThreshold;
  final double rightMargin;

  const _ScrollToTopOverlay({
    required this.scrollController,
    required this.showThreshold,
    required this.rightMargin,
  });

  @override
  State<_ScrollToTopOverlay> createState() => _ScrollToTopOverlayState();
}

class _ScrollToTopOverlayState extends State<_ScrollToTopOverlay> with SingleTickerProviderStateMixin {
  bool _isVisible = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isScrollingToTop = false; // ✅ 标记是否正在执行滚动到顶部操作

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    widget.scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // ✅ 如果正在执行滚动到顶部操作，忽略滚动事件
    if (_isScrollingToTop) return;

    final shouldShow = widget.scrollController.offset > widget.showThreshold;

    if (shouldShow != _isVisible) {
      setState(() {
        _isVisible = shouldShow;
      });

      if (_isVisible) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  void _scrollToTop() {
    if (!widget.scrollController.hasClients) return;

    // ✅ 标记正在执行滚动到顶部操作
    _isScrollingToTop = true;

    // ✅ 先开始淡出动画
    setState(() {
      _isVisible = false;
    });
    _animationController.reverse();

    // ✅ 然后平滑滚动到顶部
    widget.scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    ).then((_) {
      // ✅ 滚动完成后，恢复监听
      _isScrollingToTop = false;
    });
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    // 获取屏幕尺寸和底部安全区域
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;

    // 计算按钮位置：底部安全区 + 边距 + 60px偏移（导航栏上方）
    final buttonBottom = bottomPadding + widget.rightMargin + 60.0;

    // 磨玻璃背景色
    final bgColor = isDarkMode
        ? const Color(0xFF2C2C2E).withOpacity(0.85)
        : CupertinoColors.white.withOpacity(0.85);

    return Positioned(
      right: widget.rightMargin,
      bottom: buttonBottom,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Visibility(
          visible: _isVisible,
          maintainState: true,
          child: GestureDetector(
            onTap: _scrollToTop,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                CupertinoIcons.arrow_up_circle_fill,
                color: CupertinoTheme.of(context).primaryColor,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

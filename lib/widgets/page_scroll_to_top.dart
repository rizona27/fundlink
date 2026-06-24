import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class PageScrollToTop extends StatefulWidget {
  final ScrollController scrollController;
  final double showThreshold;
  final double rightMargin;
  final double bottomMargin;
  final double Function()? scrollToPosition;

  const PageScrollToTop({
    super.key,
    required this.scrollController,
    this.showThreshold = 100.0,
    this.rightMargin = 16.0,
    this.bottomMargin = 60.0,
    this.scrollToPosition,
  });

  @override
  State<PageScrollToTop> createState() => _PageScrollToTopState();
}

class _PageScrollToTopState extends State<PageScrollToTop>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isVisible = false;
  bool _isScrollingToTop = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    widget.scrollController.addListener(_onScroll);
    _checkVisibility();
  }

  void _onScroll() {
    if (_isScrollingToTop) return;
    _checkVisibility();
  }

  void _checkVisibility() {
    if (!mounted || !widget.scrollController.hasClients) return;

    final shouldShow = widget.scrollController.offset > widget.showThreshold;

    if (shouldShow != _isVisible) {
      setState(() {
        _isVisible = shouldShow;
      });
      if (shouldShow) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  Future<void> _scrollToTop() async {
    if (!widget.scrollController.hasClients || _isScrollingToTop) return;

    _isScrollingToTop = true;

    if (_isVisible) {
      setState(() {
        _isVisible = false;
      });
      _animationController.stop();
      _animationController.value = 0;
    }

    final targetPosition = widget.scrollToPosition?.call() ?? 0.0;

    await widget.scrollController.animateTo(
      targetPosition,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );

    _isScrollingToTop = false;
    _checkVisibility();
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
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;
    final bottom = bottomPadding + widget.bottomMargin;

    final bgColor = isDarkMode
        ? const Color(0xFF2C2C2E).withOpacity(0.85)
        : CupertinoColors.white.withOpacity(0.85);

    if (!_isVisible) {
      return const SizedBox.shrink();
    }

    return Positioned(
      right: widget.rightMargin,
      bottom: bottom,
      child: FadeTransition(
        opacity: _fadeAnimation,
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
    );
  }
}

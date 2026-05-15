import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, MediaQuery, OverlayEntry, Overlay;

class ScrollToTopButton {
  static final Map<ScrollController, OverlayEntry> _overlayEntries = {};

  static void show({
    required BuildContext context,
    required ScrollController scrollController,
    double showThreshold = 100.0,
    double rightMargin = 16.0,
  }) {
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

  static void hide({ScrollController? scrollController}) {
    if (scrollController != null) {
      _overlayEntries[scrollController]?.remove();
      _overlayEntries.remove(scrollController);
    } else {
      _overlayEntries.forEach((_, entry) => entry.remove());
      _overlayEntries.clear();
    }
  }
}

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
  bool _isScrollingToTop = false;

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

    _isScrollingToTop = true;

    setState(() {
      _isVisible = false;
    });
    _animationController.reverse();

    widget.scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    ).then((_) {
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

    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;

    final buttonBottom = bottomPadding + widget.rightMargin + 60.0;

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

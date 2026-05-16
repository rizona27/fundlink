import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, MediaQuery, OverlayEntry, Overlay;

class ScrollToTopButton {
  static final Map<ScrollController, OverlayEntry> _overlayEntries = {};
  static final Map<ScrollController, VoidCallback> _scrollListeners = {};

  static void show({
    required BuildContext context,
    required ScrollController scrollController,
    double showThreshold = 100.0,
    double rightMargin = 16.0,
  }) {
    hide(scrollController: scrollController);

    final scrollListener = () {
      final entry = _overlayEntries[scrollController];
      if (entry != null && scrollController.hasClients) {
        entry.markNeedsBuild();
      }
    };
    
    _scrollListeners[scrollController] = scrollListener;
    scrollController.addListener(scrollListener);

    final overlayEntry = OverlayEntry(
      builder: (context) => _ScrollToTopOverlay(
        key: ValueKey(scrollController.hashCode),
        scrollController: scrollController,
        showThreshold: showThreshold,
        rightMargin: rightMargin,
        onDispose: () {
          _removeEntry(scrollController);
        },
      ),
    );

    _overlayEntries[scrollController] = overlayEntry;
    Overlay.of(context).insert(overlayEntry);
  }

  static void hide({ScrollController? scrollController}) {
    if (scrollController != null) {
      _removeEntry(scrollController);
    }
  }
  
  static void _removeEntry(ScrollController controller) {
    final entry = _overlayEntries.remove(controller);
    entry?.remove();
    
    final listener = _scrollListeners.remove(controller);
    if (listener != null) {
      controller.removeListener(listener);
    }
  }
}

class _ScrollToTopOverlay extends StatefulWidget {
  final ScrollController scrollController;
  final double showThreshold;
  final double rightMargin;
  final VoidCallback? onDispose;

  const _ScrollToTopOverlay({
    super.key,
    required this.scrollController,
    required this.showThreshold,
    required this.rightMargin,
    this.onDispose,
  });

  @override
  State<_ScrollToTopOverlay> createState() => _ScrollToTopOverlayState();
}

class _ScrollToTopOverlayState extends State<_ScrollToTopOverlay> 
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  
  bool _isVisible = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isScrollingToTop = false;
  double _lastOffset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkVisibility();
      }
    });
    
    widget.scrollController.addListener(_onScroll);
  }

  void _checkVisibility() {
    if (!mounted) return;
    
    final hasClients = widget.scrollController.hasClients;
    final currentOffset = hasClients ? widget.scrollController.offset : 0;
    final shouldShow = hasClients && currentOffset > widget.showThreshold;
    
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

  void _onScroll() {
    if (_isScrollingToTop) return;

    final currentOffset = widget.scrollController.hasClients 
        ? widget.scrollController.offset 
        : 0.0;
    
    if ((currentOffset - _lastOffset).abs() > 5) {
      _lastOffset = currentOffset;
      _checkVisibility();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _checkVisibility();
    }
  }

  Future<void> _scrollToTop() async {
    if (!widget.scrollController.hasClients || _isScrollingToTop) return;

    _isScrollingToTop = true;

    if (mounted && _isVisible) {
      setState(() {
        _isVisible = false;
      });
      _animationController.stop();
      _animationController.value = 0;
    }

    final startOffset = widget.scrollController.offset;
    if (startOffset <= 0) {
      _isScrollingToTop = false;
      return;
    }

    await widget.scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
    
    _isScrollingToTop = false;

    if (mounted && widget.scrollController.hasClients) {
      widget.scrollController.position.notifyListeners();
    }

    _checkVisibility();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.scrollController.removeListener(_onScroll);
    _animationController.dispose();
    widget.onDispose?.call();
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

    if (!_isVisible) {
      return const SizedBox.shrink();
    }

    return Positioned(
      right: widget.rightMargin,
      bottom: buttonBottom,
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

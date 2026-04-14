import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'refresh_button.dart';
import 'search.dart';
import '../services/data_manager.dart';  // 添加导入
import '../services/fund_service.dart';  // 添加导入

class AdaptiveTopBar extends StatefulWidget {
  final double scrollOffset;

  final bool showRefresh;
  final bool showExpandCollapse;
  final bool showSearch;
  final bool showReset;
  final bool showFilter;

  final bool isAllExpanded;
  final String? searchText;
  final bool? isSearchVisible;

  // 刷新所需参数（二选一：传入 dataManager+fundService 或 回调）
  final DataManager? dataManager;
  final FundService? fundService;
  final VoidCallback? onRefresh;           // 自定义刷新回调（不使用内置 RefreshButton 时）
  final VoidCallback? onLongPressRefresh;  // 自定义长按强制刷新回调

  final VoidCallback? onToggleExpandAll;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onSearchClear;
  final VoidCallback? onReset;
  final VoidCallback? onFilter;

  final Color? backgroundColor;
  final double iconSize;
  final Color iconColor;
  final double buttonSpacing;
  final EdgeInsetsGeometry padding;
  final double maxHeight;
  final double minHeight;
  final Duration animationDuration;
  final Curve animationCurve;

  final Widget Function(BuildContext context, Widget defaultButton)? refreshButtonBuilder;
  final Widget Function(BuildContext context, Widget defaultButton)? expandCollapseButtonBuilder;
  final Widget Function(BuildContext context, Widget defaultButton)? searchButtonBuilder;
  final Widget Function(BuildContext context, Widget defaultButton)? resetButtonBuilder;
  final Widget Function(BuildContext context, Widget defaultButton)? filterButtonBuilder;

  const AdaptiveTopBar({
    super.key,
    required this.scrollOffset,
    this.showRefresh = true,
    this.showExpandCollapse = true,
    this.showSearch = true,
    this.showReset = false,
    this.showFilter = false,
    this.isAllExpanded = false,
    this.searchText,
    this.isSearchVisible,
    this.dataManager,
    this.fundService,
    this.onRefresh,
    this.onLongPressRefresh,
    this.onToggleExpandAll,
    this.onSearchChanged,
    this.onSearchClear,
    this.onReset,
    this.onFilter,
    this.backgroundColor,
    this.iconSize = 22,
    this.iconColor = CupertinoColors.label,
    this.buttonSpacing = 8,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.maxHeight = 52,
    this.minHeight = 0,
    this.animationDuration = const Duration(milliseconds: 200),
    this.animationCurve = Curves.easeOutCubic,
    this.refreshButtonBuilder,
    this.expandCollapseButtonBuilder,
    this.searchButtonBuilder,
    this.resetButtonBuilder,
    this.filterButtonBuilder,
  });

  @override
  State<AdaptiveTopBar> createState() => _AdaptiveTopBarState();
}

class _AdaptiveTopBarState extends State<AdaptiveTopBar> with TickerProviderStateMixin {
  late TextEditingController _internalSearchController;
  late FocusNode _internalFocusNode;
  late bool _internalSearchVisible;
  late String _internalSearchText;
  late AnimationController _hideController;
  double _lastProgress = 1.0;
  Timer? _scrollTimer;

  bool get _externallyControlSearchVisible => widget.isSearchVisible != null;
  bool get _externallyControlSearchText => widget.searchText != null;
  String get _currentSearchText => _externallyControlSearchText ? widget.searchText! : _internalSearchText;
  bool get _currentSearchVisible => _externallyControlSearchVisible ? widget.isSearchVisible! : _internalSearchVisible;

  bool get _useBuiltInRefresh => widget.dataManager != null && widget.fundService != null;

  @override
  void initState() {
    super.initState();
    _internalSearchController = TextEditingController(text: widget.searchText ?? '');
    _internalFocusNode = FocusNode();
    _internalSearchVisible = false;
    _internalSearchText = widget.searchText ?? '';
    _hideController = AnimationController(duration: widget.animationDuration, vsync: this)..value = 1.0;
    _internalFocusNode.addListener(() {
      if (_internalFocusNode.hasFocus && !_currentSearchVisible && mounted) {
        _setSearchVisible(true);
      }
    });
  }

  @override
  void didUpdateWidget(AdaptiveTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateHideProgress();
    if (_externallyControlSearchText && widget.searchText != _internalSearchController.text) {
      _internalSearchController.text = widget.searchText ?? '';
    }
  }

  void _updateHideProgress() {
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(milliseconds: 16), () {
      if (!mounted) return;
      final hasText = _currentSearchText.isNotEmpty;
      if (hasText && !_currentSearchVisible) {
        _setSearchVisible(true);
        return;
      }
      double rawProgress = 1.0 - (widget.scrollOffset / 100).clamp(0.0, 1.0);
      double targetProgress = widget.animationCurve.transform(rawProgress);
      if ((targetProgress - _lastProgress).abs() > 0.01) {
        _lastProgress = targetProgress;
        _hideController.animateTo(targetProgress, duration: widget.animationDuration);
      }
      if (targetProgress < 0.05 && _currentSearchVisible && _currentSearchText.isEmpty && !_internalFocusNode.hasFocus) {
        _setSearchVisible(false);
      }
    });
  }

  void _setSearchVisible(bool visible) {
    if (_externallyControlSearchVisible) {
      if (visible && !_currentSearchVisible) widget.onSearchChanged?.call(_currentSearchText);
    } else {
      setState(() => _internalSearchVisible = visible);
    }
  }

  void _onSearchChanged(String value) {
    if (_externallyControlSearchText) {
      widget.onSearchChanged?.call(value);
    } else {
      setState(() => _internalSearchText = value);
      widget.onSearchChanged?.call(value);
    }
  }

  void _onSearchClear() {
    if (_externallyControlSearchText) {
      _internalSearchController.clear();
      widget.onSearchClear?.call();
      widget.onSearchChanged?.call('');
    } else {
      setState(() {
        _internalSearchText = '';
        _internalSearchController.clear();
      });
      widget.onSearchClear?.call();
      widget.onSearchChanged?.call('');
    }
    if (!_internalFocusNode.hasFocus) _setSearchVisible(false);
  }

  void _onReset() {
    _onSearchClear();
    widget.onReset?.call();
  }

  Widget _buildRefreshButton() {
    if (widget.refreshButtonBuilder != null) {
      final placeholder = Container();
      return widget.refreshButtonBuilder!(context, placeholder);
    }

    if (_useBuiltInRefresh) {
      return RefreshButton(
        dataManager: widget.dataManager!,
        fundService: widget.fundService!,
        maxConcurrentRequests: 3,
      );
    }

    return GestureDetector(
      onTap: widget.onRefresh,
      onLongPress: widget.onLongPressRefresh,
      child: Icon(
        CupertinoIcons.arrow_clockwise,
        size: widget.iconSize,
        color: widget.iconColor,
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    bool isActive = false,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Icon(
        icon,
        size: widget.iconSize,
        color: isActive ? CupertinoColors.activeBlue : widget.iconColor,
      ),
    );
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _hideController.dispose();
    _internalSearchController.dispose();
    _internalFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _hideController.value;
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = widget.backgroundColor ??
        (isDarkMode ? Colors.black.withOpacity(0.7) : CupertinoColors.systemBackground.withOpacity(0.8));

    return AnimatedBuilder(
      animation: _hideController,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: widget.maxHeight * progress,
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.8 + progress * 0.2,
                  child: Container(
                    padding: widget.padding,
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (widget.showRefresh) _buildRefreshButton(),
                        if (widget.showRefresh && widget.showExpandCollapse) SizedBox(width: widget.buttonSpacing),
                        if (widget.showExpandCollapse)
                          _buildIconButton(
                            icon: widget.isAllExpanded ? CupertinoIcons.arrow_up_doc : CupertinoIcons.arrow_down_doc,
                            onPressed: widget.onToggleExpandAll,
                          ),
                        if (widget.showExpandCollapse && widget.showSearch) SizedBox(width: widget.buttonSpacing),
                        if (widget.showSearch)
                          _buildIconButton(
                            icon: _currentSearchVisible ? CupertinoIcons.search_circle_fill : CupertinoIcons.search,
                            onPressed: () => _setSearchVisible(!_currentSearchVisible),
                          ),
                        if (widget.showSearch && widget.showReset) SizedBox(width: widget.buttonSpacing),
                        if (widget.showReset)
                          _buildIconButton(
                            icon: CupertinoIcons.refresh_thin,
                            onPressed: _onReset,
                          ),
                        if (widget.showReset && widget.showFilter) SizedBox(width: widget.buttonSpacing),
                        if (widget.showFilter)
                          _buildIconButton(
                            icon: CupertinoIcons.slider_horizontal_3,
                            onPressed: widget.onFilter,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Opacity(
              opacity: progress,
              child: Container(
                height: _currentSearchVisible ? 52 * progress : 0,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: _currentSearchVisible ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                    firstChild: Search(
                      controller: _internalSearchController,
                      focusNode: _internalFocusNode,
                      onChanged: _onSearchChanged,
                      onClear: _onSearchClear,
                    ),
                    secondChild: const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
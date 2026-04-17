import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'dart:ui' show ImageFilter;
import 'refresh_button.dart';
import 'search.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';

// 排序字段枚举
enum SortKey {
  none,
  navReturn1m,
  navReturn3m,
  navReturn6m,
  navReturn1y,
}

extension SortKeyExtension on SortKey {
  String get displayName {
    switch (this) {
      case SortKey.none:
        return '无排序';
      case SortKey.navReturn1m:
        return '近1月';
      case SortKey.navReturn3m:
        return '近3月';
      case SortKey.navReturn6m:
        return '近6月';
      case SortKey.navReturn1y:
        return '近1年';
    }
  }

  Color get color {
    switch (this) {
      case SortKey.none:
        return CupertinoColors.systemGrey;
      case SortKey.navReturn1m:
        return CupertinoColors.systemBlue;
      case SortKey.navReturn3m:
        return CupertinoColors.systemPurple;
      case SortKey.navReturn6m:
        return CupertinoColors.systemOrange;
      case SortKey.navReturn1y:
        return CupertinoColors.systemRed;
    }
  }

  SortKey get next {
    switch (this) {
      case SortKey.none:
        return SortKey.navReturn1m;
      case SortKey.navReturn1m:
        return SortKey.navReturn3m;
      case SortKey.navReturn3m:
        return SortKey.navReturn6m;
      case SortKey.navReturn6m:
        return SortKey.navReturn1y;
      case SortKey.navReturn1y:
        return SortKey.none;
    }
  }

  double? getValue(FundHolding holding) {
    switch (this) {
      case SortKey.navReturn1m:
        return holding.navReturn1m;
      case SortKey.navReturn3m:
        return holding.navReturn3m;
      case SortKey.navReturn6m:
        return holding.navReturn6m;
      case SortKey.navReturn1y:
        return holding.navReturn1y;
      case SortKey.none:
        return null;
    }
  }
}

enum SortOrder {
  ascending,
  descending,
}

extension SortOrderExtension on SortOrder {
  String get displayName {
    switch (this) {
      case SortOrder.ascending:
        return '升序';
      case SortOrder.descending:
        return '降序';
    }
  }
}

class AdaptiveTopBar extends StatefulWidget {
  final double scrollOffset;

  final bool showBack;
  final bool showRefresh;
  final bool showExpandCollapse;
  final bool showSearch;
  final bool showReset;
  final bool showFilter;
  final bool showSort;

  final bool isAllExpanded;
  final String? searchText;
  final bool? isSearchVisible;

  final SortKey sortKey;
  final SortOrder sortOrder;
  final ValueChanged<SortKey>? onSortKeyChanged;
  final ValueChanged<SortOrder>? onSortOrderChanged;

  final DataManager? dataManager;
  final FundService? fundService;
  final VoidCallback? onBack;
  final VoidCallback? onRefresh;
  final VoidCallback? onLongPressRefresh;

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
    this.showBack = false,
    this.showRefresh = true,
    this.showExpandCollapse = true,
    this.showSearch = true,
    this.showReset = false,
    this.showFilter = false,
    this.showSort = false,
    this.isAllExpanded = false,
    this.searchText,
    this.isSearchVisible,
    this.sortKey = SortKey.none,
    this.sortOrder = SortOrder.descending,
    this.onSortKeyChanged,
    this.onSortOrderChanged,
    this.dataManager,
    this.fundService,
    this.onBack,
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
  bool get _hasData => widget.dataManager?.holdings.isNotEmpty ?? false;

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
    _scrollTimer = Timer(const Duration(milliseconds: 8), () {
      if (!mounted) return;
      final hasText = _currentSearchText.isNotEmpty;
      if (hasText && !_currentSearchVisible) {
        _setSearchVisible(true);
        return;
      }
      double rawProgress = 1.0 - (widget.scrollOffset / 150).clamp(0.0, 1.0);
      double targetProgress = Curves.easeOutCubic.transform(rawProgress);

      if ((targetProgress - _lastProgress).abs() > 0.01) {
        _lastProgress = targetProgress;
        _hideController.animateTo(targetProgress,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
        );
      }
      if (targetProgress < 0.05 && _currentSearchVisible && _currentSearchText.isEmpty && !_internalFocusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _setSearchVisible(false);
        });
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

  Color _getBackgroundColor(double progress, bool isDarkMode) {
    if (progress >= 0.95) {
      return isDarkMode
          ? Colors.black.withOpacity(0.8)
          : CupertinoColors.systemBackground.withOpacity(0.9);
    } else if (progress >= 0.5) {
      return isDarkMode
          ? Colors.black.withOpacity(0.5 + (progress - 0.5) * 0.6)
          : CupertinoColors.systemBackground.withOpacity(0.4 + (progress - 0.5) * 1.0);
    } else {
      return Colors.transparent;
    }
  }

  // 磨玻璃容器包装（支持禁用状态）
  Widget _wrapWithGlass(Widget child, {bool enabled = true, bool disabled = false}) {
    if (!enabled) return child;
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDarkMode
        ? const Color(0xFF2C2C2E).withOpacity(0.85)
        : CupertinoColors.white.withOpacity(0.85);
    final opacity = disabled ? 0.5 : 1.0;
    return Opacity(
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(30),
          boxShadow: disabled ? null : [
            BoxShadow(
              color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  List<Widget> _buildLeftChildren() {
    final children = <Widget>[];
    if (widget.showBack) {
      children.add(_wrapWithGlass(
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          onPressed: widget.onBack,
          child: Icon(
            CupertinoIcons.back,
            size: widget.iconSize,
            color: widget.iconColor,
          ),
        ),
        disabled: false,
      ));
    }
    if (widget.showRefresh) {
      if (children.isNotEmpty) children.add(SizedBox(width: widget.buttonSpacing));
      children.add(_wrapWithGlass(_buildRefreshButton(), disabled: !_hasData));
    }
    if (widget.showSort) {
      if (children.isNotEmpty) children.add(SizedBox(width: widget.buttonSpacing));
      children.add(_buildSortButton(disabled: !_hasData));
    }
    return children;
  }

  // 将搜索和折叠按钮合并为一个磨玻璃容器
  Widget _buildRightGroup() {
    final children = <Widget>[];
    if (widget.showSearch) {
      children.add(
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          onPressed: _hasData ? () => _setSearchVisible(!_currentSearchVisible) : null,
          child: Icon(
            _currentSearchVisible ? CupertinoIcons.search_circle_fill : CupertinoIcons.search,
            size: widget.iconSize,
            color: _hasData ? widget.iconColor : CupertinoColors.systemGrey3,
          ),
        ),
      );
    }
    if (widget.showExpandCollapse) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 4));
      children.add(
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          onPressed: _hasData ? widget.onToggleExpandAll : null,
          child: Icon(
            widget.isAllExpanded ? CupertinoIcons.arrow_up_doc : CupertinoIcons.arrow_down_doc,
            size: widget.iconSize,
            color: _hasData ? widget.iconColor : CupertinoColors.systemGrey3,
          ),
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return _wrapWithGlass(Row(mainAxisSize: MainAxisSize.min, children: children), disabled: !_hasData);
  }

  List<Widget> _buildRightChildren() {
    final children = <Widget>[];
    children.add(_buildRightGroup());
    if (widget.showReset) {
      if (children.isNotEmpty) children.add(SizedBox(width: widget.buttonSpacing));
      children.add(_wrapWithGlass(
        _buildIconButton(
          icon: CupertinoIcons.refresh_thin,
          onPressed: _onReset,
        ),
        disabled: !_hasData,
      ));
    }
    if (widget.showFilter) {
      if (children.isNotEmpty) children.add(SizedBox(width: widget.buttonSpacing));
      children.add(_wrapWithGlass(
        _buildIconButton(
          icon: CupertinoIcons.slider_horizontal_3,
          onPressed: widget.onFilter,
        ),
        disabled: !_hasData,
      ));
    }
    return children;
  }

  Widget _buildRefreshButton() {
    final hasData = _hasData;

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
      onLongPress: hasData ? widget.onLongPressRefresh : null,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onPressed: hasData ? widget.onRefresh : null,
        child: Icon(
          CupertinoIcons.arrow_clockwise,
          size: widget.iconSize,
          color: hasData ? widget.iconColor : CupertinoColors.systemGrey3,
        ),
      ),
    );
  }

  Widget _buildSortButton({bool disabled = false}) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDarkMode
        ? const Color(0xFF2C2C2E).withOpacity(0.85)
        : CupertinoColors.white.withOpacity(0.85);
    final textColor = widget.sortKey == SortKey.none
        ? (isDarkMode ? CupertinoColors.white : CupertinoColors.label)
        : widget.sortKey.color;

    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(30),
          boxShadow: disabled ? null : [
            BoxShadow(
              color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onPressed: disabled ? null : () => widget.onSortKeyChanged?.call(widget.sortKey.next),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.sortKey == SortKey.none
                        ? CupertinoIcons.line_horizontal_3_decrease_circle
                        : CupertinoIcons.calendar,
                    size: 16,
                    color: textColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.sortKey.displayName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.sortKey != SortKey.none) ...[
              Container(
                width: 1,
                height: 20,
                color: isDarkMode ? CupertinoColors.white.withOpacity(0.2) : CupertinoColors.black.withOpacity(0.1),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                onPressed: disabled ? null : () => widget.onSortOrderChanged?.call(
                  widget.sortOrder == SortOrder.ascending ? SortOrder.descending : SortOrder.ascending,
                ),
                child: Icon(
                  widget.sortOrder == SortOrder.ascending ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                  size: 14,
                  color: widget.sortKey.color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    bool isActive = false,
  }) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
    final bgColor = widget.backgroundColor ?? _getBackgroundColor(progress, isDarkMode);
    final blurAmount = (1 - progress) * 8;

    return AnimatedBuilder(
      animation: _hideController,
      builder: (context, _) {
        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: progress,
                  child: Transform.translate(
                    offset: Offset(0, -16 * (1 - progress)),
                    child: Container(
                      height: widget.maxHeight * progress,
                      padding: widget.padding,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(16 * progress),
                        ),
                      ),
                      child: Row(
                        children: [
                          ..._buildLeftChildren(),
                          const Spacer(),
                          ..._buildRightChildren(),
                        ],
                      ),
                    ),
                  ),
                ),
                Opacity(
                  opacity: progress,
                  child: Transform.translate(
                    offset: Offset(0, -8 * (1 - progress)),
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
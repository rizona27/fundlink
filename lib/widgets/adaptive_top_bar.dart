import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'dart:ui' show ImageFilter;
import 'search.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import 'toast.dart';

// 排序循环类型枚举
enum SortCycleType {
  fundReturns,
  holdings,
}

// 排序字段枚举
enum SortKey {
  none,
  navReturn1m,
  navReturn3m,
  navReturn6m,
  navReturn1y,
  amount,
  profit,
  profitRate,
  days,
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
      case SortKey.amount:
        return '金额';
      case SortKey.profit:
        return '收益';
      case SortKey.profitRate:
        return '收益率';
      case SortKey.days:
        return '天数';
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
      case SortKey.amount:
        return const Color(0xFF4A90D9);
      case SortKey.profit:
        return const Color(0xFF34C759);
      case SortKey.profitRate:
        return const Color(0xFFFF9500);
      case SortKey.days:
        return const Color(0xFFD46B6B);
    }
  }

  IconData get icon {
    switch (this) {
      case SortKey.none:
        return CupertinoIcons.line_horizontal_3_decrease;
      case SortKey.navReturn1m:
      case SortKey.navReturn3m:
      case SortKey.navReturn6m:
      case SortKey.navReturn1y:
        return CupertinoIcons.chart_bar;
      case SortKey.amount:
        return CupertinoIcons.money_dollar;
      case SortKey.profit:
        return CupertinoIcons.chart_bar;
      case SortKey.profitRate:
        return CupertinoIcons.percent;
      case SortKey.days:
        return CupertinoIcons.calendar;
    }
  }

  SortKey next({SortCycleType cycleType = SortCycleType.fundReturns}) {
    switch (cycleType) {
      case SortCycleType.fundReturns:
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
          default:
            return SortKey.none;
        }
      case SortCycleType.holdings:
        switch (this) {
          case SortKey.none:
            return SortKey.amount;
          case SortKey.amount:
            return SortKey.profit;
          case SortKey.profit:
            return SortKey.profitRate;
          case SortKey.profitRate:
            return SortKey.days;
          case SortKey.days:
            return SortKey.none;
          default:
            return SortKey.none;
        }
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
      case SortKey.amount:
        return holding.purchaseAmount;
      case SortKey.profit:
        return holding.profit;
      case SortKey.profitRate:
        return holding.annualizedProfitRate;
      case SortKey.days:
        return DateTime.now().difference(holding.purchaseDate).inDays.toDouble();
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
  final SortCycleType sortCycleType;
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
    this.sortCycleType = SortCycleType.fundReturns,
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
  bool _isRefreshing = false;

  bool get _externallyControlSearchVisible => widget.isSearchVisible != null;
  bool get _externallyControlSearchText => widget.searchText != null;
  String get _currentSearchText => _externallyControlSearchText ? widget.searchText! : _internalSearchText;
  bool get _currentSearchVisible => _externallyControlSearchVisible ? widget.isSearchVisible! : _internalSearchVisible;

  bool get _hasData => widget.dataManager?.holdings.isNotEmpty ?? false;

  // 检查是否有需要刷新的基金（缺失收益率数据）
  bool get _hasMissingReturnData {
    final holdings = widget.dataManager?.holdings ?? [];
    for (final holding in holdings) {
      if (holding.navReturn1m == null &&
          holding.navReturn3m == null &&
          holding.navReturn6m == null &&
          holding.navReturn1y == null) {
        return true;
      }
    }
    return false;
  }

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

  // 普通刷新
  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    if (widget.dataManager == null || widget.fundService == null) return;

    // 检查是否有缺失收益率数据的基金
    if (!_hasMissingReturnData) {
      context.showToast('所有基金已有收益率数据，无需刷新', duration: const Duration(seconds: 2));
      widget.dataManager?.addLog('手动刷新: 所有基金已有收益率数据，跳过刷新', type: LogType.info);
      return;
    }

    setState(() => _isRefreshing = true);
    context.showToast('正在刷新缺失数据的基金...', duration: const Duration(seconds: 1));

    try {
      await widget.dataManager!.refreshAllHoldingsForce(widget.fundService!, null);
      if (mounted) {
        context.showToast('刷新完成');
        widget.dataManager?.addLog('手动刷新数据完成', type: LogType.success);
      }
    } catch (e) {
      if (mounted) {
        context.showToast('刷新失败: $e');
        widget.dataManager?.addLog('手动刷新失败: $e', type: LogType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  // 强制刷新（长按）
  Future<void> _onLongPressRefresh() async {
    if (_isRefreshing) return;
    if (widget.dataManager == null || widget.fundService == null) return;

    setState(() => _isRefreshing = true);
    context.showToast('强制刷新中，将重新获取所有基金净值...', duration: const Duration(seconds: 2));

    try {
      await widget.dataManager!.refreshAllHoldingsForce(widget.fundService!, null);
      if (mounted) {
        context.showToast('强制刷新完成');
        widget.dataManager?.addLog('强制刷新所有基金数据完成', type: LogType.success);
      }
    } catch (e) {
      if (mounted) {
        context.showToast('强制刷新失败: $e');
        widget.dataManager?.addLog('强制刷新失败: $e', type: LogType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
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

  // 磨玻璃容器包装
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
      children.add(_buildRefreshButton());
    }
    if (widget.showSort) {
      if (children.isNotEmpty) children.add(SizedBox(width: widget.buttonSpacing));
      children.add(_buildSortButton(disabled: !_hasData));
    }
    return children;
  }

  Widget _buildRightGroup() {
    final children = <Widget>[];
    if (widget.showReset) {
      children.add(_buildResetButton());
    }
    if (widget.showFilter) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 4));
      children.add(_buildFilterButton());
    }
    if (widget.showSearch) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 4));
      children.add(_buildSearchButton());
    }
    if (widget.showExpandCollapse) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 4));
      children.add(_buildExpandCollapseButton());
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return _wrapWithGlass(Row(mainAxisSize: MainAxisSize.min, children: children), disabled: !_hasData);
  }

  List<Widget> _buildRightChildren() {
    final children = <Widget>[];
    children.add(_buildRightGroup());
    return children;
  }

  Widget _buildRefreshButton() {
    final hasData = _hasData;
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return GestureDetector(
      onTap: hasData ? _onRefresh : null,
      onLongPress: hasData ? _onLongPressRefresh : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF2C2C2E).withOpacity(0.85)
              : CupertinoColors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _isRefreshing
            ? SizedBox(
          width: widget.iconSize,
          height: widget.iconSize,
          child: const CupertinoActivityIndicator(),
        )
            : Icon(
          CupertinoIcons.arrow_clockwise,
          size: widget.iconSize,
          color: hasData ? widget.iconColor : CupertinoColors.systemGrey3,
        ),
      ),
    );
  }

  Widget _buildResetButton() {
    final hasData = _hasData;
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return GestureDetector(
      onTap: hasData ? widget.onReset : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF2C2C2E).withOpacity(0.85)
              : CupertinoColors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          CupertinoIcons.delete,  // 改为垃圾桶图标
          size: widget.iconSize,
          color: hasData ? widget.iconColor : CupertinoColors.systemGrey3,
        ),
      ),
    );
  }

  Widget _buildFilterButton() {
    final hasData = _hasData;
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return GestureDetector(
      onTap: hasData ? widget.onFilter : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF2C2C2E).withOpacity(0.85)
              : CupertinoColors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          CupertinoIcons.slider_horizontal_3,
          size: widget.iconSize,
          color: hasData ? widget.iconColor : CupertinoColors.systemGrey3,
        ),
      ),
    );
  }

  Widget _buildSearchButton() {
    final hasData = _hasData;
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return GestureDetector(
      onTap: hasData ? () => _setSearchVisible(!_currentSearchVisible) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF2C2C2E).withOpacity(0.85)
              : CupertinoColors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          _currentSearchVisible ? CupertinoIcons.search_circle_fill : CupertinoIcons.search,
          size: widget.iconSize,
          color: hasData ? widget.iconColor : CupertinoColors.systemGrey3,
        ),
      ),
    );
  }

  Widget _buildExpandCollapseButton() {
    final hasData = _hasData;
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return GestureDetector(
      onTap: hasData ? widget.onToggleExpandAll : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF2C2C2E).withOpacity(0.85)
              : CupertinoColors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          widget.isAllExpanded ? CupertinoIcons.arrow_up_doc : CupertinoIcons.arrow_down_doc,
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
              onPressed: disabled ? null : () => widget.onSortKeyChanged?.call(
                  widget.sortKey.next(cycleType: widget.sortCycleType)
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.sortKey.icon,
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
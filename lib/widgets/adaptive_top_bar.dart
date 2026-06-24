import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;
import '../utils/animation_config.dart';
import 'search.dart';
import 'countdown_refresh_button.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import 'toast.dart';

enum SortCycleType {
  fundReturns,
  holdings,
}

enum SortKey {
  none,
  latestNav,
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
      case SortKey.latestNav:
        return '查估值';
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
      case SortKey.latestNav:
        return const Color(0xFF8B5CF6);
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
      case SortKey.latestNav:
        return CupertinoIcons.chart_bar;
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
            return SortKey.latestNav;
          case SortKey.latestNav:
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

  double? getValue(FundHolding holding, {DataManager? dataManager}) {
    switch (this) {
      case SortKey.latestNav:
        return holding.currentNav;
      case SortKey.navReturn1m:
        return holding.navReturn1m;
      case SortKey.navReturn3m:
        return holding.navReturn3m;
      case SortKey.navReturn6m:
        return holding.navReturn6m;
      case SortKey.navReturn1y:
        return holding.navReturn1y;
      case SortKey.amount:
        return holding.totalCost;
      case SortKey.profit:
        return holding.profit;
      case SortKey.profitRate:
        // Use precomputed holding.profitRate instead of expensive calculateProfit()
        return holding.totalCost > 0
            ? holding.profit / holding.totalCost * 100
            : 0.0;
      case SortKey.days:
        // Use navDate-based holdingDays from FundHolding (precomputed)
        return holding.holdingDays.toDouble();
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
  final ScrollController? scrollController;

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
  final String? searchPlaceholder;

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

  final bool showValuationRefresh;
  final int? valuationRefreshIntervalSeconds;
  final VoidCallback? onValuationRefresh;
  final Function(int)? onValuationRefreshIntervalChanged;
  final String? valuationUpdateTime;
  final double valuationRefreshProgress;
  final bool isValuationRefreshing;

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

  final bool useMenuStyle;
  
  final bool? hasData;

  const AdaptiveTopBar({
    super.key,
    required this.scrollOffset,
    this.scrollController,
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
    this.searchPlaceholder,
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
    this.showValuationRefresh = false,
    this.valuationRefreshIntervalSeconds,
    this.onValuationRefresh,
    this.onValuationRefreshIntervalChanged,
    this.valuationUpdateTime,
    this.valuationRefreshProgress = 0.0,
    this.isValuationRefreshing = false,
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
    this.useMenuStyle = false,
    this.hasData,
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
  Timer? _autoCloseTimer; 
  Timer? _searchDebounceTimer;
  bool _isRefreshing = false;
  final GlobalKey _sortButtonKey = GlobalKey();
  String _lastCommittedSearchText = '';

  bool get _externallyControlSearchVisible => widget.isSearchVisible != null;
  bool get _externallyControlSearchText => widget.searchText != null;
  String get _currentSearchText => _externallyControlSearchText ? widget.searchText! : _internalSearchText;
  bool get _currentSearchVisible => _externallyControlSearchVisible ? widget.isSearchVisible! : _internalSearchVisible;

  bool get _hasData {
    if (widget.hasData != null) {
      return widget.hasData!;
    }
    return widget.dataManager?.holdings.isNotEmpty ?? false;
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
      if (!_internalFocusNode.hasFocus) {
        _resetAutoCloseTimer();
      }
    });
  }

  @override
  void didUpdateWidget(AdaptiveTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateHideProgress();
    if (_externallyControlSearchText && 
        widget.searchText != _internalSearchController.text &&
        !_internalFocusNode.hasFocus) {
      _internalSearchController.text = widget.searchText ?? '';
      if ((widget.searchText ?? '').isEmpty) {
        _internalSearchController.selection = TextSelection.collapsed(offset: 0);
      }
    } else if (_externallyControlSearchText && widget.searchText != _internalSearchController.text) {
    }
  }

  void _updateHideProgress() {
    bool isDesktop = kIsWeb || 
                     defaultTargetPlatform == TargetPlatform.windows ||
                     defaultTargetPlatform == TargetPlatform.macOS ||
                     defaultTargetPlatform == TargetPlatform.linux;
    
    if (isDesktop) {
      _hideController.value = 1.0; 
      return;
    }

    final hasText = _currentSearchText.isNotEmpty;
    if (hasText && !_currentSearchVisible) {
      _setSearchVisible(true);
      return;
    }

    final rawOffset = widget.scrollOffset.isNaN ? 0 : widget.scrollOffset;
    double rawProgress = 1.0 - (rawOffset / 150).clamp(0.0, 1.0);
    double targetProgress = Curves.easeOutCubic.transform(rawProgress);

    if ((targetProgress - _lastProgress).abs() > 0.01) {
      _lastProgress = targetProgress;
      if (_hideController.isAnimating) {
        _hideController.stop();
      }
      _hideController.value = targetProgress;
    }
    if (targetProgress < 0.05 && _currentSearchVisible && _currentSearchText.isEmpty && !_internalFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !_currentSearchVisible) {
          _setSearchVisible(false);
        }
      });
    }
  }

  void _setSearchVisible(bool visible) {
    if (_externallyControlSearchVisible) {
      if (visible && !_currentSearchVisible) widget.onSearchChanged?.call(_currentSearchText);
    } else {
      setState(() => _internalSearchVisible = visible);
    }
    if (visible) {
      _startAutoCloseTimer();
    } else {
      _cancelAutoCloseTimer();
    }
  }

  void _startAutoCloseTimer() {
    _cancelAutoCloseTimer();
    _autoCloseTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _currentSearchVisible && _currentSearchText.isEmpty && !_internalFocusNode.hasFocus) {
        _setSearchVisible(false);
      }
    });
  }

  void _cancelAutoCloseTimer() {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;
  }

  void _resetAutoCloseTimer() {
    if (_currentSearchVisible) {
      _startAutoCloseTimer();
    }
  }

  void _onSearchChanged(String value) {
    
    _searchDebounceTimer?.cancel();
    
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      
      if (_lastCommittedSearchText != value) {
        _lastCommittedSearchText = value;
        
        if (_externallyControlSearchText) {
          widget.onSearchChanged?.call(value);
        } else {
          setState(() => _internalSearchText = value);
        }
      } else {
      }
    });
    
    _resetAutoCloseTimer();
  }

  void _onSearchClear() {
    _searchDebounceTimer?.cancel();
    
    _internalSearchController.clear();
    _lastCommittedSearchText = '';
    
    if (_externallyControlSearchText) {
      widget.onSearchClear?.call();
      widget.onSearchChanged?.call('');
    } else {
      setState(() {
        _internalSearchText = '';
      });
      widget.onSearchClear?.call();
      widget.onSearchChanged?.call('');
    }
    
    if (!_internalFocusNode.hasFocus) {
      _internalFocusNode.requestFocus();
    }
  }

  void _onReset() {
    _onSearchClear();
    widget.onReset?.call();
  }

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;

    if (widget.dataManager == null || widget.fundService == null) return;

    final holdings = widget.dataManager!.holdings;
    if (holdings.isEmpty) {
      if (mounted) {
        context.showToast('暂无基金数据，请先添加基金', duration: const Duration(seconds: 1));
      }
      return;
    }

    if (mounted) {
      setState(() => _isRefreshing = true);
      context.showToast('正在刷新净值...', duration: const Duration(seconds: 1));
    }

    try {
      // Per-fund cache freshness is checked inside fetchFundInfo (FundService).
      // Funds whose cached NAV already matches the latest trading day hit the
      // cache and skip the API; only truly stale funds reach the network.
      if (widget.onRefresh != null) {
        // External callback manages its own completion toast.
        widget.onRefresh!();
      } else {
        await widget.dataManager!.refreshAllHoldings(widget.fundService!, null);
        if (mounted) {
          context.showToast('刷新完成');
          widget.dataManager?.addLog('手动刷新基金数据完成', type: LogType.success);
        }
      }
    } catch (e) {
      if (mounted) {
        context.showToast('刷新失败: $e');
        widget.dataManager?.addLog('手动刷新基金数据失败: $e', type: LogType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _onLongPressRefresh() async {
    if (_isRefreshing) return;
    if (widget.dataManager == null || widget.fundService == null) return;

    if (mounted) setState(() => _isRefreshing = true);
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
        widget.dataManager?.addLog('强制刷新所有基金数据失败: $e', type: LogType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  void _onValuationRefresh() {
    if (widget.isValuationRefreshing) return;
    widget.onValuationRefresh?.call();
  }

  Color _getBackgroundColor(double progress, bool isDarkMode) {
    if (progress >= 0.95) {
      return isDarkMode
          ? const Color(0xFF1C1C1E).withOpacity(0.95)
          : const Color(0xFFF2F2F7).withOpacity(0.95);
    } else if (progress >= 0.5) {
      final opacity = 0.5 + (progress - 0.5) * 0.9;
      return isDarkMode
          ? const Color(0xFF1C1C1E).withOpacity(opacity)
          : const Color(0xFFF2F2F7).withOpacity(opacity);
    } else {
      return isDarkMode
          ? const Color(0xFF1C1C1E).withOpacity(0.5)
          : const Color(0xFFF2F2F7).withOpacity(0.5);
    }
  }

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

  Widget _buildValuationWidget() {
    if (!widget.showValuationRefresh || widget.valuationRefreshIntervalSeconds == null) {
      return const SizedBox.shrink();
    }
    
    final isTradingTime = _checkIsTradingTime();
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CountdownRefreshButton(
          onRefresh: _onValuationRefresh,
          refreshIntervalSeconds: widget.valuationRefreshIntervalSeconds!,
          isRefreshing: widget.isValuationRefreshing,
          refreshProgress: widget.valuationRefreshProgress,
          size: 32,
          onIntervalChanged: widget.onValuationRefreshIntervalChanged,
          isTradingTime: isTradingTime,
        ),
        if (widget.valuationUpdateTime != null && widget.valuationUpdateTime!.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            widget.valuationUpdateTime!,
            style: TextStyle(
              fontSize: 10,
              color: CupertinoTheme.brightnessOf(context) == Brightness.dark
                  ? CupertinoColors.white.withOpacity(0.5)
                  : CupertinoColors.systemGrey,
            ),
          ),
        ],
      ],
    );
  }
  
  bool _checkIsTradingTime() {
    final now = DateTime.now();
    final weekday = now.weekday;
    
    if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
      return false;
    }
    
    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 60 + minute;
    
    final morningStart = 9 * 60 + 30;
    final morningEnd = 11 * 60 + 30;
    final afternoonStart = 13 * 60;
    final afternoonEnd = 15 * 60;
    
    return (currentTime >= morningStart && currentTime <= morningEnd) ||
           (currentTime >= afternoonStart && currentTime <= afternoonEnd);
  }

  Widget _buildLeftForMenuStyle() {
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
    if (widget.showSort && widget.onSortKeyChanged != null) {
      if (children.isNotEmpty) children.add(SizedBox(width: widget.buttonSpacing));
      children.add(_buildSortButton(disabled: !_hasData));
    }
    if (widget.showValuationRefresh && widget.sortKey == SortKey.latestNav) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 8));
      children.add(_buildValuationWidget());
    }
    return children.isEmpty ? const SizedBox.shrink() : Row(children: children);
  }

  Widget _buildRightForMenuStyle() {
    final children = <Widget>[];
    if (widget.showValuationRefresh && widget.sortKey != SortKey.latestNav) {
      children.add(_buildValuationWidget());
      children.add(const SizedBox(width: 8));
    }

    final menuItems = <_MenuItem>[];
    if (widget.showRefresh) {
      menuItems.add(_MenuItem(
        icon: CupertinoIcons.arrow_clockwise,
        label: '刷新',
        onTap: () => _onRefresh(),
        onLongPress: () => _onLongPressRefresh(),
      ));
    }
    if (widget.showSearch) {
      menuItems.add(_MenuItem(
        icon: CupertinoIcons.search,
        label: '搜索',
        onTap: () => _setSearchVisible(!_currentSearchVisible),
      ));
    }
    if (widget.showExpandCollapse) {
      menuItems.add(_MenuItem(
        icon: widget.isAllExpanded ? CupertinoIcons.arrow_up_doc : CupertinoIcons.arrow_down_doc,
        label: widget.isAllExpanded ? '折叠' : '展开',
        onTap: () => widget.onToggleExpandAll?.call(),
      ));
    }

    if (menuItems.isNotEmpty && _hasData) {
      children.add(_GlassPopupMenuButton(
        items: menuItems,
        icon: Icon(
          CupertinoIcons.ellipsis,
          size: widget.iconSize,
          color: widget.iconColor,
        ),
        disabled: false,
        scrollController: widget.scrollController,
      ));
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: children);
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
    if (widget.showSort) {
      if (children.isNotEmpty) children.add(SizedBox(width: widget.buttonSpacing));
      children.add(_buildSortButton(disabled: !_hasData));
    }
    return children;
  }

  Widget _buildRightGroup() {
    final children = <Widget>[];
    
    if (widget.showRefresh) {
      children.add(_buildRefreshButton());
    }
    
    if (widget.showValuationRefresh && widget.valuationUpdateTime != null && widget.valuationUpdateTime!.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            widget.valuationUpdateTime!,
            style: TextStyle(
              fontSize: 10,
              color: CupertinoTheme.brightnessOf(context) == Brightness.dark
                  ? CupertinoColors.white.withOpacity(0.5)
                  : CupertinoColors.systemGrey,
            ),
          ),
        ),
      );
    }
    if (widget.showValuationRefresh && widget.valuationRefreshIntervalSeconds != null) {
      final isTradingTime = _checkIsTradingTime();
      
      children.add(CountdownRefreshButton(
        onRefresh: _onValuationRefresh,
        refreshIntervalSeconds: widget.valuationRefreshIntervalSeconds!,
        isRefreshing: widget.isValuationRefreshing,
        refreshProgress: widget.valuationRefreshProgress,
        size: 32,
        onIntervalChanged: widget.onValuationRefreshIntervalChanged,
        isTradingTime: isTradingTime,
      ));
      if (widget.showReset || widget.showFilter || widget.showSearch || widget.showExpandCollapse) {
        children.add(const SizedBox(width: 4));
      }
    }
    if (widget.showReset) {
      children.add(
        AnimatedOpacity(
          opacity: widget.showReset ? 1.0 : 0.0,
          duration: AnimationConfig.durationFade,
          curve: AnimationConfig.curveFade,
          child: _buildResetButton(),
        ),
      );
    }
    if (widget.showFilter) {
      if (children.isNotEmpty && !widget.showReset) {
        children.add(const SizedBox(width: 4));
      }
      children.add(
        AnimatedOpacity(
          opacity: widget.showFilter ? 1.0 : 0.0,
          duration: AnimationConfig.durationFade,
          curve: AnimationConfig.curveFade,
          child: _buildFilterButton(),
        ),
      );
    }
    if (widget.showSearch) {
      if (children.isNotEmpty && !widget.showReset && !widget.showFilter) {
        children.add(const SizedBox(width: 4));
      }
      children.add(
        AnimatedOpacity(
          opacity: widget.showSearch ? 1.0 : 0.0,
          duration: AnimationConfig.durationFade,
          curve: AnimationConfig.curveFade,
          child: _buildSearchButton(),
        ),
      );
    }
    if (widget.showExpandCollapse) {
      if (children.isNotEmpty && !widget.showReset && !widget.showFilter && !widget.showSearch) {
        children.add(const SizedBox(width: 4));
      }
      children.add(
        AnimatedOpacity(
          opacity: widget.showExpandCollapse ? 1.0 : 0.0,
          duration: AnimationConfig.durationFade,
          curve: AnimationConfig.curveFade,
          child: _buildExpandCollapseButton(),
        ),
      );
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
          color: isDarkMode ? const Color(0xFF2C2C2E).withOpacity(0.85) : CupertinoColors.white.withOpacity(0.85),
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
            ? SizedBox(width: widget.iconSize, height: widget.iconSize, child: const CupertinoActivityIndicator())
            : Icon(CupertinoIcons.arrow_clockwise, size: widget.iconSize, color: hasData ? widget.iconColor : CupertinoColors.systemGrey3),
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
          color: isDarkMode ? const Color(0xFF2C2C2E).withOpacity(0.85) : CupertinoColors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(CupertinoIcons.delete, size: widget.iconSize, color: hasData ? widget.iconColor : CupertinoColors.systemGrey3),
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
          color: isDarkMode ? const Color(0xFF2C2C2E).withOpacity(0.85) : CupertinoColors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(CupertinoIcons.slider_horizontal_3, size: widget.iconSize, color: hasData ? widget.iconColor : CupertinoColors.systemGrey3),
      ),
    );
  }

  Widget _buildSearchButton() {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return GestureDetector(
      onTap: () => _setSearchVisible(!_currentSearchVisible),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF2C2C2E).withOpacity(0.85) : CupertinoColors.white.withOpacity(0.85),
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
          color: widget.iconColor,
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
          color: isDarkMode ? const Color(0xFF2C2C2E).withOpacity(0.85) : CupertinoColors.white.withOpacity(0.85),
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
    final bgColor = isDarkMode ? const Color(0xFF2C2C2E).withOpacity(0.85) : CupertinoColors.white.withOpacity(0.85);
    final textColor = widget.sortKey == SortKey.none
        ? (isDarkMode ? CupertinoColors.white : CupertinoColors.label)
        : widget.sortKey.color;
    
    final List<_MenuItem> sortMenuItems = [];
    
    if (widget.sortCycleType == SortCycleType.fundReturns) {
      sortMenuItems.addAll([
        _MenuItem(
          icon: SortKey.none.icon,
          label: SortKey.none.displayName,
          onTap: () {
            widget.onSortKeyChanged?.call(SortKey.none);
          },
        ),
        _MenuItem(
          icon: SortKey.latestNav.icon,
          label: SortKey.latestNav.displayName,
          onTap: () {
            widget.onSortKeyChanged?.call(SortKey.latestNav);
          },
        ),
        _MenuItem(
          icon: SortKey.navReturn1m.icon,
          label: SortKey.navReturn1m.displayName,
          onTap: () {
            widget.onSortKeyChanged?.call(SortKey.navReturn1m);
          },
        ),
        _MenuItem(
          icon: SortKey.navReturn3m.icon,
          label: SortKey.navReturn3m.displayName,
          onTap: () {
            widget.onSortKeyChanged?.call(SortKey.navReturn3m);
          },
        ),
        _MenuItem(
          icon: SortKey.navReturn6m.icon,
          label: SortKey.navReturn6m.displayName,
          onTap: () {
            widget.onSortKeyChanged?.call(SortKey.navReturn6m);
          },
        ),
        _MenuItem(
          icon: SortKey.navReturn1y.icon,
          label: SortKey.navReturn1y.displayName,
          onTap: () {
            widget.onSortKeyChanged?.call(SortKey.navReturn1y);
          },
        ),
      ]);
    } else {
      sortMenuItems.addAll([
        _MenuItem(
          icon: SortKey.none.icon,
          label: SortKey.none.displayName,
          onTap: () => widget.onSortKeyChanged?.call(SortKey.none),
        ),
        _MenuItem(
          icon: SortKey.amount.icon,
          label: SortKey.amount.displayName,
          onTap: () => widget.onSortKeyChanged?.call(SortKey.amount),
        ),
        _MenuItem(
          icon: SortKey.days.icon,
          label: SortKey.days.displayName,
          onTap: () => widget.onSortKeyChanged?.call(SortKey.days),
        ),
        _MenuItem(
          icon: SortKey.profitRate.icon,
          label: SortKey.profitRate.displayName,
          onTap: () => widget.onSortKeyChanged?.call(SortKey.profitRate),
        ),
        _MenuItem(
          icon: SortKey.profit.icon,
          label: SortKey.profit.displayName,
          onTap: () => widget.onSortKeyChanged?.call(SortKey.profit),
        ),
      ]);
    }
    
    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Container(
        key: _sortButtonKey, 
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              onPressed: disabled ? null : () {
                _showSortMenu(sortMenuItems, isDarkMode, textColor);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.sortKey.icon, size: 16, color: textColor),
                  const SizedBox(width: 6),
                  Text(widget.sortKey.displayName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textColor)),
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
  
  void _showSortMenu(List<_MenuItem> items, bool isDarkMode, Color textColor) {
    final RenderBox? renderBox = _sortButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    final overlay = Overlay.of(_sortButtonKey.currentContext!);
    OverlayEntry? overlayEntry;
    GlobalKey<_AnimatedButtonGroupState>? menuKey;
    Timer? autoCloseTimer;

    menuKey = GlobalKey<_AnimatedButtonGroupState>();
    bool isClosed = false;
    VoidCallback? scrollListener;

    void _closeMenuWithAnimation() {
      if (isClosed) return;
      isClosed = true;
      scrollListener?.call();
      if (menuKey?.currentState != null) {
        menuKey!.currentState!.close();
      } else {
        try {
          overlayEntry?.remove();
        } catch (_) {}
      }
    }

    void _closeMenuImmediately() {
      if (isClosed) return;
      isClosed = true;
      scrollListener?.call();
      try {
        overlayEntry?.remove();
      } catch (_) {}
    }

    void startAutoCloseTimer() {
      autoCloseTimer?.cancel();
      autoCloseTimer = Timer(const Duration(seconds: 5), () {
        if (!isClosed) _closeMenuWithAnimation();
      });
    }

    void cancelAutoCloseTimer() {
      autoCloseTimer?.cancel();
    }

    // Close menu when user scrolls
    if (widget.scrollController != null) {
      final initialOffset = widget.scrollController!.offset;
      scrollListener = () {
        widget.scrollController?.removeListener(scrollListener!);
      };
      void onScroll() {
        if (!isClosed && (widget.scrollController!.offset - initialOffset).abs() > 4.0) {
          scrollListener?.call();
          _closeMenuWithAnimation();
        }
      }
      widget.scrollController!.addListener(onScroll);
      scrollListener = () {
        widget.scrollController?.removeListener(onScroll);
      };
    }

    overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                cancelAutoCloseTimer();
                _closeMenuWithAnimation();
              },
              behavior: HitTestBehavior.translucent,
            ),
          ),
          Positioned(
            top: offset.dy + size.height + 8,
            left: offset.dx,
            child: Material(
              color: Colors.transparent,
              child: MouseRegion(
                onEnter: (_) => cancelAutoCloseTimer(),
                onExit: (_) => startAutoCloseTimer(),
                child: _AnimatedButtonGroup(
                  key: menuKey,
                  items: items.map((item) => _MenuItem(
                    icon: item.icon,
                    label: item.label,
                    onTap: () {
                      cancelAutoCloseTimer();
                      item.onTap();
                      _closeMenuImmediately();
                    },
                  )).toList(),
                  onHide: () {
                    if (!isClosed) isClosed = true;
                    scrollListener?.call();
                    overlayEntry?.remove();
                  },
                  columns: 2,
                  isGlassStyle: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(overlayEntry);
    startAutoCloseTimer();
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _searchDebounceTimer?.cancel();
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

    final bool shouldDisableInteraction = progress < 0.95;

    return GestureDetector(
      onTap: () {
        if (_currentSearchVisible && _internalFocusNode.hasFocus) {
          _internalFocusNode.unfocus();
        }
      },
      behavior: HitTestBehavior.translucent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _hideController,
            builder: (context, _) {
              final barContent = Opacity(
                opacity: progress,
                child: Transform.translate(
                  offset: Offset(0, -16 * (1 - progress)),
                  child: IgnorePointer(
                    ignoring: shouldDisableInteraction,
                    child: Container(
                      height: widget.maxHeight * progress,
                      padding: widget.padding,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16 * progress)),
                      ),
                      child: Row(
                        children: [
                          widget.useMenuStyle ? _buildLeftForMenuStyle() : Row(children: _buildLeftChildren()),
                          const Spacer(),
                          widget.useMenuStyle ? _buildRightForMenuStyle() : Row(children: _buildRightChildren()),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              if (blurAmount < 0.5) return barContent;

              return RepaintBoundary(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
                    child: barContent,
                  ),
                ),
              );
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutCubic,
            child: AnimatedOpacity(
              opacity: _currentSearchVisible ? 1.0 : 0.0,
              duration: AnimationConfig.durationFade,
              curve: AnimationConfig.curveFade,
              child: SizedBox(
                height: _currentSearchVisible ? 52 : 0,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Search(
                    controller: _internalSearchController,
                    focusNode: _internalFocusNode,
                    onChanged: _onSearchChanged,
                    onClear: _onSearchClear,
                    placeholder: widget.searchPlaceholder,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  _MenuItem({required this.icon, required this.label, required this.onTap, this.onLongPress});
}

class _GlassPopupMenuButton extends StatefulWidget {
  final List<_MenuItem> items;
  final Widget icon;
  final bool disabled;
  final ScrollController? scrollController;
  const _GlassPopupMenuButton({
    required this.items,
    required this.icon,
    this.disabled = false,
    this.scrollController,
  });

  @override
  State<_GlassPopupMenuButton> createState() => _GlassPopupMenuButtonState();
}

class _GlassPopupMenuButtonState extends State<_GlassPopupMenuButton> with SingleTickerProviderStateMixin {
  final GlobalKey _buttonKey = GlobalKey();
  final GlobalKey<_AnimatedButtonGroupState> _menuKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _isShowing = false;
  Timer? _autoCloseTimer;
  VoidCallback? _scrollListener;

  void _startAutoCloseTimer() {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = Timer(const Duration(seconds: 5), () {
      if (_isShowing) {
        _hideMenuWithAnimation(); 
      }
    });
  }

  void _cancelAutoCloseTimer() {
    _autoCloseTimer?.cancel();
  }

  void _showMenu() {
    if (widget.disabled || _isShowing) return;
    _isShowing = true;
    final RenderBox renderBox = _buttonKey.currentContext!.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    // Register scroll-to-close. Remove the overlay directly rather than
    // delegating through _menuKey.currentState which may be null if the
    // widget tree hasn't settled (race on first frame after overlay insert).
    _scrollListener?.call();
    _scrollListener = null;
    if (widget.scrollController != null) {
      final sc = widget.scrollController!;
      final initialOffset = sc.offset;
      void onScroll() {
        if (!_isShowing) return;
        if ((sc.offset - initialOffset).abs() <= 4.0) return;
        _cancelAutoCloseTimer();
        _isShowing = false;
        _scrollListener?.call();
        _scrollListener = null;
        _overlayEntry?.remove();
        _overlayEntry = null;
      }
      sc.addListener(onScroll);
      _scrollListener = () => sc.removeListener(onScroll);
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _hideMenuWithAnimation,
              behavior: HitTestBehavior.translucent,
            ),
          ),
          Positioned(
            top: offset.dy + size.height + 8,
            right: MediaQuery.of(context).size.width - (offset.dx + size.width),
            child: MouseRegion(
              onEnter: (_) => _cancelAutoCloseTimer(),
              onExit: (_) => _startAutoCloseTimer(),
              child: Material(
                color: Colors.transparent,
                child: _AnimatedButtonGroup(
                  key: _menuKey,
                  items: widget.items,
                  onHide: _removeOverlay,
                  isGlassStyle: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
    _startAutoCloseTimer();
  }

  void _hideMenuWithAnimation() {
    if (!_isShowing) return;
    _cancelAutoCloseTimer();
    _isShowing = false;
    
    _menuKey.currentState?.close();
  }

  void _removeOverlay() {
    _scrollListener?.call();
    _scrollListener = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isShowing = false;
  }

  void _hideMenu() {
    _removeOverlay();
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  Widget _buildButtonGroupOverlay(Offset buttonOffset, Size buttonSize) {
    final screenSize = MediaQuery.of(context).size;
    final menuHeight = widget.items.length * 48.0 + 16.0; 
    final menuWidth = kIsWeb ? 50.0 : 120.0;
    
    final spaceBelow = screenSize.height - (buttonOffset.dy + buttonSize.height);
    final spaceAbove = buttonOffset.dy;
    final spaceRight = screenSize.width - (buttonOffset.dx + buttonSize.width);
    
    double menuTop;
    double? menuLeft;
    double? menuRight;
    bool showAbove = false;
    
    if (spaceRight >= menuWidth) {
      menuLeft = null;
      menuRight = screenSize.width - (buttonOffset.dx + buttonSize.width);
    } else {
      menuLeft = null;
      menuRight = 8; 
    }
    
    if (spaceBelow >= menuHeight || spaceBelow > spaceAbove) {
      showAbove = false;
      menuTop = buttonOffset.dy + buttonSize.height + 8;
      if (menuTop + menuHeight > screenSize.height - 8) {
        menuTop = screenSize.height - menuHeight - 8;
      }
    } else {
      showAbove = true;
      menuTop = buttonOffset.dy - menuHeight - 8;
      if (menuTop < 8) {
        menuTop = 8;
      }
    }

    return GestureDetector(
      onTap: _hideMenu,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.transparent)),
          Positioned(
            top: menuTop,
            left: menuLeft,
            right: menuRight,
            child: _AnimatedButtonGroup(
              items: widget.items,
              onHide: _hideMenu,
              isGlassStyle: true,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _buttonKey,
      onTap: _showMenu,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: CupertinoTheme.brightnessOf(context) == Brightness.dark
              ? const Color(0xFF2C2C2E).withOpacity(0.85)
              : CupertinoColors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(CupertinoTheme.brightnessOf(context) == Brightness.dark ? 0.2 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: widget.icon,
      ),
    );
  }
}

/// Builds a frosted-glass container. On web (HTML renderer) skips the
/// BackdropFilter which is unsupported and causes framework rebuild errors.
Widget _buildGlassBackground({
  required bool isDark,
  required Color bgColor,
  required BorderRadiusGeometry br,
  required bool isGlassStyle,
  required Widget child,
}) {
  final container = Container(
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: br,
      border: isGlassStyle
          ? Border.all(
              color: isDark
                  ? CupertinoColors.white.withOpacity(0.06)
                  : CupertinoColors.black.withOpacity(0.04),
            )
          : null,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
  if (kIsWeb || !isGlassStyle) return container;
  return BackdropFilter(
    filter: ImageFilter.blur(
      sigmaX: AnimationConfig.menuBlurSigma,
      sigmaY: AnimationConfig.menuBlurSigma,
    ),
    child: container,
  );
}

class _AnimatedButtonGroup extends StatefulWidget {
  final List<_MenuItem> items;
  final VoidCallback onHide;
  final bool showAbove;
  final VoidCallback? onAnimationComplete;
  final int columns;
  final bool isGlassStyle;

  const _AnimatedButtonGroup({
    super.key,
    required this.items,
    required this.onHide,
    this.showAbove = false,
    this.onAnimationComplete,
    this.columns = 1,
    this.isGlassStyle = false,
  });

  @override
  State<_AnimatedButtonGroup> createState() => _AnimatedButtonGroupState();
}

class _AnimatedButtonGroupState extends State<_AnimatedButtonGroup> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  List<AnimationController> _itemControllers = [];
  List<Animation<double>> _itemAnimations = [];
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AnimationConfig.menuExpandDuration,
      vsync: this,
    );
    _opacityAnimation = CurvedAnimation(parent: _controller, curve: AnimationConfig.curveEaseOutCubic);
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: AnimationConfig.menuExpandCurve),
    );

    for (int i = 0; i < widget.items.length; i++) {
      final itemController = AnimationController(
        duration: AnimationConfig.menuItemPopDuration,
        vsync: this,
      );
      final itemAnimation = CurvedAnimation(
        parent: itemController,
        curve: const Interval(0.0, 0.65, curve: AnimationConfig.menuItemPopCurve),
      );
      _itemControllers.add(itemController);
      _itemAnimations.add(itemAnimation);

      Future.delayed(Duration(milliseconds: 40 + i * 60), () {
        if (mounted && !_isClosing) {
          itemController.forward();
        }
      });
    }

    _controller.forward();
  }

  @override
  void dispose() {
    for (var c in _itemControllers) {
      c.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> close() async {
    if (_isClosing) return;
    _isClosing = true;

    // Reverse items quickly (reverse order)
    for (int i = _itemControllers.length - 1; i >= 0; i--) {
      try {
        _itemControllers[i].reverse();
        if (i > 0) await Future.delayed(const Duration(milliseconds: 50));
      } catch (_) {
        break;
      }
    }

    await Future.delayed(const Duration(milliseconds: 200));

    try {
      if (!_controller.isAnimating && _controller.status != AnimationStatus.dismissed) {
        await _controller.reverse();
      }
    } catch (_) {}

    if (mounted) widget.onHide();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgOpacity = isDark
        ? AnimationConfig.menuBackgroundOpacityDark
        : AnimationConfig.menuBackgroundOpacityLight;
    final bgColor = widget.isGlassStyle
        ? (isDark
            ? const Color(0xFF1C1C1E).withOpacity(bgOpacity)
            : CupertinoColors.white.withOpacity(bgOpacity))
        : Colors.transparent;
    final br = BorderRadius.circular(AnimationConfig.menuBorderRadius);

    final items = widget.items;
    final colCount = widget.columns.clamp(1, items.length);
    final rows = (items.length / colCount).ceil();
    // Row-major: iterate rows then columns so items fill left→right, top→bottom
    final cols = <List<_MenuItem>>[];
    for (int c = 0; c < colCount; c++) {
      cols.add(<_MenuItem>[]);
    }
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < colCount; c++) {
        final idx = r * colCount + c;
        if (idx < items.length) cols[c].add(items[idx]);
      }
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final s = _scaleAnimation.value;
        final o = _opacityAnimation.value;
        return Opacity(
          opacity: o,
          child: Transform.scale(
            scale: s,
            alignment: Alignment.topLeft,
            child: child!,
          ),
        );
      },
      child: IgnorePointer(
        ignoring: _isClosing,
        child: ClipRRect(
          borderRadius: br,
          child: _buildGlassBackground(
            isDark: isDark,
            bgColor: bgColor,
            br: br,
            isGlassStyle: widget.isGlassStyle,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: cols.asMap().entries.map((colEntry) {
                  final isLastCol = colEntry.key == cols.length - 1;
                  return Padding(
                    padding: EdgeInsets.only(right: isLastCol ? 0 : 10),
                    child: SizedBox(
                      width: AnimationConfig.menuItemMinWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: colEntry.value.asMap().entries.map((entry) {
                          final idx = items.indexOf(entry.value);
                          if (idx < 0 || idx >= _itemAnimations.length) {
                            return const SizedBox.shrink();
                          }
                          final item = entry.value;
                          final isLast = entry.key == colEntry.value.length - 1;
                          return AnimatedBuilder(
                            animation: _itemAnimations[idx],
                            builder: (context, child) {
                              final v = _itemAnimations[idx].value.clamp(0.0, 1.0);
                              return Opacity(
                                opacity: v,
                                child: Transform.scale(
                                  scale: (0.8 + 0.2 * v).clamp(0.0, 1.0),
                                  alignment: Alignment.topLeft,
                                  child: child,
                                ),
                              );
                            },
                            child: Padding(
                              padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
                              child: _SortMenuItem(
                                item: item,
                                onClose: close,
                                isGlassStyle: widget.isGlassStyle,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SortMenuItem extends StatelessWidget {
  final _MenuItem item;
  final Future<void> Function() onClose;
  final bool isGlassStyle;

  const _SortMenuItem({
    required this.item,
    required this.onClose,
    this.isGlassStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isGlassStyle
        ? (isDark
            ? const Color(0xFF3A3A3C).withOpacity(0.45)
            : const Color(0xFFF2F2F7).withOpacity(0.5))
        : (isDark
            ? const Color(0xFF2C2C2E).withOpacity(0.9)
            : CupertinoColors.white.withOpacity(0.9));
    final textColor = isDark ? CupertinoColors.white : CupertinoColors.label;

    return GestureDetector(
      onTap: () {
        item.onTap();
        Future.delayed(const Duration(milliseconds: 50), onClose);
      },
      onLongPress: item.onLongPress != null
          ? () {
              item.onLongPress?.call();
              Future.delayed(const Duration(milliseconds: 50), onClose);
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: isGlassStyle
              ? Border.all(
                  color: isDark
                      ? CupertinoColors.white.withOpacity(0.06)
                      : CupertinoColors.black.withOpacity(0.04),
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 14, color: textColor.withOpacity(0.65)),
            const SizedBox(width: 8),
            Text(
              item.label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}
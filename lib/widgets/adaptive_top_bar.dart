import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;
import 'search.dart';
import 'countdown_refresh_button.dart';
import 'glass_button.dart';
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
        return '最新估值';
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
        // 使用DataManager的calculateProfit方法获取准确的年化收益率
        if (dataManager != null) {
          return dataManager.calculateProfit(holding).annualized;
        }
        return 0.0;
      case SortKey.days:
        if (dataManager == null) return 0.0;
        final transactions = dataManager.getTransactionHistory(holding.clientId, holding.fundCode);
        final days = transactions.isNotEmpty 
            ? DateTime.now().difference(transactions.last.tradeDate).inDays 
            : 0;
        return days.toDouble();
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
  final VoidCallback? onValuationRefreshIntervalChanged;
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
  Timer? _autoCloseTimer; // 自动关闭定时器
  bool _isRefreshing = false;

  bool get _externallyControlSearchVisible => widget.isSearchVisible != null;
  bool get _externallyControlSearchText => widget.searchText != null;
  String get _currentSearchText => _externallyControlSearchText ? widget.searchText! : _internalSearchText;
  bool get _currentSearchVisible => _externallyControlSearchVisible ? widget.isSearchVisible! : _internalSearchVisible;

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
      // 失去焦点时重置自动关闭定时器
      if (!_internalFocusNode.hasFocus) {
        _resetAutoCloseTimer();
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
    // 如果是PC端（Windows/macOS/Linux）或Web平台，始终显示顶部工具栏
    bool isDesktop = kIsWeb; // Web平台始终显示
    
    if (!isDesktop) {
      // 非Web平台才检查Platform
      try {
        // 这里需要导入dart:io，但为了Web兼容性，我们只在非Web时使用
        // 由于移除了dart:io导入，这里简化处理：移动端隐藏，其他显示
        isDesktop = false; // 默认按移动端处理
      } catch (e) {
        isDesktop = false;
      }
    }
    
    if (isDesktop) {
      _hideController.value = 1.0; // 始终完全显示
      return;
    }

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
    // 搜索框状态改变时，管理自动关闭定时器
    if (visible) {
      _startAutoCloseTimer();
    } else {
      _cancelAutoCloseTimer();
    }
  }

  // 启动自动关闭定时器（5秒后自动关闭）
  void _startAutoCloseTimer() {
    _cancelAutoCloseTimer();
    _autoCloseTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _currentSearchVisible && _currentSearchText.isEmpty && !_internalFocusNode.hasFocus) {
        _setSearchVisible(false);
      }
    });
  }

  // 取消自动关闭定时器
  void _cancelAutoCloseTimer() {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;
  }

  // 重置自动关闭定时器
  void _resetAutoCloseTimer() {
    if (_currentSearchVisible) {
      _startAutoCloseTimer();
    }
  }

  void _onSearchChanged(String value) {
    if (_externallyControlSearchText) {
      widget.onSearchChanged?.call(value);
    } else {
      setState(() => _internalSearchText = value);
      widget.onSearchChanged?.call(value);
    }
    // 每次输入时重置自动关闭定时器
    _resetAutoCloseTimer();
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

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    if (widget.dataManager == null || widget.fundService == null) return;

    final holdings = widget.dataManager!.holdings;
    final needRefresh = holdings.any((h) => h.currentNav <= 0);
    if (!needRefresh) {
      context.showToast('数据已是最新，跳过刷新', duration: const Duration(seconds: 1));
      return;
    }

    setState(() => _isRefreshing = true);
    context.showToast('正在刷新基金数据...', duration: const Duration(seconds: 1));

    try {
      await widget.dataManager!.refreshAllHoldingsForce(widget.fundService!, null);
      if (mounted) {
        context.showToast('刷新完成');
        widget.dataManager?.addLog('手动刷新基金数据完成', type: LogType.success);
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
    // 刷新按钮已移至右侧
    if (widget.showSort) {
      if (children.isNotEmpty) children.add(SizedBox(width: widget.buttonSpacing));
      children.add(_buildSortButton(disabled: !_hasData));
    }
    return children;
  }

  Widget _buildRightGroup() {
    final children = <Widget>[];
    
    // 刷新按钮放在最右侧
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
      children.add(CountdownRefreshButton(
        onRefresh: _onValuationRefresh,
        refreshIntervalSeconds: widget.valuationRefreshIntervalSeconds!,
        isRefreshing: widget.isValuationRefreshing,
        refreshProgress: widget.valuationRefreshProgress,
        size: 32,
        onIntervalChanged: widget.onValuationRefreshIntervalChanged,
      ));
      if (widget.showReset || widget.showFilter || widget.showSearch || widget.showExpandCollapse) {
        children.add(const SizedBox(width: 4));
      }
    }
    if (widget.showReset) {
      children.add(
        AnimatedOpacity(
          opacity: widget.showReset ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
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
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
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
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
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
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
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
    final hasData = _hasData;
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return GestureDetector(
      onTap: hasData ? () => _setSearchVisible(!_currentSearchVisible) : null,
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
              onPressed: disabled ? null : () => widget.onSortKeyChanged?.call(widget.sortKey.next(cycleType: widget.sortCycleType)),
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

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _autoCloseTimer?.cancel(); // 清理自动关闭定时器
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
                AnimatedSize(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOutCubic,
                  child: AnimatedOpacity(
                    opacity: _currentSearchVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: Container(
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
          ),
        );
      },
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
  const _GlassPopupMenuButton({required this.items, required this.icon, this.disabled = false});

  @override
  State<_GlassPopupMenuButton> createState() => _GlassPopupMenuButtonState();
}

class _GlassPopupMenuButtonState extends State<_GlassPopupMenuButton> with SingleTickerProviderStateMixin {
  final GlobalKey _buttonKey = GlobalKey();
  final GlobalKey<_AnimatedButtonGroupState> _menuKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _isShowing = false;
  Timer? _autoCloseTimer;

  void _startAutoCloseTimer() {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = Timer(const Duration(seconds: 5), () {
      if (_isShowing) {
        _hideMenu();
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

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // 透明背景，点击关闭（但不拦截菜单内的点击）
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                // 点击背景时，触发菜单项的_close方法
                // 通过找到_AnimatedButtonGroup的state来调用
                _hideMenuWithAnimation();
              },
              behavior: HitTestBehavior.translucent,
            ),
          ),
          // 菜单内容
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
                  onHide: _removeOverlay, // 动画完成后移除
                  showAbove: false,
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

  // 带淡出动画的关闭
  void _hideMenuWithAnimation() {
    if (!_isShowing) return;
    _cancelAutoCloseTimer();
    _isShowing = false;
    
    // 通过GlobalKey调用_AnimatedButtonGroupState的_close方法
    _menuKey.currentState?._close();
  }

  // 直接移除overlay（动画完成后调用）
  void _removeOverlay() {
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
    final menuHeight = widget.items.length * 48.0 + 16.0; // 每个按钮约48px + padding
    // PC端使用较小宽度（仅图标），移动端使用较大宽度（图标+文字）
    final menuWidth = kIsWeb ? 50.0 : 120.0;
    
    // 计算可用空间
    final spaceBelow = screenSize.height - (buttonOffset.dy + buttonSize.height);
    final spaceAbove = buttonOffset.dy;
    final spaceRight = screenSize.width - (buttonOffset.dx + buttonSize.width);
    
    double menuTop;
    double? menuLeft;
    double? menuRight;
    bool showAbove = false;
    
    // 子菜单右对齐按钮（确保不超出屏幕右边界）
    if (spaceRight >= menuWidth) {
      // 右侧空间充足，右对齐按钮
      menuLeft = null;
      menuRight = screenSize.width - (buttonOffset.dx + buttonSize.width);
    } else {
      // 右侧空间不足，左对齐到屏幕右边距
      menuLeft = null;
      menuRight = 8; // 距离右边界8px
    }
    
    // 判断向上还是向下弹出
    if (spaceBelow >= menuHeight || spaceBelow > spaceAbove) {
      // 向下弹出
      showAbove = false;
      menuTop = buttonOffset.dy + buttonSize.height + 8;
      // 确保不超出屏幕底部
      if (menuTop + menuHeight > screenSize.height - 8) {
        menuTop = screenSize.height - menuHeight - 8;
      }
    } else {
      // 向上弹出
      showAbove = true;
      menuTop = buttonOffset.dy - menuHeight - 8;
      // 确保不超出屏幕顶部
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
              showAbove: showAbove,
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

class _AnimatedButtonGroup extends StatefulWidget {
  final List<_MenuItem> items;
  final VoidCallback onHide;
  final bool showAbove;
  final VoidCallback? onAnimationComplete; // 动画完成回调
  const _AnimatedButtonGroup({
    super.key,
    required this.items,
    required this.onHide,
    this.showAbove = false,
    this.onAnimationComplete,
  });

  @override
  State<_AnimatedButtonGroup> createState() => _AnimatedButtonGroupState();
}

class _AnimatedButtonGroupState extends State<_AnimatedButtonGroup> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;
  List<AnimationController> _itemControllers = [];
  List<Animation<double>> _itemAnimations = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    
    // 根据弹出方向调整滑动动画
    Offset slideOffset;
    if (widget.showAbove) {
      // 向上弹出：从下往上滑入
      slideOffset = const Offset(0, 0.1);
    } else {
      // 向下弹出：从上往下滑入
      slideOffset = const Offset(0, -0.1);
    }
    
    _slideAnimation = Tween<Offset>(begin: slideOffset, end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic)
    );
    
    // 为每个菜单项创建独立的动画控制器
    for (int i = 0; i < widget.items.length; i++) {
      final itemController = AnimationController(
        duration: const Duration(milliseconds: 250),
        vsync: this,
      );
      final itemAnimation = CurvedAnimation(
        parent: itemController,
        curve: Curves.easeOutCubic,
      );
      _itemControllers.add(itemController);
      _itemAnimations.add(itemAnimation);
      
      // 依次延迟启动动画（每个间隔100ms）
      Future.delayed(Duration(milliseconds: 50 + i * 100), () {
        if (mounted) {
          itemController.forward();
        }
      });
    }
    
    _controller.forward();
  }

  @override
  void dispose() {
    for (var controller in _itemControllers) {
      controller.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> close() async {
    // 先依次关闭每个菜单项（从后往前）
    for (int i = _itemControllers.length - 1; i >= 0; i--) {
      await _itemControllers[i].reverse();
    }
    // 然后反向播放整体动画
    await _controller.reverse();
    if (mounted) {
      widget.onHide();
    }
  }

  Future<void> _close() async {
    await close();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacityAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end, // 右对齐
              children: widget.items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final isLast = index == widget.items.length - 1;
                return AnimatedBuilder(
                  animation: _itemAnimations[index],
                  builder: (context, child) {
                    return Opacity(
                      opacity: _itemAnimations[index].value,
                      child: child,
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end, // 右对齐
                    children: [
                      _buildMenuItemButton(item),
                      if (!isLast) const SizedBox(height: 8),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItemButton(_MenuItem item) {
    return _HoverableMenuItem(
      item: item,
      onClose: _close,
    );
  }
}

// PC端悬停显示文字的菜单项组件
class _HoverableMenuItem extends StatefulWidget {
  final _MenuItem item;
  final Future<void> Function() onClose;
  
  const _HoverableMenuItem({
    required this.item,
    required this.onClose,
  });

  @override
  State<_HoverableMenuItem> createState() => _HoverableMenuItemState();
}

class _HoverableMenuItemState extends State<_HoverableMenuItem> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _animationController;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _opacityAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final buttonColor = isDark 
        ? const Color(0xFF2C2C2E).withOpacity(0.9)
        : CupertinoColors.white.withOpacity(0.9);
    final textColor = isDark ? CupertinoColors.white : CupertinoColors.label;
    
    // 移动端：始终显示图标+文字
    // PC端（Web和Windows）：通过动画控制文字显示和宽度扩展
    Widget buttonChild;
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      // PC端：使用Row布局，图标固定，文字动态显示
      buttonChild = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // 图标（始终显示）
          Icon(
            widget.item.icon,
            size: 16,
            color: textColor,
          ),
          // 文字区域（使用IntrinsicWidth自适应宽度）
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            child: _isHovered
                ? Padding(
                    key: const ValueKey('text'),
                    padding: const EdgeInsets.only(left: 4),
                    child: FadeTransition(
                      opacity: _opacityAnimation,
                      child: Text(
                        widget.item.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('empty')),
          ),
        ],
      );
    } else {
      // 移动端：直接显示图标+文字
      buttonChild = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.item.icon,
            size: 16,
            color: textColor,
          ),
          const SizedBox(width: 8),
          Text(
            widget.item.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ],
      );
    }
    
    Widget buttonWidget;
    if (widget.item.onLongPress != null) {
      buttonWidget = GestureDetector(
        onLongPress: () {
          // 先执行功能，再关闭菜单
          widget.item.onLongPress!();
          // 延迟关闭，让功能先执行
          Future.delayed(const Duration(milliseconds: 50), () {
            widget.onClose();
          });
        },
        onTap: () {
          // 先执行功能，再关闭菜单
          widget.item.onTap();
          // 延迟关闭，让功能先执行
          Future.delayed(const Duration(milliseconds: 50), () {
            widget.onClose();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: kIsWeb
              ? EdgeInsets.symmetric(
                  horizontal: _isHovered ? 16 : 12,
                  vertical: 10,
                )
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: buttonColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: buttonChild,
        ),
      );
    } else {
      buttonWidget = GestureDetector(
        onTap: () {
          // 先执行功能，再关闭菜单
          widget.item.onTap();
          // 延迟关闭，让功能先执行
          Future.delayed(const Duration(milliseconds: 50), () {
            widget.onClose();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: kIsWeb
              ? EdgeInsets.symmetric(
                  horizontal: _isHovered ? 16 : 12,
                  vertical: 10,
                )
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: buttonColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: buttonChild,
        ),
      );
    }
    
    // PC端添加MouseRegion实现悬停效果
    if (kIsWeb) {
      return MouseRegion(
        onEnter: (_) {
          setState(() {
            _isHovered = true;
          });
          _animationController.forward();
        },
        onExit: (_) {
          setState(() {
            _isHovered = false;
          });
          _animationController.reverse();
        },
        child: buttonWidget,
      );
    }
    
    return buttonWidget;
  }
}
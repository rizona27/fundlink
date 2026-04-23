import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../widgets/empty_state.dart';
import '../widgets/adaptive_top_bar.dart';
import '../widgets/gradient_card.dart';
import '../widgets/glass_button.dart';
import '../widgets/toast.dart';
import '../widgets/fund_performance_dialog.dart';
import 'add_holding_view.dart';

class SummaryView extends StatefulWidget {
  const SummaryView({super.key});

  @override
  State<SummaryView> createState() => _SummaryViewState();
}

class _SummaryViewState extends State<SummaryView> with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  late DataManager _dataManager;
  late FundService _fundService;
  late VoidCallback _dataListener;

  String _searchText = '';
  final Set<String> _expandedFundCodes = {};

  SortKey _sortKey = SortKey.none;
  SortOrder _sortOrder = SortOrder.descending;

  int _valuationRefreshIntervalSeconds = 180;
  Timer? _valuationTimer;
  bool _isPageVisible = true;
  DateTime? _lastValuationRefreshTime;

  double _scrollOffset = 0;
  Timer? _scrollThrottleTimer;
  final ScrollController _scrollController = ScrollController(); // 添加滚动控制器

  bool get _hasAnyExpanded => _expandedFundCodes.isNotEmpty;
  bool get _hasData => _dataManager.holdings.isNotEmpty;
  bool get _showValuationRefresh => _sortKey == SortKey.latestNav && _hasData;

  @override
  bool get wantKeepAlive => true;

  static const String _keySortKey = 'summary_sort_key';
  static const String _keySortOrder = 'summary_sort_order';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dataListener = () {
      if (mounted) setState(() {});
    };
    _loadSortState();
    _loadValuationRefreshInterval();
  }

  void _onScrollUpdate(double offset) {
    if (_scrollThrottleTimer != null && _scrollThrottleTimer!.isActive) {
      return;
    }
    _scrollThrottleTimer = Timer(const Duration(milliseconds: 8), () {
      if (mounted && _scrollOffset != offset) {
        setState(() {
          _scrollOffset = offset;
        });
      }
      _scrollThrottleTimer = null;
    });
  }

  Future<void> _loadSortState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sortKeyStr = prefs.getString(_keySortKey);
      final sortOrderStr = prefs.getString(_keySortOrder);
      
      // 如果没有保存的排序状态，使用默认的无排序
      if (sortKeyStr != null) {
        _sortKey = SortKey.values.firstWhere(
              (e) => e.toString() == sortKeyStr,
          orElse: () => SortKey.none,
        );
      } else {
        _sortKey = SortKey.none; // 默认无排序
      }
      
      if (sortOrderStr != null) {
        _sortOrder = SortOrder.values.firstWhere(
              (e) => e.toString() == sortOrderStr,
          orElse: () => SortOrder.descending,
        );
      } else {
        _sortOrder = SortOrder.descending; // 默认排序顺序
      }
    } catch (e) {
      debugPrint('加载排序状态失败: $e');
    }
  }

  Future<void> _saveSortState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySortKey, _sortKey.toString());
      await prefs.setString(_keySortOrder, _sortOrder.toString());
    } catch (e) {
      debugPrint('保存排序状态失败: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _dataManager.removeListener(_dataListener);
    _dataManager.addListener(_dataListener);
    _fundService = FundService(_dataManager);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopValuationTimer();
    _dataManager.removeListener(_dataListener);
    _scrollThrottleTimer?.cancel();
    _scrollController.dispose(); // 释放滚动控制器
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isPageVisible = true;
      _restartValuationTimer();
      if (_dataManager.isValuationRefreshInProgress) {
        setState(() {});
      } else {
        _checkAndRefreshStaleValuation();
      }
    } else if (state == AppLifecycleState.paused) {
      _isPageVisible = false;
      _stopValuationTimer();
    }
  }

  void _startValuationTimer() {
    _stopValuationTimer();
    if (!_showValuationRefresh || !_isPageVisible || _dataManager.isValuationRefreshing) return;

    _valuationTimer = Timer.periodic(
      Duration(seconds: _valuationRefreshIntervalSeconds),
          (timer) {
        if (_isPageVisible && mounted && _showValuationRefresh && !_dataManager.isValuationRefreshing && !_dataManager.isValuationRefreshInProgress) {
          _onValuationRefresh();
        }
      },
    );
  }

  void _stopValuationTimer() {
    _valuationTimer?.cancel();
    _valuationTimer = null;
  }

  void _restartValuationTimer() {
    if (_showValuationRefresh && _isPageVisible && !_dataManager.isValuationRefreshing) {
      _startValuationTimer();
    }
  }

  Future<void> _loadValuationRefreshInterval() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seconds = prefs.getInt('valuationRefreshInterval');
      if (seconds != null && [60, 180, 300].contains(seconds)) {
        _valuationRefreshIntervalSeconds = seconds;
      } else {
        _valuationRefreshIntervalSeconds = 180;
      }
      _restartValuationTimer();
    } catch (e) {
      _valuationRefreshIntervalSeconds = 180;
      _restartValuationTimer();
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveValuationRefreshInterval(int seconds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('valuationRefreshInterval', seconds);
    } catch (e) {
      debugPrint('保存刷新间隔失败: $e');
    }
  }

  void _onValuationRefreshIntervalChanged() async {
    setState(() {
      if (_valuationRefreshIntervalSeconds == 60) {
        _valuationRefreshIntervalSeconds = 180;
      } else if (_valuationRefreshIntervalSeconds == 180) {
        _valuationRefreshIntervalSeconds = 300;
      } else {
        _valuationRefreshIntervalSeconds = 60;
      }
    });
    await _saveValuationRefreshInterval(_valuationRefreshIntervalSeconds);
    _restartValuationTimer();
    String intervalText = _valuationRefreshIntervalSeconds == 60 ? '1分钟'
        : (_valuationRefreshIntervalSeconds == 180 ? '3分钟' : '5分钟');
    if (mounted) {
      context.showToast('估值刷新间隔已改为 $intervalText', duration: const Duration(seconds: 2));
    }
  }

  Future<Map<String, dynamic>?> _fetchSingleValuation(String code) async {
    try {
      final valuation = await _fundService.fetchRealtimeValuation(code);
      if (valuation != null && valuation['gsz'] != null && valuation['gsz'] > 0) {
        return {
          'gsz': valuation['gsz'],
          'gszzl': valuation['gszzl'] ?? 0.0,
          'gztime': valuation['gztime'] ?? '',
        };
      } else {
        debugPrint('⚠️ 基金 $code 估值数据无效: $valuation');
        await _dataManager.addLog('基金 $code 估值获取失败: 数据无效', type: LogType.error);
        return null;
      }
    } catch (e) {
      debugPrint('❌ 基金 $code 估值获取异常: $e');
      await _dataManager.addLog('基金 $code 估值获取异常: $e', type: LogType.error);
      return null;
    }
  }

  Future<void> _checkAndRefreshStaleValuation() async {
    if (!_showValuationRefresh || _dataManager.isValuationRefreshInProgress) return;
    if (_lastValuationRefreshTime != null &&
        DateTime.now().difference(_lastValuationRefreshTime!).inSeconds < 5) {
      return;
    }
    bool needRefresh = false;
    for (var holding in _dataManager.holdings) {
      final cached = _dataManager.getValuation(holding.fundCode);
      if (cached == null) {
        needRefresh = true;
        break;
      }
    }
    if (needRefresh) {
      await _onValuationRefresh(silent: true);
    }
  }

  Future<void> _onValuationRefresh({bool silent = false}) async {
    if (_dataManager.isValuationRefreshInProgress) {
      if (!silent && mounted) {
        context.showToast('估值刷新正在进行中...');
      }
      return;
    }

    _lastValuationRefreshTime = DateTime.now();
    _stopValuationTimer();

    try {
      await _dataManager.refreshAllValuations(_fundService, silent: silent);
      if (mounted && !silent) {
        context.showToast('估值刷新完成');
      }
    } catch (e) {
      if (mounted && !silent) {
        context.showToast('估值刷新失败: $e');
      }
    } finally {
      if (mounted) {
        _restartValuationTimer();
      }
    }
  }

  Future<void> _onFundRefresh() async {
    if (!mounted) return;
    try {
      await _dataManager.refreshAllHoldingsForce(_fundService, null);
      if (mounted) {
        setState(() {});
        context.showToast('基金数据刷新完成');
        await _dataManager.addLog('手动刷新基金数据完成', type: LogType.success);
      }
    } catch (e) {
      if (mounted) {
        context.showToast('基金数据刷新失败: $e');
        await _dataManager.addLog('手动刷新基金数据失败: $e', type: LogType.error);
      }
    }
  }

  Future<void> _onFundLongPressRefresh() async {
    if (!mounted) return;
    try {
      await _dataManager.refreshAllHoldingsForce(_fundService, null);
      if (mounted) {
        setState(() {});
        context.showToast('强制刷新完成');
        await _dataManager.addLog('强制刷新所有基金数据完成', type: LogType.success);
      }
    } catch (e) {
      if (mounted) {
        context.showToast('强制刷新失败: $e');
        await _dataManager.addLog('强制刷新所有基金数据失败: $e', type: LogType.error);
      }
    }
  }

  String _getValuationDisplayText(FundHolding holding) {
    final cache = _dataManager.getValuation(holding.fundCode);
    if (cache != null) {
      final gsz = cache['gsz'] as double;
      final gszzl = cache['gszzl'] as double;
      return '${gszzl >= 0 ? '+' : ''}${gszzl.toStringAsFixed(2)}% (${gsz.toStringAsFixed(4)})';
    }
    return '--% (--)';
  }

  Color _getChangeColor(double? value) {
    if (value == null) return CupertinoColors.systemGrey;
    if (value > 0) return CupertinoColors.systemRed;
    if (value < 0) return CupertinoColors.systemGreen;
    return CupertinoColors.systemGrey;
  }

  Map<String, List<FundHolding>> get _filteredGroupedFunds {
    final allHoldings = _dataManager.holdings;
    if (_searchText.isEmpty) {
      return _groupByFundCode(allHoldings);
    }
    final filtered = allHoldings.where((holding) {
      return holding.fundCode.contains(_searchText) ||
          holding.fundName.contains(_searchText) ||
          holding.clientName.contains(_searchText);
    }).toList();
    return _groupByFundCode(filtered);
  }

  Map<String, List<FundHolding>> _groupByFundCode(List<FundHolding> holdings) {
    final map = <String, List<FundHolding>>{};
    for (final holding in holdings) {
      map.putIfAbsent(holding.fundCode, () => []).add(holding);
    }
    return map;
  }

  List<String> get _sortedFundCodes {
    final codes = _filteredGroupedFunds.keys.toList();
    if (_sortKey == SortKey.none) {
      codes.sort();
      return codes;
    }
    codes.sort((a, b) {
      final fundsA = _filteredGroupedFunds[a]!;
      final fundsB = _filteredGroupedFunds[b]!;

      double? valueA, valueB;
      if (_sortKey == SortKey.latestNav) {
        final cacheA = _dataManager.getValuation(a);
        final cacheB = _dataManager.getValuation(b);
        valueA = cacheA != null ? cacheA['gszzl'] as double : null;
        valueB = cacheB != null ? cacheB['gszzl'] as double : null;
      } else {
        final firstA = fundsA.first;
        final firstB = fundsB.first;
        valueA = _sortKey.getValue(firstA);
        valueB = _sortKey.getValue(firstB);
      }

      if (valueA == null && valueB == null) return a.compareTo(b);
      if (valueA == null) return 1;
      if (valueB == null) return -1;
      if (_sortOrder == SortOrder.ascending) {
        return valueA.compareTo(valueB);
      } else {
        return valueB.compareTo(valueA);
      }
    });
    return codes;
  }

  void _toggleExpandAll() {
    if (!_hasData) return;
    setState(() {
      if (_hasAnyExpanded) {
        _expandedFundCodes.clear();
      } else {
        _expandedFundCodes.addAll(_sortedFundCodes);
      }
    });
  }

  void _toggleExpand(String fundCode) {
    setState(() {
      if (_expandedFundCodes.contains(fundCode)) {
        _expandedFundCodes.remove(fundCode);
      } else {
        _expandedFundCodes.add(fundCode);
        
        // 只有当展开的是最后一个卡片时，才滚动到底部
        final sortedCodes = _sortedFundCodes;
        if (sortedCodes.isNotEmpty && fundCode == sortedCodes.last) {
          Future.delayed(const Duration(milliseconds: 100), () {
            _scrollToBottom();
          });
        }
      }
    });
  }

  // 滚动到底部
  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    
    Future.delayed(const Duration(milliseconds: 400), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  List<Color> _getGradientForFundCode(String fundCode) {
    int hash = 0;
    for (int i = 0; i < fundCode.length; i++) {
      hash = (hash << 5) - hash + fundCode.codeUnitAt(i);
    }
    hash = hash.abs();
    final softColors = [
      const Color(0xFFA8C4E0), const Color(0xFFB8D0C4), const Color(0xFFD4C4A8),
      const Color(0xFFE0B8C4), const Color(0xFFC4B8E0), const Color(0xFFA8D4D4),
      const Color(0xFFE0C8A8), const Color(0xFFC8D4A8), const Color(0xFFD4A8C4),
      const Color(0xFFA8D0E0), const Color(0xFFE0C0B0), const Color(0xFFB0C8E0),
      const Color(0xFFD0B8C8), const Color(0xFFC0D4B0), const Color(0xFFE0D0B0),
    ];
    final mainColor = softColors[hash % softColors.length];
    return [mainColor, mainColor.withOpacity(0.3)];
  }

  Color _colorForHoldingCount(int count) {
    if (count == 1) return const Color(0xFFD4A84B);
    if (count <= 3) return const Color(0xFFD4844B);
    return const Color(0xFFD46B6B);
  }

  double? _calculateHoldingReturn(FundHolding holding) {
    if (holding.totalCost <= 0) return null;
    final profit = _dataManager.calculateProfit(holding);
    return (profit.absolute / holding.totalCost) * 100;
  }

  Color _getReturnColor(double? value) {
    if (value == null) return CupertinoColors.systemGrey;
    if (value > 0) return CupertinoColors.systemRed;
    if (value < 0) return CupertinoColors.systemGreen;
    return CupertinoColors.systemGrey;
  }

  Widget? _buildHoldersListInline(List<FundHolding> holdings, bool isDarkMode) {
    if (!_dataManager.showHoldersOnSummaryCard) return null;

    final sorted = List<FundHolding>.from(holdings);
    sorted.sort((a, b) {
      final retA = _calculateHoldingReturn(a) ?? -double.infinity;
      final retB = _calculateHoldingReturn(b) ?? -double.infinity;
      if (_sortOrder == SortOrder.ascending) {
        return retA.compareTo(retB);
      } else {
        return retB.compareTo(retA);
      }
    });

    final children = <InlineSpan>[];
    for (int i = 0; i < sorted.length; i++) {
      final holding = sorted[i];
      final name = _dataManager.obscuredName(holding.clientName);
      final ret = _calculateHoldingReturn(holding);
      final retStr = ret != null ? '${ret >= 0 ? '+' : ''}${ret.toStringAsFixed(2)}%' : '/';
      final retColor = _getReturnColor(ret);

      children.add(TextSpan(
        text: name,
        style: TextStyle(
          color: isDarkMode ? CupertinoColors.white : CupertinoColors.black,
          fontSize: 13,
          height: 1.2,
        ),
      ));
      children.add(TextSpan(
        text: '($retStr)',
        style: TextStyle(color: retColor, fontSize: 12, height: 1.2),
      ));
      if (i < sorted.length - 1) {
        children.add(const TextSpan(text: '、'));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: RichText(
        text: TextSpan(children: children),
        strutStyle: const StrutStyle(height: 1.2),
      ),
    );
  }

  Widget _buildExpandedContent(FundHolding firstHolding, List<FundHolding> holdings, bool isDarkMode) {
    final bgColor = isDarkMode ? Colors.black.withOpacity(0.95) : CupertinoColors.white;
    final holdersList = _buildHoldersListInline(holdings, isDarkMode);

    return GestureDetector(
      onTap: () => _showPerformanceDialog(
        firstHolding.fundCode,
        firstHolding.fundName,
        holding: firstHolding,
      ),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 业绩周期展示
            Row(
              children: [
                _buildReturnItem('近1月', firstHolding.navReturn1m),
                const SizedBox(width: 16),
                _buildReturnItem('近3月', firstHolding.navReturn3m),
                const SizedBox(width: 16),
                _buildReturnItem('近6月', firstHolding.navReturn6m),
                const SizedBox(width: 16),
                _buildReturnItem('近1年', firstHolding.navReturn1y),
              ],
            ),
            
            if (holdersList != null) ...[
              const Divider(height: 24),
              holdersList,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReturnItem(String label, double? value) {
    final textColor = _getReturnColor(value);
    final displayValue = value != null
        ? '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%'
        : '--';
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: CupertinoColors.systemGrey, height: 1.2),
          ),
          const SizedBox(height: 4),
          Text(
            displayValue,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  void _showSortToast() {
    String sortType = _sortKey.displayName;
    String orderText = _sortOrder == SortOrder.ascending ? '升序' : '降序';
    context.showToast('${sortType}${_sortKey == SortKey.none ? '' : ' $orderText'}');
  }

  void _showPerformanceDialog(String fundCode, String fundName, {FundHolding? holding}) {
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => FundPerformanceDialog(
        fundCode: fundCode,
        fundName: fundName,
        dataManager: _dataManager,
        holding: holding,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final groups = _filteredGroupedFunds;
    final sortedCodes = _sortedFundCodes;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final hasData = _hasData;
    final showHolderCount = !_dataManager.isPrivacyMode;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const bottomNavBarHeight = 56.0;
    final totalBottomPadding = bottomPadding + bottomNavBarHeight + 20;

    final enableButtons = hasData;

    return Container(
      color: backgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            AdaptiveTopBar(
              scrollOffset: _scrollOffset,
              showBack: false,
              showRefresh: true,
              showExpandCollapse: true,
              showSearch: true,
              showReset: false,
              showFilter: false,
              showSort: true,
              isAllExpanded: _hasAnyExpanded,
              searchText: _searchText,
              sortKey: _sortKey,
              sortOrder: _sortOrder,
              sortCycleType: SortCycleType.fundReturns,
              onSortKeyChanged: enableButtons
                  ? (key) async {
                setState(() => _sortKey = key);
                await _saveSortState();
                _showSortToast();
              }
                  : null,
              onSortOrderChanged: enableButtons
                  ? (order) async {
                setState(() => _sortOrder = order);
                await _saveSortState();
                _showSortToast();
              }
                  : null,
              dataManager: _dataManager,
              fundService: _fundService,
              onRefresh: _onFundRefresh,
              onLongPressRefresh: _onFundLongPressRefresh,
              showValuationRefresh: _showValuationRefresh,
              valuationRefreshIntervalSeconds: _valuationRefreshIntervalSeconds,
              onValuationRefresh: _onValuationRefresh,
              onValuationRefreshIntervalChanged: _onValuationRefreshIntervalChanged,
              valuationUpdateTime: _dataManager.lastValuationUpdateTime,
              isValuationRefreshing: _dataManager.isValuationRefreshing,
              valuationRefreshProgress: _dataManager.valuationRefreshProgress,
              onToggleExpandAll: enableButtons ? _toggleExpandAll : null,
              onSearchChanged: enableButtons
                  ? (text) => setState(() => _searchText = text)
                  : null,
              onSearchClear: enableButtons
                  ? () => setState(() => _searchText = '')
                  : null,
              backgroundColor: Colors.transparent,
              iconColor: CupertinoTheme.of(context).primaryColor,
              iconSize: 24,
              buttonSpacing: 12,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              useMenuStyle: true,
            ),
            Expanded(
              child: !hasData
                  ? EmptyState(
                icon: CupertinoIcons.chart_bar,
                title: '点击开始添加吧～',
                message: '',
                titleFontWeight: FontWeight.normal,
                titleFontSize: 18,
                customButton: GlassButton(
                  label: 'Go!',
                  onPressed: () {
                    Navigator.of(context).push(
                      CupertinoPageRoute(builder: (_) => const AddHoldingView()),
                    );
                  },
                  isPrimary: false,
                  width: null,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                ),
              )
                  : AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification) {
                      _onScrollUpdate(notification.metrics.pixels);
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scrollController, // 添加滚动控制器
                    key: ValueKey('list_${_sortKey}_${_sortOrder}_${_searchText}'),
                    padding: EdgeInsets.only(
                      left: 12,
                      right: 12,
                      top: 8,
                      bottom: totalBottomPadding,
                    ),
                    itemCount: sortedCodes.length,
                    itemBuilder: (context, index) {
                      final fundCode = sortedCodes[index];
                      final holdings = groups[fundCode]!;
                      final first = holdings.first;
                      final isExpanded = _expandedFundCodes.contains(fundCode);
                      final gradient = _getGradientForFundCode(fundCode);
                      final holderCount = holdings.length;

                      Widget? trailing;
                      if (_sortKey != SortKey.none) {
                        if (_sortKey == SortKey.latestNav) {
                          final cache = _dataManager.getValuation(fundCode);
                          if (cache != null) {
                            final gsz = cache['gsz'] as double;
                            final gszzl = cache['gszzl'] as double;
                            final changeColor = _getChangeColor(gszzl);

                            trailing = Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${gszzl >= 0 ? '+' : ''}${gszzl.toStringAsFixed(2)}%',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    height: 1.2,
                                    color: changeColor,
                                  ),
                                ),
                                Text(
                                  ' (${gsz.toStringAsFixed(4)})',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.normal,
                                    height: 1.2,
                                    color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                  ),
                                ),
                              ],
                            );
                          } else {
                            trailing = Text(
                              '--% (--)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                              ),
                            );
                          }
                        } else {
                          final sortValue = _sortKey.getValue(first);
                          final valueStr = sortValue != null
                              ? '${sortValue >= 0 ? '+' : ''}${sortValue.toStringAsFixed(2)}%'
                              : '--';
                          final valueColor = _getReturnColor(sortValue);
                          trailing = Text(
                            valueStr,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              color: valueColor,
                            ),
                          );
                        }
                      } else if (showHolderCount) {
                        trailing = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '持有人数: ',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.2,
                                color: isDark ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
                              ),
                            ),
                            Text(
                              '$holderCount',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                fontStyle: FontStyle.italic,
                                height: 1.2,
                                color: _colorForHoldingCount(holderCount),
                              ),
                            ),
                            Text(
                              '人',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.2,
                                color: isDark ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
                              ),
                            ),
                          ],
                        );
                      }

                      return Column(
                        key: ValueKey('fund_$fundCode'), // 添加key用于滚动定位
                        children: [
                          GradientCard(
                            title: first.fundName,
                            clientId: fundCode,
                            gradient: gradient,
                            isExpanded: isExpanded,
                            onTap: () => _toggleExpand(fundCode),
                            isDarkMode: isDark,
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                            trailing: trailing,
                            maxTitleLength: 6,
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            child: isExpanded
                                ? ClipRect(
                              child: _buildExpandedContent(first, holdings, isDark),
                            )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
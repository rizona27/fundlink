import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../mixins/scroll_to_top_mixin.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../models/net_worth_point.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../services/ui_state_service.dart';
import '../utils/animation_config.dart';
import '../widgets/adaptive_top_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/fund_performance_dialog.dart';
import '../widgets/glass_button.dart';
import '../widgets/gradient_card.dart';
import '../widgets/toast.dart';
import 'add_holding_view.dart';
import 'fund_detail_view.dart';

class SummaryView extends StatefulWidget {
  const SummaryView({super.key});

  @override
  State<SummaryView> createState() => _SummaryViewState();
}

class _SummaryViewState extends State<SummaryView> with WidgetsBindingObserver, AutomaticKeepAliveClientMixin, ScrollToTopMixin, SingleTickerProviderStateMixin {
  late DataManager _dataManager;
  late FundService _fundService;
  late VoidCallback _dataListener;
  int _lastSeenHoldingsVersion = -1;

  String _searchText = '';
  final Set<String> _expandedFundCodes = {};

  SortKey _sortKey = SortKey.none;
  SortOrder _sortOrder = SortOrder.descending;

  // Gentle sort animation — position-swap for dimension change,
  // staggered slide-up for order toggle
  late final AnimationController _sortAnimCtrl;
  Map<String, int>? _oldPositions;
  bool _isOrderToggle = false;

  int _valuationRefreshIntervalSeconds = 180;
  Timer? _valuationTimer;
  Timer? _marketStatusTimer;
  bool _isPageVisible = true;
  bool _lastMarketOpenState = false; // Track transitions to avoid unnecessary setState

  bool get _isMarketOpen => AppConstants.isInTradingHours();
  
  bool _shouldPauseAutoRefresh() => !AppConstants.isInTradingHours();

  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier(0.0);
  final ScrollController _scrollController = ScrollController();

  bool get _hasAnyExpanded => _expandedFundCodes.isNotEmpty;
  bool get _hasData => _dataManager.holdings.isNotEmpty;
  bool get _showValuationRefresh => _sortKey == SortKey.latestNav && _hasData;

  @override
  ScrollController get scrollController => _scrollController;

  @override
  bool get wantKeepAlive => true;

  static const String _keySortKey = AppConstants.keySortKey;
  static const String _keySortOrder = AppConstants.keySortOrder;
  static const String _keyExpandedFunds = AppConstants.keyExpandedFunds; 

  @override
  void initState() {
    super.initState();
    _sortAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _sortAnimCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) _oldPositions = null;
    });
    WidgetsBinding.instance.addObserver(this);
    _dataListener = () {
      if (mounted) {
        final currentVersion = _dataManager.holdingsVersion;
        if (currentVersion != _lastSeenHoldingsVersion) {
          _lastSeenHoldingsVersion = currentVersion;
          setState(() {
            _cachedSortedFundCodes = null;
          });
        } else {
          // Settings/valuation changes — no need to invalidate sort cache
          setState(() {});
        }
      }
    };
    _scrollController.addListener(() {
      if (mounted) {
        _onScrollUpdate(_scrollController.offset);
      }
    });
    _loadSortState();
    _loadValuationRefreshInterval();
    _startMarketStatusTimer();

    
    Future.microtask(() {
      if (mounted) {
        _loadNavTrendsForNavOnlyFunds();
        setState(() {});
      }
    });
  }

  void _onScrollUpdate(double offset) {
    _scrollOffsetNotifier.value = offset < 1.0 ? 0.0 : offset;
  }

  Future<void> _loadSortState() async {
    try {
      final uiState = UIStateService();
      final sortKeyStr = await uiState.getString(_keySortKey);
      final sortOrderStr = await uiState.getString(_keySortOrder);
      
      if (sortKeyStr != null) {
        _sortKey = SortKey.values.firstWhere(
              (e) => e.toString() == sortKeyStr,
          orElse: () => SortKey.none,
        );
      } else {
        _sortKey = SortKey.none; 
      }
      
      if (sortOrderStr != null) {
        _sortOrder = SortOrder.values.firstWhere(
              (e) => e.toString() == sortOrderStr,
          orElse: () => SortOrder.descending,
        );
      } else {
        _sortOrder = SortOrder.descending;
      }
    } catch (e) {
    }
  }

  Future<void> _saveSortState() async {
    try {
      final uiState = UIStateService();
      await uiState.saveString(_keySortKey, _sortKey.toString());
      await uiState.saveString(_keySortOrder, _sortOrder.toString());
    } catch (e) {
    }
  }
  
  void _captureOldPositions() {
    _oldPositions = {};
    final codes = _sortedFundCodes;
    for (int i = 0; i < codes.length; i++) {
      _oldPositions![codes[i]] = i;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _dataManager.removeListener(_dataListener);
    _dataManager.addListener(_dataListener);
    _fundService = FundService(_dataManager);
    
    _autoConfirmPendingTransactions();

    final route = ModalRoute.of(context);
    
    Future.microtask(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _sortAnimCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _cancelAllTimers();
    _scrollOffsetNotifier.dispose();
    _dataManager.removeListener(_dataListener);
    _scrollController.dispose();
    super.dispose();
  }

  void _cancelAllTimers() {
    _stopValuationTimer();
    _stopMarketStatusTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    
    if (state == AppLifecycleState.resumed) {
      _isPageVisible = true;
      _startMarketStatusTimer();
      _restartValuationTimer();
      if (_dataManager.isValuationRefreshInProgress) {
        setState(() {});
      }
      // Don't force-refresh on resume — let the countdown timer trigger it.
    } else if (state == AppLifecycleState.paused) {
      _isPageVisible = false;
      _stopValuationTimer();
      _stopMarketStatusTimer(); 
    }
  }

  void _startValuationTimer() {
    _stopValuationTimer();
    
    if (_shouldPauseAutoRefresh()) {
      return;
    }
    
    if (!_showValuationRefresh || !_isPageVisible || _dataManager.isValuationRefreshing) {
      return;
    }

    _valuationTimer = Timer.periodic(
      Duration(seconds: _valuationRefreshIntervalSeconds),
          (timer) {
        if (_shouldPauseAutoRefresh()) {
          _stopValuationTimer();
          return;
        }
        
        final now = DateTime.now();
        final shouldRefresh = _isPageVisible && mounted && _showValuationRefresh && 
            !_dataManager.isValuationRefreshing && 
            !_dataManager.isValuationRefreshInProgress;
        
        
        if (shouldRefresh) {
          _onValuationRefresh();
        } else {
        }
      },
    );
  }

  void _stopValuationTimer() {
    _valuationTimer?.cancel();
    _valuationTimer = null;
  }

  void _restartValuationTimer() {
    if (_shouldPauseAutoRefresh()) {
      return;
    }
    
    if (_showValuationRefresh && _isPageVisible && !_dataManager.isValuationRefreshing) {
      _startValuationTimer();
    }
  }
  
  void _startMarketStatusTimer() {
    _stopMarketStatusTimer();
    _lastMarketOpenState = !_shouldPauseAutoRefresh();
    _marketStatusTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!_isPageVisible || !mounted) return;

      final shouldPause = _shouldPauseAutoRefresh();

      if (_showValuationRefresh && _valuationTimer == null && !shouldPause) {
        _restartValuationTimer();
      }
      else if (shouldPause && _valuationTimer != null) {
        _stopValuationTimer();
      }

      // Only rebuild when market open/close state actually transitions
      final isOpen = !shouldPause;
      if (isOpen != _lastMarketOpenState) {
        _lastMarketOpenState = isOpen;
        setState(() {});
      }
    });
  }
  
  void _stopMarketStatusTimer() {
    _marketStatusTimer?.cancel();
    _marketStatusTimer = null;
  }

  Future<void> _loadValuationRefreshInterval() async {
    try {
      final uiState = UIStateService();
      final seconds = await uiState.getInt('valuationRefreshInterval');
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
  
  Future<void> _autoConfirmPendingTransactions() async {
    try {
      final pendingTxs = _dataManager.getPendingTransactions();
      final pendingCount = pendingTxs.length;
      
      if (pendingCount == 0) {
        return;
      }
      
      for (final tx in pendingTxs) {
      }
      
      final confirmedCount = await _dataManager.autoConfirmPendingTransactions(_fundService);
      
      if (confirmedCount > 0 && mounted) {
        context.showToast('已自动确认 $confirmedCount 笔交易');
      }
    } catch (e) {
    }
  }

  Future<void> _saveValuationRefreshInterval(int seconds) async {
    try {
      final uiState = UIStateService();
      await uiState.saveInt('valuationRefreshInterval', seconds);
    } catch (e) {
    }
  }

  void _onValuationRefreshIntervalChanged(int seconds) async {
    if (mounted) {
      setState(() {
        _valuationRefreshIntervalSeconds = seconds;
      });
    }
    await _saveValuationRefreshInterval(_valuationRefreshIntervalSeconds);
    _restartValuationTimer();
    String intervalText = seconds == 60 ? '1分钟'
        : (seconds == 180 ? '3分钟' : '5分钟');
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
        await _dataManager.addLog('基金 $code 估值获取失败: 数据无效', type: LogType.error);
        return null;
      }
    } catch (e) {
      await _dataManager.addLog('基金 $code 估值获取异常: $e', type: LogType.error);
      return null;
    }
  }

  Future<void> _onValuationRefresh({bool silent = false}) async {
    if (_dataManager.isValuationRefreshInProgress) {
      if (!silent && mounted) {
        context.showToast('估值刷新正在进行中...');
      }
      return;
    }

    if (!silent && mounted && !_isMarketOpen) {
      context.showToast('当前为非交易时间，净值更新后刷新');
    }

    _stopValuationTimer();

    try {
      await _dataManager.refreshAllValuations(_fundService, silent: silent);
      // After valuation refresh, also refresh NAV trends for funds without
      // valuation API so blue 「净」labels have fresh data.
      await _loadNavTrendsForNavOnlyFunds();

      // After market close, also refresh fund-holding NAV data so
      // _isNavPublishedForHolding() can detect just-published NAVs and
      // switch from grey 「估」to green 「净」.
      if (AppConstants.isAfterMarketClose()) {
        await _dataManager.refreshAllHoldings(_fundService, null,
            forceRefresh: false, navToleranceTradingDays: 0);
      }

      if (mounted && _sortKey == SortKey.latestNav) {
        setState(() {
          _cachedSortedFundCodes = null;
        });
      }
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
      await _dataManager.refreshAllHoldings(_fundService, null);
      // After refreshing NAV data, also refresh valuations so the display
      // can immediately switch from grey 「估」to green 「净」when the NAV
      // has been published.
      if (!_dataManager.isValuationRefreshInProgress) {
        await _dataManager.refreshAllValuations(_fundService, silent: true);
        await _loadNavTrendsForNavOnlyFunds();
      }
      if (mounted) {
        setState(() {
          _cachedSortedFundCodes = null;
        });
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
      await _dataManager.refreshAllHoldings(_fundService, null, forceRefresh: true);
      // After force-refreshing NAV data, also refresh valuations so both
      // data sources are current and the green 「净」detection works.
      if (!_dataManager.isValuationRefreshInProgress) {
        await _dataManager.refreshAllValuations(_fundService, silent: true);
        await _loadNavTrendsForNavOnlyFunds();
      }
      if (mounted) {
        setState(() {
          _cachedSortedFundCodes = null;
        });
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
      final gsz = (cache['gsz'] as num?)?.toDouble();
      final gszzl = (cache['gszzl'] as num?)?.toDouble();
      if (gsz == null || gszzl == null) return '--% (--)';
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

  /// Builds the trailing widget for the "查估值" sort mode.
  ///
  /// Three labels:
  ///   灰「估」— has valuation API, showing intraday estimate %.
  ///   绿「净」— has valuation API, after hours AND jzrq indicates
  ///            the latest closed trading day's NAV has been published.
  ///   蓝「净」— no valuation API (weekly / closed-period funds), showing
  ///            growth % from the last two NAV trend points.
  Widget? _buildValuationTrailing(String fundCode, FundHolding holding, bool isDark) {
    final cache = _dataManager.getValuation(fundCode);
    final hasRecord = _dataManager.hasValuationRecord(fundCode);

    // Only funds that have NEVER had valuation data go to blue 「净」.
    if (cache == null && !hasRecord) {
      return _buildNavOnlyTrailing(holding, isDark);
    }

    // Fund has (or had) valuation data but the cache is currently empty
    // (TTL expired, or not yet refreshed).  Show grey 「估」placeholder
    // rather than incorrectly routing to blue 「净」.
    final gszzl = cache?['gszzl'] as double?;
    final jzrq = cache?['jzrq'] as String?;

    if (gszzl == null) {
      // Valuation cache stale.  If after close and NAV is published,
      // show green 净; otherwise grey 估.
      if (AppConstants.isAfterMarketClose() && _isNavPublishedForHolding(holding)) {
        final navChange = _getGreenNavChangeFromHolding(fundCode, holding);
        if (navChange != null) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildBadge('净', const Color(0xFF34C759), isDark),
              const SizedBox(width: 4),
              Text(
                '${navChange >= 0 ? '+' : ''}${navChange.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                  color: _getChangeColor(navChange),
                ),
              ),
            ],
          );
        }
      }
      return _buildStaleValuationTrailing(holding, isDark);
    }

    final bool isAfterClose = AppConstants.isAfterMarketClose();

    // Green 「净」when: after the market is fully closed for the day (after
    // 15:00) AND the fund's official NAV has been published for the latest
    // trading day.  During the midday break (11:30–13:00) valuation estimates
    // are still live from the API, so we stay on grey 「估」.
    //
    // We deliberately ignore the valuation API's jzrq here — it may not
    // update after hours even when the NAV has been published.
    // holding.navDate (from pingzhongdata.js) is the authoritative source.
    final bool navPublished = isAfterClose && _isNavPublishedForHolding(holding);

    final double changeValue;
    final Color badgeColor;
    final String badgeLabel;

    if (navPublished) {
      // Green 净: the fund's official NAV has been published today.
      // Use holding.currentNav (from fund info API, same source as the
      // fund card) divided by yesterday's NAV from the trend cache to
      // compute the true daily change.  Fall back to gszzl only when
      // the trend cache is unavailable.
      final navChange = _getGreenNavChangeFromHolding(fundCode, holding);
      changeValue = navChange ?? gszzl;
      badgeColor = const Color(0xFF34C759);
      badgeLabel = '净';
    } else {
      changeValue = gszzl;
      badgeColor = CupertinoColors.systemGrey;
      badgeLabel = '估';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBadge(badgeLabel, badgeColor, isDark),
        const SizedBox(width: 4),
        Text(
          '${changeValue >= 0 ? '+' : ''}${changeValue.toStringAsFixed(2)}%',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            height: 1.2,
            color: _getChangeColor(changeValue),
          ),
        ),
      ],
    );
  }

  /// Returns true when today's NAV has actually been published.
  ///
  /// On a trading day after ~20:00 (fund companies typically publish by then):
  ///   → true only when holding.navDate == today
  /// On a weekend:
  ///   → true only when holding.navDate == Friday
  /// Before 20:00 on a trading day:
  ///   → always false (today's NAV hasn't been published yet, even though
  ///     yesterday's NAV exists — showing yesterday as green 净 is misleading
  ///     because the user expects green to mean "today's NAV is out")
  bool _isNavPublishedForHolding(FundHolding holding) {
    final now = DateTime.now();
    final navDay = DateTime(holding.navDate.year, holding.navDate.month, holding.navDate.day);
    final today = DateTime(now.year, now.month, now.day);
    final weekday = now.weekday;
    final hour = now.hour;

    // After 20:00 on a trading day: expect today's NAV
    if (weekday <= DateTime.friday && hour >= 20) {
      return !navDay.isBefore(today);
    }

    // Weekend: expect Friday's NAV
    if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
      final friday = today.subtract(Duration(days: weekday - DateTime.friday));
      return !navDay.isBefore(friday);
    }

    // Before 20:00 on a trading day (or Monday before 20:00):
    // today's NAV hasn't been published yet — stay grey 估.
    return false;
  }


  /// Builds a translucent capsule badge for valuation/net-value labels.
  Widget _buildBadge(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          height: 1.2,
          letterSpacing: 0.2,
          color: color,
        ),
      ),
    );
  }

  /// Returns the NAV trend growth % for [fundCode] from the last two NAV
  /// points in the in-memory cache. Returns null if trend data is unavailable
  /// or insufficient.
  double? _getNavTrendChange(String fundCode) {
    final points = _fundService.getNavFromCacheSync(fundCode);
    if (points == null || points.length < 2) return null;
    final newest = points.last.nav;
    final previous = points[points.length - 2].nav;
    if (previous <= 0) return null;
    return (newest - previous) / previous * 100;
  }

  /// Computes the green-「净」NAV daily change using [holding.currentNav] as
  /// today's published NAV and the last point in the trend cache as the prior
  /// trading day's NAV.  This matches the data shown in the fund card and
  /// historical NAV views (both sourced from pingzhongdata.js via fetchFundInfo),
  /// NOT the valuation API.
  double? _getGreenNavChangeFromHolding(String fundCode, FundHolding holding) {
    final todayNav = holding.currentNav;
    if (todayNav <= 0) return null;

    // Get yesterday's NAV from the trend cache.
    // The last point in the trend cache is typically yesterday's (or today's
    // if recently updated).  We need the point before today's NAV date.
    final points = _fundService.getNavFromCacheSync(fundCode);
    if (points == null || points.isEmpty) return null;

    // Find the data point whose date matches holding.navDate (today).
    // Its previous point is yesterday's NAV.
    final navDay = DateTime(holding.navDate.year, holding.navDate.month, holding.navDate.day);
    for (int i = points.length - 1; i >= 0; i--) {
      final pDay = DateTime(points[i].date.year, points[i].date.month, points[i].date.day);
      if (pDay.isAtSameMomentAs(navDay) && i > 0) {
        final prevNav = points[i - 1].nav;
        if (prevNav > 0) return (todayNav - prevNav) / prevNav * 100;
        break;
      }
    }

    // Fallback: today's point not yet in trend cache — use last point as
    // previous day and holding.currentNav as today.
    final prevNav = points.last.nav;
    if (prevNav > 0) return (todayNav - prevNav) / prevNav * 100;

    return null;
  }

  /// Triggers a background refresh of the NAV trend cache for [fundCode] so
  /// that the next render picks up today's just-published NAV.
  /// Builds a grey 「估」placeholder for funds that have a valuation record
  /// but whose cache is currently stale (TTL expired).  These are NOT blue-净
  /// funds — they just need a refresh.
  Widget? _buildStaleValuationTrailing(FundHolding holding, bool isDark) {
    // Try NAV trend data as a stand-in
    final navChange = _getNavTrendChange(holding.fundCode);
    final changeValue = navChange;
    if (changeValue == null) return null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBadge('估', CupertinoColors.systemGrey, isDark),
        const SizedBox(width: 4),
        Text(
          '${changeValue >= 0 ? '+' : ''}${changeValue.toStringAsFixed(2)}%',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            height: 1.2,
            color: _getChangeColor(changeValue),
          ),
        ),
      ],
    );
  }

  /// Builds a trailing widget for funds without valuation API data (weekly /
  /// closed-period funds), showing the growth % from the last two NAV trend
  /// points.  Trend data is loaded by [_loadNavTrendsForNavOnlyFunds] after
  /// each valuation refresh.
  Widget? _buildNavOnlyTrailing(FundHolding holding, bool isDark) {
    final navChange = _getNavTrendChange(holding.fundCode);
    if (navChange == null) return null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBadge('净', CupertinoColors.systemBlue, isDark),
        const SizedBox(width: 4),
        Text(
          '${navChange >= 0 ? '+' : ''}${navChange.toStringAsFixed(2)}%',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            height: 1.2,
            color: _getChangeColor(navChange),
          ),
        ),
      ],
    );
  }

  /// Loads NAV trend data for funds that have no valuation API (blue-「净」).
  /// Called once per calendar day after the valuation refresh completes.
  /// Loads NAV trend data for ALL funds after each valuation refresh.
  /// This keeps the trend cache in sync with the valuation cache so that
  /// green-「净」funds always have fresh trend data to compute the true
  /// NAV daily change.
  Future<void> _loadNavTrendsForNavOnlyFunds() async {
    final codes = _dataManager.holdings.map((h) => h.fundCode).toSet().toList();
    if (codes.isEmpty) return;

    final futures = codes.map((c) =>
        _fundService.fetchNetWorthTrend(c).catchError((_) => <NetWorthPoint>[]));
    await Future.wait(futures);

    if (mounted) {
      _cachedSortedFundCodes = null;
      setState(() {});
    }
  }

  Map<String, List<FundHolding>> get _filteredGroupedFunds {
    final allHoldings = _dataManager.holdings;
    if (_searchText.isEmpty) {
      return _groupByFundCode(allHoldings);
    }
    
    final filtered = allHoldings.where((holding) {
      final match = holding.fundCode.contains(_searchText) ||
          holding.fundName.contains(_searchText) ||
          holding.clientName.contains(_searchText);
      if (match) {
      }
      return match;
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

  /// Compares two fund codes for the "查估值" sort mode.
  ///
  /// Funds are sorted into three tiers:
  ///   1. Valuation (gszzl) available, NAV not yet updated → 「估」label
  ///   2. Valuation (gszzl) available, NAV updated (green 「净」)
  ///   3. No valuation API, growth from trend cache (blue 「净」)
  /// Within each tier, sorted by the respective change %.
  int _compareForLatestNav(String codeA, String codeB,
      List<FundHolding> fundsA, List<FundHolding> fundsB) {
    final cacheA = _dataManager.getValuation(codeA);
    final cacheB = _dataManager.getValuation(codeB);

    final holdingA = fundsA.isNotEmpty ? fundsA.first : null;
    final holdingB = fundsB.isNotEmpty ? fundsB.first : null;

    final tierA = _latestNavTier(codeA, cacheA, holdingA);
    final tierB = _latestNavTier(codeB, cacheB, holdingB);

    if (tierA != tierB) return tierA.compareTo(tierB);

    // Same tier — sort by the respective change %
    final valueA = _latestNavSortValue(codeA, cacheA, tierA, holding: holdingA);
    final valueB = _latestNavSortValue(codeB, cacheB, tierB, holding: holdingB);

    if (valueA != null && valueB != null) {
      return _sortOrder == SortOrder.ascending
          ? valueA.compareTo(valueB)
          : valueB.compareTo(valueA);
    }
    if (valueA != null) return -1;
    if (valueB != null) return 1;
    return codeA.compareTo(codeB);
  }

  /// Returns the tier for [fundCode]: 1 =估, 2 =绿净, 3 =蓝净。
  ///
  /// Green 「净」(tier 2) is used after hours when the fund's NAV has been
  /// published for today.  We check both the valuation API's jzrq (fast but
  /// can lag) and the holding's navDate (updated by refreshAllHoldings via
  /// pingzhongdata.js, which is typically fresher after ~20:00).
  int _latestNavTier(String fundCode, Map<String, dynamic>? cache,
      FundHolding? holding) {
    // Only truly API-less funds go to blue tier
    if (cache == null && !_dataManager.hasValuationRecord(fundCode)) return 3;

    // Fund has a valuation record but cache is currently stale.
    // Don't relegate to blue tier — keep as grey 估.
    final hasGszzl = cache != null && cache['gszzl'] != null;
    if (!hasGszzl) return 1; // grey 「估」(stale, needs refresh)

    // During trading hours (including midday break): valuation takes priority
    if (!AppConstants.isAfterMarketClose()) return 1;

    // After close (after 15:00): check if NAV is published → green 净
    if (holding != null && _isNavPublishedForHolding(holding)) return 2;

    return 1; // grey 「估」
  }

  /// Returns the sort value for [fundCode] based on its tier.
  double? _latestNavSortValue(
      String fundCode, Map<String, dynamic>? cache, int tier,
      {FundHolding? holding}) {
    switch (tier) {
      case 1: // grey 「估」: sort by gszzl (valuation estimate %)
        if (cache == null) return null;
        final gszzl = cache['gszzl'];
        return gszzl != null ? (gszzl as num).toDouble() : null;
      case 2: // green 「净」: sort by the actual published NAV daily change
        if (holding != null && holding.currentNav > 0) {
          return _getGreenNavChangeFromHolding(fundCode, holding);
        }
        return _getNavTrendChange(fundCode);
      case 3: // blue 「净」: sort by NAV trend growth
        return _getNavTrendChange(fundCode);
      default:
        return null;
    }
  }

  List<String>? _cachedSortedFundCodes;
  String? _lastSearchText;
  SortKey? _lastSortKey;
  SortOrder? _lastSortOrder;
  final Map<String, List<Color>> _gradientCache = {};

  List<String> get _sortedFundCodes {
    if (_cachedSortedFundCodes != null &&
        _lastSearchText == _searchText &&
        _lastSortKey == _sortKey &&
        _lastSortOrder == _sortOrder) {
      return _cachedSortedFundCodes!;
    }

    final codes = _filteredGroupedFunds.keys.toList();
    if (_sortKey == SortKey.none) {
      codes.sort();
      _cachedSortedFundCodes = codes;
      _lastSearchText = _searchText;
      _lastSortKey = _sortKey;
      _lastSortOrder = _sortOrder;
      return codes;
    }
    
    codes.sort((a, b) {
      final fundsA = _filteredGroupedFunds[a]!;
      final fundsB = _filteredGroupedFunds[b]!;

      if (_sortKey == SortKey.latestNav) {
        return _compareForLatestNav(a, b, fundsA, fundsB);
      }

      double? valueA, valueB;
      final firstA = fundsA.first;
      final firstB = fundsB.first;
      valueA = _sortKey.getValue(firstA);
      valueB = _sortKey.getValue(firstB);

      if (valueA == null && valueB == null) return a.compareTo(b);
      if (valueA == null) return 1;
      if (valueB == null) return -1;
      if (_sortOrder == SortOrder.ascending) {
        return valueA.compareTo(valueB);
      } else {
        return valueB.compareTo(valueA);
      }
    });
    
    _cachedSortedFundCodes = codes;
    _lastSearchText = _searchText;
    _lastSortKey = _sortKey;
    _lastSortOrder = _sortOrder;
    
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
        
        final sortedCodes = _sortedFundCodes;
        if (sortedCodes.isNotEmpty && fundCode == sortedCodes.last) {
          Future.delayed(const Duration(milliseconds: 100), () {
            _scrollToBottom();
          });
        }
      }
    });
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    
    Future.delayed(AnimationConfig.durationSlow, () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AnimationConfig.durationMedium,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  static const List<Color> _softColors = [
    Color(0xFFA8C4E0), Color(0xFFB8D0C4), Color(0xFFD4C4A8),
    Color(0xFFE0B8C4), Color(0xFFC4B8E0), Color(0xFFA8D4D4),
    Color(0xFFE0C8A8), Color(0xFFC8D4A8), Color(0xFFD4A8C4),
    Color(0xFFA8D0E0), Color(0xFFE0C0B0), Color(0xFFB0C8E0),
    Color(0xFFD0B8C8), Color(0xFFC0D4B0), Color(0xFFE0D0B0),
  ];

  List<Color> _getGradientForFundCode(String fundCode) {
    final cached = _gradientCache[fundCode];
    if (cached != null) return cached;

    int hash = 0;
    for (int i = 0; i < fundCode.length; i++) {
      hash = (hash << 5) - hash + fundCode.codeUnitAt(i);
    }
    hash = hash.abs();
    final mainColor = _softColors[hash % _softColors.length];
    final result = [mainColor, Color.fromRGBO(mainColor.red, mainColor.green, mainColor.blue, 0.3)];
    _gradientCache[fundCode] = result;
    return result;
  }

  Color _colorForHoldingCount(int count) {
    if (count == 1) return const Color(0xFFD4A84B);
    if (count <= 3) return const Color(0xFFD4844B);
    return AppConstants.lossRed;
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
    final isDark = AppConstants.isDark(context);
    final backgroundColor = isDark ? AppConstants.darkBackground : AppConstants.lightBackground;
    final hasData = _hasData;
    final showHolderCount = !_dataManager.isPrivacyMode;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const bottomNavBarHeight = 56.0;
    final totalBottomPadding = bottomPadding + bottomNavBarHeight + 20;

    final enableButtons = hasData;

    return buildWithScrollToTop(
      Container(
        color: backgroundColor,
        child: SafeArea(
          child: Column(
            children: [
            ValueListenableBuilder<double>(
              valueListenable: _scrollOffsetNotifier,
              builder: (context, offset, child) {
                return AdaptiveTopBar(
              scrollOffset: offset,
              scrollController: _scrollController,
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
                if (mounted) {
                  _isOrderToggle = false;
                  _captureOldPositions();
                  setState(() => _sortKey = key);
                  _sortAnimCtrl.forward(from: 0);
                }
                await _saveSortState();
                _showSortToast();
              }
                  : null,
              onSortOrderChanged: enableButtons
                  ? (order) async {
                if (mounted) {
                  _isOrderToggle = true;
                  _oldPositions = null;
                  setState(() => _sortOrder = order);
                  _sortAnimCtrl.forward(from: 0);
                }
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
                  ? (text) { 
                      if (mounted) {
                        setState(() => _searchText = text);
                      }
                    }
                  : null,
              onSearchClear: enableButtons
                  ? () { 
                      if (mounted) {
                        setState(() => _searchText = '');
                      }
                    }
                  : null,
              backgroundColor: Colors.transparent,
              iconColor: CupertinoTheme.of(context).primaryColor,
              iconSize: 24,
              buttonSpacing: 12,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              useMenuStyle: true,
            );
          },
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
                    showCupertinoDialog(
                      context: context,
                      barrierDismissible: true,
                      builder: (_) => const AddHoldingView(),
                    );
                  },
                  isPrimary: false,
                  width: null,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                ),
              )
                  : NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification) {
                      _onScrollUpdate(notification.metrics.pixels);
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.only(
                      left: 12,
                      right: 12,
                      top: 8,
                      bottom: totalBottomPadding,
                    ),
                    itemCount: sortedCodes.length,
                    cacheExtent: 500,
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
                          trailing = _buildValuationTrailing(fundCode, first, isDark);
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

                      Widget? finalTrailing = trailing;
                      if (isExpanded) {
                        finalTrailing = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (trailing != null) ...[
                              trailing!,
                              const SizedBox(width: 8),
                            ],
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  AnimationConfig.createPageRoute(
                                    page: FundDetailPage(holding: first),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: isDark 
                                      ? CupertinoColors.white.withOpacity(0.2)
                                      : CupertinoColors.black.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  CupertinoIcons.ellipsis,
                                  size: 16,
                                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                ),
                              ),
                            ),
                          ],
                        );
                      }

                      // ── Sort animation (matches iOS withAnimation spring) ──
                      final oldI = _oldPositions?[fundCode];
                      final delta = oldI != null
                          ? (oldI - index).toDouble()
                          : 0.0;
                      const kCardH = 56.0;

                      return AnimatedBuilder(
                        animation: _sortAnimCtrl,
                        builder: (context, child) {
                          final t = _sortAnimCtrl.value;
                          final stagger = (index * 0.025).clamp(0.0, 0.35);
                          final lt = ((t - stagger) / (1.0 - stagger)).clamp(0.0, 1.0);
                          final c = Curves.easeOutCubic.transform(lt);

                          if (_isOrderToggle) {
                            // Order toggle: subtle staggered slide-up + fade
                            return Opacity(
                              opacity: lt,
                              child: Transform.translate(
                                offset: Offset(0, (1.0 - c) * 14.0),
                                child: child,
                              ),
                            );
                          }

                          // Dimension change: position-swap from old→new index
                          if (delta.abs() < 0.5) return child!;
                          return Transform.translate(
                            offset: Offset(0, delta * kCardH * (1.0 - c)),
                            child: child,
                          );
                        },
                        child: Column(
                          key: ValueKey('fund_$fundCode'),
                          children: [
                            GradientCard(
                              title: first.fundName,
                              clientId: fundCode,
                              gradient: gradient,
                              isExpanded: isExpanded,
                              onTap: () => _toggleExpand(fundCode),
                              isDarkMode: isDark,
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                              trailing: finalTrailing,
                              maxTitleLength: 6,
                            ),
                            AnimationConfig.listExpandTransition(
                              isExpanded: isExpanded,
                              child: Container(
                                margin: const EdgeInsets.only(left: 16, top: 8),
                                child: _buildExpandedContent(first, holdings, isDark),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

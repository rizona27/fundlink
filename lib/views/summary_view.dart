import 'dart:async';
import 'package:flutter/cupertino.dart';
import '../utils/animation_config.dart';
import 'package:flutter/material.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../services/ui_state_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../widgets/empty_state.dart';
import '../widgets/adaptive_top_bar.dart';
import '../widgets/gradient_card.dart';
import '../widgets/glass_button.dart';
import '../widgets/toast.dart';
import '../widgets/fund_performance_dialog.dart';
import 'add_holding_view.dart';
import 'fund_detail_view.dart';
import '../constants/app_constants.dart';

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
  Timer? _marketStatusTimer; 
  bool _isPageVisible = true;
  DateTime? _lastValuationRefreshTime;
  
  bool get _isMarketOpen {
    final now = DateTime.now();
    final weekday = now.weekday;
    
    if (weekday == DateTime.saturday || weekday == DateTime.sunday) return false;
    
    final today = DateTime(now.year, now.month, now.day);
    
    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 60 + minute;
    
    final morningStart = 9 * 60 + 15;  
    final morningEnd = 11 * 60 + 30;   
    final afternoonStart = 13 * 60;     
    final afternoonEnd = 15 * 60 + 30;  
    
    return currentTime >= morningStart && currentTime < afternoonEnd;
  }
  
  bool _shouldPauseAutoRefresh() {
    final now = DateTime.now();
    final weekday = now.weekday;
    
    // ✅ 修复：周末不交易
    if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
      return true;
    }
    
    // ✅ 修复：检查当前时间是否在交易时间内，而不是检查估值时间
    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 60 + minute;
    
    // 交易时间：9:15-11:30, 13:00-15:00
    final morningStart = 9 * 60 + 15;
    final morningEnd = 11 * 60 + 30;
    final afternoonStart = 13 * 60;
    final afternoonEnd = 15 * 60;
    
    final isTradingTime = (currentTime >= morningStart && currentTime <= morningEnd) ||
                         (currentTime >= afternoonStart && currentTime <= afternoonEnd);
    
    return !isTradingTime;  // 非交易时间应该暂停
  }

  double _scrollOffset = 0;
  Timer? _scrollThrottleTimer;
  final ScrollController _scrollController = ScrollController(); 

  bool get _hasAnyExpanded => _expandedFundCodes.isNotEmpty;
  bool get _hasData => _dataManager.holdings.isNotEmpty;
  bool get _showValuationRefresh => _sortKey == SortKey.latestNav && _hasData;

  @override
  bool get wantKeepAlive => true;

  static const String _keySortKey = AppConstants.keySortKey;
  static const String _keySortOrder = AppConstants.keySortOrder;
  static const String _keyExpandedFunds = AppConstants.keyExpandedFunds; 

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dataListener = () {
      if (mounted) {
        setState(() {
          _cachedSortedFundCodes = null;
        });
      }
    };
    _loadSortState();
    _loadValuationRefreshInterval();
    _startMarketStatusTimer();
    
    Future.microtask(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _onScrollUpdate(double offset) {
    if (_scrollThrottleTimer != null && _scrollThrottleTimer!.isActive) {
      return;
    }
    _scrollThrottleTimer = Timer(const Duration(milliseconds: 16), () {
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
      debugPrint('加载排序状态失败: $e');
    }
  }

  Future<void> _saveSortState() async {
    try {
      final uiState = UIStateService();
      await uiState.saveString(_keySortKey, _sortKey.toString());
      await uiState.saveString(_keySortOrder, _sortOrder.toString());
    } catch (e) {
      debugPrint('保存排序状态失败: $e');
    }
  }
  
  void _saveExpandedState() {
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _dataManager.removeListener(_dataListener);
    _dataManager.addListener(_dataListener);
    _fundService = FundService(_dataManager);
    
    _autoConfirmPendingTransactions();
    
    Future.microtask(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopValuationTimer();
    _stopMarketStatusTimer(); 
    _dataManager.removeListener(_dataListener);
    _scrollThrottleTimer?.cancel();
    _scrollController.dispose(); 
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;  // ✅ 生命周期方法中检查 mounted
    
    if (state == AppLifecycleState.resumed) {
      _isPageVisible = true;
      _startMarketStatusTimer(); 
      _restartValuationTimer();
      if (_dataManager.isValuationRefreshInProgress) {
        setState(() {});
      } else {
        _checkAndRefreshStaleValuation();
      }
    } else if (state == AppLifecycleState.paused) {
      _isPageVisible = false;
      _stopValuationTimer();
      _stopMarketStatusTimer(); 
    }
  }

  void _startValuationTimer() {
    _stopValuationTimer();
    
    // ✅ 修复：在非交易时间或周末时，不启动定时器
    if (_shouldPauseAutoRefresh()) {
      return;
    }
    
    if (!_showValuationRefresh || !_isPageVisible || _dataManager.isValuationRefreshing) {
      return;
    }

    _valuationTimer = Timer.periodic(
      Duration(seconds: _valuationRefreshIntervalSeconds),
          (timer) {
        // ✅ 修复：每次触发时再次检查是否为交易时间
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
    _marketStatusTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!_isPageVisible || !mounted) return;
      
      final shouldPause = _shouldPauseAutoRefresh();
      
      if (_showValuationRefresh && _valuationTimer == null && !shouldPause) {
        _restartValuationTimer();
      }
      else if (shouldPause && _valuationTimer != null) {
        _stopValuationTimer();
      }
      
      setState(() {});
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
      debugPrint('加载估值刷新间隔失败: $e');
      _valuationRefreshIntervalSeconds = 180;
      _restartValuationTimer();
    }
    if (mounted) setState(() {});  // ✅ 已有 mounted 检查
  }
  
  Future<void> _autoConfirmPendingTransactions() async {
    try {
      final pendingCount = _dataManager.getPendingTransactions().length;
      if (pendingCount == 0) return;
      
      final confirmedCount = await _dataManager.autoConfirmPendingTransactions(_fundService);
      
      if (confirmedCount > 0 && mounted) {
        context.showToast('已自动确认 $confirmedCount 笔交易');
      }
    } catch (e) {
      debugPrint('自动确认待确认交易失败: $e');
      // 静默失败，不影响用户使用
    }
  }

  Future<void> _saveValuationRefreshInterval(int seconds) async {
    try {
      final uiState = UIStateService();
      await uiState.saveInt('valuationRefreshInterval', seconds);
    } catch (e) {
      debugPrint('保存估值刷新间隔失败: $e');
    }
  }

  void _onValuationRefreshIntervalChanged(int seconds) async {
    print('DEBUG: 用户选择的刷新间隔 = $seconds 秒');
    if (mounted) {  // ✅ 添加 mounted 检查
      setState(() {
        _valuationRefreshIntervalSeconds = seconds;
      });
    }
    print('DEBUG: 设置后的值 = $_valuationRefreshIntervalSeconds 秒');
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

  Future<void> _checkAndRefreshStaleValuation() async {
    if (!_showValuationRefresh || _dataManager.isValuationRefreshInProgress) return;
    
    // ✅ 修复：非交易时间不进行自动检查和刷新
    if (_shouldPauseAutoRefresh()) {
      debugPrint('[SummaryView] 非交易时间，跳过估值缓存检查');
      return;
    }
    
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

    if (!silent && mounted && !_isMarketOpen) {
      context.showToast('当前为非交易时间，仅能获取收市后估值');
    }

    _lastValuationRefreshTime = DateTime.now();
    _stopValuationTimer();

    try {
      await _dataManager.refreshAllValuations(_fundService, silent: silent);
      if (mounted && _sortKey == SortKey.latestNav) {
        setState(() {  // ✅ 已有 mounted 检查
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

  List<String>? _cachedSortedFundCodes;
  String? _lastSearchText;
  SortKey? _lastSortKey;
  SortOrder? _lastSortOrder;

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
    _saveExpandedState(); 
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
    _saveExpandedState(); 
  }

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
                if (mounted) setState(() => _sortKey = key);  // ✅ 添加 mounted 检查
                await _saveSortState();
                _showSortToast();
              }
                  : null,
              onSortOrderChanged: enableButtons
                  ? (order) async {
                if (mounted) setState(() => _sortOrder = order);  // ✅ 添加 mounted 检查
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
                  ? (text) { if (mounted) setState(() => _searchText = text); }  // ✅ 添加 mounted 检查
                  : null,
              onSearchClear: enableButtons
                  ? () { if (mounted) setState(() => _searchText = ''); }  // ✅ 添加 mounted 检查
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
                duration: AnimationConfig.durationMedium,
                switchInCurve: AnimationConfig.curveEaseInOutCubic,
                switchOutCurve: AnimationConfig.curveEaseInOutCubic,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification) {
                      _onScrollUpdate(notification.metrics.pixels);
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scrollController, 
                    key: ValueKey('list_${_sortKey}_${_sortOrder}_${_searchText}'),
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

                      return Column(
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
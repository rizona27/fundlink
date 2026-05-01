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
import 'fund_detail_view.dart';

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
  Timer? _marketStatusTimer; // 检测开市状态变化的定时器
  bool _isPageVisible = true;
  DateTime? _lastValuationRefreshTime;
  
  // 开市时间检测
  bool get _isMarketOpen {
    final now = DateTime.now();
    final weekday = now.weekday;
    
    // 周末闭市
    if (weekday == DateTime.saturday || weekday == DateTime.sunday) return false;
    
    // 检查是否为节假日（使用 DataManager 的交易日判断）
    final today = DateTime(now.year, now.month, now.day);
    // 这里简化处理，实际应该调用 DataManager.isTradingDay
    // 但由于是同步 getter，我们先用基础判断
    
    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 60 + minute;
    
    // A股交易时间：9:30-11:30, 13:00-15:00
    final morningStart = 9 * 60 + 15;  // 9:15（估值可能提前开始）
    final morningEnd = 11 * 60 + 30;   // 11:30
    final afternoonStart = 13 * 60;     // 13:00
    final afternoonEnd = 15 * 60 + 30;  // 15:30（估值可能延迟更新）
    
    // 在交易时间段内（包含午休，因为午休期间估值仍可能更新）
    return currentTime >= morningStart && currentTime < afternoonEnd;
  }
  
  /// 判断是否应该暂停自动刷新
  /// 返回 true 表示应该暂停，false 表示可以继续
  bool _shouldPauseAutoRefresh() {
    final now = DateTime.now();
    final weekday = now.weekday;
    
    // 周末肯定暂停
    if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
      return true;
    }
    
    // 获取所有持仓的最新估值时间
    final holdings = _dataManager.holdings;
    if (holdings.isEmpty) return false;
    
    DateTime? latestValuationTime;
    for (final holding in holdings) {
      final cache = _dataManager.getValuation(holding.fundCode);
      if (cache != null && cache['gztime'] != null) {
        final gztimeStr = cache['gztime'] as String;
        if (gztimeStr.isNotEmpty) {
          try {
            final parts = gztimeStr.split(' ');
            final datePart = parts[0];
            final timePart = parts.length > 1 ? parts[1] : '15:00';
            
            final dateTime = DateTime.parse('$datePart $timePart');
            if (latestValuationTime == null || dateTime.isAfter(latestValuationTime!)) {
              latestValuationTime = dateTime;
            }
          } catch (e) {
            // 解析失败，跳过
          }
        }
      }
    }
    
    // 如果没有估值时间，不暂停
    if (latestValuationTime == null) return false;
    
    // 判断估值时间是否是今天
    final today = DateTime(now.year, now.month, now.day);
    final valuationDay = DateTime(latestValuationTime!.year, latestValuationTime!.month, latestValuationTime!.day);
    
    // 如果估值不是今天的，说明是非交易日，暂停
    if (!valuationDay.isAtSameMomentAs(today)) {
      return true;
    }
    
    // 估值是今天的，检查是否已经过了交易时间
    final valuationHour = latestValuationTime!.hour;
    final valuationMinute = latestValuationTime!.minute;
    final valuationTime = valuationHour * 60 + valuationMinute;
    
    // 如果估值时间已经达到或超过15:00，说明今日交易已结束
    if (valuationTime >= 15 * 60) {
      return true;
    }
    
    // 其他情况不暂停
    return false;
  }

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
  static const String _keyExpandedFunds = 'summary_expanded_funds'; // 展开的基金代码

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dataListener = () {
      if (mounted) {
        setState(() {
          // 清除缓存以强制重新计算
          // 注：排序操作非常快（O(n log n)），对性能影响可忽略
          _cachedSortedFundCodes = null;
        });
      }
    };
    _loadSortState();
    _loadValuationRefreshInterval();
    // 启动市场状态检测定时器
    _startMarketStatusTimer();
    
    // 立即触发一次 UI 更新，确保 isMarketOpen 的值被正确传递
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
    // 优化：增加节流时间到16ms（约60fps），减少setState频率
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
        _sortOrder = SortOrder.descending;
      }
      
      // 加载展开状态（重启app后重置，所以不加载）
      // 展开状态只在会话期间保持，应用重启后清空
    } catch (e) {
    }
  }

  Future<void> _saveSortState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySortKey, _sortKey.toString());
      await prefs.setString(_keySortOrder, _sortOrder.toString());
      // 不保存展开状态，重启app后重置
    } catch (e) {
    }
  }
  
  /// 保存展开状态（仅在当前会话中保持）
  void _saveExpandedState() {
    // 展开状态不持久化到SharedPreferences，只在内存中保持
    // 应用重启后会自动清空
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _dataManager.removeListener(_dataListener);
    _dataManager.addListener(_dataListener);
    _fundService = FundService(_dataManager);
    
    // 启动时自动确认已过期的待确认交易
    _autoConfirmPendingTransactions();
    
    // 强制刷新UI，确保显示最新数据（特别是添加第一个持仓时）
    // 使用 Future.microtask 确保在下一帧执行，避免与当前构建冲突
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
    _stopMarketStatusTimer(); // 停止市场状态检测
    _dataManager.removeListener(_dataListener);
    _scrollThrottleTimer?.cancel();
    _scrollController.dispose(); // 释放滚动控制器
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isPageVisible = true;
      _startMarketStatusTimer(); // 重启市场状态检测
      _restartValuationTimer();
      if (_dataManager.isValuationRefreshInProgress) {
        setState(() {});
      } else {
        _checkAndRefreshStaleValuation();
      }
    } else if (state == AppLifecycleState.paused) {
      _isPageVisible = false;
      _stopValuationTimer();
      _stopMarketStatusTimer(); // 停止市场状态检测
    }
  }

  void _startValuationTimer() {
    _stopValuationTimer();
    
    // 检查是否应该暂停自动刷新
    if (_shouldPauseAutoRefresh()) {
      return;
    }
    
    // 只有在开市期间才启动自动刷新
    if (!_showValuationRefresh || !_isPageVisible || _dataManager.isValuationRefreshing) {
      return;
    }

    _valuationTimer = Timer.periodic(
      Duration(seconds: _valuationRefreshIntervalSeconds),
          (timer) {
        // 每次触发前再次检查是否应该暂停
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
    // 检查是否应该暂停
    if (_shouldPauseAutoRefresh()) {
      return;
    }
    
    // 只有在开市期间才重启定时器
    if (_showValuationRefresh && _isPageVisible && !_dataManager.isValuationRefreshing) {
      _startValuationTimer();
    }
  }
  
  // 启动市场状态检测定时器（每分钟检查一次）
  void _startMarketStatusTimer() {
    _stopMarketStatusTimer();
    _marketStatusTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!_isPageVisible || !mounted) return;
      
      // 检查是否应该暂停自动刷新
      final shouldPause = _shouldPauseAutoRefresh();
      
      // 如果当前应该显示估值刷新但定时器未运行，且不应该暂停
      if (_showValuationRefresh && _valuationTimer == null && !shouldPause) {
        _restartValuationTimer();
      }
      // 如果现在应该暂停，停止定时器
      else if (shouldPause && _valuationTimer != null) {
        _stopValuationTimer();
      }
      
      // 触发 UI 更新，让 AdaptiveTopBar 重新获取 isMarketOpen 的值
      setState(() {});
    });
  }
  
  // 停止市场状态检测定时器
  void _stopMarketStatusTimer() {
    _marketStatusTimer?.cancel();
    _marketStatusTimer = null;
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
  
  /// 自动确认已过期的待确认交易
  Future<void> _autoConfirmPendingTransactions() async {
    try {
      final pendingCount = _dataManager.getPendingTransactions().length;
      if (pendingCount == 0) return;
      
      final confirmedCount = await _dataManager.autoConfirmPendingTransactions(_fundService);
      
      if (confirmedCount > 0 && mounted) {
        context.showToast('已自动确认 $confirmedCount 笔交易');
      }
    } catch (e) {
    }
  }

  Future<void> _saveValuationRefreshInterval(int seconds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('valuationRefreshInterval', seconds);
    } catch (e) {
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

    // 非交易时间手动刷新时提示用户
    if (!silent && mounted && !_isMarketOpen) {
      context.showToast('当前为非交易时间，仅能获取收市后估值');
    }

    _lastValuationRefreshTime = DateTime.now();
    _stopValuationTimer();

    try {
      await _dataManager.refreshAllValuations(_fundService, silent: silent);
      // 估值刷新完成后，如果当前是按最新估值排序，需要清除缓存并重新排序
      if (mounted && _sortKey == SortKey.latestNav) {
        setState(() {
          // 清除排序缓存，强制重新排序
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

  // 性能优化：缓存排序后的基金代码列表
  List<String>? _cachedSortedFundCodes;
  String? _lastSearchText;
  SortKey? _lastSortKey;
  SortOrder? _lastSortOrder;

  List<String> get _sortedFundCodes {
    // 检查缓存是否有效
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
    
    // 更新缓存
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
    _saveExpandedState(); // 保存展开状态
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
    _saveExpandedState(); // 保存展开状态
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
              showValuationRefresh: _showValuationRefresh, // 始终显示估值刷新按钮
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
                    // 添加缓存机制，减少重建
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

                      // 如果展开，在 trailing 中添加三个点菜单按钮
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
                                // 跳转到第一个持仓的基金详情页
                                Navigator.of(context).push(
                                  CupertinoPageRoute(
                                    builder: (context) => FundDetailPage(holding: first),
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
                            trailing: finalTrailing, // 使用包含三个点按钮的 trailing
                            maxTitleLength: 6,
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                            child: isExpanded
                                ? Container(
                                    margin: const EdgeInsets.only(left: 16, top: 8), // 左侧添加16px margin，与ClientView保持一致
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
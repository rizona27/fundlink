import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/fund_holding.dart';
import '../models/net_worth_point.dart';
import '../models/top_holding.dart';
import '../services/fund_service.dart';

class FundDetailPage extends StatefulWidget {
  final FundHolding holding;

  const FundDetailPage({super.key, required this.holding});

  @override
  State<FundDetailPage> createState() => _FundDetailPageState();
}

class _FundDetailPageState extends State<FundDetailPage> {
  late FundService _fundService;

  // 对齐后的数据（按日期升序）
  List<DateTime> _alignedDates = [];
  List<double> _fundPcts = [];      // 本基金累计收益率（%）
  List<double> _avgPcts = [];       // 同类平均累计收益率（%）
  List<double> _hsPcts = [];        // 沪深300累计收益率（%）

  // 原始净值点（用于历史净值）
  List<NetWorthPoint> _fundPoints = [];

  List<TopHolding> _topHoldings = [];
  Map<String, dynamic>? _valuation;
  bool _loading = true;
  String? _error;
  Map<String, double> _stockQuotes = {};

  // 缓存控制
  bool _isDataCached = false;
  static const Duration _cacheDuration = Duration(minutes: 10);
  DateTime? _lastFetchTime;

  // 业绩走势控制
  String _selectedRange = '3m';
  final Map<String, String> _rangeLabels = {
    '1m': '近1月',
    '3m': '近3月',
    '6m': '近6月',
    '1y': '近1年',
    '3y': '近3年',
    'all': '成立来',
  };
  bool _showAverage = true;
  bool _showHs300 = true;

  // 历史净值分页（默认5条）
  List<NetWorthPoint> _historyList = [];
  int _historyPage = 1;
  final int _historyPageSize = 5;
  bool _hasMoreHistory = true;
  bool _loadingMoreHistory = false;

  // 刷新估值防抖（倒计时）
  bool _isRefreshingValuation = false;
  int _refreshCountdown = 0;

  // 全局刷新状态
  bool _isRefreshingAll = false;

  // 自定义 Toast（无需 Material）
  OverlayEntry? _toastEntry;
  void _showToast(String message, {Duration duration = const Duration(seconds: 2)}) {
    _toastEntry?.remove();
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 80,
        left: MediaQuery.of(context).size.width * 0.1,
        width: MediaQuery.of(context).size.width * 0.8,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: CupertinoColors.darkBackgroundGray.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CupertinoColors.white, fontSize: 14),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    _toastEntry = entry;
    Future.delayed(duration, () {
      if (_toastEntry != null) {
        _toastEntry?.remove();
        _toastEntry = null;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _fundService = FundService();
    _loadDetailData();
  }

  /// 加载所有数据（净值走势、基准、重仓股、估值）
  Future<void> _loadDetailData({bool forceRefresh = false}) async {
    // 检查缓存
    if (!forceRefresh && _isDataCached && _lastFetchTime != null) {
      final elapsed = DateTime.now().difference(_lastFetchTime!);
      if (elapsed < _cacheDuration) {
        await _refreshValuationOnly();
        setState(() {});
        return;
      }
    }

    setState(() => _loading = true);
    try {
      // 1. 获取本基金净值走势（原始点）
      final rawTrend = await _fundService.fetchNetWorthTrend(widget.holding.fundCode);
      _fundPoints = List<NetWorthPoint>.from(rawTrend)
        ..sort((a, b) => a.date.compareTo(b.date));
      // 计算日涨幅（升序）
      _fundPoints = _calculateDailyChanges(_fundPoints);

      // 2. 获取同类平均和沪深300基准数据
      final benchmark = await _fundService.fetchBenchmarkData(widget.holding.fundCode);
      List<NetWorthPoint> avgPoints = benchmark['average'] ?? [];
      List<NetWorthPoint> hsPoints = benchmark['hs300'] ?? [];
      avgPoints.sort((a, b) => a.date.compareTo(b.date));
      hsPoints.sort((a, b) => a.date.compareTo(b.date));

      // 3. 日期对齐：以本基金的日期为基准
      final aligned = _alignCurves(_fundPoints, avgPoints, hsPoints);
      _alignedDates = aligned.dates;
      _fundPcts = _calculateCumulativePct(aligned.fundNorms);
      _avgPcts = _calculateCumulativePct(aligned.avgNorms);
      _hsPcts = _calculateCumulativePct(aligned.hsNorms);

      // 4. 重仓股和估值
      final holdings = await _fundService.fetchTopHoldingsFromHtml(widget.holding.fundCode);
      final valuation = await _fundService.fetchRealtimeValuation(widget.holding.fundCode);

      setState(() {
        _topHoldings = holdings;
        _valuation = valuation;
        _loading = false;
        _isDataCached = true;
        _lastFetchTime = DateTime.now();
      });

      // 初始化历史净值分页
      _initHistoryPagination();
      _fetchStockQuotesForHoldings();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 计算每个点的日涨幅（升序列表，第一个点为 null）
  List<NetWorthPoint> _calculateDailyChanges(List<NetWorthPoint> points) {
    final calculated = <NetWorthPoint>[];
    for (int i = 0; i < points.length; i++) {
      double? growth;
      if (i > 0) {
        final prevNav = points[i - 1].nav;
        final currentNav = points[i].nav;
        growth = prevNav > 0 ? ((currentNav - prevNav) / prevNav) * 100 : 0.0;
      }
      calculated.add(NetWorthPoint(
        date: points[i].date,
        nav: points[i].nav,
        growth: growth,
        series: 'fund',
      ));
    }
    return calculated;
  }

  _AlignResult _alignCurves(List<NetWorthPoint> fund, List<NetWorthPoint> avg, List<NetWorthPoint> hs) {
    final dates = <DateTime>[];
    final fundNorms = <double>[];
    final avgNorms = <double>[];
    final hsNorms = <double>[];

    for (final fp in fund) {
      dates.add(fp.date);
      fundNorms.add(fp.nav);
      final avgMatch = _findClosestPoint(avg, fp.date);
      avgNorms.add(avgMatch?.nav ?? double.nan);
      final hsMatch = _findClosestPoint(hs, fp.date);
      hsNorms.add(hsMatch?.nav ?? double.nan);
    }
    return _AlignResult(dates: dates, fundNorms: fundNorms, avgNorms: avgNorms, hsNorms: hsNorms);
  }

  NetWorthPoint? _findClosestPoint(List<NetWorthPoint> points, DateTime target) {
    if (points.isEmpty) return null;
    int lo = 0, hi = points.length - 1;
    while (lo <= hi) {
      int mid = (lo + hi) ~/ 2;
      if (points[mid].date.isBefore(target)) {
        lo = mid + 1;
      } else if (points[mid].date.isAfter(target)) {
        hi = mid - 1;
      } else {
        return points[mid];
      }
    }
    if (hi >= 0) return points[hi];
    return points.first;
  }

  List<double> _calculateCumulativePct(List<double> values) {
    if (values.isEmpty) return [];
    final first = values.firstWhere((v) => v.isFinite, orElse: () => double.nan);
    if (first.isNaN || first == 0) return List.filled(values.length, 0.0);
    return values.map((v) => ((v - first) / first) * 100).toList();
  }

  Future<void> _refreshValuationOnly() async {
    try {
      final valuation = await _fundService.fetchRealtimeValuation(widget.holding.fundCode);
      setState(() {
        _valuation = valuation;
      });
    } catch (e) {
      // ignore
    }
  }

  Future<void> _refreshAll() async {
    if (_isRefreshingAll) return;
    setState(() => _isRefreshingAll = true);
    await _loadDetailData(forceRefresh: true);
    setState(() => _isRefreshingAll = false);
  }

  Future<void> _fetchStockQuotesForHoldings() async {
    if (_topHoldings.isEmpty) return;
    final stockCodes = _topHoldings.map((h) => h.stockCode).toList();
    final quotes = await _fundService.fetchStockQuotes(stockCodes);
    setState(() {
      _stockQuotes = quotes;
    });
  }

  void _initHistoryPagination() {
    // 从 _fundPoints（升序）取最后5条（最近日期）并反转得到降序列表
    final total = _fundPoints.length;
    final start = total > _historyPageSize ? total - _historyPageSize : 0;
    _historyList = _fundPoints.sublist(start).reversed.toList();
    _hasMoreHistory = start > 0;
    _historyPage = 1;
  }

  Future<void> _loadMoreHistory() async {
    if (_loadingMoreHistory || !_hasMoreHistory) return;
    setState(() => _loadingMoreHistory = true);
    try {
      final total = _fundPoints.length;
      final currentLoaded = _historyList.length;
      final nextStart = total - currentLoaded - _historyPageSize;
      if (nextStart < 0) {
        _hasMoreHistory = false;
        _showToast('暂无更多历史净值');
      } else {
        final newItems = _fundPoints.sublist(nextStart, nextStart + _historyPageSize).reversed.toList();
        final lastDate = newItems.last.date;
        setState(() {
          _historyList.addAll(newItems);
          _historyPage++;
          _hasMoreHistory = nextStart > 0;
        });
        _showToast('已加载到 ${_formatDate(lastDate)} 数据');
      }
    } catch (e) {
      _showToast('加载失败: $e');
    } finally {
      setState(() => _loadingMoreHistory = false);
    }
  }

  Future<void> _refreshValuation() async {
    if (_isRefreshingValuation) return;
    setState(() => _isRefreshingValuation = true);
    try {
      final valuation = await _fundService.fetchRealtimeValuation(widget.holding.fundCode);
      setState(() {
        _valuation = valuation;
      });
      _showToast('估值已刷新');
      _startCountdown();
    } catch (e) {
      _showToast('刷新失败: $e');
      setState(() => _isRefreshingValuation = false);
    }
  }

  void _startCountdown() {
    _refreshCountdown = 59;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (_refreshCountdown <= 1) {
        if (mounted) setState(() => _isRefreshingValuation = false);
        return false;
      }
      if (mounted) setState(() => _refreshCountdown--);
      return true;
    });
  }

  /// 根据选中的区间筛选对齐后的数据，并返回起始索引和结束索引
  (int start, int end) _getRangeIndices() {
    if (_alignedDates.isEmpty) return (0, 0);
    final now = DateTime.now();
    DateTime startDate;
    switch (_selectedRange) {
      case '1m':
        startDate = now.subtract(const Duration(days: 30));
        break;
      case '3m':
        startDate = now.subtract(const Duration(days: 90));
        break;
      case '6m':
        startDate = now.subtract(const Duration(days: 180));
        break;
      case '1y':
        startDate = now.subtract(const Duration(days: 365));
        break;
      case '3y':
        startDate = now.subtract(const Duration(days: 1095));
        break;
      default:
        startDate = DateTime.fromMillisecondsSinceEpoch(0);
    }
    int startIdx = _alignedDates.indexWhere((d) => d.isAfter(startDate));
    if (startIdx == -1) startIdx = 0;
    return (startIdx, _alignedDates.length - 1);
  }

  double _calculateRangeReturn() {
    final (start, end) = _getRangeIndices();
    if (start >= end || _fundPcts.isEmpty) return 0.0;
    return _fundPcts[end] - _fundPcts[start];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final rangeReturn = _calculateRangeReturn();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.holding.fundName),
        previousPageTitle: '返回',
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isRefreshingAll ? null : _refreshAll,
          child: _isRefreshingAll
              ? const SizedBox(width: 22, height: 22, child: CupertinoActivityIndicator())
              : const Icon(CupertinoIcons.refresh, size: 22),
        ),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : _error != null
            ? Center(child: Text('加载失败: $_error'))
            : SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildValuationCard(isDark),
              const SizedBox(height: 24),
              _buildPerformanceCard(isDark, rangeReturn),
              const SizedBox(height: 24),
              _buildHistoryTable(isDark),
              const SizedBox(height: 24),
              _buildTopHoldingsGrid(isDark),
            ],
          ),
        ),
      ),
    );
  }

  // 顶部估值卡片
  Widget _buildValuationCard(bool isDark) {
    final gsz = _valuation?['gsz'] ?? 0.0;
    final gszzl = _valuation?['gszzl'] ?? 0.0;
    final gztime = _valuation?['gztime'] ?? '';
    final jzrq = _valuation?['jzrq'] ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('估算净值', style: TextStyle(fontSize: 14, color: isDark ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey)),
                  const SizedBox(height: 4),
                  Text(gsz.toStringAsFixed(4), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('估算涨幅', style: TextStyle(fontSize: 14, color: isDark ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey)),
                  const SizedBox(height: 4),
                  Text(
                    '${gszzl >= 0 ? '+' : ''}${gszzl.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: gszzl > 0 ? CupertinoColors.systemRed : (gszzl < 0 ? CupertinoColors.systemGreen : CupertinoColors.systemGrey),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('估值时间: ${_formatGzTime(gztime)}', style: TextStyle(fontSize: 12, color: isDark ? CupertinoColors.white.withOpacity(0.5) : CupertinoColors.systemGrey)),
              Text('净值日期: ${jzrq.isNotEmpty ? jzrq : '--'}', style: TextStyle(fontSize: 12, color: isDark ? CupertinoColors.white.withOpacity(0.5) : CupertinoColors.systemGrey)),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                onPressed: _isRefreshingValuation ? null : _refreshValuation,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isRefreshingValuation ? CupertinoColors.systemGrey.withOpacity(0.3) : CupertinoColors.activeBlue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _isRefreshingValuation
                      ? Text('$_refreshCountdown s', style: const TextStyle(fontSize: 12, color: CupertinoColors.white))
                      : const Text('刷新', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: CupertinoColors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 业绩走势卡片
  Widget _buildPerformanceCard(bool isDark, double rangeReturn) {
    final (startIdx, endIdx) = _getRangeIndices();
    if (startIdx >= endIdx || _fundPcts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: const Center(child: Text('暂无数据')),
      );
    }

    final fundSlice = _fundPcts.sublist(startIdx, endIdx + 1);
    final avgSlice = _avgPcts.sublist(startIdx, endIdx + 1);
    final hsSlice = _hsPcts.sublist(startIdx, endIdx + 1);

    double minY = 0, maxY = 0;
    final allValues = [...fundSlice];
    if (_showAverage) allValues.addAll(avgSlice);
    if (_showHs300) allValues.addAll(hsSlice);
    if (allValues.isNotEmpty) {
      minY = allValues.reduce((a, b) => a < b ? a : b);
      maxY = allValues.reduce((a, b) => a > b ? a : b);
      final padding = (maxY - minY) * 0.1;
      minY = minY - padding;
      maxY = maxY + padding;
    } else {
      minY = -5;
      maxY = 5;
    }

    final isShortRange = ['1m', '3m', '6m'].contains(_selectedRange);
    final showAvg = isShortRange && _showAverage;
    final showHs = isShortRange && _showHs300;
    final rangeName = _rangeLabels[_selectedRange] ?? '';
    final returnColor = rangeReturn > 0
        ? CupertinoColors.systemRed
        : (rangeReturn < 0 ? CupertinoColors.systemGreen : CupertinoColors.systemGrey);

    List<FlSpot> fundSpots = [];
    List<FlSpot> avgSpots = [];
    List<FlSpot> hsSpots = [];
    for (int i = 0; i < fundSlice.length; i++) {
      fundSpots.add(FlSpot(i.toDouble(), fundSlice[i]));
      if (showAvg && i < avgSlice.length && avgSlice[i].isFinite) avgSpots.add(FlSpot(i.toDouble(), avgSlice[i]));
      if (showHs && i < hsSlice.length && hsSlice[i].isFinite) hsSpots.add(FlSpot(i.toDouble(), hsSlice[i]));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('业绩走势', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: returnColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  '$rangeName涨跌幅 ${rangeReturn >= 0 ? '+' : ''}${rangeReturn.toStringAsFixed(2)}%',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: returnColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 时间按钮：第一行（三等分）
          Row(
            children: ['1m', '3m', '6m'].map((key) {
              final isSelected = _selectedRange == key;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedRange = key;
                      _showAverage = true;
                      _showHs300 = true;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? CupertinoColors.activeBlue : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? CupertinoColors.white.withOpacity(0.3) : CupertinoColors.systemGrey.withOpacity(0.5)),
                    ),
                    child: Text(
                      _rangeLabels[key]!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                        color: isSelected ? CupertinoColors.white : (isDark ? CupertinoColors.white : CupertinoColors.black),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // 时间按钮：第二行（三等分）
          Row(
            children: ['1y', '3y', 'all'].map((key) {
              final isSelected = _selectedRange == key;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedRange = key;
                      _showAverage = false;
                      _showHs300 = false;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? CupertinoColors.activeBlue : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? CupertinoColors.white.withOpacity(0.3) : CupertinoColors.systemGrey.withOpacity(0.5)),
                    ),
                    child: Text(
                      _rangeLabels[key]!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                        color: isSelected ? CupertinoColors.white : (isDark ? CupertinoColors.white : CupertinoColors.black),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 2,
                  getDrawingHorizontalLine: (value) => FlLine(color: isDark ? CupertinoColors.white.withOpacity(0.1) : CupertinoColors.systemGrey.withOpacity(0.2)),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text('${value.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 10)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < fundSlice.length) {
                          final date = _alignedDates[startIdx + idx];
                          return Text(_formatDateShort(date), style: const TextStyle(fontSize: 10));
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true, border: Border.all(color: isDark ? CupertinoColors.white.withOpacity(0.2) : CupertinoColors.systemGrey.withOpacity(0.5))),
                minX: 0,
                maxX: (fundSlice.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: fundSpots,
                    isCurved: true,
                    color: CupertinoColors.systemRed,
                    barWidth: 2,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: CupertinoColors.systemRed.withOpacity(0.1),
                    ),
                  ),
                  if (showAvg && avgSpots.isNotEmpty)
                    LineChartBarData(
                      spots: avgSpots,
                      isCurved: true,
                      color: CupertinoColors.systemBlue,
                      barWidth: 1.5,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                  if (showHs && hsSpots.isNotEmpty)
                    LineChartBarData(
                      spots: hsSpots,
                      isCurved: true,
                      color: CupertinoColors.systemGrey,
                      barWidth: 1.5,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (isShortRange)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildLegendItem('本基金', CupertinoColors.systemRed),
                _buildLegendItem('同类平均', CupertinoColors.systemBlue),
                _buildLegendItem('沪深300', CupertinoColors.systemGrey),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  // 历史净值表格（精确高度：表头+5行 ≈ 220px）
  Widget _buildHistoryTable(bool isDark) {
    if (_historyList.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('历史净值', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDark ? CupertinoColors.white : CupertinoColors.black)),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: Table(
                border: TableBorder(
                  horizontalInside: BorderSide(color: isDark ? CupertinoColors.white.withOpacity(0.1) : CupertinoColors.systemGrey.withOpacity(0.2)),
                ),
                columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.lightBackgroundGray,
                    ),
                    children: [
                      Padding(padding: const EdgeInsets.all(8), child: Text('日期', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600))),
                      Padding(padding: const EdgeInsets.all(8), child: Text('单位净值', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600))),
                      Padding(padding: const EdgeInsets.all(8), child: Text('日涨幅', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600))),
                    ],
                  ),
                  ..._historyList.map((p) {
                    final growth = p.growth ?? 0.0;
                    return TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.all(8), child: Text(_formatDate(p.date), textAlign: TextAlign.center)),
                        Padding(padding: const EdgeInsets.all(8), child: Text(p.nav.toStringAsFixed(4), textAlign: TextAlign.center)),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            growth == 0 ? '--' : '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(2)}%',
                            style: TextStyle(color: growth > 0 ? CupertinoColors.systemRed : (growth < 0 ? CupertinoColors.systemGreen : null)),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_hasMoreHistory)
            Center(
              child: CupertinoButton(
                onPressed: _loadingMoreHistory ? null : _loadMoreHistory,
                child: _loadingMoreHistory ? const CupertinoActivityIndicator() : const Text('加载更多历史净值'),
              ),
            ),
        ],
      ),
    );
  }

  // 十大重仓股网格
  Widget _buildTopHoldingsGrid(bool isDark) {
    if (_topHoldings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Center(child: Text('暂无重仓股数据', style: TextStyle(color: isDark ? CupertinoColors.white.withOpacity(0.5) : CupertinoColors.systemGrey))),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('前10重仓股票', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDark ? CupertinoColors.white : CupertinoColors.black)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.8,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _topHoldings.length,
            itemBuilder: (context, index) {
              final h = _topHoldings[index];
              // 根据股票代码确定市场前缀，用于查找涨跌幅
              String fullCode = '';
              final codeStr = h.stockCode;
              if (codeStr.length == 5 && RegExp(r'^\d{5}$').hasMatch(codeStr)) {
                fullCode = 'hk$codeStr';
              } else if (codeStr.startsWith('6')) {
                fullCode = 'sh$codeStr';
              } else if (codeStr.startsWith('0') || codeStr.startsWith('3')) {
                fullCode = 'sz$codeStr';
              } else if (codeStr.startsWith('5')) {
                fullCode = 'sz$codeStr';
              } else {
                fullCode = codeStr;
              }
              final changePercent = _stockQuotes[fullCode] ?? 0.0;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? CupertinoColors.white.withOpacity(0.1) : CupertinoColors.systemGrey.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      h.stockName,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? CupertinoColors.white : CupertinoColors.black),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: changePercent > 0 ? CupertinoColors.systemRed.withOpacity(0.2) : (changePercent < 0 ? CupertinoColors.systemGreen.withOpacity(0.2) : CupertinoColors.systemGrey.withOpacity(0.2)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: changePercent > 0 ? CupertinoColors.systemRed : (changePercent < 0 ? CupertinoColors.systemGreen : CupertinoColors.systemGrey),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '占比 ${h.ratio.toStringAsFixed(2)}%',
                          style: TextStyle(fontSize: 12, color: isDark ? CupertinoColors.white.withOpacity(0.6) : CupertinoColors.systemGrey),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatGzTime(String gztime) => gztime.isEmpty ? '--' : gztime;
  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _formatDateShort(DateTime d) => '${d.month}/${d.day}';
}

class _AlignResult {
  final List<DateTime> dates;
  final List<double> fundNorms;
  final List<double> avgNorms;
  final List<double> hsNorms;
  _AlignResult({required this.dates, required this.fundNorms, required this.avgNorms, required this.hsNorms});
}
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/fund_holding.dart';
import '../models/net_worth_point.dart';
import '../models/top_holding.dart';
import '../services/fund_service.dart';
import '../widgets/toast.dart';

class FundDetailPage extends StatefulWidget {
  final FundHolding holding;

  const FundDetailPage({super.key, required this.holding});

  @override
  State<FundDetailPage> createState() => _FundDetailPageState();
}

class _FundDetailPageState extends State<FundDetailPage> {
  late FundService _fundService;

  List<DateTime> _alignedDates = [];
  List<double> _fundPcts = [];
  List<double> _avgPcts = [];
  List<double> _hsPcts = [];

  List<NetWorthPoint> _fundPoints = [];

  List<TopHolding> _topHoldings = [];
  Map<String, dynamic>? _valuation;
  bool _loading = true;
  String? _error;
  Map<String, double> _stockQuotes = {};

  bool _isDataCached = false;
  static const Duration _cacheDuration = Duration(minutes: 10);
  DateTime? _lastFetchTime;

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

  List<NetWorthPoint> _historyList = [];
  int _historyPage = 1;
  final int _historyPageSize = 5;
  bool _hasMoreHistory = true;
  bool _loadingMoreHistory = false;
  final ScrollController _historyScrollController = ScrollController();

  bool _isRefreshingValuation = false;
  int _refreshCountdown = 0;

  @override
  void initState() {
    super.initState();
    _fundService = FundService();
    _loadDetailData();
    _historyScrollController.addListener(_onHistoryScroll);
  }

  @override
  void dispose() {
    _historyScrollController.removeListener(_onHistoryScroll);
    _historyScrollController.dispose();
    super.dispose();
  }

  void _onHistoryScroll() {
    if (_historyScrollController.position.pixels >=
        _historyScrollController.position.maxScrollExtent - 20 &&
        _hasMoreHistory &&
        !_loadingMoreHistory) {
      _loadMoreHistory();
    }
  }

  Future<void> _loadDetailData({bool forceRefresh = false}) async {
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
      final rawTrend = await _fundService.fetchNetWorthTrend(widget.holding.fundCode);
      _fundPoints = List<NetWorthPoint>.from(rawTrend)
        ..sort((a, b) => a.date.compareTo(b.date));
      _fundPoints = _calculateDailyChanges(_fundPoints);

      final benchmark = await _fundService.fetchBenchmarkData(widget.holding.fundCode);
      List<NetWorthPoint> avgPoints = benchmark['average'] ?? [];
      List<NetWorthPoint> hsPoints = benchmark['hs300'] ?? [];
      avgPoints.sort((a, b) => a.date.compareTo(b.date));
      hsPoints.sort((a, b) => a.date.compareTo(b.date));

      final aligned = _normalizeCurves(_fundPoints, avgPoints, hsPoints);
      _alignedDates = aligned.dates;
      _fundPcts = aligned.fundPcts;
      _avgPcts = aligned.avgPcts;
      _hsPcts = aligned.hsPcts;

      final holdings = await _fundService.fetchTopHoldingsFromHtml(widget.holding.fundCode);
      final valuation = await _fundService.fetchRealtimeValuation(widget.holding.fundCode);

      setState(() {
        _topHoldings = holdings;
        _valuation = valuation;
        _loading = false;
        _isDataCached = true;
        _lastFetchTime = DateTime.now();
      });

      _initHistoryPagination();
      _fetchStockQuotesForHoldings();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  _NormalizedResult _normalizeCurves(
      List<NetWorthPoint> fund,
      List<NetWorthPoint> avg,
      List<NetWorthPoint> hs,
      ) {
    if (fund.isEmpty) {
      return _NormalizedResult(dates: [], fundPcts: [], avgPcts: [], hsPcts: []);
    }

    final sortedFund = List<NetWorthPoint>.from(fund)..sort((a, b) => a.date.compareTo(b.date));
    final sortedAvg = List<NetWorthPoint>.from(avg)..sort((a, b) => a.date.compareTo(b.date));
    final sortedHs = List<NetWorthPoint>.from(hs)..sort((a, b) => a.date.compareTo(b.date));

    String dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final Map<String, double> avgMap = {for (var p in sortedAvg) dateKey(p.date): p.nav};
    final Map<String, double> hsMap = {for (var p in sortedHs) dateKey(p.date): p.nav};

    final baseDate = sortedFund.first.date;
    final baseDateStr = dateKey(baseDate);
    final fundBase = sortedFund.first.nav;

    final avgBase = avgMap[baseDateStr] ?? (sortedAvg.isNotEmpty ? sortedAvg.first.nav : 1.0);
    final hsBase = hsMap[baseDateStr] ?? (sortedHs.isNotEmpty ? sortedHs.first.nav : 1.0);

    final dates = <DateTime>[];
    final fundPcts = <double>[];
    final avgPcts = <double>[];
    final hsPcts = <double>[];

    for (final p in sortedFund) {
      final dateStr = dateKey(p.date);
      dates.add(p.date);

      final fundPct = ((p.nav - fundBase) / fundBase) * 100;
      fundPcts.add(fundPct);

      final curAvg = avgMap[dateStr];
      if (curAvg != null && avgBase != 0) {
        avgPcts.add(((curAvg - avgBase) / avgBase) * 100);
      } else {
        avgPcts.add(avgPcts.isNotEmpty ? avgPcts.last : 0.0);
      }

      final curHs = hsMap[dateStr];
      if (curHs != null && hsBase != 0) {
        hsPcts.add(((curHs - hsBase) / hsBase) * 100);
      } else {
        hsPcts.add(hsPcts.isNotEmpty ? hsPcts.last : 0.0);
      }
    }

    return _NormalizedResult(
      dates: dates,
      fundPcts: fundPcts,
      avgPcts: avgPcts,
      hsPcts: hsPcts,
    );
  }

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

  Future<void> _refreshValuationOnly() async {
    try {
      final valuation = await _fundService.fetchRealtimeValuation(widget.holding.fundCode);
      setState(() {
        _valuation = valuation;
      });
    } catch (e) {}
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
    final descending = List<NetWorthPoint>.from(_fundPoints)
      ..sort((a, b) => b.date.compareTo(a.date));
    _historyList = descending.take(_historyPageSize).toList();
    _hasMoreHistory = descending.length > _historyPageSize;
    _historyPage = 1;
  }

  Future<void> _loadMoreHistory() async {
    if (_loadingMoreHistory || !_hasMoreHistory) return;
    setState(() => _loadingMoreHistory = true);
    try {
      final descending = List<NetWorthPoint>.from(_fundPoints)
        ..sort((a, b) => b.date.compareTo(a.date));
      final start = _historyPage * _historyPageSize;
      final end = start + _historyPageSize;
      if (start >= descending.length) {
        _hasMoreHistory = false;
        context.showToast('暂无更多历史净值');
      } else {
        final newItems = descending.sublist(start, end.clamp(0, descending.length));
        final lastDate = newItems.last.date;
        setState(() {
          _historyList.addAll(newItems);
          _historyPage++;
          _hasMoreHistory = end < descending.length;
        });
        context.showToast('已加载到 ${_formatDate(lastDate)} 数据');
      }
    } catch (e) {
      context.showToast('加载失败: $e');
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
      context.showToast('估值已刷新');
      _startCountdown();
    } catch (e) {
      context.showToast('刷新失败: $e');
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

  double _getNiceInterval(double minY, double maxY) {
    final range = maxY - minY;
    if (range <= 0) return 1.0;
    final roughInterval = range / 5;
    const niceNumbers = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0];
    for (final nice in niceNumbers) {
      if (roughInterval <= nice) return nice;
    }
    return (roughInterval / 10).ceilToDouble() * 10;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final rangeReturn = _calculateRangeReturn();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.holding.fundName),
        previousPageTitle: null,
        leading: _buildBackButton(isDark),
        automaticallyImplyLeading: false,
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

  Widget _buildBackButton(bool isDark) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF2C2C2E).withOpacity(0.85)
              : CupertinoColors.white.withOpacity(0.85),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(CupertinoIcons.back, size: 20),
      ),
    );
  }

  Widget _buildValuationCard(bool isDark) {
    final gsz = _valuation?['gsz'] ?? 0.0;
    final gszzl = _valuation?['gszzl'] ?? 0.0;
    final gztime = _valuation?['gztime'] ?? '';
    final jzrq = _valuation?['jzrq'] ?? '';

    Color changeColor;
    if (gszzl > 0) {
      changeColor = CupertinoColors.systemRed;
    } else if (gszzl < 0) {
      changeColor = CupertinoColors.systemGreen;
    } else {
      changeColor = CupertinoColors.systemGrey;
    }

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('估算净值', style: TextStyle(fontSize: 14, color: isDark ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey)),
                    const SizedBox(height: 4),
                    Text(
                      gsz.toStringAsFixed(4),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('估算涨幅', style: TextStyle(fontSize: 14, color: isDark ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey)),
                    const SizedBox(height: 4),
                    Text(
                      '${gszzl >= 0 ? '+' : ''}${gszzl.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: changeColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('估值时间: ${_formatGzTime(gztime)}', style: TextStyle(fontSize: 12, color: isDark ? CupertinoColors.white.withOpacity(0.5) : CupertinoColors.systemGrey)),
              Text('净值日期: ${jzrq.isNotEmpty ? jzrq : '--'}', style: TextStyle(fontSize: 12, color: isDark ? CupertinoColors.white.withOpacity(0.5) : CupertinoColors.systemGrey)),
              _buildRefreshButton(isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRefreshButton(bool isDark) {
    final textColor = isDark ? CupertinoColors.white : CupertinoColors.black;
    return GestureDetector(
      onTap: _isRefreshingValuation ? null : _refreshValuation,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF2C2C2E).withOpacity(0.85)
              : CupertinoColors.white.withOpacity(0.85),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: _isRefreshingValuation
              ? Text(
            '$_refreshCountdown',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor),
          )
              : const Icon(CupertinoIcons.refresh, size: 18),
        ),
      ),
    );
  }

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

    List<FlSpot> fundSpots = [];
    List<FlSpot> avgSpots = [];
    List<FlSpot> hsSpots = [];
    for (int i = 0; i < fundSlice.length; i++) {
      if (fundSlice[i].isFinite) fundSpots.add(FlSpot(i.toDouble(), fundSlice[i]));
      if (i < avgSlice.length && avgSlice[i].isFinite) avgSpots.add(FlSpot(i.toDouble(), avgSlice[i]));
      if (i < hsSlice.length && hsSlice[i].isFinite) hsSpots.add(FlSpot(i.toDouble(), hsSlice[i]));
    }

    if (fundSpots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: const Center(child: Text('无有效数据')),
      );
    }

    double minY = fundSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    double maxY = fundSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    if (avgSpots.isNotEmpty) {
      minY = minY < avgSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b) ? minY : avgSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
      maxY = maxY > avgSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b) ? maxY : avgSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    }
    if (hsSpots.isNotEmpty) {
      minY = minY < hsSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b) ? minY : hsSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
      maxY = maxY > hsSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b) ? maxY : hsSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    }
    final padding = (maxY - minY) * 0.05;
    minY = minY - padding;
    maxY = maxY + padding;
    if (minY > 0) minY = 0;
    if (maxY < 0) maxY = 0;

    final isShortRange = ['1m', '3m', '6m'].contains(_selectedRange);
    final showAvg = isShortRange && _showAverage && avgSpots.isNotEmpty;
    final showHs = isShortRange && _showHs300 && hsSpots.isNotEmpty;
    final rangeName = _rangeLabels[_selectedRange] ?? '';
    final returnColor = rangeReturn > 0
        ? CupertinoColors.systemRed
        : (rangeReturn < 0 ? CupertinoColors.systemGreen : CupertinoColors.systemGrey);

    double interval = _getNiceInterval(minY, maxY);

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
          Row(
            children: ['1m', '3m', '6m'].map((key) {
              final isSelected = _selectedRange == key;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildGlassButton(
                    label: _rangeLabels[key]!,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() {
                        _selectedRange = key;
                        _showAverage = true;
                        _showHs300 = true;
                      });
                    },
                    isDark: isDark,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: ['1y', '3y', 'all'].map((key) {
              final isSelected = _selectedRange == key;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildGlassButton(
                    label: _rangeLabels[key]!,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() {
                        _selectedRange = key;
                        _showAverage = false;
                        _showHs300 = false;
                      });
                    },
                    isDark: isDark,
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
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: isDark ? CupertinoColors.white.withOpacity(0.08) : CupertinoColors.systemGrey.withOpacity(0.15),
                    strokeWidth: 0.5,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: interval,
                      getTitlesWidget: (value, meta) {
                        String label = value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
                        return Text('$label%', style: const TextStyle(fontSize: 10));
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < fundSpots.length) {
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
                maxX: (fundSpots.length - 1).toDouble(),
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
                      color: CupertinoColors.systemRed.withOpacity(0.05),
                    ),
                  ),
                  if (showAvg)
                    LineChartBarData(
                      spots: avgSpots,
                      isCurved: true,
                      color: CupertinoColors.systemBlue,
                      barWidth: 1.5,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                  if (showHs)
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

  Widget _buildGlassButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? CupertinoColors.activeBlue.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? CupertinoColors.activeBlue
                : (isDark ? CupertinoColors.white.withOpacity(0.3) : CupertinoColors.systemGrey.withOpacity(0.5)),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.normal,
            color: isSelected
                ? CupertinoColors.activeBlue
                : (isDark ? CupertinoColors.white : CupertinoColors.black),
          ),
        ),
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
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.lightBackgroundGray,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  child: Table(
                    columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
                    children: [
                      TableRow(
                        children: [
                          Padding(padding: const EdgeInsets.all(8), child: Text('日期', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600))),
                          Padding(padding: const EdgeInsets.all(8), child: Text('单位净值', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600))),
                          Padding(padding: const EdgeInsets.all(8), child: Text('日涨幅', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600))),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    child: ListView.builder(
                      controller: _historyScrollController,
                      itemCount: _historyList.length + (_loadingMoreHistory ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _historyList.length) {
                          return const Padding(
                            padding: EdgeInsets.all(8),
                            child: Center(child: CupertinoActivityIndicator()),
                          );
                        }
                        final p = _historyList[index];
                        final growth = p.growth ?? 0.0;
                        return Table(
                          columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
                          children: [
                            TableRow(
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
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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

  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _formatGzTime(String gztime) => gztime.isEmpty ? '--' : gztime;
  String _formatDateShort(DateTime d) => '${d.month}/${d.day}';
}

class _NormalizedResult {
  final List<DateTime> dates;
  final List<double> fundPcts;
  final List<double> avgPcts;
  final List<double> hsPcts;
  _NormalizedResult({
    required this.dates,
    required this.fundPcts,
    required this.avgPcts,
    required this.hsPcts,
  });
}
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
  List<NetWorthPoint> _fundPoints = [];
  List<NetWorthPoint> _averagePoints = [];
  List<NetWorthPoint> _hs300Points = [];
  List<TopHolding> _topHoldings = [];
  Map<String, dynamic>? _valuation;
  bool _loading = true;
  String? _error;
  Map<String, double> _stockQuotes = {};

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
  bool _showAverage = true;   // 是否显示同类平均
  bool _showHs300 = true;     // 是否显示沪深300

  // 历史净值分页（默认5条）
  List<NetWorthPoint> _historyList = [];
  int _historyPage = 1;
  final int _historyPageSize = 5;
  bool _hasMoreHistory = true;
  bool _loadingMoreHistory = false;

  // 刷新估值防抖
  bool _isRefreshingValuation = false;
  DateTime? _lastValuationRefreshTime;

  @override
  void initState() {
    super.initState();
    _fundService = FundService();
    _loadDetailData();
  }

  Future<void> _loadDetailData() async {
    setState(() => _loading = true);
    try {
      final trends = await _fundService.fetchNetWorthTrend(widget.holding.fundCode);
      final benchmark = await _fundService.fetchBenchmarkData(widget.holding.fundCode);
      final holdings = await _fundService.fetchTopHoldingsFromHtml(widget.holding.fundCode);
      final valuation = await _fundService.fetchRealtimeValuation(widget.holding.fundCode);

      // 排序本基金净值点
      final sortedFund = List<NetWorthPoint>.from(trends)..sort((a, b) => a.date.compareTo(b.date));
      final calculatedFund = _calculateDailyChanges(sortedFund);

      // 排序同类平均和沪深300
      final sortedAvg = List<NetWorthPoint>.from(benchmark['average'] ?? [])..sort((a, b) => a.date.compareTo(b.date));
      final sortedHs = List<NetWorthPoint>.from(benchmark['hs300'] ?? [])..sort((a, b) => a.date.compareTo(b.date));

      setState(() {
        _fundPoints = calculatedFund;
        _averagePoints = sortedAvg;
        _hs300Points = sortedHs;
        _topHoldings = holdings;
        _valuation = valuation;
        _loading = false;
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
      } else {
        final newItems = descending.sublist(start, end.clamp(0, descending.length));
        setState(() {
          _historyList.addAll(newItems);
          _historyPage++;
          _hasMoreHistory = end < descending.length;
        });
        // 增加加载成功的 Toast 提示
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已加载更多历史净值'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载失败: $e'), duration: Duration(seconds: 2)),
      );
    } finally {
      setState(() => _loadingMoreHistory = false);
    }
  }

  Future<void> _refreshValuation() async {
    final now = DateTime.now();
    if (_isRefreshingValuation) return;
    if (_lastValuationRefreshTime != null &&
        now.difference(_lastValuationRefreshTime!) < const Duration(minutes: 1)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请稍后再试，1分钟内只能刷新一次'), duration: Duration(seconds: 2)),
      );
      return;
    }
    setState(() => _isRefreshingValuation = true);
    _lastValuationRefreshTime = now;
    try {
      final valuation = await _fundService.fetchRealtimeValuation(widget.holding.fundCode);
      setState(() {
        _valuation = valuation;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('估值已刷新'), duration: Duration(seconds: 1)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刷新失败: $e'), duration: Duration(seconds: 2)),
      );
    } finally {
      setState(() => _isRefreshingValuation = false);
    }
  }

  // 根据时间范围筛选净值点，并转换为涨幅百分比（以区间起始点为基准）
  List<FlSpot> _getSpotsForRange(List<NetWorthPoint> points, String range) {
    if (points.isEmpty) return [];
    final now = DateTime.now();
    DateTime startDate;
    switch (range) {
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
    final filtered = points.where((p) => p.date.isAfter(startDate)).toList();
    if (filtered.length < 2) return [];
    final baseNav = filtered.first.nav;
    if (baseNav <= 0) return [];
    return filtered.asMap().entries.map((e) {
      final percent = ((e.value.nav - baseNav) / baseNav) * 100;
      return FlSpot(e.key.toDouble(), percent);
    }).toList();
  }

  // 计算近3月涨跌幅（用于顶部徽章）
  double _calculateRecent3mReturn() {
    if (_fundPoints.isEmpty) return 0.0;
    final now = DateTime.now();
    final threeMonthsAgo = now.subtract(const Duration(days: 90));
    final recentPoints = _fundPoints.where((p) => p.date.isAfter(threeMonthsAgo)).toList();
    if (recentPoints.length < 2) return 0.0;
    final startNav = recentPoints.first.nav;
    final endNav = recentPoints.last.nav;
    if (startNav <= 0) return 0.0;
    return ((endNav - startNav) / startNav) * 100;
  }

  DateTime _getStartDateForRange(String range) {
    final now = DateTime.now();
    switch (range) {
      case '1m': return now.subtract(const Duration(days: 30));
      case '3m': return now.subtract(const Duration(days: 90));
      case '6m': return now.subtract(const Duration(days: 180));
      case '1y': return now.subtract(const Duration(days: 365));
      case '3y': return now.subtract(const Duration(days: 1095));
      default: return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final threeMonthReturn = _calculateRecent3mReturn();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.holding.fundName),
        previousPageTitle: '返回',
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
              _buildCombinedInfoCard(isDark),
              const SizedBox(height: 24),
              _buildPerformanceCard(isDark, threeMonthReturn),
              const SizedBox(height: 24),
              _buildHistoryListWithLoadMore(isDark),
              const SizedBox(height: 24),
              _buildTopHoldingsGrid(isDark),
            ],
          ),
        ),
      ),
    );
  }

  // 合并卡片（基金代码 + 单位净值 + 最新涨幅 + 估算净值 + 估算涨幅 + 刷新按钮）
  Widget _buildCombinedInfoCard(bool isDark) {
    final dwjz = widget.holding.currentNav;
    final dwjzDate = widget.holding.navDate;
    final gsz = _valuation?['gsz'] ?? 0.0;
    final gszzl = _valuation?['gszzl'] ?? 0.0;
    final gztime = _valuation?['gztime'] ?? '';

    double latestGrowth = 0.0;
    if (_fundPoints.isNotEmpty) {
      latestGrowth = _fundPoints.last.growth ?? 0.0;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.holding.fundName,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDark ? CupertinoColors.white : CupertinoColors.black),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? CupertinoColors.darkBackgroundGray : CupertinoColors.lightBackgroundGray,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.holding.fundCode,
                  style: TextStyle(fontSize: 13, color: isDark ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('单位净值', style: TextStyle(fontSize: 12, color: isDark ? CupertinoColors.white.withOpacity(0.6) : CupertinoColors.systemGrey)),
                  const SizedBox(height: 4),
                  Text(dwjz.toStringAsFixed(4), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('最新涨幅', style: TextStyle(fontSize: 12, color: isDark ? CupertinoColors.white.withOpacity(0.6) : CupertinoColors.systemGrey)),
                  const SizedBox(height: 4),
                  Text(
                    '${latestGrowth >= 0 ? '+' : ''}${latestGrowth.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: latestGrowth > 0 ? CupertinoColors.systemRed : (latestGrowth < 0 ? CupertinoColors.systemGreen : null),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('估算净值', style: TextStyle(fontSize: 12, color: isDark ? CupertinoColors.white.withOpacity(0.6) : CupertinoColors.systemGrey)),
                  const SizedBox(height: 4),
                  Text(gsz.toStringAsFixed(4), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                ],
              ),
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('估算涨幅', style: TextStyle(fontSize: 12, color: isDark ? CupertinoColors.white.withOpacity(0.6) : CupertinoColors.systemGrey)),
                      const SizedBox(height: 4),
                      Text(
                        '${gszzl >= 0 ? '+' : ''}${gszzl.toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: gszzl > 0 ? CupertinoColors.systemRed : (gszzl < 0 ? CupertinoColors.systemGreen : null),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 0,
                    onPressed: _isRefreshingValuation ? null : _refreshValuation,
                    child: _isRefreshingValuation
                        ? const SizedBox(width: 20, height: 20, child: CupertinoActivityIndicator())
                        : const Icon(CupertinoIcons.refresh, size: 18),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '估值时间: ${_formatGzTime(gztime)}',
                style: TextStyle(fontSize: 11, color: isDark ? CupertinoColors.white.withOpacity(0.5) : CupertinoColors.systemGrey),
              ),
              Text(
                '净值日期: ${_formatDate(dwjzDate)}',
                style: TextStyle(fontSize: 11, color: isDark ? CupertinoColors.white.withOpacity(0.5) : CupertinoColors.systemGrey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 业绩走势卡片（完整实现，使用默认圆点）
  Widget _buildPerformanceCard(bool isDark, double threeMonthReturn) {
    final fundSpots = _getSpotsForRange(_fundPoints, _selectedRange);
    final avgSpots = _getSpotsForRange(_averagePoints, _selectedRange);
    final hsSpots = _getSpotsForRange(_hs300Points, _selectedRange);

    // 计算Y轴范围
    double minY = 0, maxY = 0;
    final allSpots = [...fundSpots];
    if (_showAverage) allSpots.addAll(avgSpots);
    if (_showHs300) allSpots.addAll(hsSpots);
    if (allSpots.isNotEmpty) {
      final yValues = allSpots.map((s) => s.y).toList();
      minY = yValues.reduce((a, b) => a < b ? a : b);
      maxY = yValues.reduce((a, b) => a > b ? a : b);
      final padding = (maxY - minY) * 0.1;
      minY = minY - padding;
      maxY = maxY + padding;
    } else {
      minY = -5;
      maxY = 5;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))
        ],
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
                decoration: BoxDecoration(
                  color: CupertinoColors.systemRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '近3月涨跌幅 ${threeMonthReturn >= 0 ? '+' : ''}${threeMonthReturn.toStringAsFixed(2)}%',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: CupertinoColors.systemRed),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 时间维度切换按钮
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _rangeLabels.keys.map((key) {
                final isSelected = _selectedRange == key;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedRange = key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? CupertinoColors.activeBlue : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isDark ? CupertinoColors.white.withOpacity(0.3) : CupertinoColors.systemGrey.withOpacity(0.5)),
                      ),
                      child: Text(
                        _rangeLabels[key]!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected ? CupertinoColors.white : (isDark ? CupertinoColors.white : CupertinoColors.black),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          // 曲线图（使用默认圆点，避免参数错误）
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
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
                        final index = value.toInt();
                        final points = _getSpotsForRange(_fundPoints, _selectedRange);
                        if (index >= 0 && index < points.length) {
                          final date = _fundPoints
                              .where((p) => p.date.isAfter(_getStartDateForRange(_selectedRange)))
                              .toList()[index].date;
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
                    dotData: FlDotData(show: true), // 使用默认圆点，不自定义
                    belowBarData: BarAreaData(show: false),
                  ),
                  if (_showAverage && avgSpots.isNotEmpty)
                    LineChartBarData(
                      spots: avgSpots,
                      isCurved: true,
                      color: CupertinoColors.systemGreen,
                      barWidth: 2,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(show: false),
                    ),
                  if (_showHs300 && hsSpots.isNotEmpty)
                    LineChartBarData(
                      spots: hsSpots,
                      isCurved: true,
                      color: CupertinoColors.systemBlue,
                      barWidth: 2,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(show: false),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 图例和显示开关
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegendItem('本基金', CupertinoColors.systemRed, true),
              _buildToggleableLegendItem('同类平均', CupertinoColors.systemGreen, _showAverage, (value) {
                setState(() => _showAverage = value);
              }),
              _buildToggleableLegendItem('沪深300', CupertinoColors.systemBlue, _showHs300, (value) {
                setState(() => _showHs300 = value);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, bool enabled) {
    return Row(
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildToggleableLegendItem(String label, Color color, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            color: value ? color : CupertinoColors.systemGrey.withOpacity(0.3),
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: value ? null : CupertinoColors.systemGrey)),
        ],
      ),
    );
  }

  // 历史净值表格（带滚动条、自适应列宽、加载更多 Toast）
  Widget _buildHistoryListWithLoadMore(bool isDark) {
    if (_historyList.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('历史净值', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDark ? CupertinoColors.white : CupertinoColors.black)),
        const SizedBox(height: 12),
        SizedBox(
          height: 300,
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: Table(
                border: TableBorder(
                  horizontalInside: BorderSide(color: isDark ? CupertinoColors.white.withOpacity(0.1) : CupertinoColors.systemGrey.withOpacity(0.2)),
                ),
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1),
                },
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
                  }).toList(),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_hasMoreHistory)
          Center(
            child: CupertinoButton(
              onPressed: _loadingMoreHistory ? null : _loadMoreHistory,
              child: _loadingMoreHistory
                  ? const CupertinoActivityIndicator()
                  : const Text('加载更多历史净值'),
            ),
          ),
      ],
    );
  }

  // 十大重仓股网格（完整实现）
  Widget _buildTopHoldingsGrid(bool isDark) {
    if (_topHoldings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: Text('暂无重仓股数据', style: TextStyle(color: isDark ? CupertinoColors.white.withOpacity(0.5) : CupertinoColors.systemGrey)),
        ),
      );
    }
    return Column(
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
            if (h.stockCode.startsWith('6')) fullCode = 'sh${h.stockCode}';
            else if (h.stockCode.startsWith('0') || h.stockCode.startsWith('3')) fullCode = 'sz${h.stockCode}';
            else if (h.stockCode.startsWith('5')) fullCode = 'hk${h.stockCode}';
            else fullCode = h.stockCode;
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
    );
  }

  String _formatGzTime(String gztime) => gztime.isEmpty ? '--' : gztime;
  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _formatDateShort(DateTime d) => '${d.month}/${d.day}';
}
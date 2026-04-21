import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/fund_holding.dart';
import '../models/net_worth_point.dart';
import '../models/top_holding.dart';
import '../services/fund_service.dart';
import '../widgets/fund_performance_chart.dart';
import '../widgets/toast.dart';
import 'history_view.dart';

class FundDetailPage extends StatefulWidget {
  final FundHolding holding;

  const FundDetailPage({super.key, required this.holding});

  @override
  State<FundDetailPage> createState() => _FundDetailPageState();
}

class _FundDetailPageState extends State<FundDetailPage> {
  late FundService _fundService;

  List<NetWorthPoint> _fundPoints = [];
  List<NetWorthPoint> _avgPoints = [];
  List<NetWorthPoint> _hsPoints = [];

  List<NetWorthPoint>? _cachedFundPointsWithChanges;
  String? _lastFundCodeForCache;

  List<TopHolding> _topHoldings = [];
  Map<String, dynamic>? _valuation;
  bool _loading = true;
  String? _error;
  Map<String, double> _stockQuotes = {};

  bool _isDataCached = false;
  static const Duration _cacheDuration = Duration(minutes: 10);
  DateTime? _lastFetchTime;

  bool _isRefreshingValuation = false;
  int _refreshCountdown = 0;

  final ScrollController _mainScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fundService = FundService();
    _loadDetailData();
  }

  @override
  void dispose() {
    _mainScrollController.dispose();
    super.dispose();
  }

  List<NetWorthPoint> get _fundPointsWithChanges {
    if (_cachedFundPointsWithChanges != null &&
        _lastFundCodeForCache == widget.holding.fundCode &&
        _fundPoints.isNotEmpty) {
      return _cachedFundPointsWithChanges!;
    }

    _cachedFundPointsWithChanges = _calculateDailyChanges(_fundPoints);
    _lastFundCodeForCache = widget.holding.fundCode;
    return _cachedFundPointsWithChanges!;
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
      _cachedFundPointsWithChanges = null;

      final benchmark = await _fundService.fetchBenchmarkData(widget.holding.fundCode);
      _avgPoints = (benchmark['average'] as List<NetWorthPoint>)
        ..sort((a, b) => a.date.compareTo(b.date));
      _hsPoints = (benchmark['hs300'] as List<NetWorthPoint>)
        ..sort((a, b) => a.date.compareTo(b.date));

      final holdings = await _fundService.fetchTopHoldingsFromHtml(widget.holding.fundCode);
      final valuation = await _fundService.fetchRealtimeValuation(widget.holding.fundCode);

      setState(() {
        _topHoldings = holdings;
        _valuation = valuation;
        _loading = false;
        _isDataCached = true;
        _lastFetchTime = DateTime.now();
      });

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

  void _openHistoryDialog() {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) {
        return HistoryDialog(fundCode: widget.holding.fundCode);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

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
          controller: _mainScrollController,
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildValuationCard(isDark),
              const SizedBox(height: 24),
              _buildChartSection(isDark),
              const SizedBox(height: 24),
              _buildTopHoldingsSection(isDark),
              const SizedBox(height: 24),
              _buildHistoryEntry(isDark),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartSection(bool isDark) {
    return RepaintBoundary(
      key: ValueKey('chart_${widget.holding.fundCode}_${_fundPoints.length}'),
      child: FundPerformanceChart(
        fundPoints: _fundPointsWithChanges,
        avgPoints: _avgPoints,
        hsPoints: _hsPoints,
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
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 2)),
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
                    Text('估算净值',
                        style: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? CupertinoColors.white.withOpacity(0.7)
                                : CupertinoColors.systemGrey)),
                    const SizedBox(height: 4),
                    Text(
                      gsz.toStringAsFixed(4),
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
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
                    Text('估算涨幅',
                        style: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? CupertinoColors.white.withOpacity(0.7)
                                : CupertinoColors.systemGrey)),
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
              Text('估值时间: ${_formatGzTime(gztime)}',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? CupertinoColors.white.withOpacity(0.5)
                          : CupertinoColors.systemGrey)),
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
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: textColor),
          )
              : const Icon(CupertinoIcons.refresh, size: 18),
        ),
      ),
    );
  }

  Widget _buildTopHoldingsSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '前10重仓股票',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? CupertinoColors.white : CupertinoColors.black),
          ),
          const SizedBox(height: 12),
          _buildTopHoldingsGrid(isDark),
        ],
      ),
    );
  }

  Widget _buildTopHoldingsGrid(bool isDark) {
    if (_topHoldings.isEmpty) {
      return Center(
        child: Text(
          '暂无重仓股数据',
          style: TextStyle(
              color: isDark
                  ? CupertinoColors.white.withOpacity(0.5)
                  : CupertinoColors.systemGrey),
        ),
      );
    }
    return GridView.builder(
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
            border: Border.all(
                color: isDark
                    ? CupertinoColors.white.withOpacity(0.1)
                    : CupertinoColors.systemGrey.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                h.stockName,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? CupertinoColors.white : CupertinoColors.black),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: changePercent > 0
                          ? CupertinoColors.systemRed.withOpacity(0.2)
                          : (changePercent < 0
                          ? CupertinoColors.systemGreen.withOpacity(0.2)
                          : CupertinoColors.systemGrey.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: changePercent > 0
                            ? CupertinoColors.systemRed
                            : (changePercent < 0
                            ? CupertinoColors.systemGreen
                            : CupertinoColors.systemGrey),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '占比 ${h.ratio.toStringAsFixed(2)}%',
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? CupertinoColors.white.withOpacity(0.6)
                            : CupertinoColors.systemGrey),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryEntry(bool isDark) {
    return GestureDetector(
      onTap: _openHistoryDialog,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '历史净值',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black),
            ),
            Icon(
              CupertinoIcons.forward,
              size: 18,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
            ),
          ],
        ),
      ),
    );
  }

  String _formatGzTime(String gztime) => gztime.isEmpty ? '--' : gztime;
}
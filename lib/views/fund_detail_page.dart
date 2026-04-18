import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:io' show Platform;
import '../models/fund_holding.dart';
import '../models/net_worth_point.dart';
import '../models/top_holding.dart';
import '../services/fund_service.dart';
import '../widgets/fund_performance_chart.dart';
import '../widgets/toast.dart';

class FundDetailPage extends StatefulWidget {
  final FundHolding holding;

  const FundDetailPage({super.key, required this.holding});

  @override
  State<FundDetailPage> createState() => _FundDetailPageState();
}

class _FundDetailPageState extends State<FundDetailPage> with TickerProviderStateMixin {
  late FundService _fundService;

  List<NetWorthPoint> _fundPoints = [];
  List<NetWorthPoint> _avgPoints = [];
  List<NetWorthPoint> _hsPoints = [];

  // 缓存计算结果
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
  List<NetWorthPoint> _historyList = [];
  int _historyPage = 1;
  final int _historyPageSize = 5;
  bool _hasMoreHistory = true;
  bool _loadingMoreHistory = false;
  final ScrollController _historyScrollController = ScrollController();
  final ScrollController _mainScrollController = ScrollController();

  bool _isRefreshingValuation = false;
  int _refreshCountdown = 0;

  bool _isTopHoldingsExpanded = false;
  bool _isHistoryExpanded = false;

  final GlobalKey _topHoldingsKey = GlobalKey();
  final GlobalKey _historyKey = GlobalKey();

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _fundService = FundService();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _loadDetailData();
    _historyScrollController.addListener(_onHistoryScroll);
  }

  @override
  void dispose() {
    _historyScrollController.removeListener(_onHistoryScroll);
    _historyScrollController.dispose();
    _mainScrollController.dispose();
    _animationController.dispose();
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

  // 获取带涨跌幅的净值数据（带缓存）
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
      // 清除缓存，下次访问时会重新计算
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
    final descending = List<NetWorthPoint>.from(_fundPointsWithChanges)
      ..sort((a, b) => b.date.compareTo(a.date));
    _historyList = descending.take(_historyPageSize).toList();
    _hasMoreHistory = descending.length > _historyPageSize;
    _historyPage = 1;
  }

  Future<void> _loadMoreHistory() async {
    if (_loadingMoreHistory || !_hasMoreHistory) return;
    setState(() => _loadingMoreHistory = true);
    try {
      final descending = List<NetWorthPoint>.from(_fundPointsWithChanges)
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

  Future<void> _smoothScrollTo(GlobalKey key, bool isExpanding) async {
    if (!isExpanding) return;
    await Future.delayed(const Duration(milliseconds: 200));
    final context = key.currentContext;
    if (context != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        );
      });
    }
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
            : LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              controller: _mainScrollController,
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: _getDynamicBottomPadding(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildValuationCard(isDark),
                  const SizedBox(height: 24),
                  _buildChartSection(isDark),
                  const SizedBox(height: 24),
                  _buildCollapsibleTopHoldings(isDark),
                  const SizedBox(height: 24),
                  _buildCollapsibleHistory(isDark),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  double _getDynamicBottomPadding() {
    if (_isHistoryExpanded || _isTopHoldingsExpanded) {
      return 40;
    }
    return 20;
  }

  // 优化后的图表部分 - 支持移动端触摸和PC端悬停
  Widget _buildChartSection(bool isDark) {
    return RepaintBoundary(
      key: ValueKey('chart_${widget.holding.fundCode}_${_fundPoints.length}'),
      child: _OptimizedPerformanceChart(
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
              Text('净值日期: ${jzrq.isNotEmpty ? jzrq : '--'}',
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

  Widget _buildCollapsibleTopHoldings(bool isDark) {
    return Container(
      key: _topHoldingsKey,
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _isTopHoldingsExpanded = !_isTopHoldingsExpanded;
              });
              _smoothScrollTo(_topHoldingsKey, _isTopHoldingsExpanded);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '前10重仓股票',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? CupertinoColors.white : CupertinoColors.black),
                ),
                AnimatedRotation(
                  turns: _isTopHoldingsExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    CupertinoIcons.chevron_down,
                    size: 20,
                    color: isDark ? CupertinoColors.white : CupertinoColors.black,
                  ),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 400),
            crossFadeState: _isTopHoldingsExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _buildTopHoldingsGrid(isDark),
            ),
            secondChild: const SizedBox.shrink(),
          ),
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

  Widget _buildCollapsibleHistory(bool isDark) {
    return Container(
      key: _historyKey,
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _isHistoryExpanded = !_isHistoryExpanded;
              });
              _smoothScrollTo(_historyKey, _isHistoryExpanded);
            },
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
                AnimatedRotation(
                  turns: _isHistoryExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    CupertinoIcons.chevron_down,
                    size: 20,
                    color: isDark ? CupertinoColors.white : CupertinoColors.black,
                  ),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 400),
            crossFadeState: _isHistoryExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _buildHistoryTable(isDark),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTable(bool isDark) {
    if (_historyList.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 220,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF2C2C2E)
                  : CupertinoColors.lightBackgroundGray,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1)
              },
              children: [
                TableRow(
                  children: [
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('日期',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w600))),
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('单位净值',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w600))),
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('日涨幅',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w600))),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _historyScrollController,
              child: ListView.separated(
                controller: _historyScrollController,
                primary: false,
                itemCount: _historyList.length + (_loadingMoreHistory ? 1 : 0),
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: isDark
                      ? CupertinoColors.white.withOpacity(0.1)
                      : CupertinoColors.black.withOpacity(0.05),
                ),
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
                    columnWidths: const {
                      0: FlexColumnWidth(1),
                      1: FlexColumnWidth(1),
                      2: FlexColumnWidth(1)
                    },
                    children: [
                      TableRow(
                        children: [
                          Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(_formatDate(p.date),
                                  textAlign: TextAlign.center)),
                          Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(p.nav.toStringAsFixed(4),
                                  textAlign: TextAlign.center)),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              growth == 0
                                  ? '--'
                                  : '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(2)}%',
                              style: TextStyle(
                                  color: growth > 0
                                      ? CupertinoColors.systemRed
                                      : (growth < 0
                                      ? CupertinoColors.systemGreen
                                      : null)),
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
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _formatGzTime(String gztime) => gztime.isEmpty ? '--' : gztime;
}

// 优化后的图表组件 - 分离触摸和悬停逻辑
class _OptimizedPerformanceChart extends StatefulWidget {
  final List<NetWorthPoint> fundPoints;
  final List<NetWorthPoint> avgPoints;
  final List<NetWorthPoint> hsPoints;

  const _OptimizedPerformanceChart({
    required this.fundPoints,
    required this.avgPoints,
    required this.hsPoints,
  });

  @override
  State<_OptimizedPerformanceChart> createState() => _OptimizedPerformanceChartState();
}

class _OptimizedPerformanceChartState extends State<_OptimizedPerformanceChart> {
  Timer? _hoverDebounceTimer;

  // 判断是否为移动端
  bool get _isMobile => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  @override
  void dispose() {
    _hoverDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: Listener(
        onPointerMove: _isMobile ? _handleTouchMove : null,
        onPointerHover: !_isMobile ? _handleHover : null,
        child: FundPerformanceChart(
          fundPoints: widget.fundPoints,
          avgPoints: widget.avgPoints,
          hsPoints: widget.hsPoints,
        ),
      ),
    );
  }

  void _handleTouchMove(PointerMoveEvent event) {
    // 移动端触摸移动逻辑 - 直接响应，无需防抖
    // 这里调用图表的触摸移动方法
    _updateChartHover(event.localPosition);
  }

  void _handleHover(PointerHoverEvent event) {
    // PC端悬停 - 使用防抖避免频繁重绘导致闪烁
    _hoverDebounceTimer?.cancel();
    _hoverDebounceTimer = Timer(const Duration(milliseconds: 16), () {
      _updateChartHover(event.localPosition);
    });
  }

  void _updateChartHover(Offset position) {
    // 这里实现图表的悬停/触摸更新逻辑
    // 具体实现取决于 FundPerformanceChart 的接口
    // 如果 FundPerformanceChart 有更新悬停位置的方法，在这里调用
  }
}
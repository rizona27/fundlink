import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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

class _FundDetailPageState extends State<FundDetailPage> {
  late FundService _fundService;

  List<NetWorthPoint> _fundPoints = [];
  List<NetWorthPoint> _avgPoints = [];
  List<NetWorthPoint> _hsPoints = [];

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

  bool _isRefreshingValuation = false;
  int _refreshCountdown = 0;

  bool _isTopHoldingsExpanded = false;
  bool _isHistoryExpanded = false;

  final GlobalKey _topHoldingsKey = GlobalKey();
  final GlobalKey _historyKey = GlobalKey();

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

  // 平滑滚动，解决 Web 端定位偏差
  Future<void> _smoothScrollTo(GlobalKey key) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        alignment: 0.0,
      );
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
            : SingleChildScrollView(
          // 使用静态底部留白，避免动态 SizedBox 导致的收缩异常
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildValuationCard(isDark),
              const SizedBox(height: 24),
              // 图表区域：增强合成层 + 鼠标区域拦截，防止 Web 悬停闪烁
              Container(
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(),
                child: MouseRegion(
                  onHover: (_) {},
                  child: RepaintBoundary(
                    key: ValueKey('chart_container_${widget.holding.fundCode}'),
                    child: FundPerformanceChart(
                      fundPoints: _fundPoints,
                      avgPoints: _avgPoints,
                      hsPoints: _hsPoints,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildCollapsibleTopHoldings(isDark),
              const SizedBox(height: 24),
              _buildCollapsibleHistory(isDark),
              // 不再需要任何动态 SizedBox
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

  // ========== 可折叠的「前10重仓股票」模块 ==========
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
              if (_isTopHoldingsExpanded) {
                _smoothScrollTo(_topHoldingsKey);
              }
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
                Icon(
                  _isTopHoldingsExpanded
                      ? CupertinoIcons.chevron_down
                      : CupertinoIcons.chevron_right,
                  size: 20,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _isTopHoldingsExpanded ? 1.0 : 0.0,
              child: _isTopHoldingsExpanded
                  ? Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _buildTopHoldingsGrid(isDark),
              )
                  : const SizedBox.shrink(),
            ),
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

  // ========== 可折叠的「历史净值」模块 ==========
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
              if (_isHistoryExpanded) {
                _smoothScrollTo(_historyKey);
              }
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
                Icon(
                  _isHistoryExpanded
                      ? CupertinoIcons.chevron_down
                      : CupertinoIcons.chevron_right,
                  size: 20,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _isHistoryExpanded ? 1.0 : 0.0,
              child: _isHistoryExpanded
                  ? Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _buildHistoryTable(isDark),
              )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  // 恢复原始固定高度 220，内部 ListView 滚动加载更多
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
              child: ListView.builder(
                controller: _historyScrollController,
                primary: false,
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
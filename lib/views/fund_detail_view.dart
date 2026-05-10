import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show debugPrint, defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/fund_holding.dart';
import '../models/net_worth_point.dart';
import '../models/top_holding.dart';
import '../models/log_entry.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../widgets/fund_performance_chart.dart';
import '../widgets/toast.dart';
import '../widgets/glass_button.dart';
import '../widgets/adaptive_top_bar.dart';
import '../widgets/custom_fund_config_dialog.dart';
import '../widgets/top_holdings_widget.dart';
import '../widgets/stock_detail_dialog.dart';
import '../widgets/error_boundary.dart';
import 'history_view.dart';

class FundDetailPage extends StatefulWidget {
  final FundHolding holding;

  const FundDetailPage({super.key, required this.holding});

  @override
  State<FundDetailPage> createState() => _FundDetailPageState();
}

class _FundDetailPageState extends State<FundDetailPage> {
  DataManager? _dataManager;
  FundService? _fundService;
  bool _isInitialized = false;

  List<NetWorthPoint> _fundPoints = [];
  List<NetWorthPoint> _avgPoints = [];
  List<NetWorthPoint> _hsPoints = [];
  List<NetWorthPoint>? _zz500Points;
  List<NetWorthPoint>? _zz1000Points;
  List<NetWorthPoint>? _customFundPoints;

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
  
  String _customFundCode = '';

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _dataManager = DataManagerProvider.of(context);
      _fundService = FundService(_dataManager!);
      _isInitialized = true;
      _loadDetailData();
    }
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
        if (mounted) setState(() {});  // ✅ 添加 mounted 检查
        return;
      }
    }

    if (mounted) setState(() => _loading = true);  // ✅ 添加 mounted 检查
    try {
      final rawTrend = await _fundService!.fetchNetWorthTrend(widget.holding.fundCode);
      _fundPoints = List<NetWorthPoint>.from(rawTrend)
        ..sort((a, b) => a.date.compareTo(b.date));
      _cachedFundPointsWithChanges = null;

      final benchmark = await _fundService!.fetchBenchmarkData(widget.holding.fundCode);
      _avgPoints = (benchmark['average'] as List<NetWorthPoint>)
        ..sort((a, b) => a.date.compareTo(b.date));
      _hsPoints = (benchmark['hs300'] as List<NetWorthPoint>)
        ..sort((a, b) => a.date.compareTo(b.date));

      
      final hs300Future = _fundService!.fetchNetWorthTrend('460300');
      final zz500Future = _fundService!.fetchNetWorthTrend('004348');
      final zz1000Future = _fundService!.fetchNetWorthTrend('011860');
      final customFundFuture = _customFundCode.isNotEmpty 
          ? _fundService!.fetchNetWorthTrend(_customFundCode) 
          : Future.value(<NetWorthPoint>[]);
      
      final results = await Future.wait([
        hs300Future.catchError((e) {
          return <NetWorthPoint>[];
        }),
        zz500Future.catchError((e) {
          return <NetWorthPoint>[];
        }),
        zz1000Future.catchError((e) {
          return <NetWorthPoint>[];
        }),
        customFundFuture.catchError((e) {
          return <NetWorthPoint>[];
        }),
      ]);
      
      _hsPoints = (results[0] as List<NetWorthPoint>)..sort((a, b) => a.date.compareTo(b.date));
      _zz500Points = (results[1] as List<NetWorthPoint>)..sort((a, b) => a.date.compareTo(b.date));
      _zz1000Points = (results[2] as List<NetWorthPoint>)..sort((a, b) => a.date.compareTo(b.date));
      _customFundPoints = (results[3] as List<NetWorthPoint>)..sort((a, b) => a.date.compareTo(b.date));
      
      
      if (_avgPoints.isNotEmpty) {
      }
      if (_hsPoints.isNotEmpty) {
      }
      if (_zz500Points != null && _zz500Points!.isNotEmpty) {
      }
      if (_zz1000Points != null && _zz1000Points!.isNotEmpty) {
      }
      if (_customFundPoints != null && _customFundPoints!.isNotEmpty) {
      }

      final holdings = await _fundService!.fetchTopHoldingsFromHtml(widget.holding.fundCode);
      final valuation = await _fundService!.fetchRealtimeValuation(widget.holding.fundCode);

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
      final valuation = await _fundService!.fetchRealtimeValuation(widget.holding.fundCode);
      if (mounted) {  // ✅ 添加 mounted 检查
        setState(() {
          _valuation = valuation;
        });
      }
    } catch (e) {
      _dataManager?.addLog('基金 ${widget.holding.fundCode} 估值刷新失败: $e', type: LogType.error);
    }
  }
  
  Future<void> _fetchStockQuotesForHoldings() async {
    if (_topHoldings.isEmpty) return;
    final stockCodes = _topHoldings.map((h) => h.stockCode).toList();
    final quotes = await _fundService!.fetchStockQuotes(stockCodes);
    if (mounted) {  // ✅ 添加 mounted 检查
      setState(() {
        _stockQuotes = quotes;
      });
    }
  }
  
  Future<void> _refreshValuation() async {
    if (_isRefreshingValuation) return;
    if (mounted) setState(() => _isRefreshingValuation = true);  // ✅ 添加 mounted 检查
    try {
      final valuation = await _fundService!.fetchRealtimeValuation(widget.holding.fundCode);
      if (mounted) {
        setState(() {
          _valuation = valuation;
        });
      }
      if (mounted) context.showToast('估值已刷新');
      _startCountdown();
    } catch (e) {
      if (mounted) context.showToast('刷新失败: $e');
      if (mounted) setState(() => _isRefreshingValuation = false);
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

  void _showCustomFundConfigDialog() {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) {
        return CustomFundConfigDialog(
          currentCode: _customFundCode,
          onConfirm: (newCode) async {
            if (mounted) {  // ✅ 添加 mounted 检查
              setState(() {
                _customFundCode = newCode;
                _loading = true;
              });
            }
            
            try {
              final customData = await _fundService!.fetchNetWorthTrend(newCode);
              if (customData.isNotEmpty) {
                if (mounted) {
                  setState(() {
                    _customFundPoints = customData..sort((a, b) => a.date.compareTo(b.date));
                    _loading = false;
                  });
                }
                
                if (mounted) {
                  setState(() {});
                }
                
                context.showToast('已更新');
              } else {
                if (mounted) {
                  setState(() {
                    _loading = false;
                  });
                }
                context.showToast('基金数据为空');
              }
            } catch (e) {
              if (mounted) {
                setState(() {
                  _loading = false;
                });
              }
              context.showToast('加载失败');
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoPageScaffold(
      child: SafeArea(
        child: Column(
          children: [
            AdaptiveTopBar(
              scrollOffset: 0,
              showBack: true,
              onBack: () => Navigator.of(context).pop(),
              showRefresh: false,
              showExpandCollapse: false,
              showSearch: false,
              showReset: false,
              showFilter: false,
              showSort: false,
              backgroundColor: Colors.transparent,
              iconColor: CupertinoTheme.of(context).primaryColor,
              iconSize: 24,
              buttonSpacing: 12,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator())
                  : _error != null
                  ? _buildErrorView(isDark)
                  : SingleChildScrollView(
                      controller: _mainScrollController,
                      padding: const EdgeInsets.only(left: 16, right: 16, top: 0, bottom: 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildValuationCard(isDark),
                          const SizedBox(height: 24),
                          _buildChartSection(isDark),
                          const SizedBox(height: 24),
                          // ✅ 修复：使用ErrorBoundary包裹十大持仓，启用自动重试
                          ErrorBoundary(
                            errorMessage: '重仓股加载失败',
                            autoRetry: true,
                            retryDelay: const Duration(seconds: 3),
                            child: TopHoldingsWidget(
                              topHoldings: _topHoldings,
                              stockQuotes: _stockQuotes,
                              isDark: isDark,
                              onStockTap: (stockCode, stockName) {
                                showCupertinoModalPopup(
                                  context: context,
                                  builder: (context) => StockDetailDialog(
                                    stockCode: stockCode,
                                    stockName: stockName,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildHistoryEntry(isDark),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 使用错误边界包裹图表组件，防止图表崩溃导致整个页面白屏
        ErrorBoundary(
          errorMessage: '图表加载失败',
          child: RepaintBoundary(
            key: ValueKey('chart_${widget.holding.fundCode}_${_fundPoints.length}'),
            child: FundPerformanceChart(
              fundPoints: _fundPointsWithChanges,
              avgPoints: _avgPoints,
              hsPoints: _hsPoints,
              zz500Points: _zz500Points,
              zz1000Points: _zz1000Points,
              customFundPoints: _customFundPoints,
              onCustomFundConfig: _showCustomFundConfigDialog,
              fundCode: widget.holding.fundCode,
              customFundCode: _customFundCode.isNotEmpty ? _customFundCode : null,
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildErrorView(bool isDark) {
    final bool isNetworkError = _error!.contains('ClientException') || 
                                 _error!.contains('SocketException') ||
                                 _error!.contains('Failed host lookup');
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isNetworkError ? CupertinoIcons.wifi_slash : CupertinoIcons.exclamationmark_triangle,
              size: 64,
              color: isNetworkError 
                  ? CupertinoColors.systemOrange 
                  : CupertinoColors.systemRed,
            ),
            const SizedBox(height: 16),
            Text(
              isNetworkError ? '网络连接失败' : '加载失败',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isNetworkError 
                  ? '请检查网络连接后重试' 
                  : '数据加载出现错误',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark 
                    ? CupertinoColors.white.withOpacity(0.6)
                    : CupertinoColors.systemGrey,
              ),
            ),
            const SizedBox(height: 24),
            GlassButton(
              label: isNetworkError ? '重新连接' : '重试',
              icon: CupertinoIcons.refresh,
              onPressed: _loadDetailData,
              isPrimary: true,
            ),
          ],
        ),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.holding.fundName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.holding.fundCode,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? CupertinoColors.white.withOpacity(0.5)
                            : CupertinoColors.systemGrey,
                      ),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '估算净值',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? CupertinoColors.white.withOpacity(0.5)
                            : CupertinoColors.systemGrey,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      gsz.toStringAsFixed(4),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '估算涨幅',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? CupertinoColors.white.withOpacity(0.5)
                            : CupertinoColors.systemGrey,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${gszzl >= 0 ? '+' : ''}${gszzl.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 18,
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
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                '估值时间: ${_formatGzTime(gztime)}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? CupertinoColors.white.withOpacity(0.5)
                      : CupertinoColors.systemGrey,
                ),
              ),
              const SizedBox(width: 8),
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
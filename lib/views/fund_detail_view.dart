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
  
  // 自定义基金配置
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
        setState(() {});
        return;
      }
    }

    setState(() => _loading = true);
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

      // 获取对比基金数据（并行加载）- 使用ETF联接基金
      print('开始加载对比基金数据...');
      print('沪深300 ETF联接: 460300 (华泰柏瑞沪深300ETF联接A)');
      print('中证500 ETF联接: 004348');
      print('中证1000 ETF联接: 011860');
      print('自定义基金代码: $_customFundCode');
      
      // iOS优化：使用Future.wait并发加载对比基金数据
      final hs300Future = _fundService!.fetchNetWorthTrend('460300');
      final zz500Future = _fundService!.fetchNetWorthTrend('004348');
      final zz1000Future = _fundService!.fetchNetWorthTrend('011860');
      final customFundFuture = _customFundCode.isNotEmpty 
          ? _fundService!.fetchNetWorthTrend(_customFundCode) 
          : Future.value(<NetWorthPoint>[]);
      
      final results = await Future.wait([
        hs300Future.catchError((e) {
          print('沪深300加载失败: $e');
          return <NetWorthPoint>[];
        }),
        zz500Future.catchError((e) {
          print('中证500加载失败: $e');
          return <NetWorthPoint>[];
        }),
        zz1000Future.catchError((e) {
          print('中证1000加载失败: $e');
          return <NetWorthPoint>[];
        }),
        customFundFuture.catchError((e) {
          print('自定义基金加载失败: $e');
          return <NetWorthPoint>[];
        }),
      ]);
      
      _hsPoints = (results[0] as List<NetWorthPoint>)..sort((a, b) => a.date.compareTo(b.date));
      _zz500Points = (results[1] as List<NetWorthPoint>)..sort((a, b) => a.date.compareTo(b.date));
      _zz1000Points = (results[2] as List<NetWorthPoint>)..sort((a, b) => a.date.compareTo(b.date));
      _customFundPoints = (results[3] as List<NetWorthPoint>)..sort((a, b) => a.date.compareTo(b.date));
      
      print('同类平均数据点数: ${_avgPoints.length}');
      print('沪深300数据点数: ${_hsPoints.length}');
      print('中证500数据点数: ${_zz500Points?.length ?? 0}');
      print('中证1000数据点数: ${_zz1000Points?.length ?? 0}');
      print('自定义基金数据点数: ${_customFundPoints?.length ?? 0}');
      
      if (_avgPoints.isNotEmpty) {
        print('同类平均最新日期: ${_avgPoints.last.date}, 净值: ${_avgPoints.last.nav}');
      }
      if (_hsPoints.isNotEmpty) {
        print('沪深300最新日期: ${_hsPoints.last.date}, 净值: ${_hsPoints.last.nav}');
      }
      if (_zz500Points != null && _zz500Points!.isNotEmpty) {
        print('中证500最新日期: ${_zz500Points!.last.date}, 净值: ${_zz500Points!.last.nav}');
      }
      if (_zz1000Points != null && _zz1000Points!.isNotEmpty) {
        print('中证1000最新日期: ${_zz1000Points!.last.date}, 净值: ${_zz1000Points!.last.nav}');
      }
      if (_customFundPoints != null && _customFundPoints!.isNotEmpty) {
        print('自定义基金最新日期: ${_customFundPoints!.last.date}, 净值: ${_customFundPoints!.last.nav}');
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
      setState(() {
        _valuation = valuation;
      });
    } catch (e) {
      _dataManager?.addLog('基金 ${widget.holding.fundCode} 估值刷新失败: $e', type: LogType.error);
    }
  }
  
  Future<void> _fetchStockQuotesForHoldings() async {
    if (_topHoldings.isEmpty) return;
    final stockCodes = _topHoldings.map((h) => h.stockCode).toList();
    final quotes = await _fundService!.fetchStockQuotes(stockCodes);
    setState(() {
      _stockQuotes = quotes;
    });
  }
  
  Future<void> _refreshValuation() async {
    if (_isRefreshingValuation) return;
    setState(() => _isRefreshingValuation = true);
    try {
      final valuation = await _fundService!.fetchRealtimeValuation(widget.holding.fundCode);
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

  void _showCustomFundConfigDialog() {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) {
        return CustomFundConfigDialog(
          currentCode: _customFundCode,
          onConfirm: (newCode) async {
            setState(() {
              _customFundCode = newCode;
              _loading = true;
            });
            
            try {
              final customData = await _fundService!.fetchNetWorthTrend(newCode);
              if (customData.isNotEmpty) {
                setState(() {
                  _customFundPoints = customData..sort((a, b) => a.date.compareTo(b.date));
                  _loading = false;
                });
                
                // 强制刷新图表
                if (mounted) {
                  setState(() {});
                }
                
                context.showToast('已更新');
              } else {
                setState(() {
                  _loading = false;
                });
                context.showToast('基金数据为空');
              }
            } catch (e) {
              setState(() {
                _loading = false;
              });
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
                          _buildTopHoldingsSection(isDark),
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
        // 业绩走势图
        RepaintBoundary(
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
              // 左侧：基金名称和代码
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
              
              // 中间：估算净值
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
              
              // 右侧：估算涨幅
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据窗口宽度和设备类型动态计算每行显示数量
        final double width = constraints.maxWidth;
        
        int crossAxisCount;
        double childAspectRatio;
        
        // 判断是否为移动设备
        final bool isMobile = !kIsWeb && 
            (defaultTargetPlatform == TargetPlatform.iOS || 
             defaultTargetPlatform == TargetPlatform.android);
        
        if (isMobile) {
          // 移动端：根据屏幕宽度调整
          if (width < 350) {
            crossAxisCount = 2; // 超小屏幕
            childAspectRatio = 3.2; // 更保守的比例，避免溢出
          } else if (width < 450) {
            crossAxisCount = 2; // 普通手机
            childAspectRatio = 3.5;
          } else {
            crossAxisCount = 3; // 大屏手机/小平板
            childAspectRatio = 3.8;
          }
        } else {
          // PC端（Windows/macOS/Web）：根据窗口宽度调整
          if (width < 400) {
            crossAxisCount = 2; // 窄窗口
            childAspectRatio = 3.2; // 更保守的比例，避免溢出
          } else if (width < 600) {
            crossAxisCount = 3; // 中等窗口
            childAspectRatio = 3.5;
          } else if (width < 900) {
            crossAxisCount = 4; // 较宽窗口
            childAspectRatio = 3.8;
          } else if (width < 1200) {
            crossAxisCount = 5; // 宽窗口
            childAspectRatio = 4.0;
          } else {
            crossAxisCount = 6; // 超宽窗口
            childAspectRatio = 4.2;
          }
        }
        
        // 使用 ClipRect 防止布局切换时的溢出警告
        return ClipRect(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            child: GridView.builder(
              key: ValueKey('grid_$crossAxisCount'), // 使用 key 触发动画
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: childAspectRatio,
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark
                            ? CupertinoColors.white.withOpacity(0.1)
                            : CupertinoColors.systemGrey.withOpacity(0.2)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          h.stockName,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                  color: changePercent > 0
                                      ? CupertinoColors.systemRed
                                      : (changePercent < 0
                                      ? CupertinoColors.systemGreen
                                      : CupertinoColors.systemGrey),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${h.ratio.toStringAsFixed(2)}%',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: isDark
                                      ? CupertinoColors.white.withOpacity(0.6)
                                      : CupertinoColors.systemGrey),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
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
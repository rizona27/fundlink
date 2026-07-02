import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../data/industry_classification.dart';
import '../models/fund_holding.dart';
import '../models/top_holding.dart';
import '../models/weighted_holding.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../services/industry_classifier.dart';
import '../services/stock_quote_service.dart';
import '../widgets/adaptive_top_bar.dart';
import '../constants/app_constants.dart';

class ClientFundSummaryPage extends StatefulWidget {
  final String clientName;
  final String clientId;
  final List<FundHolding> holdings;
  final DataManager dataManager;
  final FundService fundService;

  const ClientFundSummaryPage({
    super.key,
    required this.clientName,
    required this.clientId,
    required this.holdings,
    required this.dataManager,
    required this.fundService,
  });

  @override
  State<ClientFundSummaryPage> createState() => _ClientFundSummaryPageState();
}

class _ClientFundSummaryPageState extends State<ClientFundSummaryPage> {
  final StockQuoteService _quoteService = StockQuoteService();
  final Map<String, List<TopHolding>> _fundTopHoldings = {};

  bool _loadingTopHoldings = true;
  bool _loadingQuotes = true;
  int _touchedPieIndex = -1;
  bool _usingBackendData = false;

  Map<String, StockQuote> _stockQuotes = {};
  Map<String, String> _stockIndustries = {};    // stockCode → industry (from backend)
  // ignore: unused_field — cached for potential diagnostic use
  Map<String, dynamic>? _backendAnalysis;
  List<WeightedHolding> _weightedHoldings = [];
  late IndustryClassifier _classifier;

  // --- Display layout constants ---
  static const int _topIndustriesCount = 3;
  static const int _maxIndustriesVisible = 8;
  static const double _cardBorderRadius = 10.0;
  static const double _cardInnerRadius = 6.0;
  static const double _sectionPaddingWide = 16.0;
  static const double _sectionPaddingNarrow = 10.0;
  static const double _sectionSpacingWide = 14.0;
  static const double _sectionSpacingNarrow = 8.0;

  // --- Chart colour palette ---
  static const List<Color> _chartColors = [
    Color(0xFF4A90D9), Color(0xFFE85D75), Color(0xFF50C878),
    Color(0xFFFFB347), Color(0xFF9B59B6), Color(0xFF1ABC9C),
    Color(0xFFE74C3C), Color(0xFF3498DB), Color(0xFF2ECC71),
    Color(0xFFF39C12), Color(0xFF8E44AD), Color(0xFF16A085),
    Color(0xFFD35400), Color(0xFF2980B9), Color(0xFFC0392B),
    Color(0xFF27AE60),
  ];

  @override
  void initState() {
    super.initState();
    _classifier = const IndustryClassifier();
    _loadData();
  }

  Future<void> _loadData() async {
    // ── Try backend portfolio analysis first (akshare-powered) ──
    try {
      final funds = widget.holdings.map((h) => {
        'code': h.fundCode,
        'name': h.fundName,
        'cost': h.totalCost,
      }).toList();

      debugPrint('[FundSummary] 尝试后端组合分析... 基金数量: ${funds.length}');
      final analysis = await widget.fundService.fetchPortfolioAnalysis(funds);
      if (analysis != null && mounted) {
        debugPrint('[FundSummary] 后端分析成功，加权持仓: ${analysis['weightedHoldings']?.length ?? 0}条');
        _applyBackendAnalysis(analysis);
        _usingBackendData = true;

        // Supplement missing data with Tencent API
        await _supplementWithTencentQuotes();
        _logIndustryClassificationSources();

        setState(() { _loadingTopHoldings = false; _loadingQuotes = false; });
        return;
      }
      debugPrint('[FundSummary] 后端返回null，降级到客户端抓取');
    } catch (e) {
      debugPrint('[FundSummary] 后端调用异常: $e，降级到客户端抓取');
    }

    // ── Fallback: client-side HTML scraping + Tencent quotes ──
    try {
      final results = await Future.wait(
        widget.holdings.map((h) => widget.fundService
            .fetchTopHoldingsFromHtml(h.fundCode)
            .catchError((_) => <TopHolding>[])),
      );
      if (!mounted) return;

      for (int i = 0; i < widget.holdings.length; i++) {
        _fundTopHoldings[widget.holdings[i].fundCode] = results[i];
      }

      _computeWeightedHoldings();
      setState(() => _loadingTopHoldings = false);

      await _fetchStockQuotes();
      if (mounted) setState(() => _loadingQuotes = false);
    } catch (_) {
      if (mounted) {
        setState(() { _loadingTopHoldings = false; _loadingQuotes = false; });
      }
    }
  }

  /// Populate local state from the backend's portfolio analysis response.
  void _applyBackendAnalysis(Map<String, dynamic> analysis) {
    // 1. Weighted holdings — backend weightedRatio is already a percentage
    final rawHoldings = analysis['weightedHoldings'] as List<dynamic>? ?? [];
    _weightedHoldings = rawHoldings.map((h) {
      final rawPct = (h['weightedRatio'] as num?)?.toDouble() ?? 0;
      return WeightedHolding(
        stockCode: h['stockCode']?.toString() ?? '',
        stockName: h['stockName']?.toString() ?? '',
        weightedRatio: rawPct,
        totalRatio: rawPct,
        fundCodes: (h['fundCodes'] as List<dynamic>?)
            ?.map((e) => e.toString()).toSet() ?? {},
        fundNames: (h['fundNames'] as List<dynamic>?)
            ?.map((e) => e.toString()).toSet() ?? {},
      );
    }).toList();

    // 2. Stock quotes
    _stockQuotes.clear();
    _stockIndustries.clear();
    for (final h in rawHoldings) {
      final code = h['stockCode']?.toString() ?? '';
      if (code.isEmpty) continue;
      final fullCode = _quoteService.toFullCode(code);
      _stockQuotes[fullCode] = StockQuote(
        code: fullCode,
        price: (h['price'] as num?)?.toDouble() ?? 0,
        pe: (h['pe'] as num?)?.toDouble(),
        pb: (h['pb'] as num?)?.toDouble(),
        totalMv: (h['totalMv'] as num?)?.toDouble(),
      );
      final industry = h['industry']?.toString();
      if (industry != null && industry.isNotEmpty && industry != 'None') {
        _stockIndustries[code] = industry;
      }
    }

    // 3. Cache the full backend response
    _backendAnalysis = analysis;

    // 4. Update classifier with backend data
    _classifier = IndustryClassifier(
      usingBackendData: true,
      stockIndustries: Map<String, String>.from(_stockIndustries),
    );
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  void _computeWeightedHoldings() {
    final totalInv = _totalInvestment;
    if (totalInv <= 0) return;

    final map = <String, WeightedHolding>{};
    for (final h in widget.holdings) {
      final weight = h.totalCost / totalInv;
      final holdings = _fundTopHoldings[h.fundCode] ?? [];
      for (final th in holdings) {
        final key = '${th.stockCode}_${th.stockName}';
        final wr = weight * th.ratio;
        if (map.containsKey(key)) {
          map[key] = map[key]!.add(wr, th.ratio, h.fundCode, h.fundName);
        } else {
          map[key] = WeightedHolding(
            stockCode: th.stockCode, stockName: th.stockName,
            weightedRatio: wr, totalRatio: th.ratio,
            fundCodes: {h.fundCode}, fundNames: {h.fundName},
          );
        }
      }
    }

    final list = map.values.toList();
    list.sort((a, b) => b.weightedRatio.compareTo(a.weightedRatio));
    _weightedHoldings = list;
  }

  Future<void> _fetchStockQuotes() async {
    final allCodes = _weightedHoldings.map((w) => w.stockCode).toList();
    if (allCodes.isEmpty) return;
    _stockQuotes = await _quoteService.fetchQuotes(allCodes);
  }

  /// Supplement stocks with missing totalMv/PE/PB from Tencent GTIMG API.
  Future<void> _supplementWithTencentQuotes() async {
    final missingCodes = <String>[];
    for (final wh in _weightedHoldings) {
      final fullCode = _quoteService.toFullCode(wh.stockCode);
      final q = _stockQuotes[fullCode];
      if (q == null || q.totalMv == null || q.pe == null || q.pb == null) {
        missingCodes.add(wh.stockCode);
      }
    }

    if (missingCodes.isEmpty) {
      debugPrint('[FundSummary] 腾讯补全: 所有股票数据完整，无需补充');
      return;
    }

    debugPrint('[FundSummary] 腾讯补全: ${missingCodes.length}只股票缺少数据 → '
        'codes=${missingCodes.join(",")}');
    final tencentQuotes = await _quoteService.fetchQuotes(missingCodes);

    int supplemented = 0;
    int totalMvFilled = 0;
    int peFilled = 0;
    int pbFilled = 0;

    for (final entry in tencentQuotes.entries) {
      final existing = _stockQuotes[entry.key];
      if (existing != null) {
        final hadTotalMv = existing.totalMv != null;
        final hadPe = existing.pe != null;
        final hadPb = existing.pb != null;

        _stockQuotes[entry.key] = StockQuote(
          code: entry.key,
          price: existing.price > 0 ? existing.price : entry.value.price,
          pe: existing.pe ?? entry.value.pe,
          pb: existing.pb ?? entry.value.pb,
          totalMv: existing.totalMv ?? entry.value.totalMv,
        );

        if (!hadTotalMv && entry.value.totalMv != null) totalMvFilled++;
        if (!hadPe && entry.value.pe != null) peFilled++;
        if (!hadPb && entry.value.pb != null) pbFilled++;
        supplemented++;
      } else {
        _stockQuotes[entry.key] = entry.value;
        if (entry.value.totalMv != null) totalMvFilled++;
        if (entry.value.pe != null) peFilled++;
        if (entry.value.pb != null) pbFilled++;
        supplemented++;
      }
    }

    debugPrint('[FundSummary] 腾讯补全完成: $supplemented只已补充 '
        '(totalMv=$totalMvFilled, pe=$peFilled, pb=$pbFilled)');
  }

  /// Log the source tier used for each stock's industry classification.
  void _logIndustryClassificationSources() {
    int akshareCount = 0;
    int hardcodedCount = 0;
    int keywordCount = 0;
    int fallbackCount = 0;

    for (final wh in _weightedHoldings) {
      final code = wh.stockCode;
      final name = wh.stockName;
      final result = _classifier.classify(name, code: code);

      String tier;
      if (_usingBackendData && code.isNotEmpty && _stockIndustries.containsKey(code)) {
        tier = 'akshare';
        akshareCount++;
      } else if (code.isNotEmpty && hardcodedIndustryMap.containsKey(code)) {
        tier = 'hardcoded';
        hardcodedCount++;
      } else if (result == '其他') {
        tier = 'fallback-其他';
        fallbackCount++;
      } else {
        tier = 'keyword';
        keywordCount++;
      }

      debugPrint('[FundSummary] 行业分类: $code($name) → $result [$tier]');
    }

    debugPrint('[FundSummary] 行业分类来源统计: '
        'akshare=$akshareCount, hardcoded=$hardcodedCount, '
        'keyword=$keywordCount, fallback-其他=$fallbackCount, '
        'total=${_weightedHoldings.length}');
  }

  double get _totalInvestment =>
      widget.holdings.fold(0.0, (sum, h) => sum + h.totalCost);
  double get _totalProfit =>
      widget.holdings.fold(0.0, (sum, h) => sum + h.profit);

  // ---------------------------------------------------------------------------
  // Style & industry helpers
  // ---------------------------------------------------------------------------

  /// Asset-weighted style distribution.
  Map<String, double> _calculateStyleDistribution() {
    double largeW = 0, midW = 0, smallW = 0;
    double valueW = 0, growthW = 0, balancedW = 0;
    int missingTotalMv = 0;
    int missingValueStyle = 0;
    int totalStocks = 0;

    for (final wh in _weightedHoldings) {
      final w = wh.weightedRatio;
      if (w <= 0) continue;
      totalStocks++;

      final fullCode = _quoteService.toFullCode(wh.stockCode);
      final q = _stockQuotes[fullCode];

      // Market cap style
      if (q != null && q.totalMv != null) {
        switch (q.marketCapStyle) {
          case '大盘': largeW += w; break;
          case '中盘': midW += w; break;
          case '小盘': smallW += w; break;
        }
      } else {
        missingTotalMv++;
      }

      // Value / Growth style
      String style;
      if (q != null && (q.pe != null || q.pb != null)) {
        style = q.valueStyle;
      } else {
        style = '均衡';
        if (q == null || (q.pe == null && q.pb == null)) missingValueStyle++;
      }
      switch (style) {
        case '价值': valueW += w; break;
        case '成长': growthW += w; break;
        case '均衡': balancedW += w; break;
        default: balancedW += w; break;
      }
    }

    final totalW = largeW + midW + smallW;
    if (totalW <= 0) {
      debugPrint('[FundSummary] 风格分布为空! totalW=0, '
          'totalStocks=$totalStocks, missingTotalMv=$missingTotalMv, '
          'missingValueStyle=$missingValueStyle, '
          'stockQuotesSize=${_stockQuotes.length}');
      return {};
    }

    // Audit logs
    final largeList = <String>[];
    final midList = <String>[];
    final smallList = <String>[];
    for (final wh in _weightedHoldings) {
      final fullCode = _quoteService.toFullCode(wh.stockCode);
      final q = _stockQuotes[fullCode];
      if (q != null && q.totalMv != null) {
        final label = '${wh.stockName}(${wh.stockCode},${q.totalMv!.toStringAsFixed(0)}亿)';
        switch (q.marketCapStyle) {
          case '大盘': largeList.add(label); break;
          case '中盘': midList.add(label); break;
          case '小盘': smallList.add(label); break;
        }
      }
    }
    debugPrint('[FundSummary] 市值分类明细:');
    debugPrint('[FundSummary]   大盘(${largeList.length}只): ${largeList.join(", ")}');
    debugPrint('[FundSummary]   中盘(${midList.length}只): ${midList.join(", ")}');
    debugPrint('[FundSummary]   小盘(${smallList.length}只): ${smallList.join(", ")}');

    final valueList = <String>[];
    final growthList = <String>[];
    final balancedList = <String>[];
    for (final wh in _weightedHoldings) {
      final fullCode = _quoteService.toFullCode(wh.stockCode);
      final q = _stockQuotes[fullCode];
      if (q != null) {
        final peStr = q.pe?.toStringAsFixed(1) ?? '-';
        final pbStr = q.pb?.toStringAsFixed(1) ?? '-';
        final label = '${wh.stockName}(${wh.stockCode},PE=$peStr,PB=$pbStr)';
        if (q.pe == null && q.pb == null) continue;
        switch (q.valueStyle) {
          case '价值': valueList.add(label); break;
          case '成长': growthList.add(label); break;
          case '均衡': balancedList.add(label); break;
        }
      }
    }
    debugPrint('[FundSummary] 价值风格明细:');
    debugPrint('[FundSummary]   价值(${valueList.length}只): ${valueList.join(", ")}');
    debugPrint('[FundSummary]   成长(${growthList.length}只): ${growthList.join(", ")}');
    debugPrint('[FundSummary]   均衡(${balancedList.length}只): ${balancedList.join(", ")}');

    debugPrint('[FundSummary] 风格分布: 覆盖${totalW.toStringAsFixed(2)}权重, '
        'totalStocks=$totalStocks, missingTotalMv=$missingTotalMv, '
        'missingValueStyle=$missingValueStyle');
    return {
      '大盘占比': largeW / totalW, '中盘占比': midW / totalW,
      '小盘占比': smallW / totalW, '价值占比': valueW / totalW,
      '成长占比': growthW / totalW, '均衡占比': balancedW / totalW,
    };
  }

  int _getOverlapStockCount() =>
      _weightedHoldings.where((w) => w.fundCodes.length > 1).length;

  List<MapEntry<String, double>> _getTopIndustries({int count = 3}) {
    final industryMap = <String, double>{};
    for (final wh in _weightedHoldings) {
      final label = _classifier.classify(wh.stockName, code: wh.stockCode);
      industryMap[label] = (industryMap[label] ?? 0) + wh.weightedRatio;
    }
    if (industryMap.isEmpty) return [];
    final sorted = industryMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(count).toList();
  }

  // ---------------------------------------------------------------------------
  // Color helpers
  // ---------------------------------------------------------------------------

  Color _getProfitColor(double value) {
    if (value > 0) return CupertinoColors.systemRed;
    if (value < 0) return CupertinoColors.systemGreen;
    return CupertinoColors.systemGrey;
  }

  Color _chartColor(int index) => _chartColors[index % _chartColors.length];

  // ---------------------------------------------------------------------------
  // Smart summary — neutral, objective, data-driven
  // ---------------------------------------------------------------------------

  String _generateSmartSummary() {
    final dist = _calculateStyleDistribution();
    if (dist.isEmpty || _weightedHoldings.isEmpty) {
      debugPrint('[FundSummary] 智能总结: 风格分布为空或加权持仓为空 → 暂无足够数据');
      return '暂无足够数据进行分析。';
    }

    final large = ((dist['大盘占比'] ?? 0) * 100).round();
    final mid = ((dist['中盘占比'] ?? 0) * 100).round();
    final small = ((dist['小盘占比'] ?? 0) * 100).round();
    final valuePct = ((dist['价值占比'] ?? 0) * 100).round();
    final growthPct = ((dist['成长占比'] ?? 0) * 100).round();
    final balancedPct = ((dist['均衡占比'] ?? 0) * 100).round();

    final topIndustries = _getTopIndustries(count: _topIndustriesCount);
    final fundCount = widget.holdings.length;
    final totalInv = _totalInvestment;
    final buf = StringBuffer();

    // 1. Portfolio overview
    final totalYi = totalInv / 100000000;
    if (totalYi >= 0.01) {
      buf.write('该客户共持有$fundCount只基金（总投入${totalYi.toStringAsFixed(2)}亿），');
    } else {
      buf.write('该客户共持有$fundCount只基金（总投入${(totalInv / 10000).toStringAsFixed(0)}万），');
    }

    // 2. Market cap style with detailed breakdown
    if (large >= mid && large >= small) {
      buf.write('重仓股整体偏向大盘风格（大盘占$large%');
      if (mid > 0) buf.write('，中盘占$mid%');
      if (small > 0) buf.write('，小盘占$small%');
      buf.write('），');
    } else if (mid >= large && mid >= small) {
      buf.write('重仓股以中盘为主（中盘占$mid%');
      if (large > 0) buf.write('，大盘占$large%');
      if (small > 0) buf.write('，小盘占$small%');
      buf.write('），');
    } else {
      buf.write('重仓股偏小盘风格（小盘占$small%');
      if (mid > 0) buf.write('，中盘占$mid%');
      if (large > 0) buf.write('，大盘占$large%');
      buf.write('），');
    }

    // 3. Value / Growth style
    if (growthPct >= 40) {
      buf.write('成长型股票权重较高（$growthPct%），估值水平相对偏高，进攻性较强；');
    } else if (valuePct >= 40) {
      buf.write('价值型股票权重较高（$valuePct%），估值水平相对偏低，防御性较好；');
    } else {
      if (balancedPct > 0) {
        buf.write('成长（$growthPct%）与价值（$valuePct%）风格较为均衡，兼具攻守特性；');
      } else {
        buf.write('成长（$growthPct%）与价值（$valuePct%）风格分布适中；');
      }
    }

    // 4. Top industries
    if (topIndustries.isNotEmpty) {
      final visible = topIndustries.where((e) => e.key != '其他').toList();
      if (visible.isNotEmpty) {
        buf.write('前三大重仓行业为${visible[0].key}（${visible[0].value.toStringAsFixed(1)}%）');
        for (int i = 1; i < visible.length; i++) {
          buf.write('、${visible[i].key}（${visible[i].value.toStringAsFixed(1)}%）');
        }
        buf.write('。');
      } else {
        buf.write('行业分布较为分散。');
      }
    } else {
      buf.write('行业分布较为分散。');
    }

    // 5. Top weighted stocks
    final top3Stocks = _weightedHoldings.take(3).toList();
    if (top3Stocks.isNotEmpty) {
      buf.write('前三大重仓个股为');
      for (int i = 0; i < top3Stocks.length; i++) {
        if (i > 0) buf.write('、');
        buf.write('${top3Stocks[i].stockName}（${top3Stocks[i].weightedRatio.toStringAsFixed(2)}%）');
      }
      buf.write('。');
    }

    // 6. Concentration / overlap assessment
    final overlapCount = _getOverlapStockCount();
    if (overlapCount > 3) {
      buf.write('有$overlapCount只股票被多只基金同时重仓，存在一定的持仓集中风险，建议关注分散度。');
    } else if (overlapCount > 0) {
      buf.write('有$overlapCount只股票被多只基金重仓，持仓重叠度较低，分散性较好。');
    } else {
      buf.write('各基金重仓股无重叠，持仓分散度较高。');
    }

    return buf.toString();
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final isDark = AppConstants.isDark(context);
    final bgColor = isDark ? AppConstants.darkBackground : AppConstants.lightBackground;
    final cardColor = isDark ? AppConstants.darkCardBg : CupertinoColors.white;
    final textColor = isDark ? CupertinoColors.white : CupertinoColors.black;
    final subTextColor = isDark
        ? CupertinoColors.white.withValues(alpha: 0.6)
        : CupertinoColors.systemGrey;
    final surfaceColor = isDark ? AppConstants.darkBackground : AppConstants.lightBackground;

    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 600;
    final pad = isWide ? _sectionPaddingWide : _sectionPaddingNarrow;
    final gap = isWide ? _sectionSpacingWide : _sectionSpacingNarrow;

    return CupertinoPageScaffold(
      backgroundColor: Colors.transparent,
      child: Container(
        color: bgColor,
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
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.all(pad),
                  children: [
                    // Debug: data source indicator
                    if (!_usingBackendData && !_loadingTopHoldings && !_loadingQuotes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('⚠ 后端未连接，使用本地抓取数据',
                          style: TextStyle(fontSize: 10, color: CupertinoColors.systemOrange)),
                      ),

                    // Module 1: Investment pie with integrated profit/loss
                    _buildSectionCard(
                      title: '持仓分析',
                      icon: CupertinoIcons.chart_pie,
                      isDark: isDark, cardColor: cardColor,
                      textColor: textColor, subTextColor: subTextColor,
                      pad: pad,
                      children: [
                        _buildIntegratedPie(isDark, textColor, subTextColor, cardColor),
                      ],
                    ),
                    SizedBox(height: gap),

                    // Module 2: Weighted top holdings
                    _buildSectionCard(
                      title: '重仓统计（前5大重仓股）',
                      icon: CupertinoIcons.star_circle,
                      isDark: isDark, cardColor: cardColor,
                      textColor: textColor, subTextColor: subTextColor,
                      pad: pad,
                      children: [
                        if (_loadingTopHoldings)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CupertinoActivityIndicator()),
                          )
                        else if (_weightedHoldings.isEmpty)
                          Text('暂无重仓股数据', style: TextStyle(fontSize: 13, color: subTextColor))
                        else
                          _buildWeightedHoldingsTable(isDark, textColor, subTextColor),
                      ],
                    ),
                    SizedBox(height: gap),

                    // Module 3: Investment direction
                    _buildSectionCard(
                      title: '投资方向',
                      icon: CupertinoIcons.scope,
                      isDark: isDark, cardColor: cardColor,
                      textColor: textColor, subTextColor: subTextColor,
                      pad: pad,
                      children: [
                        if (_loadingTopHoldings || _loadingQuotes)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CupertinoActivityIndicator()),
                          )
                        else
                          _buildInvestmentDirectionAnalysis(isDark, textColor, subTextColor, surfaceColor, isWide),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Module 1: Investment donut chart with integrated profit/loss per fund
  // ---------------------------------------------------------------------------

  Widget _buildIntegratedPie(bool isDark, Color textColor, Color subTextColor, Color cardColor) {
    final funds = widget.holdings;
    final total = _totalInvestment;
    final totalProfit = _totalProfit;
    if (total <= 0) {
      return _emptySub(title: '持仓分析', textColor: textColor, subTextColor: subTextColor);
    }

    final sections = <PieChartSectionData>[];
    final legendRows = <Widget>[];
    final isWide = MediaQuery.of(context).size.width >= 600;
    final fs = isWide ? 11.0 : 10.0;

    // Sort by investment amount descending
    final sorted = List<FundHolding>.from(funds)
      ..sort((a, b) => b.totalCost.compareTo(a.totalCost));

    for (int i = 0; i < sorted.length; i++) {
      final h = sorted[i];
      final pct = h.totalCost / total * 100;
      if (pct < 0.01) continue;
      final color = _chartColor(i);
      final isTouched = _touchedPieIndex == i;
      final profitColor = _getProfitColor(h.profit);

      sections.add(PieChartSectionData(
        value: h.totalCost, color: color,
        radius: isTouched ? 36 : 28,
        title: '', titleStyle: const TextStyle(fontSize: 0),
        borderSide: isTouched
            ? const BorderSide(color: CupertinoColors.white, width: 2)
            : BorderSide.none,
      ));

      // Fixed-width columns for alignment: amount (L) | pct (L) | profit (R)
      final amountW = isWide ? 70.0 : 62.0;
      final pctW = 44.0;
      final profitW = isWide ? 56.0 : 48.0;

      legendRows.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isTouched ? 4 : 0, vertical: isTouched ? 1 : 0),
          decoration: BoxDecoration(
            color: isTouched ? color.withValues(alpha: 0.12) : const Color(0x00000000),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            Container(
              width: isTouched ? 9 : 7, height: isTouched ? 9 : 7,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text('${h.fundName} (${h.fundCode})',
                style: TextStyle(fontSize: fs,
                  fontWeight: isTouched ? FontWeight.w700 : FontWeight.w400,
                  color: textColor),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: amountW,
              child: Text('¥${h.totalCost.toStringAsFixed(0)}',
                style: TextStyle(fontSize: fs - 1, color: textColor),
                textAlign: TextAlign.left),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: pctW,
              child: Text('${pct.toStringAsFixed(1)}%',
                style: TextStyle(fontSize: fs - 1, color: subTextColor),
                textAlign: TextAlign.left),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: profitW,
              child: Text(
                '${h.profit >= 0 ? '+' : ''}¥${h.profit.toStringAsFixed(0)}',
                style: TextStyle(fontSize: fs - 1, fontWeight: FontWeight.w600, color: profitColor),
                textAlign: TextAlign.right, maxLines: 1,
              ),
            ),
          ]),
        ),
      ));
    }

    final totalColor = _getProfitColor(totalProfit);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('投资金额分布', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
            const SizedBox(height: 2),
            Text('合计 ¥${total.toStringAsFixed(0)}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('总盈亏', style: TextStyle(fontSize: 11, color: subTextColor)),
          Text('${totalProfit >= 0 ? '+' : ''}¥${totalProfit.toStringAsFixed(0)}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: totalColor)),
        ]),
      ]),
      const SizedBox(height: 10),
      // Donut + legend
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 90, height: 90,
          child: Stack(alignment: Alignment.center, children: [
            PieChart(PieChartData(
              sections: sections, centerSpaceRadius: 20, sectionsSpace: 2,
              borderData: FlBorderData(show: false),
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, PieTouchResponse? response) {
                  // Only handle on tap-down to implement toggle behavior.
                  // On mobile: tap segment → highlight, tap same → unhighlight,
                  // tap different → switch, tap outside → clear.
                  if (event is FlTapDownEvent || event is FlLongPressStart) {
                    if (response == null || response.touchedSection == null) {
                      if (_touchedPieIndex != -1) {
                        setState(() => _touchedPieIndex = -1);
                      }
                      return;
                    }
                    final touched = response.touchedSection;
                    if (touched == null) return;
                    final newIndex = touched.touchedSectionIndex;
                    setState(() =>
                        _touchedPieIndex = newIndex == _touchedPieIndex ? -1 : newIndex);
                  }
                },
              ),
            )),
            IgnorePointer(
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: cardColor, shape: BoxShape.circle),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(children: legendRows)),
      ]),
    ]);
  }

  Widget _emptySub({required String title, required Color textColor, required Color subTextColor}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
      const SizedBox(height: 12),
      Text('暂无数据', style: TextStyle(fontSize: 13, color: subTextColor)),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Module 3: Weighted holdings table
  // ---------------------------------------------------------------------------

  Widget _buildWeightedHoldingsTable(bool isDark, Color textColor, Color subTextColor) {
    final top = _weightedHoldings.take(5).toList();
    if (top.isEmpty) return Text('暂无重仓股数据', style: TextStyle(fontSize: 13, color: subTextColor));

    final screenWidth = MediaQuery.of(context).size.width;
    final useTwoCols = screenWidth > 440;
    final left = top.take(3).toList();
    final right = top.skip(3).take(2).toList();

    Widget buildRow(int idx, WeightedHolding wh) {
      final fullCode = _quoteService.toFullCode(wh.stockCode);
      final q = _stockQuotes[fullCode];
      final marketLabel = q?.marketLabel ?? _marketLabelFromCode(wh.stockCode);
      final isTop3 = idx < 3;
      final rankColor = isTop3 ? _chartColor(idx) : subTextColor;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
            width: 18,
            child: Text('${idx + 1}',
              style: TextStyle(
                fontSize: isTop3 ? 11 : 10,
                fontWeight: isTop3 ? FontWeight.w700 : FontWeight.w400,
                color: rankColor,
              )),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text('${wh.stockName} ${wh.stockCode}',
              style: TextStyle(fontSize: 10, color: textColor),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ),
          if (marketLabel.isNotEmpty) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
              decoration: BoxDecoration(
                color: marketLabel == 'HK'
                    ? CupertinoColors.systemOrange.withValues(alpha: 0.15)
                    : CupertinoColors.systemBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(marketLabel, style: TextStyle(fontSize: 7, fontWeight: FontWeight.w600,
                color: marketLabel == 'HK' ? CupertinoColors.systemOrange : CupertinoColors.systemBlue)),
            ),
          ],
          const SizedBox(width: 4),
          SizedBox(width: 42, child: Text('${wh.weightedRatio.toStringAsFixed(2)}%',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
              color: _ratioColor(wh.weightedRatio)),
            textAlign: TextAlign.right,
          )),
          const SizedBox(width: 2),
          SizedBox(width: 24, child: Text('${wh.fundCodes.length}支',
            style: TextStyle(fontSize: 9, color: subTextColor),
            textAlign: TextAlign.right,
          )),
        ]),
      );
    }

    Widget buildColumn(List<WeightedHolding> items, int startIdx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('股票', style: TextStyle(fontSize: 9, color: CupertinoColors.systemGrey)),
        ),
        Container(height: 1, color: CupertinoColors.systemGrey.withValues(alpha: 0.15)),
        ...items.asMap().entries.map((e) => buildRow(startIdx + e.key, e.value)),
      ]);
    }

    if (useTwoCols) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: buildColumn(left, 0)),
        const SizedBox(width: 12),
        Expanded(child: buildColumn(right, 3)),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          SizedBox(width: 20, child: Text('#', style: TextStyle(fontSize: 9, color: subTextColor))),
          const Expanded(child: Text('股票', style: TextStyle(fontSize: 9, color: CupertinoColors.systemGrey))),
          SizedBox(width: 44, child: Text('权重/基金',
            style: TextStyle(fontSize: 9, color: CupertinoColors.systemGrey),
            textAlign: TextAlign.right,
          )),
        ]),
      ),
      Container(height: 1, color: CupertinoColors.systemGrey.withValues(alpha: 0.15)),
      ...top.asMap().entries.map((e) => buildRow(e.key, e.value)),
    ]);
  }

  String _marketLabelFromCode(String code) {
    if (code.length == 5 && RegExp(r'^\d{5}$').hasMatch(code)) return 'HK';
    if (code.startsWith('6')) return '沪A';
    if (code.startsWith('0') || code.startsWith('3') || code.startsWith('5')) return '深A';
    return '';
  }

  Color _ratioColor(double r) {
    if (r >= 5) return CupertinoColors.systemRed;
    if (r >= 2) return AppConstants.warningOrange;
    return CupertinoColors.systemBlue;
  }

  // ---------------------------------------------------------------------------
  // Module 4: Investment direction analysis
  // ---------------------------------------------------------------------------

  Widget _buildInvestmentDirectionAnalysis(bool isDark, Color textColor,
      Color subTextColor, Color surfaceColor, bool isWide) {
    final dist = _calculateStyleDistribution();
    final smartSummary = _generateSmartSummary();
    final overlapCount = _getOverlapStockCount();

    if (_weightedHoldings.isEmpty) {
      return Text('暂无重仓股数据可供分析', style: TextStyle(fontSize: 13, color: subTextColor));
    }

    // Shared font sizes
    final sectionFs = isWide ? 13.0 : 12.0;
    final bodyFs = isWide ? 12.0 : 11.0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Style distribution — compact segmented bar
      if (dist.isNotEmpty) ...[
        Text('风格分布', style: TextStyle(fontSize: sectionFs, fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 8),
        _buildCompactStyleBar(
          label: '市值',
          segments: [
            _StyleSegment('大盘', dist['大盘占比'] ?? 0, CupertinoColors.systemBlue),
            _StyleSegment('中盘', dist['中盘占比'] ?? 0, CupertinoColors.systemOrange),
            _StyleSegment('小盘', dist['小盘占比'] ?? 0, CupertinoColors.systemGreen),
          ],
          isDark: isDark, textColor: textColor, subTextColor: subTextColor, fs: bodyFs,
        ),
        const SizedBox(height: 6),
        _buildCompactStyleBar(
          label: '风格',
          segments: [
            _StyleSegment('价值', dist['价值占比'] ?? 0, const Color(0xFF50C878)),
            _StyleSegment('成长', dist['成长占比'] ?? 0, CupertinoColors.systemRed),
            _StyleSegment('均衡', dist['均衡占比'] ?? 0, const Color(0xFFFFB347)),
          ],
          isDark: isDark, textColor: textColor, subTextColor: subTextColor, fs: bodyFs,
        ),
        const SizedBox(height: 14),
      ],

      // Industry distribution — compact inline with top3 highlighted
      if (_weightedHoldings.isNotEmpty) ...[
        Text('行业分布', style: TextStyle(fontSize: sectionFs, fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 8),
        _buildCompactIndustryDistribution(isDark, textColor, subTextColor, surfaceColor, bodyFs),
        const SizedBox(height: 14),
      ],

      // Overlapping stocks
      if (overlapCount > 0) ...[
        Text('重叠重仓股（被多支基金持有）',
          style: TextStyle(fontSize: sectionFs, fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 6),
        ..._weightedHoldings
            .where((w) => w.fundCodes.length > 1)
            .take(6)
            .map((w) => _buildOverlapItem(w, isDark, textColor, subTextColor)),
        const SizedBox(height: 14),
      ],

      // Summary
      Text('总结', style: TextStyle(fontSize: sectionFs, fontWeight: FontWeight.w600, color: textColor)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(_cardInnerRadius),
        ),
        child: Text(smartSummary,
          style: TextStyle(fontSize: bodyFs, color: textColor, height: 1.5)),
      ),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Compact style bar — label + segments with inline text (connected)
  // ---------------------------------------------------------------------------

  Widget _buildCompactStyleBar({
    required String label,
    required List<_StyleSegment> segments,
    required bool isDark,
    required Color textColor,
    required Color subTextColor,
    required double fs,
  }) {
    final total = segments.fold(0.0, (s, seg) => s + seg.value);
    final active = segments.where((s) => s.value > 0.001).toList();
    if (active.isEmpty) return const SizedBox.shrink();

    return Row(children: [
      SizedBox(
        width: 32,
        child: Text(label, style: TextStyle(fontSize: fs - 1, color: subTextColor)),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            // Minimum width per segment to show text fully (~54px for "大盘 67%")
            const minSegmentWidth = 54.0;

            // Calculate raw pixel widths based on proportion
            final rawWidths = active.map((seg) {
              final fraction = total > 0 ? seg.value / total : 0;
              return fraction * totalWidth;
            }).toList();

            // Ensure each segment has at least minSegmentWidth
            // If any segment needs boosting, reduce from larger segments proportionally
            final adjustedWidths = List<double>.filled(active.length, 0);
            double boostNeeded = 0;
            double reducibleTotal = 0;
            final boolsNeeded = <int>[];
            final reducibleIndices = <int>[];

            for (int i = 0; i < rawWidths.length; i++) {
              if (rawWidths[i] < minSegmentWidth) {
                boostNeeded += minSegmentWidth - rawWidths[i];
                adjustedWidths[i] = minSegmentWidth;
                boolsNeeded.add(i);
              } else {
                reducibleIndices.add(i);
                reducibleTotal += rawWidths[i];
              }
            }

            if (boostNeeded > 0 && reducibleIndices.isNotEmpty) {
              // Reduce from larger segments proportionally
              final availableForReduction = reducibleTotal - reducibleIndices.length * minSegmentWidth;
              if (availableForReduction > 0) {
                final scaleFactor = (reducibleTotal - boostNeeded.clamp(0, availableForReduction)) / reducibleTotal;
                for (final i in reducibleIndices) {
                  adjustedWidths[i] = (rawWidths[i] * scaleFactor).clamp(minSegmentWidth, totalWidth);
                }
              }
            } else if (boostNeeded <= 0) {
              // No boosting needed, use raw widths
              for (int i = 0; i < rawWidths.length; i++) {
                adjustedWidths[i] = rawWidths[i];
              }
            }

            // If total adjusted exceeds totalWidth, scale everything down proportionally
            final adjustedTotal = adjustedWidths.fold(0.0, (s, w) => s + w);
            if (adjustedTotal > totalWidth && totalWidth > 0) {
              final scale = totalWidth / adjustedTotal;
              for (int i = 0; i < adjustedWidths.length; i++) {
                adjustedWidths[i] *= scale;
              }
            }

            final pcts = active.map((seg) => (seg.value * 100).round()).toList();

            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              clipBehavior: Clip.antiAlias,
              child: Container(
                height: 22,
                child: Row(children: List.generate(active.length, (i) {
                  final seg = active[i];
                  return Container(
                    width: adjustedWidths[i].clamp(1, totalWidth),
                    color: seg.color.withValues(alpha: 0.75),
                    alignment: Alignment.center,
                    child: Text(
                      '${seg.label} ${pcts[i]}%',
                      style: TextStyle(
                        fontSize: fs - 2,
                        fontWeight: FontWeight.w600,
                        color: _contrastTextColor(seg.color),
                      ),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  );
                })),
              ),
            );
          },
        ),
      ),
    ]);
  }

  /// Return white or black depending on perceived brightness of [color].
  Color _contrastTextColor(Color color) {
    final luminance = (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
    return luminance > 0.55 ? CupertinoColors.black : CupertinoColors.white;
  }

  // ---------------------------------------------------------------------------
  // Compact industry distribution — top 3 inline highlighted, rest chips
  // ---------------------------------------------------------------------------

  Widget _buildCompactIndustryDistribution(bool isDark, Color textColor,
      Color subTextColor, Color surfaceColor, double fs) {
    final industryMap = <String, double>{};
    for (final wh in _weightedHoldings) {
      final label = _classifier.classify(wh.stockName, code: wh.stockCode);
      industryMap[label] = (industryMap[label] ?? 0) + wh.weightedRatio;
    }
    if (industryMap.isEmpty) return const SizedBox.shrink();

    final sorted = industryMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top3 = sorted.take(_topIndustriesCount).toList();
    final rest = sorted.skip(_topIndustriesCount).take(_maxIndustriesVisible - _topIndustriesCount).toList();
    final totalWeight = _weightedHoldings.fold(0.0, (sum, w) => sum + w.weightedRatio);

    // Merge top3 + rest into a single wrapping flow
    final allItems = <MapEntry<String, double>>[...top3, ...rest];

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: List.generate(allItems.length, (i) {
        final e = allItems[i];
        final pct = totalWeight > 0 ? (e.value / totalWeight * 100) : 0.0;
        final isTop3 = i < _topIndustriesCount;
        const rankMarks = ['❶', '❷', '❸'];

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isTop3 ? 7 : 6,
            vertical: isTop3 ? 4 : 2,
          ),
          decoration: BoxDecoration(
            color: isTop3 ? surfaceColor : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (isTop3) ...[
              Text(rankMarks[i], style: const TextStyle(fontSize: 10)),
              const SizedBox(width: 3),
            ],
            Text(e.key,
              style: TextStyle(
                fontSize: isTop3 ? fs - 1 : fs - 2,
                fontWeight: isTop3 ? FontWeight.w600 : FontWeight.w400,
                color: isTop3 ? textColor : subTextColor,
              )),
            const SizedBox(width: 3),
            Text('${pct.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: isTop3 ? fs - 1 : fs - 2,
                fontWeight: isTop3 ? FontWeight.w600 : FontWeight.w400,
                color: isTop3 ? _chartColor(i) : subTextColor.withValues(alpha: 0.7),
              )),
          ]),
        );
      }),
    );
  }

  Widget _buildOverlapItem(WeightedHolding item, bool isDark, Color textColor, Color subTextColor) {
    final fullCode = _quoteService.toFullCode(item.stockCode);
    final q = _stockQuotes[fullCode];
    final marketLabel = q?.marketLabel ?? _marketLabelFromCode(item.stockCode);
    final surfaceColor = isDark ? AppConstants.darkBackground : AppConstants.lightBackground;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(_cardInnerRadius),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Row(children: [
            Flexible(child: Text('${item.stockName} (${item.stockCode})',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            )),
            if (marketLabel.isNotEmpty) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: marketLabel == 'HK'
                      ? CupertinoColors.systemOrange.withValues(alpha: 0.2)
                      : CupertinoColors.systemBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(marketLabel, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                  color: marketLabel == 'HK' ? CupertinoColors.systemOrange : CupertinoColors.systemBlue)),
              ),
            ],
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: CupertinoColors.systemOrange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('持有基金: ${item.fundCodes.length}支',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500,
                color: CupertinoColors.systemOrange)),
          ),
        ]),
        const SizedBox(height: 3),
        // Fund names colored the same accent as the holding analysis style
        Text.rich(
          TextSpan(
            text: '覆盖基金: ',
            style: TextStyle(fontSize: 11, color: subTextColor),
            children: [
              TextSpan(
                text: item.fundNames.join('、'),
                style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          maxLines: 2, overflow: TextOverflow.ellipsis,
        ),
        if (q != null) ...[
          const SizedBox(height: 3),
          Text('最新价: ${q.price.toStringAsFixed(2)}  '
              'PE: ${q.pe?.toStringAsFixed(2) ?? '-'}  '
              'PB: ${q.pb?.toStringAsFixed(2) ?? '-'}  '
              '市值: ${q.totalMv?.toStringAsFixed(0) ?? '-'}亿',
            style: TextStyle(fontSize: 10, color: subTextColor)),
        ],
      ]),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared section card
  // ---------------------------------------------------------------------------

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required bool isDark,
    required Color cardColor,
    required Color textColor,
    required Color subTextColor,
    required double pad,
    required List<Widget> children,
  }) {
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(_cardBorderRadius),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? CupertinoColors.black.withValues(alpha: 0.2)
                : CupertinoColors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: CupertinoColors.systemBlue),
          const SizedBox(width: 6),
          Text(title,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
        ]),
        SizedBox(height: pad < 14 ? 10 : 14),
        ...children,
      ]),
    );
  }
}

// =============================================================================
// Helpers
// =============================================================================

class _StyleSegment {
  final String label;
  final double value;
  final Color color;
  const _StyleSegment(this.label, this.value, this.color);
}

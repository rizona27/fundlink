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
import 'add_holding_view.dart';

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
  bool _isValuationRefreshing = false;

  final Map<String, Map<String, dynamic>> _valuationCache = {};
  String _lastValuationUpdateTime = '';

  Timer? _valuationTimer;
  bool _isPageVisible = true;

  bool get _hasAnyExpanded => _expandedFundCodes.isNotEmpty;
  bool get _hasData => _dataManager.holdings.isNotEmpty;
  bool get _showValuationRefresh => _sortKey == SortKey.latestNav && _hasData;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dataListener = () {
      if (mounted) setState(() {});
    };
    _loadValuationRefreshInterval();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isPageVisible = true;
      _restartValuationTimer();
    } else if (state == AppLifecycleState.paused) {
      _isPageVisible = false;
      _stopValuationTimer();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _dataManager.removeListener(_dataListener);
    _dataManager.addListener(_dataListener);
    _fundService = FundService(_dataManager);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopValuationTimer();
    _dataManager.removeListener(_dataListener);
    super.dispose();
  }

  @override
  void deactivate() {
    _stopValuationTimer();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    if (_showValuationRefresh) {
      _restartValuationTimer();
    }
  }

  void _startValuationTimer() {
    _stopValuationTimer();
    if (!_showValuationRefresh || !_isPageVisible) return;

    _valuationTimer = Timer.periodic(
      Duration(seconds: _valuationRefreshIntervalSeconds),
          (timer) {
        if (_isPageVisible && mounted && _showValuationRefresh) {
          _onValuationRefresh();
        }
      },
    );
  }

  void _stopValuationTimer() {
    _valuationTimer?.cancel();
    _valuationTimer = null;
  }

  void _restartValuationTimer() {
    if (_showValuationRefresh && _isPageVisible) {
      _startValuationTimer();
    }
  }

  Future<void> _loadValuationRefreshInterval() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seconds = prefs.getInt('valuationRefreshInterval');
      if (seconds != null && [60, 180, 300].contains(seconds)) {
        setState(() {
          _valuationRefreshIntervalSeconds = seconds;
        });
      } else {
        setState(() {
          _valuationRefreshIntervalSeconds = 180;
        });
      }
      _restartValuationTimer();
    } catch (e) {
      setState(() {
        _valuationRefreshIntervalSeconds = 180;
      });
      _restartValuationTimer();
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
      }
    } catch (e) {
    }
    return null;
  }

  Future<void> _onValuationRefresh() async {
    if (_isValuationRefreshing) return;
    setState(() => _isValuationRefreshing = true);

    try {
      final codes = _dataManager.holdings.map((h) => h.fundCode).toList();
      int successCount = 0;
      int failCount = 0;
      final newCache = <String, Map<String, dynamic>>{};
      String latestTime = '';

      for (final code in codes) {
        final valuation = await _fetchSingleValuation(code);
        if (valuation != null) {
          newCache[code] = valuation;
          successCount++;
          if (valuation['gztime'] != null && valuation['gztime'].toString().isNotEmpty) {
            latestTime = valuation['gztime'];
          }
        } else {
          failCount++;
        }
      }

      if (mounted) {
        setState(() {
          _valuationCache.clear();
          _valuationCache.addAll(newCache);
          if (latestTime.isNotEmpty) {
            _lastValuationUpdateTime = _formatGzTime(latestTime);
          }
        });

        if (successCount > 0) {
          context.showToast('估值刷新完成: 成功 $successCount${failCount > 0 ? ', 失败 $failCount' : ''}');
          await _dataManager.addLog('估值刷新完成: 成功 $successCount, 失败 $failCount', type: LogType.success);
        } else if (failCount > 0) {
          context.showToast('估值刷新失败: 全部失败');
          await _dataManager.addLog('估值刷新失败: 全部失败', type: LogType.error);
        }
      }
    } catch (e) {
      if (mounted) {
        context.showToast('估值刷新失败: $e');
        await _dataManager.addLog('估值刷新失败: $e', type: LogType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isValuationRefreshing = false);
      }
    }
  }

  String _formatGzTime(String gztime) {
    if (gztime.isEmpty) return '--';
    try {
      final parts = gztime.split(' ');
      if (parts.length >= 2) {
        final dateParts = parts[0].split('-');
        if (dateParts.length >= 3) {
          return '${dateParts[1]}/${dateParts[2]} ${parts[1].substring(0, 5)}';
        }
      }
    } catch (e) {
    }
    return gztime;
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
    final cache = _valuationCache[holding.fundCode];
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

  List<String> get _sortedFundCodes {
    final codes = _filteredGroupedFunds.keys.toList();
    if (_sortKey == SortKey.none) {
      codes.sort();
      return codes;
    }
    codes.sort((a, b) {
      final fundsA = _filteredGroupedFunds[a]!;
      final fundsB = _filteredGroupedFunds[b]!;

      double? valueA, valueB;
      if (_sortKey == SortKey.latestNav) {
        final cacheA = _valuationCache[a];
        final cacheB = _valuationCache[b];
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
  }

  void _toggleExpand(String fundCode) {
    setState(() {
      if (_expandedFundCodes.contains(fundCode)) {
        _expandedFundCodes.remove(fundCode);
      } else {
        _expandedFundCodes.add(fundCode);
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
    if (holding.purchaseAmount <= 0) return null;
    final profit = _dataManager.calculateProfit(holding);
    return (profit.absolute / holding.purchaseAmount) * 100;
  }

  Color _getReturnColor(double? value) {
    if (value == null) return CupertinoColors.systemGrey;
    if (value > 0) return CupertinoColors.systemRed;
    if (value < 0) return CupertinoColors.systemGreen;
    return CupertinoColors.systemGrey;
  }

  Widget? _buildHoldersListInline(List<FundHolding> holdings, bool isDarkMode) {
    if (_dataManager.isPrivacyMode && _searchText.isEmpty) return null;

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

    return Container(
      margin: const EdgeInsets.only(top: 8),
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final groups = _filteredGroupedFunds;
    final sortedCodes = _sortedFundCodes;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final hasData = _hasData;
    final showHolderCount = !_dataManager.isPrivacyMode;

    final enableButtons = hasData;

    return Container(
      color: backgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            AdaptiveTopBar(
              scrollOffset: 0,
              showBack: false,
              showRefresh: true,       // 放入菜单
              showExpandCollapse: true, // 放入菜单
              showSearch: true,         // 放入菜单
              showReset: false,
              showFilter: false,
              showSort: true,           // 排序按钮单独放在左上角
              isAllExpanded: _hasAnyExpanded,
              searchText: _searchText,
              sortKey: _sortKey,
              sortOrder: _sortOrder,
              sortCycleType: SortCycleType.fundReturns,
              onSortKeyChanged: enableButtons
                  ? (key) {
                setState(() => _sortKey = key);
                _showSortToast();
              }
                  : null,
              onSortOrderChanged: enableButtons
                  ? (order) {
                setState(() => _sortOrder = order);
                _showSortToast();
              }
                  : null,
              dataManager: _dataManager,
              fundService: _fundService,
              onRefresh: _onFundRefresh,
              onLongPressRefresh: _onFundLongPressRefresh,
              showValuationRefresh: _showValuationRefresh,
              valuationRefreshIntervalSeconds: _valuationRefreshIntervalSeconds,
              onValuationRefresh: _onValuationRefresh,
              onValuationRefreshIntervalChanged: _onValuationRefreshIntervalChanged,
              valuationUpdateTime: _lastValuationUpdateTime,
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
              useMenuStyle: true,  // 启用菜单模式
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
                child: ListView.builder(
                  key: ValueKey('list_${_sortKey}_${_sortOrder}_${_searchText}'),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: sortedCodes.length,
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
                        final cache = _valuationCache[fundCode];
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

                    return Column(
                      children: [
                        GradientCard(
                          title: first.fundName,
                          clientId: fundCode,
                          gradient: gradient,
                          isExpanded: isExpanded,
                          onTap: () => _toggleExpand(fundCode),
                          isDarkMode: isDark,
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                          trailing: trailing,
                          maxTitleLength: 6,
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          child: isExpanded
                              ? ClipRect(
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
          ],
        ),
      ),
    );
  }
}
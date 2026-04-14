import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../widgets/empty_state.dart';
import '../widgets/adaptive_top_bar.dart';
import '../widgets/gradient_card.dart';

class SummaryView extends StatefulWidget {
  const SummaryView({super.key});

  @override
  State<SummaryView> createState() => _SummaryViewState();
}

class _SummaryViewState extends State<SummaryView> {
  late DataManager _dataManager;
  late FundService _fundService;
  late VoidCallback _dataListener;

  String _searchText = '';
  final Set<String> _expandedFundCodes = {};

  bool get _isAllExpanded {
    final groups = _filteredGroupedFunds;
    if (groups.isEmpty) return false;
    return _expandedFundCodes.length == groups.length;
  }

  @override
  void initState() {
    super.initState();
    _dataListener = () {
      if (mounted) setState(() {});
    };
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
    _dataManager.removeListener(_dataListener);
    super.dispose();
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
    codes.sort();
    return codes;
  }

  void _toggleExpandAll() {
    setState(() {
      if (_isAllExpanded) {
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

  Color _getGradientStartColor(String fundCode) {
    final hash = fundCode.hashCode.abs();
    final colorList = [
      const Color(0xFF667eea),
      const Color(0xFFf093fb),
      const Color(0xFF4facfe),
      const Color(0xFF43e97b),
      const Color(0xFFfa709a),
      const Color(0xFFfee140),
      const Color(0xFF30cfd0),
      const Color(0xFFa8edea),
    ];
    return colorList[hash % colorList.length];
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

  Widget _buildHoldersListInline(List<FundHolding> holdings) {
    final sorted = List<FundHolding>.from(holdings);
    sorted.sort((a, b) {
      final retA = _calculateHoldingReturn(a) ?? -double.infinity;
      final retB = _calculateHoldingReturn(b) ?? -double.infinity;
      return retB.compareTo(retA);
    });

    final children = <TextSpan>[];
    for (int i = 0; i < sorted.length; i++) {
      final holding = sorted[i];
      final name = _dataManager.obscuredName(holding.clientName);
      final ret = _calculateHoldingReturn(holding);
      final retStr = ret != null ? '${ret >= 0 ? '+' : ''}${ret.toStringAsFixed(2)}%' : '/';
      final retColor = _getReturnColor(ret);

      children.add(TextSpan(
        text: name,
        style: const TextStyle(color: CupertinoColors.label),
      ));
      children.add(TextSpan(
        text: '($retStr)',
        style: TextStyle(color: retColor, fontSize: 12),
      ));
      if (i < sorted.length - 1) {
        children.add(const TextSpan(text: '、'));
      }
    }

    return RichText(
      text: TextSpan(children: children),
    );
  }

  Widget _buildExpandedContent(FundHolding firstHolding, List<FundHolding> holdings) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDarkMode ? Colors.black.withOpacity(0.95) : CupertinoColors.white;

    return Container(
      margin: const EdgeInsets.only(left: 12, top: 8),
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
          Divider(height: 24),
          // 持有客户不换行：放在同一行
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '持有客户：',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.systemGrey,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildHoldersListInline(holdings),
              ),
            ],
          ),
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
            style: const TextStyle(fontSize: 11, color: CupertinoColors.systemGrey),
          ),
          const SizedBox(height: 4),
          Text(
            displayValue,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _filteredGroupedFunds;
    final sortedCodes = _sortedFundCodes;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    return Container(
      color: backgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            AdaptiveTopBar(
              scrollOffset: 0,
              showRefresh: true,
              showExpandCollapse: true,
              showSearch: true,
              showReset: false,
              showFilter: false,
              isAllExpanded: _isAllExpanded,
              searchText: _searchText,
              // 不传 isSearchVisible，让组件内部管理搜索框显隐
              dataManager: _dataManager,
              fundService: _fundService,
              onToggleExpandAll: _toggleExpandAll,
              onSearchChanged: (text) {
                setState(() {
                  _searchText = text;
                });
              },
              onSearchClear: () {
                setState(() {
                  _searchText = '';
                });
              },
              onLongPressRefresh: () {},
              // 与 ClientView 保持一致的样式
              backgroundColor: Colors.transparent,
              iconColor: CupertinoTheme.of(context).primaryColor,
              iconSize: 24,
              buttonSpacing: 12,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            Expanded(
              child: groups.isEmpty
                  ? EmptyState(
                icon: CupertinoIcons.chart_bar,
                title: '暂无基金数据',
                message: _searchText.isEmpty
                    ? '还没有添加任何基金持仓'
                    : '没有找到与“$_searchText”相关的基金，试试其他关键词',
              )
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: sortedCodes.length,
                itemBuilder: (context, index) {
                  final fundCode = sortedCodes[index];
                  final holdings = groups[fundCode]!;
                  final first = holdings.first;
                  final isExpanded = _expandedFundCodes.contains(fundCode);
                  final gradientStart = _getGradientStartColor(fundCode);

                  return Column(
                    children: [
                      GradientCard(
                        title: first.fundName,
                        clientId: fundCode,
                        countValue: holdings.length,
                        gradient: [gradientStart, Colors.transparent],
                        isExpanded: isExpanded,
                        onTap: () => _toggleExpand(fundCode),
                        isDarkMode: isDark,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${holdings.length}支',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              isExpanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                              size: 16,
                              color: isDark ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
                            ),
                          ],
                        ),
                      ),
                      if (isExpanded) _buildExpandedContent(first, holdings),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
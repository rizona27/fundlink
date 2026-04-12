import 'package:flutter/cupertino.dart';
import '../providers/data_manager_provider.dart';
import '../services/data_manager.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../widgets/empty_state.dart';

class SummaryView extends StatefulWidget {
  const SummaryView({super.key});

  @override
  State<SummaryView> createState() => _SummaryViewState();
}

class _SummaryViewState extends State<SummaryView> {
  late DataManager _dataManager;
  String _searchText = '';
  final Set<String> _expandedFunds = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _dataManager.addLog('进入基金汇总页面', type: LogType.info);
  }

  Map<String, List<FundHolding>> get _groupedByFund {
    final map = <String, List<FundHolding>>{};
    for (final holding in _dataManager.holdings) {
      final key = holding.fundCode;
      if (!map.containsKey(key)) {
        map[key] = [];
      }
      map[key]!.add(holding);
    }
    return map;
  }

  Map<String, List<FundHolding>> get _filteredGroupedFunds {
    if (_searchText.isEmpty) return _groupedByFund;

    final filtered = <String, List<FundHolding>>{};
    _groupedByFund.forEach((fundCode, holdings) {
      final first = holdings.first;
      if (fundCode.contains(_searchText) ||
          first.fundName.contains(_searchText)) {
        filtered[fundCode] = holdings;
      }
    });
    return filtered;
  }

  List<String> get _sortedFundCodes {
    final codes = _filteredGroupedFunds.keys.toList();
    codes.sort();
    return codes;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: Text('基金汇总'),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            Expanded(
              child: _filteredGroupedFunds.isEmpty
                  ? const EmptyState(
                icon: CupertinoIcons.chart_bar,
                title: '暂无数据',
                message: '没有找到匹配的基金',
              )
                  : _buildFundsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: CupertinoSearchTextField(
        placeholder: '搜索基金代码或名称',
        onChanged: (value) {
          setState(() {
            _searchText = value;
          });
        },
      ),
    );
  }

  Widget _buildFundsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _sortedFundCodes.length,
      itemBuilder: (context, index) {
        final fundCode = _sortedFundCodes[index];
        final holdings = _filteredGroupedFunds[fundCode]!;
        final firstHolding = holdings.first;
        final isExpanded = _expandedFunds.contains(fundCode);

        return Column(
          children: [
            _buildFundHeader(
              fundCode: fundCode,
              fundName: firstHolding.fundName,
              holderCount: holdings.length,
              isExpanded: isExpanded,
              navReturn1m: firstHolding.navReturn1m,
              navReturn3m: firstHolding.navReturn3m,
              navReturn6m: firstHolding.navReturn6m,
              navReturn1y: firstHolding.navReturn1y,
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedFunds.remove(fundCode);
                  } else {
                    _expandedFunds.add(fundCode);
                  }
                });
              },
            ),
            if (isExpanded)
              _buildHoldersList(holdings),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildFundHeader({
    required String fundCode,
    required String fundName,
    required int holderCount,
    required bool isExpanded,
    required double? navReturn1m,
    required double? navReturn3m,
    required double? navReturn6m,
    required double? navReturn1y,
    required VoidCallback onTap,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey6,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fundName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fundCode,
                        style: const TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$holderCount人持有',
                  style: const TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isExpanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 18,
                  color: CupertinoColors.systemGrey,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildReturnItem('近1月', navReturn1m),
                const SizedBox(width: 16),
                _buildReturnItem('近3月', navReturn3m),
                const SizedBox(width: 16),
                _buildReturnItem('近6月', navReturn6m),
                const SizedBox(width: 16),
                _buildReturnItem('近1年', navReturn1y),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReturnItem(String label, double? value) {
    Color textColor = CupertinoColors.systemGrey;
    if (value != null) {
      textColor = value >= 0
          ? CupertinoColors.systemGreen
          : CupertinoColors.systemRed;
    }

    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: CupertinoColors.systemGrey),
          ),
          const SizedBox(height: 2),
          Text(
            value != null ? '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%' : '--',
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

  Widget _buildHoldersList(List<FundHolding> holdings) {
    final sortedHoldings = List<FundHolding>.from(holdings);
    sortedHoldings.sort((a, b) {
      final profitA = _dataManager.calculateProfit(a);
      final profitB = _dataManager.calculateProfit(b);
      return profitB.absolute.compareTo(profitA.absolute);
    });

    return Container(
      margin: const EdgeInsets.only(top: 8, left: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey5,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sortedHoldings.map((holding) {
          final profit = _dataManager.calculateProfit(holding);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _dataManager.obscuredName(holding.clientName),
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  '收益: ${profit.absolute >= 0 ? '+' : ''}${profit.absolute.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: profit.absolute >= 0
                        ? CupertinoColors.systemGreen
                        : CupertinoColors.systemRed,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
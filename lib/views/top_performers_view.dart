import 'package:flutter/cupertino.dart';
import '../models/fund_holding.dart';
import '../widgets/empty_state.dart';

enum SortType {
  amount,
  profit,
  profitRate,
  days,
}

extension SortTypeExtension on SortType {
  String get label {
    switch (this) {
      case SortType.amount:
        return '金额';
      case SortType.profit:
        return '收益';
      case SortType.profitRate:
        return '收益率';
      case SortType.days:
        return '天数';
    }
  }
}

class TopPerformersView extends StatefulWidget {
  final List<FundHolding> holdings;

  const TopPerformersView({super.key, required this.holdings});

  @override
  State<TopPerformersView> createState() => _TopPerformersViewState();
}

class _TopPerformersViewState extends State<TopPerformersView> {
  SortType _sortType = SortType.profit;
  bool _isAscending = false;

  // 筛选条件
  String _fundCodeFilter = '';
  double? _minAmount;
  double? _maxAmount;
  double? _minProfitRate;
  double? _maxProfitRate;

  bool _showFilter = false;

  // 获取有效的持仓（有净值数据的）
  List<FundHolding> get _validHoldings {
    return widget.holdings.where((h) => h.isValid && h.currentNav > 0).toList();
  }

  // 筛选后的持仓
  List<FundHolding> get _filteredHoldings {
    var result = _validHoldings;

    if (_fundCodeFilter.isNotEmpty) {
      result = result.where((h) =>
      h.fundCode.contains(_fundCodeFilter) ||
          h.fundName.contains(_fundCodeFilter)
      ).toList();
    }

    if (_minAmount != null) {
      result = result.where((h) => h.purchaseAmount >= _minAmount!).toList();
    }

    if (_maxAmount != null) {
      result = result.where((h) => h.purchaseAmount <= _maxAmount!).toList();
    }

    if (_minProfitRate != null) {
      result = result.where((h) => h.annualizedProfitRate >= _minProfitRate!).toList();
    }

    if (_maxProfitRate != null) {
      result = result.where((h) => h.annualizedProfitRate <= _maxProfitRate!).toList();
    }

    return result;
  }

  // 排序后的持仓
  List<FundHolding> get _sortedHoldings {
    final result = List<FundHolding>.from(_filteredHoldings);

    result.sort((a, b) {
      double valueA;
      double valueB;

      switch (_sortType) {
        case SortType.amount:
          valueA = a.purchaseAmount;
          valueB = b.purchaseAmount;
          break;
        case SortType.profit:
          valueA = a.profit;
          valueB = b.profit;
          break;
        case SortType.profitRate:
          valueA = a.annualizedProfitRate;
          valueB = b.annualizedProfitRate;
          break;
        case SortType.days:
          valueA = DateTime.now().difference(a.purchaseDate).inDays.toDouble();
          valueB = DateTime.now().difference(b.purchaseDate).inDays.toDouble();
          break;
      }

      return _isAscending ? valueA.compareTo(valueB) : valueB.compareTo(valueA);
    });

    return result;
  }

  void _resetFilters() {
    setState(() {
      _fundCodeFilter = '';
      _minAmount = null;
      _maxAmount = null;
      _minProfitRate = null;
      _maxProfitRate = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('收益排行'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            setState(() {
              _showFilter = !_showFilter;
            });
          },
          child: Icon(
            _showFilter ? CupertinoIcons.slider_horizontal_3 : CupertinoIcons.slider_horizontal_3,
            size: 22,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_showFilter) _buildFilterBar(),
            _buildSortBar(),
            Expanded(
              child: _sortedHoldings.isEmpty
                  ? const EmptyState(
                icon: CupertinoIcons.star_slash,
                title: '暂无数据',
                message: '没有找到符合条件的持仓',
              )
                  : _buildHoldingsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: CupertinoColors.systemGrey6,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: CupertinoTextField(
                  placeholder: '基金代码/名称',
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onChanged: (value) {
                    setState(() {
                      _fundCodeFilter = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CupertinoTextField(
                  placeholder: '最低金额(万)',
                  keyboardType: TextInputType.number,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onChanged: (value) {
                    setState(() {
                      _minAmount = double.tryParse(value);
                      if (_minAmount != null) _minAmount = _minAmount! * 10000;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CupertinoTextField(
                  placeholder: '最高金额(万)',
                  keyboardType: TextInputType.number,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onChanged: (value) {
                    setState(() {
                      _maxAmount = double.tryParse(value);
                      if (_maxAmount != null) _maxAmount = _maxAmount! * 10000;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: CupertinoTextField(
                  placeholder: '最低收益率(%)',
                  keyboardType: TextInputType.number,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onChanged: (value) {
                    setState(() {
                      _minProfitRate = double.tryParse(value);
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CupertinoTextField(
                  placeholder: '最高收益率(%)',
                  keyboardType: TextInputType.number,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onChanged: (value) {
                    setState(() {
                      _maxProfitRate = double.tryParse(value);
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: CupertinoColors.systemOrange,
                borderRadius: BorderRadius.circular(8),
                onPressed: _resetFilters,
                child: const Text('重置', style: TextStyle(color: CupertinoColors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSortBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: SortType.values.map((type) {
          final isSelected = _sortType == type;
          return CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            borderRadius: BorderRadius.circular(20),
            color: isSelected
                ? CupertinoColors.systemBlue
                : CupertinoColors.systemGrey5,
            onPressed: () {
              setState(() {
                if (_sortType == type) {
                  _isAscending = !_isAscending;
                } else {
                  _sortType = type;
                  _isAscending = false;
                }
              });
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  type.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? CupertinoColors.white : CupertinoColors.black,
                  ),
                ),
                if (isSelected)
                  Icon(
                    _isAscending
                        ? CupertinoIcons.arrow_up
                        : CupertinoIcons.arrow_down,
                    size: 12,
                    color: CupertinoColors.white,
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHoldingsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _sortedHoldings.length,
      itemBuilder: (context, index) {
        final holding = _sortedHoldings[index];
        final days = DateTime.now().difference(holding.purchaseDate).inDays;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey6,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: index < 3
                          ? CupertinoColors.systemYellow
                          : CupertinoColors.systemGrey4,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: index < 3 ? CupertinoColors.black : CupertinoColors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          holding.fundName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${holding.fundCode} | ${holding.clientName}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: CupertinoColors.systemGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildInfoItem('金额', '${(holding.purchaseAmount / 10000).toStringAsFixed(2)}万'),
                  _buildInfoItem('收益', '${holding.profit >= 0 ? '+' : ''}${holding.profit.toStringAsFixed(2)}'),
                  _buildInfoItem('年化收益', '${holding.annualizedProfitRate >= 0 ? '+' : ''}${holding.annualizedProfitRate.toStringAsFixed(2)}%'),
                  _buildInfoItem('持有', '${days}天'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoItem(String label, String value) {
    final isProfit = label == '收益' || label == '年化收益';
    Color? valueColor;
    if (isProfit) {
      final numValue = double.tryParse(value.replaceAll('%', '').replaceAll('+', ''));
      if (numValue != null) {
        valueColor = numValue >= 0
            ? CupertinoColors.systemGreen
            : CupertinoColors.systemRed;
      }
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
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
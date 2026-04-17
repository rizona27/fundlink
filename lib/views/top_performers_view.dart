import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../models/profit_result.dart';
import '../widgets/empty_state.dart';
import '../widgets/adaptive_top_bar.dart';
import '../widgets/gradient_card.dart';
import '../widgets/glass_button.dart';
import '../widgets/toast.dart';
import 'add_holding_view.dart';

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

  IconData get icon {
    switch (this) {
      case SortType.amount:
        return CupertinoIcons.money_dollar;
      case SortType.profit:
        return CupertinoIcons.chart_bar;
      case SortType.profitRate:
        return CupertinoIcons.percent;
      case SortType.days:
        return CupertinoIcons.calendar;
    }
  }

  Color get color {
    switch (this) {
      case SortType.amount:
        return const Color(0xFF4A90D9);
      case SortType.profit:
        return const Color(0xFF50B86C);
      case SortType.profitRate:
        return const Color(0xFFFF9500);
      case SortType.days:
        return const Color(0xFFD46B6B);
    }
  }
}

class TopPerformersView extends StatefulWidget {
  const TopPerformersView({super.key});

  @override
  State<TopPerformersView> createState() => _TopPerformersViewState();
}

class _TopPerformersViewState extends State<TopPerformersView> {
  late DataManager _dataManager;
  late FundService _fundService;
  late VoidCallback _dataListener;

  SortType _sortType = SortType.profit;
  bool _isAscending = false;

  String _searchText = '';
  double? _minAmount;
  double? _maxAmount;
  double? _minProfitRate;
  double? _maxProfitRate;
  double? _minDays;
  double? _maxDays;

  bool _showFilter = false;
  double _scrollOffset = 0;
  Timer? _scrollThrottleTimer;

  List<_RankItem> _cachedItems = [];

  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _dataListener = () {
      if (mounted) {
        _updateCachedItems();
      }
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _fundService = FundService(_dataManager);

    if (!_isInitialized) {
      _dataManager.addListener(_dataListener);
      _isInitialized = true;
      _updateCachedItems();
      _dataManager.addLog('进入收益排行页面', type: LogType.info);
    }
  }

  void _onScrollUpdate(double offset) {
    if (_scrollThrottleTimer != null && _scrollThrottleTimer!.isActive) {
      return;
    }
    _scrollThrottleTimer = Timer(const Duration(milliseconds: 8), () {
      if (mounted && _scrollOffset != offset) {
        setState(() {
          _scrollOffset = offset;
        });
      }
      _scrollThrottleTimer = null;
    });
  }

  @override
  void dispose() {
    _scrollThrottleTimer?.cancel();
    if (_isInitialized) {
      _dataManager.removeListener(_dataListener);
    }
    super.dispose();
  }

  void _updateCachedItems() {
    if (!mounted) return;

    final holdings = _dataManager.holdings;
    final validHoldings = <FundHolding>[];

    for (final h in holdings) {
      if (h.isValid && h.currentNav > 0) {
        validHoldings.add(h);
      }
    }

    var filtered = List<FundHolding>.from(validHoldings);

    if (_searchText.isNotEmpty) {
      final lower = _searchText.toLowerCase();
      filtered = filtered.where((h) {
        final code = h.fundCode.toLowerCase();
        final name = h.fundName.toLowerCase();
        final client = h.clientName.toLowerCase();
        return code.contains(lower) || name.contains(lower) || client.contains(lower);
      }).toList();
    }

    if (_minAmount != null) {
      filtered = filtered.where((h) => h.purchaseAmount >= _minAmount!).toList();
    }

    if (_maxAmount != null) {
      filtered = filtered.where((h) => h.purchaseAmount <= _maxAmount!).toList();
    }

    if (_minProfitRate != null) {
      filtered = filtered.where((h) {
        final profit = _dataManager.calculateProfit(h);
        return profit.annualized >= _minProfitRate!;
      }).toList();
    }

    if (_maxProfitRate != null) {
      filtered = filtered.where((h) {
        final profit = _dataManager.calculateProfit(h);
        return profit.annualized <= _maxProfitRate!;
      }).toList();
    }

    if (_minDays != null) {
      filtered = filtered.where((h) {
        final days = DateTime.now().difference(h.purchaseDate).inDays;
        return days >= _minDays!;
      }).toList();
    }

    if (_maxDays != null) {
      filtered = filtered.where((h) {
        final days = DateTime.now().difference(h.purchaseDate).inDays;
        return days <= _maxDays!;
      }).toList();
    }

    final items = <_RankItem>[];
    for (final holding in filtered) {
      final profit = _dataManager.calculateProfit(holding);
      final days = DateTime.now().difference(holding.purchaseDate).inDays;
      items.add(_RankItem(
        holding: holding,
        profit: profit,
        daysHeld: days,
      ));
    }

    items.sort((a, b) {
      double valueA;
      double valueB;

      switch (_sortType) {
        case SortType.amount:
          valueA = a.holding.purchaseAmount;
          valueB = b.holding.purchaseAmount;
          break;
        case SortType.profit:
          valueA = a.profit.absolute;
          valueB = b.profit.absolute;
          break;
        case SortType.profitRate:
          valueA = a.profit.annualized;
          valueB = b.profit.annualized;
          break;
        case SortType.days:
          valueA = a.daysHeld.toDouble();
          valueB = b.daysHeld.toDouble();
          break;
      }

      return _isAscending ? valueA.compareTo(valueB) : valueB.compareTo(valueA);
    });

    if (mounted) {
      setState(() {
        _cachedItems = items;
      });
    }
  }

  bool get _hasData {
    final holdings = _dataManager.holdings;
    for (final h in holdings) {
      if (h.isValid && h.currentNav > 0) {
        return true;
      }
    }
    return false;
  }

  void _resetFilters() {
    _searchText = '';
    _minAmount = null;
    _maxAmount = null;
    _minProfitRate = null;
    _maxProfitRate = null;
    _minDays = null;
    _maxDays = null;
    _updateCachedItems();
    _dataManager.addLog('重置收益排行筛选条件', type: LogType.info);
    context.showToast('筛选条件已重置');
  }

  void _applyFilters() {
    _updateCachedItems();
    context.showToast('已筛选出 ${_cachedItems.length} 条记录');
    _dataManager.addLog('应用筛选条件，结果数: ${_cachedItems.length}', type: LogType.info);
  }

  void _toggleSort(SortType type) {
    setState(() {
      if (_sortType == type) {
        _isAscending = !_isAscending;
      } else {
        _sortType = type;
        _isAscending = false;
      }
    });
    _updateCachedItems();
    _dataManager.addLog('排序方式切换为: ${type.label}${_isAscending ? "(升序)" : "(降序)"}', type: LogType.info);
  }

  void _toggleFilter() {
    setState(() {
      _showFilter = !_showFilter;
    });
  }

  void _onSearchChanged(String value) {
    _searchText = value;
    _updateCachedItems();
  }

  void _onSearchClear() {
    _searchText = '';
    _updateCachedItems();
  }

  Future<void> _onRefresh() async {
    await _dataManager.refreshAllHoldingsForce(_fundService, null);
    _updateCachedItems();
  }

  Color _getReturnColor(double? value) {
    if (value == null) return CupertinoColors.systemGrey;
    if (value > 0) return const Color(0xFF50B86C);
    if (value < 0) return const Color(0xFFFF5E5E);
    return CupertinoColors.systemGrey;
  }

  List<Color> _getRankGradient(int index) {
    if (index == 0) {
      return [const Color(0xFFFFD700), const Color(0xFFFFB347)];
    } else if (index == 1) {
      return [const Color(0xFFC0C0C0), const Color(0xFFA8A8A8)];
    } else if (index == 2) {
      return [const Color(0xFFCD7F32), const Color(0xFFB8860B)];
    }
    return [const Color(0xFFA8C4E0), CupertinoColors.white];
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const bottomNavBarHeight = 56.0;
    final totalBottomPadding = bottomPadding + bottomNavBarHeight + 20;

    final hasData = _hasData;
    final items = _cachedItems;

    return Container(
      color: backgroundColor,
      child: SafeArea(
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification) {
              _onScrollUpdate(notification.metrics.pixels);
            }
            return false;
          },
          child: Column(
            children: [
              AdaptiveTopBar(
                scrollOffset: _scrollOffset,
                showRefresh: true,
                showExpandCollapse: false,
                showSearch: hasData,
                showReset: false,
                showFilter: hasData,
                showSort: false,
                isAllExpanded: false,
                searchText: _searchText,
                dataManager: _dataManager,
                fundService: _fundService,
                onRefresh: _onRefresh,
                onSearchChanged: hasData ? _onSearchChanged : null,
                onSearchClear: hasData ? _onSearchClear : null,
                backgroundColor: Colors.transparent,
                iconColor: CupertinoTheme.of(context).primaryColor,
                iconSize: 24,
                buttonSpacing: 12,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              if (_showFilter && hasData) _buildFilterBar(isDarkMode),
              Expanded(
                child: !hasData
                    ? EmptyState(
                  icon: CupertinoIcons.star,
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
                    : Column(
                  children: [
                    _buildSortBar(isDarkMode),
                    Expanded(
                      child: items.isEmpty
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.search,
                              size: 48,
                              color: isDarkMode ? CupertinoColors.white.withOpacity(0.3) : CupertinoColors.systemGrey.withOpacity(0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '没有找到匹配的数据',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDarkMode ? CupertinoColors.white.withOpacity(0.5) : CupertinoColors.systemGrey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            GlassButton(
                              label: '重置筛选',
                              onPressed: _resetFilters,
                              isPrimary: false,
                              width: 120,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                          ],
                        ),
                      )
                          : ListView.builder(
                        padding: EdgeInsets.only(
                          left: 12,
                          right: 12,
                          top: 8,
                          bottom: totalBottomPadding,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          return _buildRankCard(items[index], index, isDarkMode);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2C2C2E) : CupertinoColors.white,
        border: Border(
          bottom: BorderSide(
            color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildFilterTextField(
                  placeholder: '金额(万) 最低',
                  onChanged: (value) {
                    _minAmount = double.tryParse(value);
                    if (_minAmount != null) _minAmount = _minAmount! * 10000;
                    _applyFilters();
                  },
                  isDarkMode: isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFilterTextField(
                  placeholder: '金额(万) 最高',
                  onChanged: (value) {
                    _maxAmount = double.tryParse(value);
                    if (_maxAmount != null) _maxAmount = _maxAmount! * 10000;
                    _applyFilters();
                  },
                  isDarkMode: isDarkMode,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildFilterTextField(
                  placeholder: '收益率(%) 最低',
                  onChanged: (value) {
                    _minProfitRate = double.tryParse(value);
                    _applyFilters();
                  },
                  isDarkMode: isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFilterTextField(
                  placeholder: '收益率(%) 最高',
                  onChanged: (value) {
                    _maxProfitRate = double.tryParse(value);
                    _applyFilters();
                  },
                  isDarkMode: isDarkMode,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildFilterTextField(
                  placeholder: '持有天数 最低',
                  onChanged: (value) {
                    _minDays = double.tryParse(value);
                    _applyFilters();
                  },
                  isDarkMode: isDarkMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFilterTextField(
                  placeholder: '持有天数 最高',
                  onChanged: (value) {
                    _maxDays = double.tryParse(value);
                    _applyFilters();
                  },
                  isDarkMode: isDarkMode,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GlassButton(
                label: '重置',
                onPressed: _resetFilters,
                isPrimary: false,
                width: 80,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTextField({
    required String placeholder,
    required Function(String) onChanged,
    required bool isDarkMode,
  }) {
    return CupertinoTextField(
      placeholder: placeholder,
      placeholderStyle: TextStyle(
        fontSize: 13,
        color: isDarkMode ? CupertinoColors.white.withOpacity(0.5) : CupertinoColors.systemGrey,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
        ),
      ),
      style: TextStyle(
        fontSize: 14,
        color: isDarkMode ? CupertinoColors.white : CupertinoColors.black,
      ),
      keyboardType: TextInputType.number,
      onChanged: onChanged,
    );
  }

  Widget _buildSortBar(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        border: Border(
          bottom: BorderSide(
            color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: SortType.values.map((type) {
            final isSelected = _sortType == type;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _toggleSort(type),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(
                      colors: [type.color, type.color.withOpacity(0.7)],
                    )
                        : null,
                    color: isSelected ? null : (isDarkMode ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? Colors.transparent : (isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05)),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        type.icon,
                        size: 14,
                        color: isSelected ? CupertinoColors.white : (isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        type.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected ? CupertinoColors.white : (isDarkMode ? CupertinoColors.white : CupertinoColors.black),
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 4),
                        Icon(
                          _isAscending ? CupertinoIcons.arrow_up : CupertinoIcons.arrow_down,
                          size: 12,
                          color: CupertinoColors.white,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRankCard(_RankItem item, int index, bool isDarkMode) {
    final holding = item.holding;
    final profit = item.profit;
    final days = item.daysHeld;
    final gradient = _getRankGradient(index);
    final isTop3 = index < 3;

    final rankWidget = Container(
      width: 36,
      height: 36,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: isTop3 ? Colors.white.withOpacity(0.3) : (isDarkMode ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: Text(
        '${index + 1}',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: isTop3 ? CupertinoColors.white : (isDarkMode ? CupertinoColors.white : CupertinoColors.black),
        ),
      ),
    );

    final trailingWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${(holding.purchaseAmount / 10000).toStringAsFixed(2)}万',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDarkMode ? CupertinoColors.white : CupertinoColors.black,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '收益: ${profit.absolute >= 0 ? '+' : ''}${profit.absolute.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 12,
            color: _getReturnColor(profit.absolute),
          ),
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          rankWidget,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GradientCard(
                  title: holding.fundName,
                  subtitle: holding.fundCode,
                  gradient: gradient,
                  isExpanded: false,
                  isDarkMode: isDarkMode,
                  onTap: () {},
                  trailing: trailingWidget,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDarkMode ? const Color(0xFF2C2C2E) : CupertinoColors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildInfoChip(
                          label: '年化收益率',
                          value: '${profit.annualized >= 0 ? '+' : ''}${profit.annualized.toStringAsFixed(2)}%',
                          valueColor: _getReturnColor(profit.annualized),
                          isDarkMode: isDarkMode,
                        ),
                        _buildInfoChip(
                          label: '持有天数',
                          value: '$days天',
                          valueColor: null,
                          isDarkMode: isDarkMode,
                        ),
                        _buildInfoChip(
                          label: '客户',
                          value: _dataManager.obscuredName(holding.clientName),
                          valueColor: null,
                          isDarkMode: isDarkMode,
                        ),
                        _buildInfoChip(
                          label: '净值日期',
                          value: _formatDate(holding.navDate),
                          valueColor: null,
                          isDarkMode: isDarkMode,
                        ),
                        _buildInfoChip(
                          label: '当前净值',
                          value: holding.currentNav.toStringAsFixed(4),
                          valueColor: null,
                          isDarkMode: isDarkMode,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required String label,
    required String value,
    Color? valueColor,
    required bool isDarkMode,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              color: isDarkMode ? CupertinoColors.white.withOpacity(0.6) : CupertinoColors.systemGrey,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: valueColor ?? (isDarkMode ? CupertinoColors.white : CupertinoColors.black),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}';
  }
}

class _RankItem {
  final FundHolding holding;
  final ProfitResult profit;
  final int daysHeld;

  _RankItem({
    required this.holding,
    required this.profit,
    required this.daysHeld,
  });
}
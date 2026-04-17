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
import '../widgets/glass_button.dart';
import '../widgets/toast.dart';
import 'add_holding_view.dart';

// 排序字段枚举（与 AdaptiveTopBar 兼容）
enum TopPerformersSortKey {
  none,
  amount,
  profit,
  profitRate,
  days,
}

extension TopPerformersSortKeyExtension on TopPerformersSortKey {
  String get displayName {
    switch (this) {
      case TopPerformersSortKey.none:
        return '无排序';
      case TopPerformersSortKey.amount:
        return '金额';
      case TopPerformersSortKey.profit:
        return '收益';
      case TopPerformersSortKey.profitRate:
        return '收益率';
      case TopPerformersSortKey.days:
        return '天数';
    }
  }

  Color get color {
    switch (this) {
      case TopPerformersSortKey.none:
        return CupertinoColors.systemGrey;
      case TopPerformersSortKey.amount:
        return const Color(0xFF4A90D9);
      case TopPerformersSortKey.profit:
        return const Color(0xFF34C759);
      case TopPerformersSortKey.profitRate:
        return const Color(0xFFFF9500);
      case TopPerformersSortKey.days:
        return const Color(0xFFD46B6B);
    }
  }

  IconData get icon {
    switch (this) {
      case TopPerformersSortKey.none:
        return CupertinoIcons.line_horizontal_3_decrease;
      case TopPerformersSortKey.amount:
        return CupertinoIcons.money_dollar;
      case TopPerformersSortKey.profit:
        return CupertinoIcons.chart_bar;
      case TopPerformersSortKey.profitRate:
        return CupertinoIcons.percent;
      case TopPerformersSortKey.days:
        return CupertinoIcons.calendar;
    }
  }

  TopPerformersSortKey get next {
    switch (this) {
      case TopPerformersSortKey.none:
        return TopPerformersSortKey.amount;
      case TopPerformersSortKey.amount:
        return TopPerformersSortKey.profit;
      case TopPerformersSortKey.profit:
        return TopPerformersSortKey.profitRate;
      case TopPerformersSortKey.profitRate:
        return TopPerformersSortKey.days;
      case TopPerformersSortKey.days:
        return TopPerformersSortKey.none;
    }
  }

  double? getValue(FundHolding holding, ProfitResult profit, int daysHeld) {
    switch (this) {
      case TopPerformersSortKey.amount:
        return holding.purchaseAmount;
      case TopPerformersSortKey.profit:
        return profit.absolute;
      case TopPerformersSortKey.profitRate:
        return profit.annualized;
      case TopPerformersSortKey.days:
        return daysHeld.toDouble();
      case TopPerformersSortKey.none:
        return null;
    }
  }
}

enum TopPerformersSortOrder {
  ascending,
  descending,
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

  TopPerformersSortKey _sortKey = TopPerformersSortKey.none;
  TopPerformersSortOrder _sortOrder = TopPerformersSortOrder.descending;

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

  // 滚动控制器
  final ScrollController _scrollController = ScrollController();

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
    _scrollController.dispose();
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
      if (_sortKey == TopPerformersSortKey.none) {
        return a.holding.fundCode.compareTo(b.holding.fundCode);
      }

      final valueA = _sortKey.getValue(a.holding, a.profit, a.daysHeld);
      final valueB = _sortKey.getValue(b.holding, b.profit, b.daysHeld);

      if (valueA == null && valueB == null) return 0;
      if (valueA == null) return 1;
      if (valueB == null) return -1;

      return _sortOrder == TopPerformersSortOrder.ascending
          ? valueA.compareTo(valueB)
          : valueB.compareTo(valueA);
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

  void _onSortKeyChanged(TopPerformersSortKey key) {
    setState(() {
      if (_sortKey == key) {
        // 同一个排序字段，切换升序/降序
        _sortOrder = _sortOrder == TopPerformersSortOrder.ascending
            ? TopPerformersSortOrder.descending
            : TopPerformersSortOrder.ascending;
      } else {
        // 新排序字段，默认降序
        _sortKey = key;
        _sortOrder = TopPerformersSortOrder.descending;
      }
    });
    _updateCachedItems();
    _dataManager.addLog('排序方式切换为: ${_sortKey.displayName}${_sortOrder == TopPerformersSortOrder.ascending ? "(升序)" : "(降序)"}', type: LogType.info);
  }

  void _onSortOrderChanged(TopPerformersSortOrder order) {
    setState(() {
      _sortOrder = order;
    });
    _updateCachedItems();
    _dataManager.addLog('排序顺序切换为: ${order == TopPerformersSortOrder.ascending ? "升序" : "降序"}', type: LogType.info);
  }

  void _toggleFilter() {
    setState(() {
      _showFilter = !_showFilter;
    });
  }

  Future<void> _onRefresh() async {
    await _dataManager.refreshAllHoldingsForce(_fundService, null);
    _updateCachedItems();
  }

  Color _getValueColor(double? value) {
    if (value == null) return CupertinoColors.systemGrey;
    if (value > 0) return const Color(0xFF34C759);
    if (value < 0) return const Color(0xFFFF3B30);
    return CupertinoColors.systemGrey;
  }

  String _formatAmountInTenThousands(double amount) {
    return '${(amount / 10000).toStringAsFixed(2)}';
  }

  bool _shouldShowDivider(int index) {
    if (_sortKey != TopPerformersSortKey.profitRate && _sortKey != TopPerformersSortKey.profit) {
      return false;
    }

    if (index >= _cachedItems.length - 1) return false;

    final currentProfit = _sortKey == TopPerformersSortKey.profitRate
        ? _cachedItems[index].profit.annualized
        : _cachedItems[index].profit.absolute;
    final nextProfit = _sortKey == TopPerformersSortKey.profitRate
        ? _cachedItems[index + 1].profit.annualized
        : _cachedItems[index + 1].profit.absolute;

    return currentProfit >= 0 && nextProfit < 0;
  }

  // 转换排序类型以兼容 AdaptiveTopBar
  SortKey _convertToAdaptiveSortKey(TopPerformersSortKey key) {
    switch (key) {
      case TopPerformersSortKey.amount:
        return SortKey.navReturn1m; // 复用，实际不使用其值
      case TopPerformersSortKey.profit:
        return SortKey.navReturn3m;
      case TopPerformersSortKey.profitRate:
        return SortKey.navReturn6m;
      case TopPerformersSortKey.days:
        return SortKey.navReturn1y;
      case TopPerformersSortKey.none:
        return SortKey.none;
    }
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
              // 顶部栏（带排序按钮和筛选按钮）
              AdaptiveTopBar(
                scrollOffset: _scrollOffset,
                showRefresh: hasData,  // 有数据时才显示刷新按钮
                showExpandCollapse: false,
                showSearch: false,
                showReset: false,
                showFilter: hasData,
                showSort: hasData,  // 显示排序按钮
                isAllExpanded: false,
                searchText: '',
                sortKey: _convertToAdaptiveSortKey(_sortKey),
                sortOrder: _sortOrder == TopPerformersSortOrder.ascending
                    ? SortOrder.ascending
                    : SortOrder.descending,
                onSortKeyChanged: hasData ? (key) {
                  // 将 SortKey 转换回 TopPerformersSortKey
                  TopPerformersSortKey newKey;
                  switch (key) {
                    case SortKey.navReturn1m:
                      newKey = TopPerformersSortKey.amount;
                      break;
                    case SortKey.navReturn3m:
                      newKey = TopPerformersSortKey.profit;
                      break;
                    case SortKey.navReturn6m:
                      newKey = TopPerformersSortKey.profitRate;
                      break;
                    case SortKey.navReturn1y:
                      newKey = TopPerformersSortKey.days;
                      break;
                    case SortKey.none:
                      newKey = TopPerformersSortKey.none;
                      break;
                  }
                  _onSortKeyChanged(newKey);
                } : null,
                onSortOrderChanged: hasData ? (order) {
                  _onSortOrderChanged(order == SortOrder.ascending
                      ? TopPerformersSortOrder.ascending
                      : TopPerformersSortOrder.descending);
                } : null,
                dataManager: _dataManager,
                fundService: _fundService,
                onRefresh: _onRefresh,
                onFilter: _toggleFilter,
                backgroundColor: Colors.transparent,
                iconColor: CupertinoTheme.of(context).primaryColor,
                iconSize: 24,
                buttonSpacing: 12,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              // 筛选栏（仅在筛选按钮打开时显示，且包含重置按钮）
              if (_showFilter && hasData) _buildFilterBar(isDarkMode),
              // 主内容区
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
                    : items.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.slider_horizontal_3,
                        size: 48,
                        color: isDarkMode
                            ? CupertinoColors.white.withOpacity(0.3)
                            : CupertinoColors.systemGrey.withOpacity(0.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '没有找到匹配的数据',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDarkMode
                              ? CupertinoColors.white.withOpacity(0.5)
                              : CupertinoColors.systemGrey,
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
                    : Column(
                  children: [
                    // 固定表头
                    _buildHeaderRow(isDarkMode),
                    // 可滚动列表
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.only(bottom: totalBottomPadding),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          return _buildHoldingRow(items[index], index, isDarkMode);
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

  Widget _buildHeaderRow(bool isDarkMode) {
    return Container(
      height: 36,
      color: isDarkMode ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey6,
      child: Row(
        children: [
          Expanded(
            flex: 7,
            child: Container(
              alignment: Alignment.center,
              child: const Text(
                '#',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Container(width: 1, color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
          Expanded(
            flex: 20,
            child: Container(
              alignment: Alignment.center,
              child: const Text(
                '代码/名称',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Container(width: 1, color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
          Expanded(
            flex: 14,
            child: Container(
              alignment: Alignment.center,
              child: const Text(
                '金额(万)',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Container(width: 1, color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
          Expanded(
            flex: 14,
            child: Container(
              alignment: Alignment.center,
              child: const Text(
                '收益(万)',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Container(width: 1, color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
          Expanded(
            flex: 10,
            child: Container(
              alignment: Alignment.center,
              child: const Text(
                '天数',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Container(width: 1, color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
          Expanded(
            flex: 16,
            child: Container(
              alignment: Alignment.center,
              child: const Text(
                '收益率(%)',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Container(width: 1, color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
          Expanded(
            flex: 19,
            child: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 8),
              child: const Text(
                '客户',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHoldingRow(_RankItem item, int index, bool isDarkMode) {
    final holding = item.holding;
    final profit = item.profit;
    final days = item.daysHeld;

    // 白灰白灰相间的底色
    final backgroundColor = isDarkMode
        ? (index % 2 == 0
        ? const Color(0xFF1C1C1E)
        : const Color(0xFF2C2C2E))
        : (index % 2 == 0
        ? CupertinoColors.white
        : CupertinoColors.systemGrey6);

    final showDivider = _shouldShowDivider(index);

    return Column(
      children: [
        Container(
          color: backgroundColor,
          child: Row(
            children: [
              Expanded(
                flex: 7,
                child: Container(
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: index < 3 ? FontWeight.bold : FontWeight.normal,
                      color: index < 3
                          ? (isDarkMode ? const Color(0xFFFF9500) : const Color(0xFFFF9500))
                          : (isDarkMode ? CupertinoColors.white : CupertinoColors.black),
                    ),
                  ),
                ),
              ),
              Container(width: 1, color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
              Expanded(
                flex: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        holding.fundCode,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        holding.fundName,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDarkMode ? CupertinoColors.white.withOpacity(0.6) : CupertinoColors.systemGrey,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              Container(width: 1, color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
              Expanded(
                flex: 14,
                child: Container(
                  alignment: Alignment.center,
                  child: Text(
                    _formatAmountInTenThousands(holding.purchaseAmount),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode ? CupertinoColors.white : CupertinoColors.black,
                    ),
                  ),
                ),
              ),
              Container(width: 1, color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
              Expanded(
                flex: 14,
                child: Container(
                  alignment: Alignment.center,
                  child: Text(
                    _formatAmountInTenThousands(profit.absolute),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _getValueColor(profit.absolute),
                    ),
                  ),
                ),
              ),
              Container(width: 1, color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
              Expanded(
                flex: 10,
                child: Container(
                  alignment: Alignment.center,
                  child: Text(
                    '$days',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
                    ),
                  ),
                ),
              ),
              Container(width: 1, color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
              Expanded(
                flex: 16,
                child: Container(
                  alignment: Alignment.center,
                  child: Text(
                    profit.annualized.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getValueColor(profit.annualized),
                    ),
                  ),
                ),
              ),
              Container(width: 1, color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
              Expanded(
                flex: 19,
                child: Container(
                  padding: const EdgeInsets.only(left: 8),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _dataManager.obscuredName(holding.clientName),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDarkMode ? CupertinoColors.white : CupertinoColors.black,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Container(
            height: 2,
            color: isDarkMode ? const Color(0xFFFF3B30).withOpacity(0.3) : const Color(0xFFFF3B30).withOpacity(0.5),
          ),
      ],
    );
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
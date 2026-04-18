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

class TopPerformersView extends StatefulWidget {
  const TopPerformersView({super.key});

  @override
  State<TopPerformersView> createState() => _TopPerformersViewState();
}

class _TopPerformersViewState extends State<TopPerformersView> {
  late DataManager _dataManager;
  late FundService _fundService;
  late VoidCallback _dataListener;

  SortKey _sortKey = SortKey.none;
  SortOrder _sortOrder = SortOrder.descending;

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

    // 排序
    items.sort((a, b) {
      if (_sortKey == SortKey.none) {
        return a.holding.fundCode.compareTo(b.holding.fundCode);
      }

      double? valueA;
      double? valueB;

      switch (_sortKey) {
        case SortKey.amount:
          valueA = a.holding.purchaseAmount;
          valueB = b.holding.purchaseAmount;
          break;
        case SortKey.profit:
          valueA = a.profit.absolute;
          valueB = b.profit.absolute;
          break;
        case SortKey.profitRate:
          valueA = a.profit.annualized;
          valueB = b.profit.annualized;
          break;
        case SortKey.days:
          valueA = a.daysHeld.toDouble();
          valueB = b.daysHeld.toDouble();
          break;
        default:
          return a.holding.fundCode.compareTo(b.holding.fundCode);
      }

      if (valueA == null && valueB == null) return 0;
      if (valueA == null) return 1;
      if (valueB == null) return -1;

      return _sortOrder == SortOrder.ascending
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

  void _onSortKeyChanged(SortKey key) {
    setState(() {
      if (_sortKey == key) {
        _sortOrder = _sortOrder == SortOrder.ascending
            ? SortOrder.descending
            : SortOrder.ascending;
      } else {
        _sortKey = key;
        _sortOrder = SortOrder.descending;
      }
    });
    _updateCachedItems();
    _dataManager.addLog('排序方式切换为: ${key.displayName}${_sortOrder == SortOrder.ascending ? "(升序)" : "(降序)"}', type: LogType.info);
  }

  void _onSortOrderChanged(SortOrder order) {
    setState(() {
      _sortOrder = order;
    });
    _updateCachedItems();
    _dataManager.addLog('排序顺序切换为: ${order == SortOrder.ascending ? "升序" : "降序"}', type: LogType.info);
  }

  void _toggleFilter() {
    setState(() {
      _showFilter = !_showFilter;
    });
  }

  // 正收益红色，负收益绿色，0灰色
  Color _getValueColor(double? value) {
    if (value == null) return CupertinoColors.systemGrey;
    if (value > 0) return const Color(0xFFFF3B30);  // 红色
    if (value < 0) return const Color(0xFF34C759);  // 绿色
    return CupertinoColors.systemGrey;
  }

  String _formatAmountInTenThousands(double amount) {
    return '${(amount / 10000).toStringAsFixed(2)}';
  }

  bool _shouldShowDivider(int index) {
    if (_sortKey != SortKey.profitRate && _sortKey != SortKey.profit) {
      return false;
    }

    if (index >= _cachedItems.length - 1) return false;

    final currentProfit = _sortKey == SortKey.profitRate
        ? _cachedItems[index].profit.annualized
        : _cachedItems[index].profit.absolute;
    final nextProfit = _sortKey == SortKey.profitRate
        ? _cachedItems[index + 1].profit.annualized
        : _cachedItems[index + 1].profit.absolute;

    return currentProfit >= 0 && nextProfit < 0;
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
              // 顶部栏
              AdaptiveTopBar(
                scrollOffset: _scrollOffset,
                showRefresh: false,
                showExpandCollapse: false,
                showSearch: false,
                showReset: false,
                showFilter: hasData,
                showSort: hasData,
                isAllExpanded: false,
                searchText: '',
                sortKey: _sortKey,
                sortOrder: _sortOrder,
                sortCycleType: SortCycleType.holdings,
                onSortKeyChanged: hasData ? _onSortKeyChanged : null,
                onSortOrderChanged: hasData ? _onSortOrderChanged : null,
                dataManager: _dataManager,
                fundService: _fundService,
                onFilter: _toggleFilter,
                backgroundColor: Colors.transparent,
                iconColor: CupertinoTheme.of(context).primaryColor,
                iconSize: 24,
                buttonSpacing: 12,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              // 筛选栏（带淡入淡出动画）
              AnimatedOpacity(
                opacity: _showFilter && hasData ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: _showFilter && hasData ? _buildFilterBar(isDarkMode) : const SizedBox.shrink(),
              ),
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
                    _buildHeaderRow(isDarkMode),
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
              // 重置按钮改为图标形式
              GlassButton(
                label: '',
                icon: CupertinoIcons.refresh_thin,
                onPressed: _resetFilters,
                isPrimary: false,
                width: 44,
                height: 36,
                padding: EdgeInsets.zero,
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
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import '../services/data_manager.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../widgets/gradient_card.dart';
import '../widgets/toast.dart';
import '../widgets/adaptive_top_bar.dart';
import '../widgets/empty_state.dart';
import 'edit_holding_view.dart';

class ManageHoldingsView extends StatefulWidget {
  const ManageHoldingsView({super.key});

  @override
  State<ManageHoldingsView> createState() => _ManageHoldingsViewState();
}

class _ManageHoldingsViewState extends State<ManageHoldingsView> {
  late DataManager _dataManager;

  String _searchText = '';
  final Set<String> _expandedClients = {};
  int _dataVersion = 0;
  double _scrollOffset = 0;
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollThrottleTimer;

  final TextEditingController _renameController = TextEditingController();

  void _onScrollUpdate(double offset) {
    if (_scrollThrottleTimer != null && _scrollThrottleTimer!.isActive) {
      return;
    }
    _scrollThrottleTimer = Timer(const Duration(milliseconds: 16), () {
      if (mounted && _scrollOffset != offset) {
        setState(() {
          _scrollOffset = offset;
        });
      }
      _scrollThrottleTimer = null;
    });
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _dataManager.addListener(_onDataManagerChanged);
  }

  void _onDataManagerChanged() {
    if (mounted) {
      setState(() => _dataVersion++);
    }
  }

  @override
  void dispose() {
    _scrollThrottleTimer?.cancel();
    _dataManager.removeListener(_onDataManagerChanged);
    _renameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Map<String, List<FundHolding>> get _groupedHoldings {
    final map = <String, List<FundHolding>>{};
    for (final holding in _dataManager.holdings) {
      final key = '${holding.clientName}|${holding.clientId}';
      if (!map.containsKey(key)) {
        map[key] = [];
      }
      map[key]!.add(holding);
    }
    return map;
  }

  Map<String, List<FundHolding>> get _filteredGroupedHoldings {
    if (_searchText.isEmpty) return _groupedHoldings;

    final filtered = <String, List<FundHolding>>{};
    _groupedHoldings.forEach((key, holdings) {
      final firstHolding = holdings.first;
      if (firstHolding.clientName.contains(_searchText) ||
          firstHolding.clientId.contains(_searchText) ||
          holdings.any((h) =>
          h.fundCode.contains(_searchText) ||
              h.fundName.contains(_searchText))) {
        filtered[key] = holdings;
      }
    });
    return filtered;
  }

  List<String> get _sortedKeys {
    final keys = _filteredGroupedHoldings.keys.toList();
    keys.sort();
    return keys;
  }

  bool get _areAnyCardsExpanded => _expandedClients.isNotEmpty;

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    
    Future.delayed(const Duration(milliseconds: 400), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _toggleAllCards() {
    setState(() {
      if (_areAnyCardsExpanded) {
        _expandedClients.clear();
      } else {
        _expandedClients.addAll(_sortedKeys);
      }
    });
  }

  String _getDisplayName(String key) {
    final parts = key.split('|');
    final clientName = parts[0];
    final clientId = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;

    final displayName = _dataManager.obscuredName(clientName);
    if (clientId != null && clientId.isNotEmpty) {
      return '$displayName($clientId)';
    }
    return displayName;
  }

  String _getClientName(String key) {
    final parts = key.split('|');
    final clientName = parts[0];
    return _dataManager.obscuredName(clientName);
  }

  String? _getClientId(String key) {
    final parts = key.split('|');
    final clientId = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
    return clientId;
  }

  Color _getClientColor(String name) {
    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = (hash << 5) - hash + name.codeUnitAt(i);
    }
    hash = hash.abs();

    final softColors = [
      const Color(0xFFA8C4E0), const Color(0xFFB8D0C4), const Color(0xFFD4C4A8),
      const Color(0xFFE0B8C4), const Color(0xFFC4B8E0), const Color(0xFFA8D4D4),
      const Color(0xFFE0C8A8), const Color(0xFFC8D4A8), const Color(0xFFD4A8C4),
      const Color(0xFFA8D0E0), const Color(0xFFE0C0B0), const Color(0xFFB0C8E0),
      const Color(0xFFD0B8C8), const Color(0xFFC0D4B0), const Color(0xFFE0D0B0),
    ];

    return softColors[hash % softColors.length];
  }

  Future<void> _renameClient(String oldKey, String newName) async {
    final holdings = _groupedHoldings[oldKey] ?? [];
    for (final holding in holdings) {
      final updated = holding.copyWith(clientName: newName);
      await _dataManager.updateHolding(updated);
    }
    await _dataManager.addLog('批量修改客户名: ${holdings.first.clientName} -> $newName', type: LogType.info);
    context.showToast('已修改 ${holdings.length} 条记录');
  }

  Future<void> _deleteClient(String key) async {
    final holdings = _groupedHoldings[key] ?? [];
    for (final holding in holdings) {
      final index = _dataManager.holdings.indexWhere((h) => h.id == holding.id);
      if (index != -1) {
        await _dataManager.deleteHoldingAt(index);
      }
    }
    await _dataManager.addLog('批量删除客户: ${holdings.first.clientName}', type: LogType.warning);
    context.showToast('已删除 ${holdings.length} 条记录');
  }

  Future<void> _deleteSingleHolding(FundHolding holding) async {
    final index = _dataManager.holdings.indexWhere((h) => h.id == holding.id);
    if (index != -1) {
      await _dataManager.deleteHoldingAt(index);
      context.showToast('已删除 ${holding.fundCode}');
    }
  }

  void _showRenameDialog(String key) {
    final parts = key.split('|');
    final oldName = parts[0];
    _renameController.text = oldName;

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: null,
        content: Container(
          width: 280,
          child: Row(
            children: [
              const Text('批量重命名: '),
              Expanded(
                child: CupertinoTextField(
                  controller: _renameController,
                  placeholder: '请输入新客户姓名',
                  autofocus: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              final newName = _renameController.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                _renameClient(key, newName);
              }
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDeleteClientDialog(String key) {
    final displayName = _getDisplayName(key);
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除客户 "$displayName" 的所有持仓吗？此操作不可撤销。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              _deleteClient(key);
              Navigator.pop(context);
            },
            isDestructiveAction: true,
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showDeleteHoldingDialog(FundHolding holding) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除基金 "${holding.fundName}" 吗？此操作不可撤销。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              _deleteSingleHolding(holding);
              Navigator.pop(context);
            },
            isDestructiveAction: true,
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardBackgroundColor = isDarkMode
        ? CupertinoColors.systemGrey6.withOpacity(0.5)
        : CupertinoColors.white;
    final textColor = isDarkMode ? CupertinoColors.white : CupertinoColors.label;
    final secondaryTextColor = isDarkMode
        ? CupertinoColors.white.withOpacity(0.5)
        : CupertinoColors.systemGrey;

    final hasData = _dataManager.holdings.isNotEmpty;

    return CupertinoPageScaffold(
      backgroundColor: Colors.transparent,
      child: Container(
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
                  showBack: true,
                  onBack: () => Navigator.of(context).pop(),
                  showRefresh: false,
                  showExpandCollapse: hasData,
                  showSearch: hasData,
                  showReset: false,
                  showFilter: false,
                  showSort: false,
                  isAllExpanded: _areAnyCardsExpanded,
                  searchText: _searchText,
                  dataManager: _dataManager,
                  fundService: null,
                  onToggleExpandAll: hasData ? _toggleAllCards : null,
                  onSearchChanged: hasData ? (value) {
                    setState(() {
                      _searchText = value;
                    });
                  } : null,
                  onSearchClear: hasData ? () {
                    setState(() {
                      _searchText = '';
                    });
                  } : null,
                  backgroundColor: Colors.transparent,
                  iconColor: CupertinoTheme.of(context).primaryColor,
                  iconSize: 24,
                  buttonSpacing: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  useMenuStyle: true,
                ),
                Expanded(
                  child: !hasData
                      ? EmptyState(
                    icon: CupertinoIcons.person,
                    title: '暂无持仓数据',
                    message: '',
                    titleFontWeight: FontWeight.normal,
                    titleFontSize: 18,
                  )
                      : CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final key = _sortedKeys[index];
                              final holdings = _filteredGroupedHoldings[key];

                              if (holdings == null || holdings.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              final isExpanded = _expandedClients.contains(key);
                              final gradientColor = _getClientColor(holdings.first.clientName);
                              final gradient = [gradientColor, isDarkMode ? CupertinoColors.systemBackground : CupertinoColors.white];
                              final bool isLastClient = index == _sortedKeys.length - 1;

                              return Column(
                                children: [
                                  GradientCard(
                                    title: _getClientName(key),
                                    clientId: _getClientId(key),
                                    subtitle: '持仓数:',
                                    countValue: holdings.length,
                                    gradient: gradient,
                                    isExpanded: isExpanded,
                                    isDarkMode: isDarkMode,
                                    onTap: () {
                                      setState(() {
                                        if (isExpanded) {
                                          _expandedClients.remove(key);
                                        } else {
                                          _expandedClients.add(key);
                                          
                                          final sortedKeys = _sortedKeys;
                                          if (sortedKeys.isNotEmpty && key == sortedKeys.last) {
                                            Future.delayed(const Duration(milliseconds: 100), () {
                                              _scrollToBottom();
                                            });
                                          }
                                        }
                                      });
                                    },
                                    trailing: isExpanded
                                        ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CupertinoButton(
                                          padding: EdgeInsets.zero,
                                          minSize: 0,
                                          onPressed: () => _showRenameDialog(key),
                                          child: Text('改名', style: TextStyle(fontSize: 12, color: CupertinoColors.activeBlue)),
                                        ),
                                        const SizedBox(width: 12),
                                        CupertinoButton(
                                          padding: EdgeInsets.zero,
                                          minSize: 0,
                                          onPressed: () => _showDeleteClientDialog(key),
                                          child: Text('删除', style: TextStyle(fontSize: 12, color: CupertinoColors.systemRed)),
                                        ),
                                      ],
                                    )
                                        : null,
                                  ),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 400),
                                    curve: Curves.easeOutCubic,
                                    child: isExpanded
                                        ? Container(
                                      margin: const EdgeInsets.only(left: 16, top: 8),
                                      child: Column(
                                        children: holdings.asMap().entries.map((entry) {
                                          final holding = entry.value;
                                          final cardIndex = entry.key;
                                          return RepaintBoundary(
                                            child: Column(
                                              key: ValueKey('holding_${holding.id}'),
                                              children: [
                                                _buildHoldingCard(holding, cardBackgroundColor, textColor, secondaryTextColor, isDarkMode),
                                                if (cardIndex < holdings.length - 1) const SizedBox(height: 4),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    )
                                        : const SizedBox.shrink(),
                                  ),
                                  SizedBox(height: isLastClient ? 0 : 8),
                                ],
                              );
                            },
                            childCount: _sortedKeys.length,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHoldingCard(FundHolding holding, Color cardBackgroundColor, Color textColor, Color secondaryTextColor, bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  holding.fundName,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
                ),
                const SizedBox(height: 2),
                Text(
                  '${holding.fundCode} | ${holding.totalCost.toStringAsFixed(2)}元 | ${holding.totalShares.toStringAsFixed(2)}份',
                  style: TextStyle(fontSize: 11, color: secondaryTextColor),
                ),
                if (holding.remarks.isNotEmpty)
                  Text(
                    '备注: ${holding.remarks}',
                    style: TextStyle(fontSize: 10, color: secondaryTextColor),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                onPressed: () {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (context) => EditHoldingView(holding: holding),
                    ),
                  );
                },
                child: Icon(CupertinoIcons.pencil, size: 18, color: isDarkMode ? CupertinoColors.activeBlue : CupertinoColors.activeBlue),
              ),
              const SizedBox(width: 12),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                onPressed: () => _showDeleteHoldingDialog(holding),
                child: const Icon(CupertinoIcons.trash, size: 18, color: CupertinoColors.systemRed),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
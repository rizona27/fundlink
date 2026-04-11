import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import '../providers/data_manager_provider.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../widgets/toast.dart';
import 'edit_holding_view.dart';

class ManageHoldingsView extends StatefulWidget {
  const ManageHoldingsView({super.key});

  @override
  State<ManageHoldingsView> createState() => _ManageHoldingsViewState();
}

class _ManageHoldingsViewState extends State<ManageHoldingsView> {
  late DataManager _dataManager;
  late FundService _fundService;

  String _searchText = '';
  bool _isSearchVisible = false;
  final Set<String> _expandedClients = {};
  int _dataVersion = 0;

  // 重命名对话框的控制器
  final TextEditingController _renameController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _fundService = FundService(_dataManager);
    _dataManager.addListener(_onDataManagerChanged);
  }

  void _onDataManagerChanged() {
    if (mounted) {
      setState(() => _dataVersion++);
    }
  }

  @override
  void dispose() {
    _dataManager.removeListener(_onDataManagerChanged);
    _renameController.dispose();
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
    if (clientId != null && clientId.isNotEmpty) {
      return '$clientName($clientId)';
    }
    return clientName;
  }

  Color _getClientColor(String key) {
    final parts = key.split('|');
    final name = parts[0];
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

  Color _colorForHoldingCount(int count) {
    if (count == 1) return const Color(0xFFD4A84B);
    if (count <= 3) return const Color(0xFFD4844B);
    return const Color(0xFFD46B6B);
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
        title: const Text('修改客户姓名'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: _renameController,
              placeholder: '新客户姓名',
              autofocus: true,
            ),
          ],
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
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('管理持仓'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.back, size: 24),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _toggleAllCards,
              child: Icon(
                _areAnyCardsExpanded ? CupertinoIcons.arrow_up_doc : CupertinoIcons.arrow_down_doc,
                size: 22,
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                setState(() {
                  _isSearchVisible = !_isSearchVisible;
                  if (!_isSearchVisible) _searchText = '';
                });
              },
              child: Icon(
                _isSearchVisible ? CupertinoIcons.search_circle_fill : CupertinoIcons.search,
                size: 22,
              ),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_isSearchVisible)
              Padding(
                padding: const EdgeInsets.all(12),
                child: CupertinoSearchTextField(
                  placeholder: '搜索客户名、基金代码',
                  onChanged: (value) => setState(() => _searchText = value),
                ),
              ),
            Expanded(
              child: _dataManager.holdings.isEmpty
                  ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.person, size: 50, color: CupertinoColors.systemGrey),
                    SizedBox(height: 12),
                    Text('暂无持仓数据'),
                  ],
                ),
              )
                  : ListView.builder(
                key: ValueKey(_dataVersion),
                padding: const EdgeInsets.all(16),
                itemCount: _sortedKeys.length,
                itemBuilder: (context, index) {
                  final key = _sortedKeys[index];
                  final holdings = _filteredGroupedHoldings[key]!;
                  final isExpanded = _expandedClients.contains(key);
                  final gradientColor = _getClientColor(key);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        // 客户卡片
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedClients.remove(key);
                              } else {
                                _expandedClients.add(key);
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [gradientColor.withOpacity(0.8), Colors.transparent],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: gradientColor.withOpacity(0.25),
                                  blurRadius: 6,
                                  offset: const Offset(3, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _getDisplayName(key),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (!isExpanded)
                                  Row(
                                    children: [
                                      Text(
                                        '持仓数: ',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: CupertinoColors.label.withOpacity(0.5),
                                        ),
                                      ),
                                      Text(
                                        '${holdings.length}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          fontStyle: FontStyle.italic,
                                          color: _colorForHoldingCount(holdings.length),
                                        ),
                                      ),
                                      const Text('支', style: TextStyle(fontSize: 11)),
                                    ],
                                  ),
                                if (isExpanded)
                                  Row(
                                    children: [
                                      CupertinoButton(
                                        padding: EdgeInsets.zero,
                                        minSize: 0,
                                        onPressed: () => _showRenameDialog(key),
                                        child: const Text('改名', style: TextStyle(fontSize: 12)),
                                      ),
                                      const SizedBox(width: 12),
                                      CupertinoButton(
                                        padding: EdgeInsets.zero,
                                        minSize: 0,
                                        onPressed: () => _showDeleteClientDialog(key),
                                        child: const Text('删除', style: TextStyle(fontSize: 12, color: CupertinoColors.systemRed)),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // 展开的持仓列表
                        if (isExpanded)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.only(left: 16, top: 8),
                            child: Column(
                              children: holdings.map((holding) {
                                return _buildHoldingCard(holding);
                              }).toList(),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoldingCard(FundHolding holding) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
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
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${holding.fundCode} | ${holding.purchaseAmount.toStringAsFixed(2)}元 | ${holding.purchaseShares.toStringAsFixed(2)}份',
                  style: const TextStyle(fontSize: 11, color: CupertinoColors.systemGrey),
                ),
                if (holding.remarks.isNotEmpty)
                  Text(
                    '备注: ${holding.remarks}',
                    style: const TextStyle(fontSize: 10, color: CupertinoColors.systemGrey),
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
                child: const Icon(CupertinoIcons.pencil, size: 18),
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
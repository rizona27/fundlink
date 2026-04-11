import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import '../providers/data_manager_provider.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../widgets/gradient_card.dart';
import '../widgets/fund_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/toast.dart';
import '../widgets/refresh_button.dart';

class ClientView extends StatefulWidget {
  const ClientView({super.key});

  @override
  State<ClientView> createState() => _ClientViewState();
}

class _ClientViewState extends State<ClientView> {
  late DataManager _dataManager;
  late FundService _fundService;
  String _searchText = '';
  final Set<String> _expandedClients = {};
  bool _isSearchVisible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _fundService = FundService(_dataManager);

    _dataManager.addListener(_onDataManagerChanged);
    _loadInitialData();
  }

  void _onDataManagerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadInitialData() async {
    if (_dataManager.holdings.isEmpty) {
      await _loadSampleData();
    }
  }

  Future<void> _loadSampleData() async {
    await _dataManager.addLog('加载示例数据', type: LogType.info);

    final sampleHoldings = MockData.getHoldings();
    for (final holding in sampleHoldings) {
      await _dataManager.addHolding(holding);
    }
  }

  Map<String, List<FundHolding>> get _groupedHoldings {
    final map = <String, List<FundHolding>>{};
    for (final holding in _dataManager.holdings) {
      final name = _dataManager.obscuredName(holding.clientName);
      if (!map.containsKey(name)) {
        map[name] = [];
      }
      map[name]!.add(holding);
    }
    return map;
  }

  Map<String, List<FundHolding>> get _filteredGroupedHoldings {
    if (_searchText.isEmpty) return _groupedHoldings;

    final filtered = <String, List<FundHolding>>{};
    _groupedHoldings.forEach((clientName, holdings) {
      if (clientName.contains(_searchText)) {
        filtered[clientName] = holdings;
      } else {
        final matchedHoldings = holdings.where((h) =>
        h.fundCode.contains(_searchText) ||
            h.fundName.contains(_searchText)
        ).toList();
        if (matchedHoldings.isNotEmpty) {
          filtered[clientName] = matchedHoldings;
        }
      }
    });
    return filtered;
  }

  List<String> get _sortedClientNames {
    final names = _filteredGroupedHoldings.keys.toList();
    names.sort((a, b) => a.compareTo(b));
    return names;
  }

  bool get _areAnyCardsExpanded => _expandedClients.isNotEmpty;

  void _expandAll() {
    setState(() {
      _expandedClients.addAll(_sortedClientNames);
    });
  }

  void _collapseAll() {
    setState(() {
      _expandedClients.clear();
    });
  }

  List<Color> _getGradientForName(String name) {
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

    return [softColors[hash % softColors.length], CupertinoColors.white];
  }

  @override
  void dispose() {
    _dataManager.removeListener(_onDataManagerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const SizedBox(),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _areAnyCardsExpanded ? _collapseAll : _expandAll,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  _areAnyCardsExpanded ? CupertinoIcons.arrow_up_doc : CupertinoIcons.arrow_down_doc,
                  key: ValueKey(_areAnyCardsExpanded),
                  size: 22,
                ),
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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: _isSearchVisible
                    ? const Icon(CupertinoIcons.search_circle_fill, size: 24)
                    : const Icon(CupertinoIcons.search, size: 22),
              ),
            ),
          ],
        ),
        trailing: RefreshButton(
          dataManager: _dataManager,
          fundService: _fundService,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: _isSearchVisible ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              firstChild: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: CupertinoColors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: CupertinoSearchTextField(
                  placeholder: '搜索客户名、基金代码',
                  placeholderStyle: const TextStyle(fontSize: 16, color: Color(0xFF8E8E93)),
                  style: const TextStyle(fontSize: 16),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  onChanged: (value) => setState(() => _searchText = value),
                ),
              ),
              secondChild: const SizedBox(height: 0),
            ),
            Expanded(
              child: _filteredGroupedHoldings.isEmpty
                  ? const EmptyState(
                icon: CupertinoIcons.person,
                title: '暂无数据',
                message: '没有找到匹配的客户',
              )
                  : _buildHoldingsList(isDarkMode),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoldingsList(bool isDarkMode) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: _sortedClientNames.length,
      itemBuilder: (context, index) {
        final clientName = _sortedClientNames[index];
        final holdings = _filteredGroupedHoldings[clientName]!;
        final isExpanded = _expandedClients.contains(clientName);
        final gradient = _getGradientForName(clientName);

        return Container(
          key: ValueKey('client_${clientName}_$index'),
          margin: const EdgeInsets.only(bottom: 6),
          child: Column(
            children: [
              GradientCard(
                title: clientName,
                subtitle: '持仓数:',
                countValue: holdings.length,
                gradient: gradient,
                isExpanded: isExpanded,
                isDarkMode: isDarkMode,
                onTap: () => setState(() {
                  if (isExpanded) {
                    _expandedClients.remove(clientName);
                  } else {
                    _expandedClients.add(clientName);
                  }
                }),
              ),
              if (isExpanded)
                Column(
                  children: holdings.map((holding) {
                    return FundCard(
                      key: ValueKey(holding.id),
                      holding: holding,
                      hideClientInfo: true,
                      onCopyClientId: () {
                        _dataManager.addLog('复制客户号: ${holding.clientId}', type: LogType.info);
                        context.showToast('客户号已复制');
                      },
                      onGenerateReport: () {
                        _dataManager.addLog('生成报告: ${holding.clientName} - ${holding.fundName}', type: LogType.info);
                        context.showToast('报告已生成');
                      },
                    );
                  }).toList(),
                ),
            ],
          ),
        );
      },
    );
  }
}
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import '../models/fund_holding.dart';
import '../services/fund_service.dart';
import '../widgets/gradient_card.dart';
import '../widgets/fund_card.dart';
import '../widgets/empty_state.dart';

class ClientView extends StatefulWidget {
  final List<FundHolding> holdings;

  const ClientView({super.key, required this.holdings});

  @override
  State<ClientView> createState() => _ClientViewState();
}

class _ClientViewState extends State<ClientView> {
  late List<FundHolding> _holdings;
  String _searchText = '';
  final Set<String> _expandedClients = {};
  bool _isSearchVisible = false;
  bool _isLoading = true;
  final FundService _fundService = FundService();

  @override
  void initState() {
    super.initState();
    _holdings = List.from(widget.holdings);
    _loadRealFundDataConcurrently();  // 使用并发请求
  }

  // 并发请求所有基金数据
  Future<void> _loadRealFundDataConcurrently() async {
    debugPrint('');
    debugPrint('╔══════════════════════════════════════════════════════════════════╗');
    debugPrint('║ [🚀 ClientView] 开始并发加载真实基金数据                           ║');
    debugPrint('╚══════════════════════════════════════════════════════════════════╝');

    // 创建所有请求的 Future
    final futures = <Future<Map<String, dynamic>>>[];
    for (int i = 0; i < _holdings.length; i++) {
      final holding = _holdings[i];
      debugPrint('📤 发起请求: ${holding.clientName} - ${holding.fundCode}');
      futures.add(_fundService.fetchFundInfo(holding.fundCode));
    }

    // 等待所有请求完成
    final results = await Future.wait(futures);
    debugPrint('📦 所有请求已完成，开始更新UI');

    // 批量更新数据
    if (mounted) {
      setState(() {
        for (int i = 0; i < _holdings.length && i < results.length; i++) {
          final realData = results[i];
          _holdings[i] = _holdings[i].copyWith(
            fundName: realData['fundName'] as String,
            currentNav: realData['currentNav'] as double,
            navDate: realData['navDate'] as DateTime,
            isValid: realData['isValid'] as bool,
          );
          debugPrint('✅ 更新成功: ${_holdings[i].clientName} - ${_holdings[i].fundName} (净值: ${_holdings[i].currentNav})');
        }
        _isLoading = false;
      });
    }

    debugPrint('');
    debugPrint('╔══════════════════════════════════════════════════════════════════╗');
    debugPrint('║ [✅ ClientView] 所有基金数据加载完成                               ║');
    debugPrint('╚══════════════════════════════════════════════════════════════════╝');
  }

  Map<String, List<FundHolding>> get _groupedHoldings {
    final map = <String, List<FundHolding>>{};
    for (final holding in _holdings) {
      if (!map.containsKey(holding.clientName)) {
        map[holding.clientName] = [];
      }
      map[holding.clientName]!.add(holding);
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
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const SizedBox(),
        leading: CupertinoButton(
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
        trailing: CupertinoButton(
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
                  placeholder: '搜索客户名',
                  placeholderStyle: const TextStyle(fontSize: 16, color: Color(0xFF8E8E93)),
                  style: const TextStyle(fontSize: 16),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  onChanged: (value) => setState(() => _searchText = value),
                ),
              ),
              secondChild: const SizedBox(height: 0),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CupertinoActivityIndicator(radius: 20),
                    SizedBox(height: 16),
                    Text('正在加载基金净值数据...'),
                  ],
                ),
              )
                  : _filteredGroupedHoldings.isEmpty
                  ? const EmptyState(icon: CupertinoIcons.person, title: '暂无数据', message: '没有找到匹配的客户')
                  : _buildHoldingsList(isDarkMode),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoldingsList(bool isDarkMode) {
    return CupertinoScrollbar(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: _sortedClientNames.length,
        itemBuilder: (context, index) {
          final clientName = _sortedClientNames[index];
          final holdings = _filteredGroupedHoldings[clientName]!;
          final isExpanded = _expandedClients.contains(clientName);
          final gradient = _getGradientForName(clientName);

          return Column(
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
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                margin: EdgeInsets.only(left: isExpanded ? 16 : 0),
                height: isExpanded ? null : 0,
                child: isExpanded
                    ? Column(
                  children: holdings.map((holding) {
                    return FundCard(
                      holding: holding,
                      hideClientInfo: true,
                      onCopyClientId: () {
                        debugPrint('复制客户号: ${holding.clientId}');
                      },
                      onGenerateReport: () {
                        debugPrint('生成报告: ${holding.clientName} - ${holding.fundName}');
                      },
                    );
                  }).toList(),
                )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 6),
            ],
          );
        },
      ),
    );
  }
}
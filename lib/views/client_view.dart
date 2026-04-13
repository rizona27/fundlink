import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
// 修改：合并 provider 后直接导入 data_manager
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../widgets/gradient_card.dart';
import '../widgets/fund_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/toast.dart';
import '../widgets/refresh_button.dart';

// 封装的搜索组件（支持清空）
class SearchHeader extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const SearchHeader({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 1))],
      ),
      child: CupertinoSearchTextField(
        controller: controller,
        focusNode: focusNode,
        placeholder: '搜索客户名、客户号、基金代码、基金名称',
        placeholderStyle: const TextStyle(fontSize: 16, color: Color(0xFF8E8E93)),
        style: const TextStyle(fontSize: 16),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        onChanged: onChanged,
        onSuffixTap: () {
          controller.clear();
          onClear();
        },
      ),
    );
  }
}

class ClientView extends StatefulWidget {
  const ClientView({super.key});

  @override
  State<ClientView> createState() => _ClientViewState();
}

class _ClientViewState extends State<ClientView> with SingleTickerProviderStateMixin {
  late DataManager _dataManager;
  late FundService _fundService;
  String _searchText = '';
  final Set<String> _expandedClients = {};
  bool _isSearchVisible = false;
  bool _isPinnedSectionExpanded = true;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  late AnimationController _topBarController;
  Timer? _scrollTimer;
  double _lastTargetProgress = 1.0;
  double _currentScrollOffset = 0;
  bool _searchVisibleBeforeScroll = false;
  String _searchTextBeforeScroll = '';

  bool _autoFixTriggered = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _topBarController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this)..value = 1.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndFixGarbledFundNames();
    });
  }

  Future<void> _checkAndFixGarbledFundNames() async {
    if (_autoFixTriggered) return;
    await Future.delayed(const Duration(milliseconds: 500));
    bool hasGarbled = false;
    for (final holding in _dataManager.holdings) {
      final name = holding.fundName;
      if (name.contains('�') || name.contains('\\ufffd') || name.isEmpty || name == '加载失败') {
        hasGarbled = true;
        break;
      }
    }
    if (hasGarbled && mounted) {
      _autoFixTriggered = true;
      context.showToast('检测到乱码，正在自动修复...', duration: const Duration(seconds: 2));
      await _dataManager.refreshAllHoldingsForce(_fundService, null);
      if (mounted) {
        setState(() {});
        context.showToast('修复完成');
      }
    }
  }

  void _handleScroll(double offset) {
    _currentScrollOffset = offset;
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(milliseconds: 16), () {
      if (!mounted) return;

      if (_searchText.isNotEmpty) {
        if (!_isSearchVisible) {
          setState(() => _isSearchVisible = true);
        }
        return;
      }

      double rawProgress = 1.0 - (_currentScrollOffset / 100).clamp(0.0, 1.0);
      double targetProgress = Curves.easeOutCubic.transform(rawProgress);
      if ((targetProgress - _lastTargetProgress).abs() > 0.01) {
        _lastTargetProgress = targetProgress;
        _topBarController.animateTo(targetProgress, duration: const Duration(milliseconds: 150));
      }

      if (targetProgress < 0.3 && _topBarController.value > 0.3) {
        _searchVisibleBeforeScroll = _isSearchVisible;
        _searchTextBeforeScroll = _searchText;
      }

      if (targetProgress < 0.05 && _isSearchVisible && _searchText.isEmpty && !_searchFocusNode.hasFocus) {
        setState(() => _isSearchVisible = false);
      }

      if (targetProgress > 0.5 && _topBarController.value < 0.5) {
        if (_searchTextBeforeScroll.isNotEmpty) {
          setState(() => _isSearchVisible = _searchVisibleBeforeScroll);
        }
      }
    });
  }

  void _toggleSearch() => setState(() {
    _isSearchVisible = !_isSearchVisible;
    if (!_isSearchVisible) {
      _searchText = '';
      _searchController.clear();
      _cancelDebounce();
    }
  });

  void _cancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  void _onSearchChanged(String value) {
    if (value.isNotEmpty && !_isSearchVisible) {
      setState(() => _isSearchVisible = true);
    }
    _cancelDebounce();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchText = value;
        });
      }
    });
  }

  void _onSearchClear() {
    _cancelDebounce();
    setState(() {
      _searchText = '';
      _searchController.clear();
    });
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _topBarController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _cancelDebounce();
    _dataManager.removeListener(_onDataManagerChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 修改：使用 DataManagerProvider.of 但导入已改为 data_manager.dart
    _dataManager = DataManagerProvider.of(context);
    _fundService = FundService(_dataManager);
    _dataManager.addListener(_onDataManagerChanged);
  }

  void _onDataManagerChanged() => setState(() {});

  List<FundHolding> get _filteredHoldings {
    if (_searchText.isEmpty) return _dataManager.holdings;
    final lower = _searchText.toLowerCase();
    return _dataManager.holdings.where((h) {
      return h.clientName.toLowerCase().contains(lower) ||
          h.clientId.toLowerCase().contains(lower) ||
          h.fundCode.toLowerCase().contains(lower) ||
          h.fundName.toLowerCase().contains(lower);
    }).toList();
  }

  List<FundHolding> get _filteredPinnedHoldings {
    return _filteredHoldings.where((h) => h.isPinned).toList();
  }

  Map<String, List<FundHolding>> get _groupedHoldings {
    final map = <String, List<FundHolding>>{};
    for (final holding in _filteredHoldings) {
      final name = _dataManager.obscuredName(holding.clientName);
      map.putIfAbsent(name, () => []).add(holding);
    }
    return map;
  }

  List<String> get _sortedClientNames {
    final names = _groupedHoldings.keys.toList();
    names.sort();
    return names;
  }

  bool get _areAnyCardsExpanded => _expandedClients.isNotEmpty;
  void _expandAll() => setState(() => _expandedClients.addAll(_sortedClientNames));
  void _collapseAll() => setState(() => _expandedClients.clear());

  List<Color> _getGradientForOriginalName(String originalName) {
    int hash = 0;
    for (int i = 0; i < originalName.length; i++) hash = (hash << 5) - hash + originalName.codeUnitAt(i);
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

  List<Widget> _buildPinnedCards() {
    final pinned = _filteredPinnedHoldings;
    return [
      for (int i = 0; i < pinned.length; i++)
        Column(children: [
          FundCard(
            key: ValueKey('pinned_${pinned[i].id}'),
            holding: pinned[i],
            hideClientInfo: true,
            onCopyClientId: () {
              _dataManager.addLog('复制客户号: ${pinned[i].clientId}', type: LogType.info);
              context.showToast('客户号已复制');
            },
            onGenerateReport: () => _dataManager.addLog('生成报告: ${pinned[i].clientName} - ${pinned[i].fundName}', type: LogType.info),
            onShowToast: context.showToast,
            onPinToggle: () => _dataManager.togglePinStatus(pinned[i].id),
          ),
          if (i < pinned.length - 1) const SizedBox(height: 8),
        ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const bottomNavBarHeight = 56.0;
    final totalBottomPadding = bottomPadding + bottomNavBarHeight + 20;

    final hasPinned = _filteredPinnedHoldings.isNotEmpty;
    final hasGroups = _groupedHoldings.isNotEmpty;

    return Container(
      color: backgroundColor,
      child: SafeArea(
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification) _handleScroll(notification.metrics.pixels);
            return false;
          },
          child: AnimatedBuilder(
            animation: _topBarController,
            builder: (context, _) {
              final progress = _topBarController.value;
              return Column(
                children: [
                  Container(
                    height: 52 * progress,
                    child: Opacity(
                      opacity: progress,
                      child: Transform.scale(
                        scale: 0.8 + progress * 0.2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              RefreshButton(dataManager: _dataManager, fundService: _fundService),
                              const Spacer(),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: _areAnyCardsExpanded ? _collapseAll : _expandAll,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(_areAnyCardsExpanded ? CupertinoIcons.arrow_up_doc : CupertinoIcons.arrow_down_doc,
                                      key: ValueKey(_areAnyCardsExpanded), size: 22),
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: _toggleSearch,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  child: _isSearchVisible ? const Icon(CupertinoIcons.search_circle_fill, size: 24) : const Icon(CupertinoIcons.search, size: 22),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: progress,
                    child: Container(
                      height: _isSearchVisible ? 52 * progress : 0,
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: AnimatedCrossFade(
                          duration: const Duration(milliseconds: 200),
                          crossFadeState: _isSearchVisible ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                          firstChild: SearchHeader(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            onChanged: _onSearchChanged,
                            onClear: _onSearchClear,
                          ),
                          secondChild: const SizedBox(height: 0),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: (!hasPinned && !hasGroups)
                        ? const EmptyState(icon: CupertinoIcons.person, title: '暂无数据', message: '没有找到匹配的客户')
                        : ListView(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, totalBottomPadding),
                      children: [
                        if (hasPinned) ...[
                          GradientCard(
                            title: '置顶',
                            subtitle: '数量:',
                            countValue: _filteredPinnedHoldings.length,
                            gradient: const [Color(0xFFFF9500), Color(0xFFFFB347)],
                            isExpanded: _isPinnedSectionExpanded,
                            isDarkMode: isDarkMode,
                            onTap: () => setState(() => _isPinnedSectionExpanded = !_isPinnedSectionExpanded),
                          ),
                          const SizedBox(height: 8),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                            child: _isPinnedSectionExpanded ? Column(children: _buildPinnedCards()) : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (hasGroups) ...[
                          ..._buildClientGroups(),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildClientGroups() {
    final groups = <Widget>[];
    for (int i = 0; i < _sortedClientNames.length; i++) {
      final name = _sortedClientNames[i];
      final holdings = _groupedHoldings[name];
      if (holdings == null || holdings.isEmpty) continue;
      final isExpanded = _expandedClients.contains(name);
      final gradient = _getGradientForOriginalName(holdings.first.clientName);
      groups.add(
        Container(
          key: ValueKey('client_$name'),
          margin: EdgeInsets.only(bottom: i == _sortedClientNames.length - 1 ? 0 : 8),
          child: Column(
            children: [
              GradientCard(
                title: name,
                clientId: holdings.first.clientId,   // 新增：传入客户号
                subtitle: '持仓数:',
                countValue: holdings.length,
                gradient: gradient,
                isExpanded: isExpanded,
                isDarkMode: CupertinoTheme.brightnessOf(context) == Brightness.dark,
                onTap: () => setState(() => isExpanded ? _expandedClients.remove(name) : _expandedClients.add(name)),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                child: isExpanded
                    ? Container(
                  margin: const EdgeInsets.only(left: 16, top: 8),
                  child: Column(children: _buildAnimatedFundCards(holdings)),
                )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return groups;
  }

  List<Widget> _buildAnimatedFundCards(List<FundHolding> holdings) {
    final cards = <Widget>[];
    for (int i = 0; i < holdings.length; i++) {
      final holding = holdings[i];
      cards.add(
        _FadeInWidget(
          key: ValueKey('fade_${holding.id}'),
          delay: Duration(milliseconds: 100 + i * 80),
          duration: const Duration(milliseconds: 400),
          child: FundCard(
            key: ValueKey('card_${holding.id}'),
            holding: holding,
            hideClientInfo: true,
            onCopyClientId: () {
              _dataManager.addLog('复制客户号: ${holding.clientId}', type: LogType.info);
              context.showToast('客户号已复制');
            },
            onGenerateReport: () => _dataManager.addLog('生成报告: ${holding.clientName} - ${holding.fundName}', type: LogType.info),
            onShowToast: context.showToast,
            onPinToggle: () => _dataManager.togglePinStatus(holding.id),
          ),
        ),
      );
      if (i < holdings.length - 1) cards.add(const SizedBox(height: 8));
    }
    if (holdings.isNotEmpty) cards.add(const SizedBox(height: 8));
    return cards;
  }
}

class _FadeInWidget extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  const _FadeInWidget({super.key, required this.child, required this.delay, required this.duration});

  @override
  State<_FadeInWidget> createState() => _FadeInWidgetState();
}

class _FadeInWidgetState extends State<_FadeInWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);
    _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    Future.delayed(widget.delay, () { if (mounted) _controller.forward(); });
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacityAnimation, child: SlideTransition(position: _slideAnimation, child: widget.child));
  }
}
import 'dart:async';
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

class _ClientViewState extends State<ClientView> with SingleTickerProviderStateMixin {
  late DataManager _dataManager;
  late FundService _fundService;
  String _searchText = '';
  final Set<String> _expandedClients = {};
  bool _isSearchVisible = false;

  late AnimationController _topBarController;
  Timer? _scrollTimer;
  double _lastTargetProgress = 1.0;
  double _currentScrollOffset = 0;

  bool _searchVisibleBeforeScroll = false;
  String _searchTextBeforeScroll = '';

  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _topBarController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    )..value = 1.0;
  }

  void _handleScroll(double offset) {
    _currentScrollOffset = offset;
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(milliseconds: 16), () {
      if (!mounted) return;

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
        setState(() {
          _isSearchVisible = false;
        });
      }

      if (targetProgress > 0.5 && _topBarController.value < 0.5) {
        if (_searchTextBeforeScroll.isNotEmpty) {
          setState(() {
            _isSearchVisible = _searchVisibleBeforeScroll;
          });
        }
      }
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearchVisible = !_isSearchVisible;
      if (!_isSearchVisible) {
        _searchText = '';
      }
    });
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchText = value;
    });
    if (value.isNotEmpty && !_isSearchVisible) {
      setState(() {
        _isSearchVisible = true;
      });
    }
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _topBarController.dispose();
    _searchFocusNode.dispose();
    _dataManager.removeListener(_onDataManagerChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _fundService = FundService(_dataManager);
    _dataManager.addListener(_onDataManagerChanged);
    // 移除自动加载示例数据的调用，应用启动时保持空白
    // _loadInitialData();
  }

  void _onDataManagerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // 删除或注释掉 _loadInitialData 和 _loadSampleData 方法
  // 如需保留，可保留但不再调用，或者直接删除以下代码块

  /*
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
  */

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

  List<Color> _getGradientForOriginalName(String originalName) {
    int hash = 0;
    for (int i = 0; i < originalName.length; i++) {
      hash = (hash << 5) - hash + originalName.codeUnitAt(i);
    }
    hash = hash.abs();
    final softColors = <Color>[
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
    final backgroundColor = isDarkMode
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF2F2F7);

    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const bottomNavBarHeight = 56.0;
    final totalBottomPadding = bottomPadding + bottomNavBarHeight + 20;

    return Container(
      color: backgroundColor,
      child: SafeArea(
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification) {
              _handleScroll(notification.metrics.pixels);
            }
            return false;
          },
          child: AnimatedBuilder(
            animation: _topBarController,
            builder: (context, child) {
              final progress = _topBarController.value;
              final opacity = progress;
              final height = 52.0 * progress;
              final scale = 0.8 + (progress * 0.2);

              return Column(
                children: [
                  Container(
                    height: height,
                    child: Opacity(
                      opacity: opacity,
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              RefreshButton(
                                dataManager: _dataManager,
                                fundService: _fundService,
                              ),
                              const Spacer(),
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
                                onPressed: _toggleSearch,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  child: _isSearchVisible
                                      ? const Icon(CupertinoIcons.search_circle_fill, size: 24)
                                      : const Icon(CupertinoIcons.search, size: 22),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: opacity,
                    child: Container(
                      height: _isSearchVisible ? (52.0 * progress) : 0,
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: AnimatedCrossFade(
                          duration: const Duration(milliseconds: 200),
                          crossFadeState: _isSearchVisible ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                          firstChild: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: CupertinoColors.white,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 6,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: CupertinoSearchTextField(
                              focusNode: _searchFocusNode,
                              placeholder: '搜索客户名、基金代码',
                              placeholderStyle: const TextStyle(fontSize: 16, color: Color(0xFF8E8E93)),
                              style: const TextStyle(fontSize: 16),
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              onChanged: _onSearchChanged,
                            ),
                          ),
                          secondChild: const SizedBox(height: 0),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _filteredGroupedHoldings.isEmpty
                        ? const EmptyState(
                      icon: CupertinoIcons.person,
                      title: '暂无数据',
                      message: '没有找到匹配的客户',
                    )
                        : ListView.builder(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, totalBottomPadding),
                      itemCount: _sortedClientNames.length,
                      itemBuilder: (context, index) {
                        final obscuredName = _sortedClientNames[index];
                        final holdings = _filteredGroupedHoldings[obscuredName];
                        if (holdings == null || holdings.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        final isExpanded = _expandedClients.contains(obscuredName);
                        final originalClientName = holdings.first.clientName;
                        final gradient = _getGradientForOriginalName(originalClientName);
                        final bool isLastClient = index == _sortedClientNames.length - 1;
                        return Container(
                          key: ValueKey('client_${obscuredName}_$index'),
                          margin: EdgeInsets.only(bottom: isLastClient ? 0 : 8),
                          child: Column(
                            children: [
                              GradientCard(
                                title: obscuredName,
                                subtitle: '持仓数:',
                                countValue: holdings.length,
                                gradient: gradient,
                                isExpanded: isExpanded,
                                isDarkMode: isDarkMode,
                                onTap: () => setState(() {
                                  if (isExpanded) {
                                    _expandedClients.remove(obscuredName);
                                  } else {
                                    _expandedClients.add(obscuredName);
                                  }
                                }),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeOutCubic,
                                child: isExpanded
                                    ? Container(
                                  margin: const EdgeInsets.only(left: 16, top: 8),
                                  child: Column(
                                    children: _buildAnimatedFundCards(holdings),
                                  ),
                                )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        );
                      },
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

  List<Widget> _buildAnimatedFundCards(List<FundHolding> holdings) {
    final cards = <Widget>[];
    for (int i = 0; i < holdings.length; i++) {
      final holding = holdings[i];
      final delay = Duration(milliseconds: 100 + (i * 80));
      cards.add(
        _FadeInWidget(
          key: ValueKey('fade_${holding.id}'),
          delay: delay,
          duration: const Duration(milliseconds: 400),
          child: FundCard(
            key: ValueKey('card_${holding.id}'),
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
          ),
        ),
      );
      if (i < holdings.length - 1) {
        cards.add(const SizedBox(height: 8));
      }
    }
    if (holdings.isNotEmpty) {
      cards.add(const SizedBox(height: 8));
    }
    return cards;
  }
}

class _FadeInWidget extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  const _FadeInWidget({
    super.key,
    required this.child,
    required this.delay,
    required this.duration,
  });

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
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    Future.delayed(widget.delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacityAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}
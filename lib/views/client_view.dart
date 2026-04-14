import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../widgets/gradient_card.dart';
import '../widgets/fund_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/toast.dart';
import '../widgets/adaptive_top_bar.dart';
import '../widgets/glass_button.dart';
import 'add_holding_view.dart';

class ClientView extends StatefulWidget {
  const ClientView({super.key});

  @override
  State<ClientView> createState() => _ClientViewState();
}

class _ClientViewState extends State<ClientView> with TickerProviderStateMixin {
  late DataManager _dataManager;
  late FundService _fundService;
  String _searchText = '';
  final Set<String> _expandedClients = {};
  bool _isPinnedSectionExpanded = false;
  double _scrollOffset = 0;
  bool _autoFixTriggered = false;
  Timer? _debounceTimer;
  Timer? _scrollThrottleTimer;
  late AnimationController _scrollAnimationController;

  @override
  void initState() {
    super.initState();
    _scrollAnimationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
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
    _debounceTimer?.cancel();
    _scrollAnimationController.dispose();
    _dataManager.removeListener(_onDataManagerChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
          Container(
            margin: const EdgeInsets.only(left: 16),
            child: _FadeInWidget(
              key: ValueKey('fade_pinned_${pinned[i].id}'),
              delay: Duration(milliseconds: 100 + i * 80),
              duration: const Duration(milliseconds: 400),
              child: FundCard(
                key: ValueKey('pinned_${pinned[i].id}'),
                holding: pinned[i],
                hideClientInfo: false,
                onCopyClientId: () {
                  _dataManager.addLog('复制客户号: ${pinned[i].clientId}', type: LogType.info);
                  context.showToast('客户号已复制');
                },
                onGenerateReport: () => _dataManager.addLog('生成报告: ${pinned[i].clientName} - ${pinned[i].fundName}', type: LogType.info),
                onShowToast: context.showToast,
                onPinToggle: () => _dataManager.togglePinStatus(pinned[i].id),
              ),
            ),
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
    final hasData = hasPinned || hasGroups;
    final enableButtons = hasData; // 无数据时禁用搜索和折叠按钮

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
                showExpandCollapse: enableButtons,
                showSearch: enableButtons,
                showReset: false,
                showFilter: false,
                showSort: false,
                isAllExpanded: _areAnyCardsExpanded,
                searchText: _searchText,
                dataManager: _dataManager,
                fundService: _fundService,
                onToggleExpandAll: enableButtons
                    ? () {
                  setState(() {
                    if (_areAnyCardsExpanded) {
                      _collapseAll();
                    } else {
                      _expandAll();
                    }
                  });
                }
                    : null,
                onSearchChanged: enableButtons
                    ? (value) {
                  setState(() {
                    _searchText = value;
                  });
                }
                    : null,
                onSearchClear: enableButtons
                    ? () {
                  setState(() {
                    _searchText = '';
                  });
                }
                    : null,
                backgroundColor: Colors.transparent,
                iconColor: CupertinoTheme.of(context).primaryColor,
                iconSize: 24,
                buttonSpacing: 12,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              Expanded(
                child: !hasData
                    ? EmptyState(
                  icon: CupertinoIcons.person,
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
                        child: _isPinnedSectionExpanded
                            ? Column(children: _buildPinnedCards())
                            : const SizedBox.shrink(),
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
        RepaintBoundary(
          key: ValueKey('repaint_$name'),
          child: Container(
            key: ValueKey('client_$name'),
            margin: EdgeInsets.only(bottom: i == _sortedClientNames.length - 1 ? 0 : 8),
            child: Column(
              children: [
                GradientCard(
                  title: name,
                  clientId: holdings.first.clientId,
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
        RepaintBoundary(
          key: ValueKey('repaint_${holding.id}'),
          child: _FadeInWidget(
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
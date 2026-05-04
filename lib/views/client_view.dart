import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:pinyin/pinyin.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../services/ui_state_service.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../widgets/gradient_card.dart';
import '../widgets/fund_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/toast.dart';
import '../widgets/adaptive_top_bar.dart';
import '../widgets/glass_button.dart';
import '../utils/animation_config.dart';
import 'add_holding_view.dart';
import '../constants/app_constants.dart';

class _ClientGroup {
  final String key;
  final String displayName;
  final String clientId;
  final List<FundHolding> holdings;

  _ClientGroup({
    required this.key,
    required this.displayName,
    required this.clientId,
    required this.holdings,
  });
}

class ClientView extends StatefulWidget {
  const ClientView({super.key});

  @override
  State<ClientView> createState() => _ClientViewState();
}

class _ClientViewState extends State<ClientView> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late DataManager _dataManager;
  late FundService _fundService;
  String _searchText = '';
  final Set<String> _expandedClients = {};
  bool _isPinnedSectionExpanded = false;
  double _scrollOffset = 0;
  bool _autoFixTriggered = false;
  DateTime? _lastAutoFixTime;
  Timer? _debounceTimer;
  Timer? _scrollThrottleTimer;
  late AnimationController _scrollAnimationController;
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  static const String _keyPinnedSectionExpanded = AppConstants.keyPinnedSectionExpanded;

  @override
  void initState() {
    super.initState();
    _scrollAnimationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _loadState(); 
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndFixGarbledFundNames();
    });
  }

  Future<void> _loadState() async {
    try {
      final uiState = UIStateService();
      final pinnedExpanded = await uiState.getBool(_keyPinnedSectionExpanded);
      if (pinnedExpanded != null) {
        _isPinnedSectionExpanded = pinnedExpanded;
      }
    } catch (e) {
      debugPrint('加载UI状态失败: $e');
    }
  }

  Future<void> _saveState() async {
    try {
      final uiState = UIStateService();
      await uiState.saveBool(_keyPinnedSectionExpanded, _isPinnedSectionExpanded);
    } catch (e) {
      debugPrint('保存UI状态失败: $e');
    }
  }

  Future<void> _checkAndFixGarbledFundNames() async {
    if (_autoFixTriggered) return;
      
    if (_lastAutoFixTime != null && 
        DateTime.now().difference(_lastAutoFixTime!).inMinutes < 5) {
      return;
    }
      
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
  
    bool hasGarbled = false;
    for (final holding in _dataManager.holdings) {
      final name = holding.fundName;
      if (name.contains('') || name.contains('\ufffd')) {
        hasGarbled = true;
        break;
      }
    }
      
    if (hasGarbled && mounted) {
      _autoFixTriggered = true;
      _lastAutoFixTime = DateTime.now();
      try {
        await _dataManager.refreshAllHoldingsForce(_fundService, null);
        if (mounted) {
          setState(() {});
        }
      } catch (e) {
      }
    }
  }

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
  void dispose() {
    _scrollThrottleTimer?.cancel();
    _debounceTimer?.cancel();
    _scrollAnimationController.dispose();
    _scrollController.dispose();
    _dataManager.removeListener(_onDataManagerChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _fundService = FundService(_dataManager);
    _dataManager.addListener(_onDataManagerChanged);
    
    Future.microtask(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _onDataManagerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

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

  List<_ClientGroup> get _clientGroups {
    final map = <String, _ClientGroup>{};
    for (final holding in _filteredHoldings) {
      final key = holding.clientId.isNotEmpty ? holding.clientId : holding.clientName;

      if (!map.containsKey(key)) {
        map[key] = _ClientGroup(
          key: key,
          displayName: _dataManager.obscuredName(holding.clientName),
          clientId: holding.clientId,
          holdings: [],
        );
      }
      map[key]!.holdings.add(holding);
    }

    var groups = map.values.toList();
    groups.sort((a, b) {
      final originalNameA = _filteredHoldings.firstWhere(
        (h) => (h.clientId.isNotEmpty ? h.clientId : h.clientName) == a.key,
        orElse: () => a.holdings.first,
      ).clientName;
      
      final originalNameB = _filteredHoldings.firstWhere(
        (h) => (h.clientId.isNotEmpty ? h.clientId : h.clientName) == b.key,
        orElse: () => b.holdings.first,
      ).clientName;
      
      String pinyinA = '';
      if (originalNameA.isNotEmpty) {
        try {
          final firstCharPinyin = PinyinHelper.getPinyinE(originalNameA[0]);
          pinyinA = firstCharPinyin.isNotEmpty ? firstCharPinyin[0].toUpperCase() : '';
        } catch (e) {
          pinyinA = originalNameA[0];
        }
      }
      
      String pinyinB = '';
      if (originalNameB.isNotEmpty) {
        try {
          final firstCharPinyin = PinyinHelper.getPinyinE(originalNameB[0]);
          pinyinB = firstCharPinyin.isNotEmpty ? firstCharPinyin[0].toUpperCase() : '';
        } catch (e) {
          pinyinB = originalNameB[0];
        }
      }
      
      return pinyinA.compareTo(pinyinB);
    });
    return groups;
  }

  bool get _areAnyCardsExpanded => _expandedClients.isNotEmpty;

  void _expandAll() {
    setState(() {
      _expandedClients.addAll(_clientGroups.map((g) => g.key));
    });
  }

  void _collapseAll() {
    setState(() {
      _expandedClients.clear();
    });
  }

  void _toggleClientExpand(String clientKey) {
    setState(() {
      if (_expandedClients.contains(clientKey)) {
        _expandedClients.remove(clientKey);
      } else {
        _expandedClients.add(clientKey);
      }
    });
  }

  void _togglePinnedSection() {
    setState(() {
      _isPinnedSectionExpanded = !_isPinnedSectionExpanded;
    });
    _saveState(); 
  }

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
    final mainColor = softColors[hash % softColors.length];
    return [mainColor, mainColor.withOpacity(0.3)];
  }

  Color _colorForHoldingCount(int count) {
    if (count == 1) return const Color(0xFFD4A84B);
    if (count <= 3) return const Color(0xFFD4844B);
    return const Color(0xFFD46B6B);
  }

  List<Widget> _buildPinnedCards() {
    final pinned = _filteredPinnedHoldings;
    return [
      for (int i = 0; i < pinned.length; i++)
        Column(children: [
          Container(
            margin: const EdgeInsets.only(left: 16),
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
          if (i < pinned.length - 1) const SizedBox(height: 8),
        ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const bottomNavBarHeight = 56.0;
    final totalBottomPadding = bottomPadding + bottomNavBarHeight + 20;

    final hasPinned = _filteredPinnedHoldings.isNotEmpty;
    final groups = _clientGroups;
    final hasGroups = groups.isNotEmpty;
    final hasData = hasPinned || hasGroups;
    final enableButtons = hasData;

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
                showBack: false,
                showRefresh: true,
                showExpandCollapse: true,
                showSearch: true,
                showReset: false,
                showFilter: false,
                showSort: false,
                isAllExpanded: _areAnyCardsExpanded,
                searchText: _searchText,
                dataManager: _dataManager,
                fundService: _fundService,
                onRefresh: () async {
                  await _dataManager.refreshAllHoldingsForce(_fundService, null);
                  if (mounted) {
                    setState(() {});
                    context.showToast('刷新完成');
                  }
                },
                onLongPressRefresh: () async {
                  await _dataManager.refreshAllHoldingsForce(_fundService, null);
                  if (mounted) {
                    setState(() {});
                    context.showToast('强制刷新完成');
                  }
                },
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
                useMenuStyle: true,
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
                    : CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.only(
                        left: 12,
                        right: 12,
                        top: 8,
                        bottom: totalBottomPadding,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (hasPinned && index == 0) {
                              return Column(
                                children: [
                                  GradientCard(
                                    title: '置顶',
                                    gradient: const [Color(0xFFFF9500), Color(0xFFFFB347)],
                                    isExpanded: _isPinnedSectionExpanded,
                                    isDarkMode: isDarkMode,
                                    onTap: _togglePinnedSection,
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '数量: ',
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.2,
                                            color: isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
                                          ),
                                        ),
                                        Text(
                                          '${_filteredPinnedHoldings.length}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            fontStyle: FontStyle.italic,
                                            height: 1.2,
                                            color: _colorForHoldingCount(_filteredPinnedHoldings.length),
                                          ),
                                        ),
                                        Text(
                                          '支',
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.2,
                                            color: isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  AnimationConfig.listExpandTransition(
                                    isExpanded: _isPinnedSectionExpanded,
                                    child: Column(
                                      children: [
                                        const SizedBox(height: 8),
                                        ..._buildPinnedCards(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              );
                            }
                            
                            final groupIndex = hasPinned ? index - 1 : index;
                            if (groupIndex >= 0 && groupIndex < groups.length) {
                              return _buildClientGroupWidget(groups[groupIndex], isDarkMode);
                            }
                            
                            return const SizedBox.shrink();
                          },
                          childCount: (hasPinned ? 1 : 0) + groups.length,
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
    );
  }

  List<Widget> _buildClientGroups(List<_ClientGroup> groups) {
    final result = <Widget>[];
    for (int i = 0; i < groups.length; i++) {
      final group = groups[i];
      final isExpanded = _expandedClients.contains(group.key);
      final gradient = _getGradientForOriginalName(group.holdings.first.clientName);
      final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;

      final trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '持仓数: ',
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              color: isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
            ),
          ),
          Text(
            '${group.holdings.length}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
              height: 1.2,
              color: _colorForHoldingCount(group.holdings.length),
            ),
          ),
          Text(
            '支',
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              color: isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
            ),
          ),
        ],
      );

      result.add(
        RepaintBoundary(
          key: ValueKey('repaint_${group.key}'),
          child: Container(
            key: ValueKey('client_${group.key}'),
            margin: EdgeInsets.only(bottom: i == groups.length - 1 ? 0 : 8),
            child: Column(
              children: [
                GradientCard(
                  title: group.displayName,
                  clientId: group.clientId.isNotEmpty ? group.clientId : null,
                  gradient: gradient,
                  isExpanded: isExpanded,
                  isDarkMode: isDarkMode,
                  onTap: () {
                    final wasExpanded = _expandedClients.contains(group.key);
                    _toggleClientExpand(group.key);
                    
                    if (!wasExpanded) {
                      final groups = _clientGroups;
                      if (groups.isNotEmpty && group.key == groups.last.key) {
                        Future.delayed(const Duration(milliseconds: 100), () {
                          _scrollToBottom();
                        });
                      }
                    }
                  },
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  trailing: trailing,
                  maxTitleLength: 10,
                ),
                AnimationConfig.listExpandTransition(
                  isExpanded: isExpanded,
                  child: Container(
                    margin: const EdgeInsets.only(left: 16, top: 8), 
                    child: Column(children: _buildFundCards(group.holdings)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return result;
  }

  Widget _buildClientGroupWidget(_ClientGroup group, bool isDarkMode) {
    final isExpanded = _expandedClients.contains(group.key);
    final gradient = _getGradientForOriginalName(group.holdings.first.clientName);

    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '持仓数: ',
          style: TextStyle(
            fontSize: 12,
            height: 1.2,
            color: isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
          ),
        ),
        Text(
          '${group.holdings.length}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontStyle: FontStyle.italic,
            height: 1.2,
            color: _colorForHoldingCount(group.holdings.length),
          ),
        ),
        Text(
          '支',
          style: TextStyle(
            fontSize: 12,
            height: 1.2,
            color: isDarkMode ? CupertinoColors.white.withOpacity(0.7) : CupertinoColors.systemGrey,
          ),
        ),
      ],
    );

    return RepaintBoundary(
      key: ValueKey('repaint_${group.key}'),
      child: Container(
        key: ValueKey('client_${group.key}'),
        margin: const EdgeInsets.only(bottom: 8),
        child: Column(
          children: [
            GradientCard(
              title: group.displayName,
              clientId: group.clientId.isNotEmpty ? group.clientId : null,
              gradient: gradient,
              isExpanded: isExpanded,
              isDarkMode: isDarkMode,
              onTap: () {
                final wasExpanded = _expandedClients.contains(group.key);
                _toggleClientExpand(group.key);
                
                if (!wasExpanded) {
                  final groups = _clientGroups;
                  if (groups.isNotEmpty && group.key == groups.last.key) {
                    Future.delayed(const Duration(milliseconds: 100), () {
                      _scrollToBottom();
                    });
                  }
                }
              },
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              trailing: trailing,
              maxTitleLength: 10,
            ),
            AnimationConfig.listExpandTransition(
              isExpanded: isExpanded,
              child: Container(
                margin: const EdgeInsets.only(left: 16, top: 8), 
                child: Column(children: _buildFundCards(group.holdings)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFundCards(List<FundHolding> holdings) {
    final cards = <Widget>[];
    for (int i = 0; i < holdings.length; i++) {
      final holding = holdings[i];
      cards.add(
        RepaintBoundary(
          key: ValueKey('card_${holding.id}'),
          child: FundCard(
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
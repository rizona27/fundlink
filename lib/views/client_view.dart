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
  
    // ✅ 详细诊断：检查每个基金的名称
    debugPrint('[ClientView] 🔍 开始检查基金名称...');
    final garbledHoldings = <FundHolding>[];
    for (final holding in _dataManager.holdings) {
      final name = holding.fundName;
      final hasReplacementChar = name.contains('\ufffd');
      // ✅ 修复：移除错误的空字符串检测（''.contains('') 永远为true）
      // 只检测替换字符�（Unicode replacement character）
      
      if (hasReplacementChar) {
        garbledHoldings.add(holding);
        debugPrint('[ClientView] ⚠️ 发现乱码基金: ${holding.fundCode} - "${holding.fundName}"');
        debugPrint('[ClientView]    - 包含替换字符(): true');
        debugPrint('[ClientView]    - 名称长度: ${name.length}');
        debugPrint('[ClientView]    - 名称字节: ${name.codeUnits}');
      }
    }
    
    if (garbledHoldings.isNotEmpty && mounted) {
      _autoFixTriggered = true;
      _lastAutoFixTime = DateTime.now();
      try {
        debugPrint('[ClientView] 🛠️ 发现 ${garbledHoldings.length} 个基金名称乱码，开始修复...');
        
        for (final holding in garbledHoldings) {
          if (!mounted) break;
          try {
            debugPrint('[ClientView] 🔄 正在修复基金 ${holding.fundCode}...');
            final fundInfo = await _fundService.fetchFundInfo(holding.fundCode);
            if (fundInfo['isValid'] == true && mounted) {
              final index = _dataManager.holdings.indexWhere((h) => h.id == holding.id);
              if (index != -1) {
                final updated = _dataManager.holdings[index].copyWith(
                  fundName: fundInfo['fundName'] as String? ?? holding.fundName,
                  isValid: true,
                );
                _dataManager.updateHolding(updated);
                debugPrint('[ClientView] ✅ 修复成功: ${holding.fundCode} - ${updated.fundName}');
              }
            } else {
              debugPrint('[ClientView] ❌ 修复失败: ${holding.fundCode} - ${fundInfo['error']}');
            }
          } catch (e) {
            debugPrint('[ClientView] ❌ 修复基金 ${holding.fundCode} 异常: $e');
          }
        }
        
        if (mounted) {
          setState(() {});
          context.showToast('已修复 ${garbledHoldings.length} 个基金名称');
        }
      } catch (e) {
        debugPrint('[ClientView] ❌ 自动修复基金名称失败: $e');
      }
    } else if (mounted) {
      // ✅ 没有乱码，记录日志但不刷新
      debugPrint('[ClientView] ✅ 所有基金名称正常，无需修复（共${_dataManager.holdings.length}个基金）');
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
    if (_searchText.isEmpty) {
      debugPrint('[ClientView] 📊 No search text, returning all ${_dataManager.holdings.length} holdings');
      return _dataManager.holdings;
    }
    
    debugPrint('[ClientView] 🔎 Filtering with searchText: "$_searchText"');
    final filtered = _dataManager.holdings.where((h) {
      final match = h.clientName.contains(_searchText) ||
          h.clientId.contains(_searchText) ||
          h.fundCode.contains(_searchText) ||
          h.fundName.contains(_searchText);
      if (match) {
        debugPrint('[ClientView]    ✅ Matched: ${h.fundCode} - ${h.fundName} (${h.clientName})');
      }
      return match;
    }).toList();
    
    debugPrint('[ClientView] 📊 Filtered result: ${filtered.length} holdings');
    return filtered;
  }

  List<FundHolding> get _filteredPinnedHoldings {
    // ✅ 修复：搜索时不显示置顶区，只在客户卡片内显示搜索结果
    if (_searchText.isNotEmpty) return [];
    return _filteredHoldings.where((h) => h.isPinned).toList();
  }

  List<_ClientGroup> get _clientGroups {
    final map = <String, _ClientGroup>{};
    // ✅ 修复：置顶的持仓仍然保留在客户列表中，不跳过
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
      // ✅ 修复：直接从分组的holdings中获取客户名，确保排序稳定
      final originalNameA = a.holdings.first.clientName;
      final originalNameB = b.holdings.first.clientName;
      
      // ✅ 修复：比较完整拼音而非仅首字母，确保同首字母客户正确排序
      String fullPinyinA = '';
      if (originalNameA.isNotEmpty) {
        try {
          fullPinyinA = PinyinHelper.getPinyinE(originalNameA);
        } catch (e) {
          fullPinyinA = originalNameA;
        }
      }
      
      String fullPinyinB = '';
      if (originalNameB.isNotEmpty) {
        try {
          fullPinyinB = PinyinHelper.getPinyinE(originalNameB);
        } catch (e) {
          fullPinyinB = originalNameB;
        }
      }
      
      return fullPinyinA.compareTo(fullPinyinB);
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
                onSearchChanged: (text) { 
                        debugPrint('[ClientView] 🔍 onSearchChanged called: "$text"');
                        debugPrint('[ClientView]    - Text length: ${text.length}');
                        debugPrint('[ClientView]    - Is empty: ${text.isEmpty}');
                        if (mounted) {
                          setState(() => _searchText = text);
                          debugPrint('[ClientView]    - _searchText updated to: "$_searchText"');
                        }
                      },
                onSearchClear: () { 
                        debugPrint('[ClientView] 🗑️ onSearchClear called');
                        if (mounted) {
                          setState(() => _searchText = '');
                          debugPrint('[ClientView]    - _searchText cleared');
                        }
                      },
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
                    : ListView.builder(
                  controller: _scrollController,
                  key: ValueKey('list_${_searchText}'),
                  padding: EdgeInsets.only(
                    left: 12,
                    right: 12,
                    top: 8,
                    bottom: totalBottomPadding,
                  ),
                  itemCount: (hasPinned ? 1 : 0) + groups.length,
                  itemBuilder: (context, index) {
                    // 如果有置顶区域且当前是第一项，渲染置顶区域
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
                    
                    // 否则渲染客户分组
                    final groupIndex = hasPinned ? index - 1 : index;
                    if (groupIndex >= 0 && groupIndex < groups.length) {
                      final isLastGroup = groupIndex == groups.length - 1;
                      return RepaintBoundary(
                        key: ValueKey('repaint_${groups[groupIndex].key}'),
                        child: Container(
                          key: ValueKey('client_${groups[groupIndex].key}'),
                          margin: EdgeInsets.only(bottom: isLastGroup ? 0 : 8),
                          child: Column(
                            children: [
                              GradientCard(
                                title: groups[groupIndex].displayName,
                                clientId: groups[groupIndex].clientId.isNotEmpty ? groups[groupIndex].clientId : null,
                                gradient: _getGradientForOriginalName(groups[groupIndex].holdings.first.clientName),
                                isExpanded: _expandedClients.contains(groups[groupIndex].key),
                                isDarkMode: isDarkMode,
                                onTap: () {
                                  final wasExpanded = _expandedClients.contains(groups[groupIndex].key);
                                  _toggleClientExpand(groups[groupIndex].key);
                                  
                                  if (!wasExpanded) {
                                    final allGroups = _clientGroups;
                                    if (allGroups.isNotEmpty && groups[groupIndex].key == allGroups.last.key) {
                                      Future.delayed(const Duration(milliseconds: 100), () {
                                        _scrollToBottom();
                                      });
                                    }
                                  }
                                },
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                                trailing: Row(
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
                                      '${groups[groupIndex].holdings.length}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        fontStyle: FontStyle.italic,
                                        height: 1.2,
                                        color: _colorForHoldingCount(groups[groupIndex].holdings.length),
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
                                maxTitleLength: 10,
                              ),
                              AnimationConfig.listExpandTransition(
                                isExpanded: _expandedClients.contains(groups[groupIndex].key),
                                child: Container(
                                  margin: const EdgeInsets.only(left: 16, top: 8), 
                                  child: _buildFundCards(groups[groupIndex].holdings),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClientGroupContent(_ClientGroup group, bool isDarkMode) {
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

    return Column(
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
            child: _buildFundCards(group.holdings),  // ✅ 修复：直接使用返回的Widget
          ),
        ),
      ],
    );
  }

  Widget _buildFundCards(List<FundHolding> holdings) {
    if (holdings.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: holdings.length,
      itemBuilder: (context, index) {
        final holding = holdings[index];
        return Column(
          children: [
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
            if (index < holdings.length - 1) const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}
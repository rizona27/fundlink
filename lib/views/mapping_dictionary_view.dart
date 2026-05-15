import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';
import 'package:pinyin/pinyin.dart';
import '../services/client_mapping_service.dart';
import '../models/client_mapping.dart';
import '../widgets/adaptive_top_bar.dart';
import '../widgets/toast.dart';
import '../utils/input_formatters.dart';
import '../utils/desktop_focus_manager.dart';
import 'import_holding_view.dart';
import 'dart:async';

class MappingDictionaryView extends StatefulWidget {
  const MappingDictionaryView({super.key});

  @override
  State<MappingDictionaryView> createState() => _MappingDictionaryViewState();
}

class _MappingDictionaryViewState extends State<MappingDictionaryView> {
  final ClientMappingService _mappingService = ClientMappingService();
  List<ClientMapping> _mappings = [];
  List<ClientMapping> _filteredMappings = [];
  bool _isLoading = true;
  
  SortColumn? _sortColumn;
  bool _sortAscending = true;
  
  String _searchText = '';
  
  double _scrollOffset = 0;
  Timer? _scrollThrottleTimer;

  @override
  void initState() {
    super.initState();
    _loadMappings();
  }

  Future<void> _loadMappings() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final mappings = await _mappingService.getAllMappings();
      setState(() {
        _mappings = mappings;
        _applyFilterAndSort();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showToast('加载失败: $e');
      }
    }
  }

  void _applyFilterAndSort() {
    var filtered = _mappings;
    if (_searchText.isNotEmpty) {
      final searchLower = _searchText.toLowerCase();
      filtered = _mappings.where((m) {
        return m.clientId.toLowerCase().contains(searchLower) ||
            m.clientName.toLowerCase().contains(searchLower);
      }).toList();
    }
    
    if (_sortColumn != null) {
      if (_sortColumn == SortColumn.clientId) {
        filtered.sort((a, b) {
          int result;
          final aNum = int.tryParse(a.clientId);
          final bNum = int.tryParse(b.clientId);
          
          if (aNum != null && bNum != null) {
            result = aNum.compareTo(bNum);
          } else {
            result = a.clientId.compareTo(b.clientId);
          }
          
          return _sortAscending ? result : -result;
        });
      } else if (_sortColumn == SortColumn.clientName) {
        filtered.sort((a, b) {
          final aPinyin = PinyinHelper.getPinyinE(a.clientName);
          final bPinyin = PinyinHelper.getPinyinE(b.clientName);
          final result = aPinyin.compareTo(bPinyin);
          return _sortAscending ? result : -result;
        });
      }
    }
    
    _filteredMappings = filtered;
  }

  void _onScrollUpdate(double offset) {
    if (_scrollThrottleTimer != null && _scrollThrottleTimer!.isActive) {
      return;
    }
    _scrollThrottleTimer = Timer(const Duration(milliseconds: 16), () {
      if (mounted) {
        final normalizedOffset = offset < 1.0 ? 0.0 : offset;
        setState(() {
          _scrollOffset = normalizedOffset;
        });
      }
      _scrollThrottleTimer = null;
    });
  }

  void _sortByClientId() {
    setState(() {
      if (_sortColumn == SortColumn.clientId) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = SortColumn.clientId;
        _sortAscending = true;
      }
      _applyFilterAndSort();
    });
  }

  void _sortByClientName() {
    setState(() {
      if (_sortColumn == SortColumn.clientName) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = SortColumn.clientName;
        _sortAscending = true;
      }
      _applyFilterAndSort();
    });
  }

  Future<void> _showEditDialog({ClientMapping? mapping}) async {
    final isEdit = mapping != null;
    final clientIdController = TextEditingController(text: isEdit ? mapping.clientId : '');
    final clientNameController = TextEditingController(text: isEdit ? mapping.clientName : '');
    
    final clientIdFocusNode = FocusNode();
    final clientNameFocusNode = FocusNode();
    
    final result = await showCupertinoDialog<Map<String, String>>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
        
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  constraints: const BoxConstraints(maxWidth: 400),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isDark
                              ? CupertinoColors.white.withOpacity(0.1)
                              : CupertinoColors.systemGrey4,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            '取消',
                            style: TextStyle(
                              fontSize: 17,
                              color: isDark
                                  ? CupertinoColors.systemGrey2
                                  : CupertinoColors.systemGrey,
                            ),
                          ),
                        ),
                        Text(
                          isEdit ? '编辑映射' : '新增映射',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: isDark ? CupertinoColors.white : CupertinoColors.label,
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            final clientId = clientIdController.text.trim();
                            final clientName = clientNameController.text.trim();
                            
                            if (clientId.isEmpty || clientName.isEmpty) {
                              context.showToast('客户号和客户名不能为空');
                              return;
                            }
                            
                            Navigator.pop(context, {
                              'clientId': clientId,
                              'clientName': clientName,
                            });
                          },
                          child: const Text(
                            '保存',
                            style: TextStyle(
                              fontSize: 17,
                              color: Color(0xFF007AFF),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        KeyboardListener(
                          focusNode: clientIdFocusNode,
                          onKeyEvent: (KeyEvent event) {
                            if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
                              final scope = FocusScope.of(context);
                              DesktopFocusManager.handleTabKey(
                                clientIdFocusNode,
                                scope,
                                shiftPressed: HardwareKeyboard.instance.isShiftPressed,
                              );
                            }
                          },
                          child: CupertinoTextField(
                            controller: clientIdController,
                            placeholder: '请输入客户号',
                            placeholderStyle: TextStyle(
                              fontSize: 15,
                              color: isDark
                                  ? CupertinoColors.white.withOpacity(0.4)
                                  : CupertinoColors.systemGrey,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            style: TextStyle(
                              fontSize: 15,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(12),
                            ],
                            autofocus: !isEdit,
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        KeyboardListener(
                          focusNode: clientNameFocusNode,
                          onKeyEvent: (KeyEvent event) {
                            if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
                              final scope = FocusScope.of(context);
                              DesktopFocusManager.handleTabKey(
                                clientNameFocusNode,
                                scope,
                                shiftPressed: HardwareKeyboard.instance.isShiftPressed,
                              );
                            }
                          },
                          child: CupertinoTextField(
                            controller: clientNameController,
                            placeholder: '请输入客户名',
                            placeholderStyle: TextStyle(
                              fontSize: 15,
                              color: isDark
                                  ? CupertinoColors.white.withOpacity(0.4)
                                  : CupertinoColors.systemGrey,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey6,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            style: TextStyle(
                              fontSize: 15,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                            textInputAction: TextInputAction.done,
                            inputFormatters: [
                              ClientNameInputFormatter(),
                            ],
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
      ),
    );
      },
    );
    
    clientIdFocusNode.dispose();
    clientNameFocusNode.dispose();
    
    if (result != null && mounted) {
      try {
        if (isEdit) {
          await _mappingService.updateMapping(
            mapping.id,
            result['clientId']!,
            result['clientName']!,
          );
          context.showToast('更新成功');
        } else {
          await _mappingService.addMapping(
            result['clientId']!,
            result['clientName']!,
          );
          context.showToast('添加成功');
        }
        await _loadMappings();
      } catch (e) {
        context.showToast('操作失败: $e');
      }
    }
  }

  Future<void> _confirmDelete(ClientMapping mapping) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认删除'),
        content: Text(
          '确定要删除客户号 "${mapping.clientId}" 的映射关系吗？\n此操作不可恢复。',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('删除'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    
    if (confirmed == true && mounted) {
      try {
        await _mappingService.deleteMapping(mapping.id);
        context.showToast('删除成功');
        await _loadMappings();
      } catch (e) {
        context.showToast('删除失败: $e');
      }
    }
  }

  @override
  void dispose() {
    _scrollThrottleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
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
                  showExpandCollapse: false,
                  showSearch: true,
                  searchText: _searchText,
                  searchPlaceholder: '搜索客户号或客户名',
                  onSearchChanged: (value) {
                    setState(() {
                      _searchText = value;
                      _applyFilterAndSort();
                    });
                  },
                  showReset: false,
                  showFilter: false,
                  showSort: false,
                  hasData: _filteredMappings.isNotEmpty,
                  backgroundColor: Colors.transparent,
                  iconColor: CupertinoTheme.of(context).primaryColor,
                  iconSize: 24,
                  buttonSpacing: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                
                AnimatedOpacity(
                  opacity: _scrollOffset < 50 ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: _scrollOffset < 50
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDarkMode ? const Color(0xFF2C2C2E) : CupertinoColors.white,
                            border: Border(
                              bottom: BorderSide(
                                color: isDarkMode
                                    ? CupertinoColors.white.withOpacity(0.1)
                                    : CupertinoColors.systemGrey4,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '共 ${_filteredMappings.length} 条记录',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode
                                      ? CupertinoColors.white.withOpacity(0.6)
                                      : CupertinoColors.systemGrey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                
                Expanded(
                  child: Stack(
                    children: [
                      _isLoading
                          ? const Center(child: CupertinoActivityIndicator())
                          : _filteredMappings.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        CupertinoIcons.book,
                                        size: 64,
                                        color: isDarkMode
                                            ? CupertinoColors.white.withOpacity(0.3)
                                            : CupertinoColors.systemGrey.withOpacity(0.5),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _searchText.isNotEmpty ? '未找到匹配的映射' : '暂无映射数据',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: isDarkMode
                                              ? CupertinoColors.white.withOpacity(0.5)
                                              : CupertinoColors.systemGrey,
                                        ),
                                      ),
                                      if (_searchText.isEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          '点击下方“+”按钮添加映射关系',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: isDarkMode
                                                ? CupertinoColors.white.withOpacity(0.4)
                                                : CupertinoColors.systemGrey2,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                )
                              : Column(
                                  children: [
                                    _buildHeaderRow(isDarkMode),
                                    Expanded(
                                      child: ListView.builder(
                                        padding: const EdgeInsets.only(bottom: 80),
                                        itemCount: _filteredMappings.length,
                                        itemBuilder: (context, index) {
                                          return _buildMappingRow(
                                            _filteredMappings[index],
                                            index,
                                            isDarkMode,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                      
                      Positioned(
                        bottom: 20,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: () => _showEditDialog(),
                            onLongPress: () {
                              Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (context) => const ImportHoldingView(),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isDarkMode 
                                    ? const Color(0xFF2C2C2E).withOpacity(0.85)
                                    : CupertinoColors.white.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                CupertinoIcons.plus,
                                size: 24,
                                color: Color(0xFF007AFF),
                              ),
                            ),
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

  Widget _buildHeaderRow(bool isDarkMode) {
    return Container(
      height: 40,
      color: isDarkMode ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey6,
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Container(
              alignment: Alignment.center,
              child: const Text(
                '序号',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          _buildDivider(isDarkMode),
          
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _sortByClientId,
              child: Container(
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '客户号',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (_sortColumn == SortColumn.clientId)
                      Icon(
                        _sortAscending
                            ? CupertinoIcons.arrow_up
                            : CupertinoIcons.arrow_down,
                        size: 12,
                        color: const Color(0xFF007AFF),
                      ),
                  ],
                ),
              ),
            ),
          ),
          _buildDivider(isDarkMode),
          
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _sortByClientName,
              child: Container(
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '客户名',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (_sortColumn == SortColumn.clientName)
                      Icon(
                        _sortAscending
                            ? CupertinoIcons.arrow_up
                            : CupertinoIcons.arrow_down,
                        size: 12,
                        color: const Color(0xFF007AFF),
                      ),
                  ],
                ),
              ),
            ),
          ),
          _buildDivider(isDarkMode),
          
          Expanded(
            flex: 2,
            child: Container(
              alignment: Alignment.center,
              child: const Text(
                '操作',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMappingRow(ClientMapping mapping, int index, bool isDarkMode) {
    final backgroundColor = isDarkMode
        ? (index % 2 == 0 ? const Color(0xFF1C1C1E) : const Color(0xFF2C2C2E))
        : (index % 2 == 0 ? CupertinoColors.white : CupertinoColors.systemGrey6);

    return Container(
      height: 50,
      color: backgroundColor,
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Container(
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
            ),
          ),
          _buildDivider(isDarkMode),
          
          Expanded(
            flex: 2,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                mapping.clientId,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDarkMode ? CupertinoColors.white : CupertinoColors.black,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          _buildDivider(isDarkMode),
          
          Expanded(
            flex: 2,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                mapping.clientName,
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode ? CupertinoColors.white : CupertinoColors.black,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          _buildDivider(isDarkMode),
          
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  onPressed: () => _showEditDialog(mapping: mapping),
                  child: const Icon(
                    CupertinoIcons.pencil,
                    size: 18,
                    color: Color(0xFF007AFF),
                  ),
                ),
                const SizedBox(width: 8),
                
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  onPressed: () => _confirmDelete(mapping),
                  child: const Icon(
                    CupertinoIcons.trash,
                    size: 18,
                    color: Color(0xFFFF3B30),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(bool isDarkMode) {
    return Container(
      width: 1,
      height: 30,
      color: isDarkMode
          ? CupertinoColors.white.withOpacity(0.1)
          : CupertinoColors.systemGrey4,
    );
  }
}

enum SortColumn {
  clientId,
  clientName,
}

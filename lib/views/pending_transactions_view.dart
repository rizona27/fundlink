import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../models/log_entry.dart';
import '../models/transaction_record.dart';
import '../services/data_manager.dart';
import '../services/fund_service.dart';
import '../utils/desktop_focus_manager.dart';
import '../utils/view_utils.dart';
import '../widgets/adaptive_top_bar.dart';
import '../widgets/toast.dart';

class PendingTransactionsView extends StatefulWidget {
  const PendingTransactionsView({super.key});

  @override
  State<PendingTransactionsView> createState() => _PendingTransactionsViewState();
}

class _PendingTransactionsViewState extends State<PendingTransactionsView> {
  late DataManager _dataManager;
  late FundService _fundService;
  List<TransactionRecord> _pendingTransactions = [];
  bool _isLoading = false;
  late VoidCallback _dataListener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataManager = DataManagerProvider.of(context);
    _fundService = FundService(_dataManager);
    
    _dataListener = () {
      if (mounted) {
        _loadPendingTransactions();
      }
    };
    _dataManager.addListener(_dataListener);
    
    _loadPendingTransactions();
  }
  
  @override
  void dispose() {
    _dataManager.removeListener(_dataListener);
    super.dispose();
  }

  void _loadPendingTransactions() {
    if (mounted) {
      setState(() {
        _pendingTransactions = _dataManager.getPendingTransactions();
      });
    }
  }

  Future<void> _refreshAndConfirm() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      int confirmedCount = 0;
      int networkErrorCount = 0;
      int holdingErrorCount = 0;
      int navNotAvailableCount = 0;
      final pendingTxs = _dataManager.getPendingTransactions();
      
      if (pendingTxs.isEmpty && mounted) {
        context.showToast('暂无待确认交易');
        setState(() => _isLoading = false);
        return;
      }
      
      for (final tx in pendingTxs) {
        try {
          final holding = _dataManager.holdings.firstWhere(
            (h) => h.fundCode == tx.fundCode,
            orElse: () {
              holdingErrorCount++;
              throw Exception('未找到${tx.fundName}的持仓信息');
            },
          );
          
          final dbNav = holding.currentNav;
          final dbNavDate = holding.navDate;
          
          final expectedNavDate = await DataManager.calculateNavDateForTradeAsync(
            tx.tradeDate, 
            tx.isAfter1500,
          );
          
          bool shouldFetchFromApi = true;
          double? navToUse;
          
          if (dbNav != null && dbNav > 0 && dbNavDate != null) {
            final dbNavDay = DateTime(dbNavDate.year, dbNavDate.month, dbNavDate.day);
            final expectedNavDay = DateTime(expectedNavDate.year, expectedNavDate.month, expectedNavDate.day);
            
            if (!dbNavDay.isBefore(expectedNavDay)) {
              navToUse = dbNav;
              shouldFetchFromApi = false;
            }
          }
          
          if (shouldFetchFromApi) {
            try {
              final fundInfo = await _fundService.fetchFundInfo(tx.fundCode, forceRefresh: true);
              if (fundInfo['isValid'] == true && fundInfo['currentNav'] > 0) {
                final apiNavDate = fundInfo['navDate'] as DateTime?;
                if (apiNavDate != null) {
                  final apiNavDay = DateTime(apiNavDate.year, apiNavDate.month, apiNavDate.day);
                  final expectedNavDay = DateTime(expectedNavDate.year, expectedNavDate.month, expectedNavDate.day);
                  
                  if (!apiNavDay.isBefore(expectedNavDay)) {
                    navToUse = fundInfo['currentNav'];
                  } else {
                    navNotAvailableCount++;
                  }
                } else {
                  navNotAvailableCount++;
                }
              } else {
                navNotAvailableCount++;
              }
            } catch (e) {
              networkErrorCount++;
              await _dataManager.addLog(
                '获取${tx.fundName}净值失败: $e',
                type: LogType.error,
              );
              rethrow;
            }
          }
          
          if (navToUse != null && navToUse > 0) {
            await _dataManager.confirmPendingTransaction(tx.id, navToUse!);
            confirmedCount++;
          }
        } catch (e) {
          await _dataManager.addLog(
            '手动确认单笔交易失败 (${tx.fundCode}): $e',
            type: LogType.error,
          );
        }
      }
      
      if (mounted) {
        _loadPendingTransactions();
        
        if (confirmedCount > 0) {
          if (networkErrorCount > 0 || holdingErrorCount > 0) {
            context.showToast('确认 $confirmedCount 笔，部分失败');
          } else {
            context.showToast('成功确认 $confirmedCount 笔交易');
          }
        } else {
          if (holdingErrorCount > 0) {
            context.showToast('缺少基金持仓信息，请先添加持仓');
          } else if (networkErrorCount > 0) {
            context.showToast('网络连接失败，请检查网络后重试');
          } else if (navNotAvailableCount > 0) {
            context.showToast('净值尚未公布，请稍后再试');
          } else {
            context.showToast('确认失败，请稍后重试');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        context.showToast('确认失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  DateTime _getExpectedConfirmDate(TransactionRecord tx) {
    return DataManager.calculateConfirmDate(tx.tradeDate, tx.isAfter1500);
  }

  Future<void> _showManualConfirmDialog(TransactionRecord tx) async {
    final TextEditingController navController = TextEditingController();
    
    final mediaQuery = MediaQuery.of(context);
    
    await showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Center(
          child: Container(
            margin: EdgeInsets.only(
              bottom: mediaQuery.viewInsets.bottom > 0 ? 20 : 0,
            ),
            constraints: const BoxConstraints(maxWidth: 400),
            child: CupertinoPopupSurface(
              isSurfacePainted: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: CupertinoTheme.brightnessOf(context) == Brightness.dark
                          ? const Color(0xFF3A3A3C)
                          : CupertinoColors.systemGrey6,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '手动确认交易',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: CupertinoTheme.of(context).textTheme.textStyle.color,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemGrey.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.xmark,
                              size: 14,
                              color: CupertinoTheme.of(context).textTheme.textStyle.color,
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '基金: ${tx.fundName}',
                          style: TextStyle(
                            fontSize: 14,
                            color: CupertinoTheme.of(context).textTheme.textStyle.color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '代码: ${tx.fundCode}',
                          style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.systemGrey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '金额: ¥${tx.amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: CupertinoTheme.of(context).textTheme.textStyle.color,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '请输入确认净值:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: CupertinoTheme.of(context).textTheme.textStyle.color,
                          ),
                        ),
                        const SizedBox(height: 8),
                        KeyboardListener(
                          focusNode: FocusNode(),
                          onKeyEvent: (KeyEvent event) {
                            if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
                              final scope = FocusScope.of(context);
                              DesktopFocusManager.handleTabKey(
                                FocusNode(),
                                scope,
                                shiftPressed: HardwareKeyboard.instance.isShiftPressed,
                              );
                            }
                          },
                          child: CupertinoTextField(
                            controller: navController,
                            placeholder: '例如: 1.2345',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textInputAction: TextInputAction.done,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: CupertinoTheme.brightnessOf(context) == Brightness.dark
                                  ? const Color(0xFF3A3A3C)
                                  : CupertinoColors.systemGrey6,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            onChanged: (value) {
                              if (value.isNotEmpty && !RegExp(r'^\d*\.?\d{0,4}$').hasMatch(value)) {
                                navController.text = value.substring(0, value.length - 1);
                                navController.selection = TextSelection.fromPosition(
                                  TextPosition(offset: navController.text.length),
                                );
                              }
                            },
                            onSubmitted: (value) async {
                              await _confirmManualNav(tx, navController.text);
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.info_circle,
                              size: 12,
                              color: CupertinoColors.systemGrey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '提示: 最多支持4位小数，按回车键确认',
                              style: TextStyle(
                                fontSize: 11,
                                color: CupertinoColors.systemGrey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: CupertinoButton(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                color: CupertinoTheme.brightnessOf(context) == Brightness.dark
                                    ? const Color(0xFF3A3A3C)
                                    : CupertinoColors.systemGrey6,
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  '取消',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: CupertinoTheme.of(context).primaryColor,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: CupertinoButton(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                color: CupertinoColors.activeBlue,
                                onPressed: () async {
                                  await _confirmManualNav(tx, navController.text);
                                },
                                child: const Text(
                                  '确认',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
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
    
    navController.dispose();
  }

  Future<void> _confirmManualNav(TransactionRecord tx, String navText) async {
    final trimmedText = navText.trim();
    
    if (trimmedText.isEmpty) {
      context.showToast('请输入净值');
      return;
    }
    
    final nav = double.tryParse(trimmedText);
    if (nav == null || nav <= 0) {
      context.showToast('请输入有效的净值');
      return;
    }
    
    if (trimmedText.contains('.') && trimmedText.split('.')[1].length > 4) {
      context.showToast('净值最多支持4位小数');
      return;
    }
    
    Navigator.pop(context);
    
    try {
      await _dataManager.manuallyConfirmTransaction(
        tx.id,
        nav,
        null,
        null,
      );
      
      if (mounted) {
        context.showToast('交易确认成功');
        _loadPendingTransactions();
      }
    } catch (e) {
      if (mounted) {
        context.showToast('确认失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final textColor = isDarkMode ? CupertinoColors.white : const Color(0xFF1C1C1E);
    final secondaryTextColor = isDarkMode 
        ? CupertinoColors.white.withOpacity(0.6)
        : const Color(0xFF8E8E93);

    return Container(
      color: bgColor,
      child: SafeArea(
        child: Column(
          children: [
            AdaptiveTopBar(
              scrollOffset: 0,
              showBack: true,
              onBack: () => Navigator.of(context).pop(),
              showRefresh: true,
              onRefresh: _refreshAndConfirm,
              hasData: true,
              showExpandCollapse: false,
              showSearch: false,
              showReset: false,
              showFilter: false,
              showSort: false,
              backgroundColor: const Color(0x00000000),
              iconColor: CupertinoTheme.of(context).primaryColor,
              iconSize: 24,
              buttonSpacing: 12,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2C2C2E) : CupertinoColors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        '待确认交易',
                        style: TextStyle(
                          fontSize: 12,
                          color: secondaryTextColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_pendingTransactions.length} 笔',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点击刷新按钮手动查询净值并确认',
                    style: TextStyle(
                      fontSize: 11,
                      color: secondaryTextColor,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: _pendingTransactions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.checkmark_seal,
                            size: 56,
                            color: isDarkMode 
                                ? CupertinoColors.white.withOpacity(0.3)
                                : CupertinoColors.systemGrey3,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '暂无待确认交易',
                            style: TextStyle(
                              fontSize: 15,
                              color: secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _pendingTransactions.length,
                      itemBuilder: (context, index) {
                        final tx = _pendingTransactions[index];
                        return _buildTransactionCard(tx, isDarkMode, textColor, secondaryTextColor);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(TransactionRecord tx, bool isDarkMode, Color textColor, Color secondaryTextColor) {
    final typeColor = tx.type == TransactionType.buy 
        ? const Color(0xFF34C759)
        : const Color(0xFFFF3B30);
    
    final expectedConfirmDate = _getExpectedConfirmDate(tx);
    final now = DateTime.now();
    final canConfirm = !now.isBefore(expectedConfirmDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2C2C2E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CupertinoColors.systemOrange.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (tx.clientId.isNotEmpty)
                Text(
                  '${tx.clientName}(${tx.clientId})',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDarkMode ? CupertinoColors.white.withOpacity(0.8) : const Color(0xFF3C3C43),
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                )
              else
                Text(
                  tx.clientName,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDarkMode ? CupertinoColors.white.withOpacity(0.8) : const Color(0xFF3C3C43),
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tx.type.displayName,
                  style: TextStyle(
                    color: typeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemOrange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.clock,
                      size: 10,
                      color: CupertinoColors.systemOrange,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '未生效',
                      style: TextStyle(
                        color: CupertinoColors.systemOrange,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                ViewUtils.formatDate(tx.tradeDate),
                style: TextStyle(fontSize: 11, color: secondaryTextColor),
              ),
            ],
          ),
          
          const SizedBox(height: 6),
          
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: tx.fundName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                TextSpan(
                  text: ' (${tx.fundCode})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                    color: secondaryTextColor.withOpacity(0.7),
                  ),
                ),
              ],
            ),
            overflow: TextOverflow.ellipsis,
          ),
          
          const SizedBox(height: 6),
          
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('金额', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                    const SizedBox(height: 2),
                    Text(
                      '${tx.amount.toStringAsFixed(2)}元',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('份额', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                    const SizedBox(height: 2),
                    Text(
                      tx.shares > 0 
                          ? '${tx.shares.toStringAsFixed(2)}份'
                          : '待计算',
                      style: TextStyle(
                        fontSize: 13, 
                        fontWeight: FontWeight.w600, 
                        color: tx.shares > 0 ? textColor : CupertinoColors.systemOrange,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('预计确认', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                    const SizedBox(height: 2),
                    Text(
                      ViewUtils.formatDate(expectedConfirmDate),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: canConfirm 
                            ? const Color(0xFF34C759)
                            : CupertinoColors.systemOrange,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 4),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: canConfirm
                  ? const Color(0xFF34C759).withOpacity(0.1)
                  : CupertinoColors.systemOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  canConfirm 
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.info_circle_fill,
                  size: 12,
                  color: canConfirm 
                      ? const Color(0xFF34C759)
                      : CupertinoColors.systemOrange,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    canConfirm
                        ? '已到达确认时间，点击刷新按钮确认'
                        : '等待净值公布中，可手动刷新检查',
                    style: TextStyle(
                      fontSize: 10,
                      color: canConfirm 
                          ? const Color(0xFF34C759)
                          : CupertinoColors.systemOrange,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          if (tx.retryCount > 0 || tx.status == TransactionStatus.confirmFailed)
            const SizedBox(height: 8),
          if (tx.retryCount > 0 || tx.status == TransactionStatus.confirmFailed)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tx.status == TransactionStatus.confirmFailed
                    ? CupertinoColors.systemRed.withOpacity(0.1)
                    : CupertinoColors.systemYellow.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: tx.status == TransactionStatus.confirmFailed
                      ? CupertinoColors.systemRed.withOpacity(0.3)
                      : CupertinoColors.systemYellow.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        tx.status == TransactionStatus.confirmFailed
                            ? CupertinoIcons.exclamationmark_triangle_fill
                            : CupertinoIcons.clock_fill,
                        size: 12,
                        color: tx.status == TransactionStatus.confirmFailed
                            ? CupertinoColors.systemRed
                            : CupertinoColors.systemYellow,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tx.status == TransactionStatus.confirmFailed
                            ? '自动确认失败(已重试${tx.retryCount}次)'
                            : '正在尝试自动确认(${tx.retryCount}/5次)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: tx.status == TransactionStatus.confirmFailed
                              ? CupertinoColors.systemRed
                              : CupertinoColors.systemYellow,
                        ),
                      ),
                    ],
                  ),
                  if (tx.status == TransactionStatus.confirmFailed)
                    const SizedBox(height: 6),
                  if (tx.status == TransactionStatus.confirmFailed)
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        color: CupertinoColors.systemRed,
                        borderRadius: BorderRadius.circular(6),
                        onPressed: () => _showManualConfirmDialog(tx),
                        child: const Text(
                          '手动确认',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

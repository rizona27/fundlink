import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';
import '../models/fund_holding.dart';

class FundCard extends StatefulWidget {
  final FundHolding holding;
  final bool hideClientInfo;
  final VoidCallback? onCopyClientId;
  final VoidCallback? onGenerateReport;
  final void Function(String message)? onShowToast;
  final VoidCallback? onPinToggle;

  const FundCard({
    super.key,
    required this.holding,
    this.hideClientInfo = false,
    this.onCopyClientId,
    this.onGenerateReport,
    this.onShowToast,
    this.onPinToggle,
  });

  @override
  State<FundCard> createState() => _FundCardState();
}

class _FundCardState extends State<FundCard> with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  bool _isRevealed = false;
  static const double _maxSwipeOffset = 80;

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dx;
      _dragOffset = _dragOffset.clamp(0.0, _maxSwipeOffset);
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final shouldReveal = _dragOffset > _maxSwipeOffset * 0.5;
    setState(() {
      if (shouldReveal) {
        _dragOffset = _maxSwipeOffset;
        _isRevealed = true;
      } else {
        _dragOffset = 0;
        _isRevealed = false;
      }
    });
  }

  void _resetSwipe() {
    setState(() {
      _dragOffset = 0;
      _isRevealed = false;
    });
  }

  void _onPinPressed() {
    widget.onPinToggle?.call();
    _resetSwipe();
  }

  int get holdingDays {
    final startDate = DateTime(widget.holding.purchaseDate.year, widget.holding.purchaseDate.month, widget.holding.purchaseDate.day);
    final endDate = DateTime(widget.holding.navDate.year, widget.holding.navDate.month, widget.holding.navDate.day);
    return endDate.difference(startDate).inDays + 1;
  }

  double get absoluteReturnPercentage {
    if (!widget.holding.isValid || widget.holding.purchaseAmount <= 0 || widget.holding.currentNav <= 0) {
      return 0.0;
    }
    return (widget.holding.profit / widget.holding.purchaseAmount) * 100;
  }

  String _formatDate(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatShortDate(DateTime date) {
    return '${date.year.toString().substring(2)}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Color _getProfitColor(double value, bool isDarkMode) {
    if (value > 0) return CupertinoColors.systemRed;
    if (value < 0) return CupertinoColors.systemGreen;
    return isDarkMode
        ? CupertinoColors.white.withOpacity(0.5)
        : CupertinoColors.label.withOpacity(0.5);
  }

  Color _getCardBackgroundColor(bool isDarkMode) {
    return isDarkMode
        ? CupertinoColors.systemGrey6.withOpacity(0.5)
        : CupertinoColors.white;
  }

  Color _getPrimaryTextColor(bool isDarkMode) {
    return isDarkMode ? CupertinoColors.white : const Color(0xFF1C1C1E);
  }

  Color _getSecondaryTextColor(bool isDarkMode) {
    return isDarkMode
        ? CupertinoColors.white.withOpacity(0.5)
        : const Color(0xFF8E8E93);
  }

  List<BoxShadow> _getBoxShadow(bool isDarkMode) {
    if (isDarkMode) {
      return [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
    }
    return [
      BoxShadow(
        color: Colors.black.withOpacity(0.08),
        blurRadius: 3,
        offset: const Offset(0, 2),
      ),
    ];
  }

  String _formatPurchaseAmount(double amount) {
    if (amount >= 10000) {
      final wan = amount / 10000;
      if (wan == wan.toInt().toDouble()) {
        return '${wan.toInt()}万元';
      }
      return '${wan.toStringAsFixed(2)}万元';
    }
    return '${amount.toStringAsFixed(2)}元';
  }

  String _formatProfitAmount(double amount) {
    if (amount >= 10000) {
      final wan = amount / 10000;
      if (wan == wan.toInt().toDouble()) {
        return '${wan.toInt()}万元';
      }
      return '${wan.toStringAsFixed(2)}万元';
    }
    return '${amount.toStringAsFixed(2)}元';
  }

  void _onCopyFundCode() {
    Clipboard.setData(ClipboardData(text: widget.holding.fundCode));
    widget.onShowToast?.call('基金代码已复制: ${widget.holding.fundCode}');
  }

  void _onCopyClientId() {
    if (widget.holding.clientId.isEmpty) return;
    Clipboard.setData(ClipboardData(text: widget.holding.clientId));
    widget.onShowToast?.call('客户号已复制到剪贴板');
    widget.onCopyClientId?.call();
  }

  void _onGenerateReport() {
    widget.onGenerateReport?.call();
  }

  // 报告内容
  String get reportContent {
    final profit = widget.holding.profit;
    final annualizedReturn = widget.holding.annualizedProfitRate;

    final purchaseAmountFormatted = _formatPurchaseAmountForReport(widget.holding.purchaseAmount);
    final formattedCurrentNav = widget.holding.currentNav.toStringAsFixed(4);
    final formattedAbsoluteProfit = _formatProfitAmountForReport(profit);
    final formattedAnnualizedProfit = _formatPercentageForReport(annualizedReturn);
    final formattedAbsoluteReturnPercentage = _formatPercentageForReport(absoluteReturnPercentage);
    final navDateString = _formatDate(widget.holding.navDate);

    return '''
${widget.holding.fundName} | ${widget.holding.fundCode}
├ 购买日期:${_formatSwiftShortDate(widget.holding.purchaseDate)}
├ 持有天数:${holdingDays}天
├ 购买金额:$purchaseAmountFormatted
├ 最新净值:$formattedCurrentNav | $navDateString
├ 收益:$formattedAbsoluteProfit
├ 收益率:$formattedAnnualizedProfit(年化)
└ 收益率:$formattedAbsoluteReturnPercentage(绝对)
''';
  }

  String _formatPurchaseAmountForReport(double amount) {
    if (amount >= 10000) {
      final wan = amount / 10000;
      if (wan == wan.toInt().toDouble()) {
        return '${wan.toInt()}万';
      }
      return '${wan.toStringAsFixed(2)}万';
    }
    return '${amount.toStringAsFixed(2)}元';
  }

  String _formatProfitAmountForReport(double amount) {
    if (amount >= 10000) {
      final wan = amount / 10000;
      if (wan == wan.toInt().toDouble()) {
        return '+${wan.toInt()}万';
      }
      return '+${wan.toStringAsFixed(2)}万';
    }
    if (amount > 0) {
      return '+${amount.toStringAsFixed(2)}元';
    } else if (amount < 0) {
      return '${amount.toStringAsFixed(2)}元';
    }
    return '0.00元';
  }

  String _formatPercentageForReport(double percentage) {
    if (percentage > 0) {
      return '+${percentage.toStringAsFixed(2)}%';
    } else if (percentage < 0) {
      return '${percentage.toStringAsFixed(2)}%';
    }
    return '0.00%';
  }

  String _formatSwiftShortDate(DateTime date) {
    return '${date.year.toString().substring(2)}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final profit = widget.holding.profit;
    final absoluteReturn = widget.holding.profitRate;
    final annualizedReturn = widget.holding.annualizedProfitRate;
    final bool hasNoData = !widget.holding.isValid || widget.holding.currentNav <= 0;
    final isPinned = widget.holding.isPinned;

    return GestureDetector(
      onHorizontalDragUpdate: _handleHorizontalDragUpdate,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      onTap: _resetSwipe,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 背景按钮（滑动后显示）
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: isPinned
                    ? CupertinoColors.systemOrange.withOpacity(0.8)
                    : CupertinoColors.systemBlue.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: isPinned ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(
                  left: isPinned ? 0 : 20,
                  right: isPinned ? 20 : 0,
                ),
                child: GestureDetector(
                  onTap: _onPinPressed,
                  child: Text(
                    isPinned ? '取消置顶' : '置顶',
                    style: const TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 卡片内容（滑动偏移）
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_dragOffset, 0, 0),
            child: Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: _getCardBackgroundColor(isDarkMode),
                borderRadius: BorderRadius.circular(12),
                boxShadow: _getBoxShadow(isDarkMode),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 第一行：基金名称 + 代码 + 净值日期
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.holding.fundName,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: _getPrimaryTextColor(isDarkMode),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onLongPress: _onCopyFundCode,
                              child: Text(
                                '(${widget.holding.fundCode})',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _getSecondaryTextColor(isDarkMode),
                                ),
                              ),
                            ),
                            if (isPinned) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                CupertinoIcons.pin_fill,
                                size: 12,
                                color: Color(0xFFFF9500),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (hasNoData)
                        const Text(
                          '净值待加载',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFFFF9500),
                          ),
                        )
                      else
                        Text(
                          '${widget.holding.currentNav.toStringAsFixed(4)}(${_formatDate(widget.holding.navDate)})',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF007AFF),
                          ),
                        ),
                    ],
                  ),
                  // 客户信息（如果不隐藏）
                  if (!widget.hideClientInfo) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '客户: ${widget.holding.clientName}',
                          style: TextStyle(
                            fontSize: 13,
                            color: _getPrimaryTextColor(isDarkMode),
                          ),
                        ),
                        if (widget.holding.clientId.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            '(${widget.holding.clientId})',
                            style: TextStyle(
                              fontSize: 11,
                              color: _getSecondaryTextColor(isDarkMode),
                            ),
                          ),
                        ],
                        const Spacer(),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  // 购买金额和份额
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '购买金额: ${_formatPurchaseAmount(widget.holding.purchaseAmount)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: _getSecondaryTextColor(isDarkMode),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '份额: ${widget.holding.purchaseShares.toStringAsFixed(2)}份',
                          style: TextStyle(
                            fontSize: 11,
                            color: _getSecondaryTextColor(isDarkMode),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 收益
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              '收益: ',
                              style: TextStyle(
                                fontSize: 13,
                                color: _getPrimaryTextColor(isDarkMode),
                              ),
                            ),
                            if (hasNoData)
                              Text(
                                '待加载',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _getSecondaryTextColor(isDarkMode),
                                ),
                              )
                            else
                              Text(
                                '${profit >= 0 ? '+' : ''}${_formatProfitAmount(profit)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _getProfitColor(profit, isDarkMode),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 收益率
                  Row(
                    children: [
                      Text(
                        '收益率: ',
                        style: TextStyle(
                          fontSize: 13,
                          color: _getPrimaryTextColor(isDarkMode),
                        ),
                      ),
                      if (hasNoData) ...[
                        Text('--%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _getSecondaryTextColor(isDarkMode))),
                        Text('[绝对]', style: TextStyle(fontSize: 10, color: _getSecondaryTextColor(isDarkMode))),
                        Text(' | ', style: TextStyle(fontSize: 13, color: _getSecondaryTextColor(isDarkMode))),
                        Text('--%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _getSecondaryTextColor(isDarkMode))),
                        Text('[年化]', style: TextStyle(fontSize: 10, color: _getSecondaryTextColor(isDarkMode))),
                      ] else ...[
                        Text(
                          '${absoluteReturn >= 0 ? '+' : ''}${absoluteReturn.toStringAsFixed(2)}%',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _getProfitColor(absoluteReturn, isDarkMode)),
                        ),
                        Text('[绝对]', style: TextStyle(fontSize: 10, color: _getSecondaryTextColor(isDarkMode))),
                        Text(' | ', style: TextStyle(fontSize: 13, color: _getSecondaryTextColor(isDarkMode))),
                        Text(
                          '${annualizedReturn >= 0 ? '+' : ''}${annualizedReturn.toStringAsFixed(2)}%',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _getProfitColor(annualizedReturn, isDarkMode)),
                        ),
                        Text('[年化]', style: TextStyle(fontSize: 10, color: _getSecondaryTextColor(isDarkMode))),
                      ],
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 购买日期和持有天数
                  Row(
                    children: [
                      Text('购买日期: ', style: TextStyle(fontSize: 11, color: _getSecondaryTextColor(isDarkMode))),
                      Text(_formatShortDate(widget.holding.purchaseDate), style: TextStyle(fontSize: 11, color: _getSecondaryTextColor(isDarkMode))),
                      const Spacer(),
                      Text('持有天数: ', style: TextStyle(fontSize: 11, color: _getSecondaryTextColor(isDarkMode))),
                      Text('${holdingDays}天', style: TextStyle(fontSize: 11, color: _getSecondaryTextColor(isDarkMode))),
                    ],
                  ),
                  // 备注
                  if (widget.holding.remarks.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('备注: ', style: TextStyle(fontSize: 11, color: _getSecondaryTextColor(isDarkMode))),
                        Expanded(
                          child: Text(
                            widget.holding.remarks,
                            style: TextStyle(fontSize: 11, color: _getSecondaryTextColor(isDarkMode)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  // 底部按钮行
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minSize: 0,
                        onPressed: widget.holding.clientId.isEmpty ? null : _onCopyClientId,
                        child: Text(
                          '复制客户号',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: widget.holding.clientId.isEmpty
                                ? CupertinoColors.systemGrey
                                : const Color(0xFF007AFF).withOpacity(0.8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minSize: 0,
                        onPressed: _onGenerateReport,
                        child: const Text(
                          '报告',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF007AFF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
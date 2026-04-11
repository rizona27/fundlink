import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import '../models/fund_holding.dart';

class FundCard extends StatelessWidget {
  final FundHolding holding;
  final bool hideClientInfo;
  final VoidCallback? onCopyClientId;
  final VoidCallback? onGenerateReport;

  const FundCard({
    super.key,
    required this.holding,
    this.hideClientInfo = false,
    this.onCopyClientId,
    this.onGenerateReport,
  });

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

  // 获取卡片背景色
  Color _getCardBackgroundColor(bool isDarkMode) {
    return isDarkMode
        ? CupertinoColors.systemGrey6.withOpacity(0.5)
        : CupertinoColors.white;
  }

  // 获取主要文字颜色
  Color _getPrimaryTextColor(bool isDarkMode) {
    return isDarkMode ? CupertinoColors.white : const Color(0xFF1C1C1E);
  }

  // 获取次要文字颜色
  Color _getSecondaryTextColor(bool isDarkMode) {
    return isDarkMode
        ? CupertinoColors.white.withOpacity(0.5)
        : const Color(0xFF8E8E93);
  }

  // 获取标签文字颜色
  Color _getLabelTextColor(bool isDarkMode) {
    return isDarkMode
        ? CupertinoColors.white.withOpacity(0.4)
        : CupertinoColors.label.withOpacity(0.5);
  }

  // 获取阴影颜色
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
        color: Colors.black.withOpacity(0.06),
        blurRadius: 6,
        offset: const Offset(2, 3),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final days = DateTime.now().difference(holding.purchaseDate).inDays;
    final absoluteReturn = holding.profitRate;
    final annualizedReturn = holding.annualizedProfitRate;

    // 判断是否没有有效数据
    final bool hasNoData = !holding.isValid || holding.currentNav <= 0;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: _getCardBackgroundColor(isDarkMode),
        borderRadius: BorderRadius.circular(12),
        boxShadow: _getBoxShadow(isDarkMode),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：基金名称 + 代码 + 净值日期（靠右）
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        holding.fundName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _getPrimaryTextColor(isDarkMode),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      holding.fundCode,
                      style: TextStyle(
                        fontSize: 10,
                        color: _getSecondaryTextColor(isDarkMode),
                      ),
                    ),
                    if (holding.isPinned) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        CupertinoIcons.pin_fill,
                        size: 10,
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
                    fontSize: 9,
                    color: Color(0xFFFF9500),
                  ),
                )
              else
                Text(
                  '${holding.currentNav.toStringAsFixed(4)}(${_formatDate(holding.navDate)})',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF007AFF),
                  ),
                ),
            ],
          ),
          // 客户信息（如果不隐藏）
          if (!hideClientInfo) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '客户: ${holding.clientName}',
                  style: TextStyle(
                    fontSize: 12,
                    color: _getPrimaryTextColor(isDarkMode),
                  ),
                ),
                if (holding.clientId.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    '(${holding.clientId})',
                    style: TextStyle(
                      fontSize: 10,
                      color: _getSecondaryTextColor(isDarkMode),
                    ),
                  ),
                ],
                const Spacer(),
              ],
            ),
          ],
          const SizedBox(height: 8),
          // 第二行：购买金额 和 份额（均匀分布）
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '购买金额: ',
                      style: TextStyle(
                        fontSize: 10,
                        color: _getLabelTextColor(isDarkMode),
                      ),
                    ),
                    Text(
                      _formatPurchaseAmount(holding.purchaseAmount),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _getPrimaryTextColor(isDarkMode),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '份额: ',
                      style: TextStyle(
                        fontSize: 10,
                        color: _getLabelTextColor(isDarkMode),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        holding.purchaseShares.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _getPrimaryTextColor(isDarkMode),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '份',
                      style: TextStyle(
                        fontSize: 9,
                        color: _getLabelTextColor(isDarkMode),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 第三行：收益（左） + 收益率组合（右）
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '收益: ',
                      style: TextStyle(
                        fontSize: 10,
                        color: _getLabelTextColor(isDarkMode),
                      ),
                    ),
                    if (hasNoData)
                      Text(
                        '待加载',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getSecondaryTextColor(isDarkMode),
                        ),
                      )
                    else
                      Text(
                        '${holding.profit >= 0 ? '+' : ''}${_formatProfitAmount(holding.profit)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getProfitColor(holding.profit, isDarkMode),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (hasNoData) ...[
                      Text(
                        '--%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getSecondaryTextColor(isDarkMode),
                        ),
                      ),
                      Text(
                        '[绝对]',
                        style: TextStyle(
                          fontSize: 9,
                          color: _getSecondaryTextColor(isDarkMode),
                        ),
                      ),
                      Text(
                        '|',
                        style: TextStyle(
                          fontSize: 11,
                          color: _getSecondaryTextColor(isDarkMode),
                        ),
                      ),
                      Text(
                        '--%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getSecondaryTextColor(isDarkMode),
                        ),
                      ),
                      Text(
                        '[年化]',
                        style: TextStyle(
                          fontSize: 9,
                          color: _getSecondaryTextColor(isDarkMode),
                        ),
                      ),
                    ] else ...[
                      Text(
                        '${absoluteReturn >= 0 ? '+' : ''}${absoluteReturn.toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getProfitColor(absoluteReturn, isDarkMode),
                        ),
                      ),
                      Text(
                        '[绝对]',
                        style: TextStyle(
                          fontSize: 9,
                          color: _getSecondaryTextColor(isDarkMode),
                        ),
                      ),
                      Text(
                        '|',
                        style: TextStyle(
                          fontSize: 11,
                          color: _getSecondaryTextColor(isDarkMode),
                        ),
                      ),
                      Text(
                        '${annualizedReturn >= 0 ? '+' : ''}${annualizedReturn.toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getProfitColor(annualizedReturn, isDarkMode),
                        ),
                      ),
                      Text(
                        '[年化]',
                        style: TextStyle(
                          fontSize: 9,
                          color: _getSecondaryTextColor(isDarkMode),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 第四行：购买日期 和 持有天数（均匀分布）
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '购买日期: ',
                      style: TextStyle(
                        fontSize: 10,
                        color: _getLabelTextColor(isDarkMode),
                      ),
                    ),
                    Text(
                      _formatShortDate(holding.purchaseDate),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _getPrimaryTextColor(isDarkMode),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '持有天数: ',
                      style: TextStyle(
                        fontSize: 10,
                        color: _getLabelTextColor(isDarkMode),
                      ),
                    ),
                    Text(
                      '$days天',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _getPrimaryTextColor(isDarkMode),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 备注
          if (holding.remarks.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '备注: ',
                  style: TextStyle(
                    fontSize: 10,
                    color: _getLabelTextColor(isDarkMode),
                  ),
                ),
                Expanded(
                  child: Text(
                    holding.remarks,
                    style: TextStyle(
                      fontSize: 10,
                      color: _getSecondaryTextColor(isDarkMode),
                    ),
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
                onPressed: onCopyClientId,
                child: Text(
                  '复制客户号',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: holding.clientId.isEmpty
                        ? CupertinoColors.systemGrey
                        : const Color(0xFF007AFF).withOpacity(0.8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minSize: 0,
                onPressed: onGenerateReport,
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
    );
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
}
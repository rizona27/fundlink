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

  String _truncateName(String name, int maxLength) {
    if (name.length <= maxLength) return name;
    return '${name.substring(0, maxLength)}...';
  }

  Color _getProfitColor(double value) {
    if (value > 0) return CupertinoColors.systemRed;
    if (value < 0) return CupertinoColors.systemGreen;
    return CupertinoColors.label.withOpacity(0.5);
  }

  @override
  Widget build(BuildContext context) {
    final days = DateTime.now().difference(holding.purchaseDate).inDays;
    final absoluteReturn = holding.profitRate;
    final annualizedReturn = holding.annualizedProfitRate;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(2, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：基金名称 + 代码 + 净值日期
          Row(
            children: [
              SizedBox(
                width: 85,
                child: Text(
                  _truncateName(holding.fundName, 7),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                holding.fundCode,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF8E8E93),
                ),
              ),
              const Spacer(),
              if (holding.isValid && holding.currentNav > 0)
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${holding.currentNav.toStringAsFixed(4)}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '($_formatDate(holding.navDate))',
                        style: const TextStyle(
                          fontSize: 8,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Text(
                  '净值加载中...',
                  style: TextStyle(
                    fontSize: 9,
                    color: Color(0xFF8E8E93),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // 第二行：购买金额 和 份额 - 移除 Expanded 避免布局错误
          Row(
            children: [
              // 购买金额
              Flexible(
                flex: 1,
                child: Row(
                  children: [
                    Text(
                      '购买金额: ',
                      style: TextStyle(
                        fontSize: 10,
                        color: CupertinoColors.label.withOpacity(0.5),
                      ),
                    ),
                    Text(
                      '${(holding.purchaseAmount / 10000).toStringAsFixed(0)}万',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 份额
              Flexible(
                flex: 1,
                child: Row(
                  children: [
                    Text(
                      '份额: ',
                      style: TextStyle(
                        fontSize: 10,
                        color: CupertinoColors.label.withOpacity(0.5),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        holding.purchaseShares.toStringAsFixed(2),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1C1C1E),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 第三行：收益 和 收益率 - 移除 Expanded
          Row(
            children: [
              // 收益
              Flexible(
                flex: 1,
                child: Row(
                  children: [
                    Text(
                      '收益: ',
                      style: TextStyle(
                        fontSize: 10,
                        color: CupertinoColors.label.withOpacity(0.5),
                      ),
                    ),
                    if (holding.isValid && holding.currentNav > 0)
                      Text(
                        '${holding.profit >= 0 ? '+' : ''}${holding.profit.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getProfitColor(holding.profit),
                        ),
                      )
                    else
                      const Text(
                        '--',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                    const Text('元', style: TextStyle(fontSize: 9)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 收益率
              Flexible(
                flex: 1,
                child: Wrap(
                  spacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '收益率: ',
                      style: TextStyle(
                        fontSize: 10,
                        color: CupertinoColors.label.withOpacity(0.5),
                      ),
                    ),
                    if (holding.isValid && holding.currentNav > 0) ...[
                      Text(
                        '${absoluteReturn >= 0 ? '+' : ''}${absoluteReturn.toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getProfitColor(absoluteReturn),
                        ),
                      ),
                      Text(
                        '[绝对]',
                        style: TextStyle(
                          fontSize: 8,
                          color: CupertinoColors.label.withOpacity(0.4),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${annualizedReturn >= 0 ? '+' : ''}${annualizedReturn.toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getProfitColor(annualizedReturn),
                        ),
                      ),
                      Text(
                        '[年化]',
                        style: TextStyle(
                          fontSize: 8,
                          color: CupertinoColors.label.withOpacity(0.4),
                        ),
                      ),
                    ] else
                      const Text(
                        '--%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 第四行：购买日期 和 持有天数 - 移除 Expanded
          Row(
            children: [
              // 购买日期
              Flexible(
                flex: 1,
                child: Row(
                  children: [
                    Text(
                      '购买日期: ',
                      style: TextStyle(
                        fontSize: 10,
                        color: CupertinoColors.label.withOpacity(0.5),
                      ),
                    ),
                    Text(
                      _formatShortDate(holding.purchaseDate),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 持有天数
              Flexible(
                flex: 1,
                child: Row(
                  children: [
                    Text(
                      '持有天数: ',
                      style: TextStyle(
                        fontSize: 10,
                        color: CupertinoColors.label.withOpacity(0.5),
                      ),
                    ),
                    Text(
                      '$days天',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
                    color: Color(0xFF007AFF).withOpacity(0.8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minSize: 0,
                onPressed: onGenerateReport,
                child: Text(
                  '报告',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF007AFF).withOpacity(0.8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
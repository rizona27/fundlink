import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import '../models/top_holding.dart';

class TopHoldingsWidget extends StatelessWidget {
  final List<TopHolding> topHoldings;
  final Map<String, double> stockQuotes;
  final bool isDark;
  final Function(String stockCode, String stockName)? onStockTap;

  const TopHoldingsWidget({
    super.key,
    required this.topHoldings,
    required this.stockQuotes,
    required this.isDark,
    this.onStockTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '前10重仓股票',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
            ),
          ),
          const SizedBox(height: 12),
          _buildTopHoldingsGrid(),
        ],
      ),
    );
  }

  Widget _buildTopHoldingsGrid() {
    if (topHoldings.isEmpty) {
      return Center(
        child: Text(
          '暂无重仓股数据',
          style: TextStyle(
            color: isDark
                ? CupertinoColors.white.withOpacity(0.5)
                : CupertinoColors.systemGrey,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;

        int crossAxisCount;
        double childAspectRatio;

        final bool isMobile = !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android);

        if (isMobile) {
          if (width < 350) {
            crossAxisCount = 2; 
            childAspectRatio = 3.2; 
          } else if (width < 450) {
            crossAxisCount = 2; 
            childAspectRatio = 3.5;
          } else {
            crossAxisCount = 3; 
            childAspectRatio = 3.8;
          }
        } else {
          if (width < 400) {
            crossAxisCount = 2; 
            childAspectRatio = 3.2; 
          } else if (width < 600) {
            crossAxisCount = 3; 
            childAspectRatio = 3.5;
          } else if (width < 900) {
            crossAxisCount = 4; 
            childAspectRatio = 3.8;
          } else if (width < 1200) {
            crossAxisCount = 5; 
            childAspectRatio = 4.0;
          } else {
            crossAxisCount = 6; 
            childAspectRatio = 4.2;
          }
        }

        return ClipRect(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            child: GridView.builder(
              key: ValueKey('grid_$crossAxisCount'), 
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: childAspectRatio,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: topHoldings.length,
              itemBuilder: (context, index) {
                final h = topHoldings[index];
                String fullCode = '';
                final codeStr = h.stockCode;
                if (codeStr.length == 5 && RegExp(r'^\d{5}$').hasMatch(codeStr)) {
                  fullCode = 'hk$codeStr';
                } else if (codeStr.startsWith('6')) {
                  fullCode = 'sh$codeStr';
                } else if (codeStr.startsWith('0') || codeStr.startsWith('3')) {
                  fullCode = 'sz$codeStr';
                } else if (codeStr.startsWith('5')) {
                  fullCode = 'sz$codeStr';
                } else {
                  fullCode = codeStr;
                }
                final changePercent = stockQuotes[fullCode] ?? 0.0;

                return GestureDetector(
                  onTap: onStockTap != null ? () => onStockTap!(fullCode, h.stockName) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? CupertinoColors.white.withOpacity(0.1)
                            : CupertinoColors.systemGrey.withOpacity(0.2),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                h.stockName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: changePercent > 0
                                          ? CupertinoColors.systemRed.withOpacity(0.2)
                                          : (changePercent < 0
                                              ? CupertinoColors.systemGreen.withOpacity(0.2)
                                              : CupertinoColors.systemGrey.withOpacity(0.2)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w500,
                                        color: changePercent > 0
                                            ? CupertinoColors.systemRed
                                            : (changePercent < 0
                                                ? CupertinoColors.systemGreen
                                                : CupertinoColors.systemGrey),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${h.ratio.toStringAsFixed(2)}%',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isDark
                                          ? CupertinoColors.white.withOpacity(0.6)
                                          : CupertinoColors.systemGrey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _getMarketLabel(fullCode),
                                style: TextStyle(
                                  fontSize: 9,
                                  color: isDark
                                      ? CupertinoColors.white.withOpacity(0.5)
                                      : CupertinoColors.systemGrey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                h.stockCode,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark
                                      ? CupertinoColors.white.withOpacity(0.5)
                                      : CupertinoColors.systemGrey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _getMarketLabel(String fullCode) {
    if (fullCode.startsWith('hk')) {
      return 'HK';
    } else if (fullCode.startsWith('sh')) {
      return '沪A';
    } else if (fullCode.startsWith('sz')) {
      return '深A';
    }
    return '';
  }
}

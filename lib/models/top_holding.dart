//十大重仓
class TopHolding {
  final String stockCode;
  final String stockName;
  final double ratio; // 占净值比例（百分比）

  TopHolding({required this.stockCode, required this.stockName, required this.ratio});

  @override
  String toString() => '$stockName($stockCode): $ratio%';
}
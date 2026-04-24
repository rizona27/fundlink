/// 十大重仓股模型
class TopHolding {
  final String stockCode;
  final String stockName;
  final double ratio;

  TopHolding({required this.stockCode, required this.stockName, required this.ratio});

  @override
  String toString() => '$stockName($stockCode): $ratio%';
}
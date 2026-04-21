//十大重仓
class TopHolding {
  final String stockCode;
  final String stockName;
  final double ratio;

  TopHolding({required this.stockCode, required this.stockName, required this.ratio});

  @override
  String toString() => '$stockName($stockCode): $ratio%';
}
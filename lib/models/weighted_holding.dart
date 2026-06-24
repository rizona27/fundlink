/// A stock holding weighted by the client's investment amount across funds.
///
/// Each instance represents one stock that appears in one or more funds'
/// top-10 holdings.  [weightedRatio] is the asset-weighted exposure (already
/// in percentage), and [fundCodes]/[fundNames] track which funds contribute.
class WeightedHolding {
  final String stockCode;
  final String stockName;
  final double weightedRatio;
  final double totalRatio;
  final Set<String> fundCodes;
  final Set<String> fundNames;

  const WeightedHolding({
    required this.stockCode,
    required this.stockName,
    required this.weightedRatio,
    required this.totalRatio,
    required this.fundCodes,
    required this.fundNames,
  });

  WeightedHolding add(double wr, double rawRatio, String fundCode, String fundName) {
    final newCodes = Set<String>.from(fundCodes)..add(fundCode);
    final newNames = Set<String>.from(fundNames)..add(fundName);
    return WeightedHolding(
      stockCode: stockCode,
      stockName: stockName,
      weightedRatio: weightedRatio + wr,
      totalRatio: totalRatio + rawRatio,
      fundCodes: newCodes,
      fundNames: newNames,
    );
  }
}

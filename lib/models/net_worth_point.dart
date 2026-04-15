class NetWorthPoint {
  final DateTime date;
  final double nav;
  final double? growth;
  final String series;

  NetWorthPoint({
    required this.date,
    required this.nav,
    this.growth,
    this.series = 'fund',
  });

  factory NetWorthPoint.fromJson(Map<String, dynamic> json, {String series = 'fund'}) {
    return NetWorthPoint(
      date: DateTime.fromMillisecondsSinceEpoch(json['x'] as int),
      nav: (json['y'] as num).toDouble(),
      series: series,
    );
  }
}
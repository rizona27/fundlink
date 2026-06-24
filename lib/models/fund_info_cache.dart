class FundInfoCache {
  final String fundCode;
  final String fundName;
  final double currentNav;
  final DateTime navDate;
  final double? navReturn1m;
  final double? navReturn3m;
  final double? navReturn6m;
  final double? navReturn1y;
  final DateTime cacheTime;

  FundInfoCache({
    required this.fundCode,
    required this.fundName,
    required this.currentNav,
    required this.navDate,
    this.navReturn1m,
    this.navReturn3m,
    this.navReturn6m,
    this.navReturn1y,
    required this.cacheTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'fundCode': fundCode,
      'fundName': fundName,
      'currentNav': currentNav,
      'navDate': navDate.toIso8601String(),
      'navReturn1m': navReturn1m,
      'navReturn3m': navReturn3m,
      'navReturn6m': navReturn6m,
      'navReturn1y': navReturn1y,
      'cacheTime': cacheTime.toIso8601String(),
    };
  }

  factory FundInfoCache.fromJson(Map<String, dynamic> json) {
    return FundInfoCache(
      fundCode: json['fundCode'] as String,
      fundName: json['fundName'] as String,
      currentNav: (json['currentNav'] as num).toDouble(),
      navDate: DateTime.parse(json['navDate'] as String),
      navReturn1m: json['navReturn1m'] != null ? (json['navReturn1m'] as num).toDouble() : null,
      navReturn3m: json['navReturn3m'] != null ? (json['navReturn3m'] as num).toDouble() : null,
      navReturn6m: json['navReturn6m'] != null ? (json['navReturn6m'] as num).toDouble() : null,
      navReturn1y: json['navReturn1y'] != null ? (json['navReturn1y'] as num).toDouble() : null,
      cacheTime: DateTime.parse(json['cacheTime'] as String),
    );
  }
}

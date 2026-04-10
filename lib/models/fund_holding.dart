import 'package:flutter/foundation.dart';

class FundHolding {
  final String id;
  final String clientName;
  final String clientId;
  final String fundCode;
  final String fundName;
  final double purchaseAmount;
  final double purchaseShares;
  final DateTime purchaseDate;
  final DateTime navDate;
  final double currentNav;
  final bool isValid;
  final String remarks;
  final bool isPinned;
  final DateTime? pinnedTimestamp;
  final double? navReturn1m;
  final double? navReturn3m;
  final double? navReturn6m;
  final double? navReturn1y;

  FundHolding({
    String? id,
    required this.clientName,
    required this.clientId,
    required this.fundCode,
    required this.fundName,
    required this.purchaseAmount,
    required this.purchaseShares,
    required this.purchaseDate,
    required this.navDate,
    required this.currentNav,
    required this.isValid,
    this.remarks = '',
    this.isPinned = false,
    this.pinnedTimestamp,
    this.navReturn1m,
    this.navReturn3m,
    this.navReturn6m,
    this.navReturn1y,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  double get totalValue => purchaseShares * currentNav;
  double get profit => totalValue - purchaseAmount;
  double get profitRate => purchaseAmount > 0 ? profit / purchaseAmount * 100 : 0;

  double get annualizedProfitRate {
    if (purchaseAmount <= 0) return 0;
    final days = DateTime.now().difference(purchaseDate).inDays;
    if (days <= 0) return 0;
    final totalReturn = profit / purchaseAmount;
    return totalReturn / days * 365 * 100;
  }

  bool get isValidHolding {
    return clientName.isNotEmpty &&
        fundCode.isNotEmpty &&
        purchaseAmount > 0 &&
        purchaseShares > 0;
  }

  FundHolding copyWith({
    String? id,
    String? clientName,
    String? clientId,
    String? fundCode,
    String? fundName,
    double? purchaseAmount,
    double? purchaseShares,
    DateTime? purchaseDate,
    DateTime? navDate,
    double? currentNav,
    bool? isValid,
    String? remarks,
    bool? isPinned,
    DateTime? pinnedTimestamp,
    double? navReturn1m,
    double? navReturn3m,
    double? navReturn6m,
    double? navReturn1y,
  }) {
    return FundHolding(
      id: id ?? this.id,
      clientName: clientName ?? this.clientName,
      clientId: clientId ?? this.clientId,
      fundCode: fundCode ?? this.fundCode,
      fundName: fundName ?? this.fundName,
      purchaseAmount: purchaseAmount ?? this.purchaseAmount,
      purchaseShares: purchaseShares ?? this.purchaseShares,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      navDate: navDate ?? this.navDate,
      currentNav: currentNav ?? this.currentNav,
      isValid: isValid ?? this.isValid,
      remarks: remarks ?? this.remarks,
      isPinned: isPinned ?? this.isPinned,
      pinnedTimestamp: pinnedTimestamp ?? this.pinnedTimestamp,
      navReturn1m: navReturn1m ?? this.navReturn1m,
      navReturn3m: navReturn3m ?? this.navReturn3m,
      navReturn6m: navReturn6m ?? this.navReturn6m,
      navReturn1y: navReturn1y ?? this.navReturn1y,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientName': clientName,
      'clientId': clientId,
      'fundCode': fundCode,
      'fundName': fundName,
      'purchaseAmount': purchaseAmount,
      'purchaseShares': purchaseShares,
      'purchaseDate': purchaseDate.toIso8601String(),
      'navDate': navDate.toIso8601String(),
      'currentNav': currentNav,
      'isValid': isValid,
      'remarks': remarks,
      'isPinned': isPinned,
      'pinnedTimestamp': pinnedTimestamp?.toIso8601String(),
      'navReturn1m': navReturn1m,
      'navReturn3m': navReturn3m,
      'navReturn6m': navReturn6m,
      'navReturn1y': navReturn1y,
    };
  }

  factory FundHolding.fromJson(Map<String, dynamic> json) {
    return FundHolding(
      id: json['id'] as String?,
      clientName: json['clientName'] as String,
      clientId: json['clientId'] as String,
      fundCode: json['fundCode'] as String,
      fundName: json['fundName'] as String,
      purchaseAmount: (json['purchaseAmount'] as num).toDouble(),
      purchaseShares: (json['purchaseShares'] as num).toDouble(),
      purchaseDate: DateTime.parse(json['purchaseDate'] as String),
      navDate: DateTime.parse(json['navDate'] as String),
      currentNav: (json['currentNav'] as num).toDouble(),
      isValid: json['isValid'] as bool,
      remarks: json['remarks'] as String? ?? '',
      isPinned: json['isPinned'] as bool? ?? false,
      pinnedTimestamp: json['pinnedTimestamp'] != null
          ? DateTime.parse(json['pinnedTimestamp'] as String)
          : null,
      navReturn1m: json['navReturn1m'] as double?,
      navReturn3m: json['navReturn3m'] as double?,
      navReturn6m: json['navReturn6m'] as double?,
      navReturn1y: json['navReturn1y'] as double?,
    );
  }

  static FundHolding invalid({required String fundCode}) {
    return FundHolding(
      clientName: '',
      clientId: '',
      fundCode: fundCode,
      fundName: '加载失败',
      purchaseAmount: 0,
      purchaseShares: 0,
      purchaseDate: DateTime.now(),
      navDate: DateTime.now(),
      currentNav: 0,
      isValid: false,
      remarks: '净值获取失败，请检查网络后重试',
    );
  }
}

// 模拟数据生成器 - 使用真实基金代码
class MockData {
  static List<FundHolding> getHoldings() {
    return [
      FundHolding(
        clientName: "张三",
        clientId: "123456789012",
        fundCode: "110022",  // 易方达消费行业股票
        fundName: "加载中...",
        purchaseAmount: 100000,
        purchaseShares: 50000,
        purchaseDate: DateTime(2024, 1, 15),
        navDate: DateTime.now(),
        currentNav: 0,
        isValid: false,
        remarks: "待加载净值",
      ),
      FundHolding(
        clientName: "张三",
        clientId: "123456789012",
        fundCode: "163406",  // 兴全合润混合
        fundName: "加载中...",
        purchaseAmount: 80000,
        purchaseShares: 30000,
        purchaseDate: DateTime(2024, 2, 20),
        navDate: DateTime.now(),
        currentNav: 0,
        isValid: false,
        remarks: "待加载净值",
      ),
      FundHolding(
        clientName: "李四",
        clientId: "234567890123",
        fundCode: "519069",  // 汇添富价值精选
        fundName: "加载中...",
        purchaseAmount: 50000,
        purchaseShares: 20000,
        purchaseDate: DateTime(2024, 3, 10),
        navDate: DateTime.now(),
        currentNav: 0,
        isValid: false,
        remarks: "待加载净值",
      ),
      FundHolding(
        clientName: "李四",
        clientId: "234567890123",
        fundCode: "000001",  // 华夏成长混合
        fundName: "加载中...",
        purchaseAmount: 60000,
        purchaseShares: 25000,
        purchaseDate: DateTime(2024, 4, 5),
        navDate: DateTime.now(),
        currentNav: 0,
        isValid: false,
        remarks: "待加载净值",
      ),
      FundHolding(
        clientName: "王五",
        clientId: "345678901234",
        fundCode: "110011",  // 易方达中小盘混合
        fundName: "加载中...",
        purchaseAmount: 120000,
        purchaseShares: 45000,
        purchaseDate: DateTime(2024, 5, 15),
        navDate: DateTime.now(),
        currentNav: 0,
        isValid: false,
        remarks: "待加载净值",
      ),
      FundHolding(
        clientName: "赵六",
        clientId: "456789012345",
        fundCode: "519688",  // 交银精选混合
        fundName: "加载中...",
        purchaseAmount: 75000,
        purchaseShares: 28000,
        purchaseDate: DateTime(2024, 6, 20),
        navDate: DateTime.now(),
        currentNav: 0,
        isValid: false,
        remarks: "待加载净值",
      ),
    ];
  }
}
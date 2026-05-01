import 'package:uuid/uuid.dart';
import 'transaction_record.dart';

class FundHolding {
  final String id;
  final String clientName;
  final String clientId;
  final String fundCode;
  final String fundName;
  
  final double totalShares;
  final double totalCost;
  final double averageCost;
  
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
  
  final List<String> transactionIds;

  FundHolding({
    String? id,
    required this.clientName,
    required this.clientId,
    required this.fundCode,
    required this.fundName,
    required this.totalShares,
    required this.totalCost,
    required this.averageCost,
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
    this.transactionIds = const [],
  }) : id = id ?? const Uuid().v4();

  double get totalValue => totalShares * currentNav;
  double get profit => totalValue - totalCost;
  double get profitRate => totalCost > 0 ? profit / totalCost * 100 : 0;

  bool get isValidHolding {
    return clientName.isNotEmpty &&
        fundCode.isNotEmpty &&
        totalCost > 0;
  }

  FundHolding copyWith({
    String? id,
    String? clientName,
    String? clientId,
    String? fundCode,
    String? fundName,
    double? totalShares,
    double? totalCost,
    double? averageCost,
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
    List<String>? transactionIds,
  }) {
    return FundHolding(
      id: id ?? this.id,
      clientName: clientName ?? this.clientName,
      clientId: clientId ?? this.clientId,
      fundCode: fundCode ?? this.fundCode,
      fundName: fundName ?? this.fundName,
      totalShares: totalShares ?? this.totalShares,
      totalCost: totalCost ?? this.totalCost,
      averageCost: averageCost ?? this.averageCost,
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
      transactionIds: transactionIds ?? this.transactionIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientName': clientName,
      'clientId': clientId,
      'fundCode': fundCode,
      'fundName': fundName,
      'totalShares': totalShares,
      'totalCost': totalCost,
      'averageCost': averageCost,
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
      'transactionIds': transactionIds,
    };
  }

  factory FundHolding.fromJson(Map<String, dynamic> json) {
    double totalShares;
    double totalCost;
    double averageCost;
    
    if (json.containsKey('totalShares')) {
      totalShares = json['totalShares'] != null ? (json['totalShares'] as num).toDouble() : 0.0;
      totalCost = json['totalCost'] != null ? (json['totalCost'] as num).toDouble() : 0.0;
      averageCost = json['averageCost'] != null ? (json['averageCost'] as num).toDouble() : 0.0;
    } else if (json.containsKey('purchaseShares')) {
      totalShares = json['purchaseShares'] != null ? (json['purchaseShares'] as num).toDouble() : 0.0;
      totalCost = json['purchaseAmount'] != null ? (json['purchaseAmount'] as num).toDouble() : 0.0;
      averageCost = totalShares > 0 ? totalCost / totalShares : 0.0;
    } else {
      totalShares = 0.0;
      totalCost = 0.0;
      averageCost = 0.0;
    }
    
    return FundHolding(
      id: json['id'] as String?,
      clientName: json['clientName'] as String,
      clientId: json['clientId'] as String,
      fundCode: json['fundCode'] as String,
      fundName: json['fundName'] as String,
      totalShares: totalShares,
      totalCost: totalCost,
      averageCost: averageCost,
      navDate: DateTime.parse(json['navDate'] as String),
      currentNav: (json['currentNav'] as num?)?.toDouble() ?? 0.0,
      isValid: json['isValid'] as bool? ?? false,
      remarks: json['remarks'] as String? ?? '',
      isPinned: json['isPinned'] as bool? ?? false,
      pinnedTimestamp: json['pinnedTimestamp'] != null
          ? DateTime.parse(json['pinnedTimestamp'] as String)
          : null,
      navReturn1m: json['navReturn1m'] as double?,
      navReturn3m: json['navReturn3m'] as double?,
      navReturn6m: json['navReturn6m'] as double?,
      navReturn1y: json['navReturn1y'] as double?,
      transactionIds: json['transactionIds'] != null
          ? List<String>.from(json['transactionIds'] as List)
          : [],
    );
  }

  /// 转换为 SQLite Map（用于数据库存储）
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'client_name': clientName,
      'client_id': clientId,
      'fund_code': fundCode,
      'fund_name': fundName,
      'total_shares': totalShares,
      'total_cost': totalCost,
      'avg_cost': averageCost,
      'nav_date': navDate.toIso8601String(),
      'current_nav': currentNav,
      'remarks': remarks,
      'is_pinned': isPinned ? 1 : 0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  /// 从 SQLite Map 创建对象（用于数据库读取）
  factory FundHolding.fromMap(Map<String, dynamic> map) {
    return FundHolding(
      id: map['id'] as String,
      clientName: map['client_name'] as String,
      clientId: map['client_id'] as String? ?? '',
      fundCode: map['fund_code'] as String,
      fundName: map['fund_name'] as String,
      totalShares: (map['total_shares'] as num?)?.toDouble() ?? 0.0,
      totalCost: (map['total_cost'] as num?)?.toDouble() ?? 0.0,
      averageCost: (map['avg_cost'] as num?)?.toDouble() ?? 0.0,
      navDate: DateTime.parse(map['nav_date'] as String),
      currentNav: (map['current_nav'] as num?)?.toDouble() ?? 0.0,
      isValid: true,
      remarks: map['remarks'] as String? ?? '',
      isPinned: (map['is_pinned'] as int?) == 1,
      pinnedTimestamp: null,
      navReturn1m: null,
      navReturn3m: null,
      navReturn6m: null,
      navReturn1y: null,
      transactionIds: [],
    );
  }

  static FundHolding invalid({required String fundCode}) {
    return FundHolding(
      clientName: '',
      clientId: '',
      fundCode: fundCode,
      fundName: '加载失败',
      totalShares: 0,
      totalCost: 0,
      averageCost: 0,
      navDate: DateTime.now(),
      currentNav: 0,
      isValid: false,
      remarks: '净值获取失败，请检查网络后重试',
    );
  }
  
  static FundHolding fromTransactions({
    required String clientId,
    required String clientName,
    required String fundCode,
    required String fundName,
    required List<TransactionRecord> transactions,
    required DateTime navDate,
    required double currentNav,
    required bool isValid,
    String remarks = '',
    bool isPinned = false,
    DateTime? pinnedTimestamp,
    double? navReturn1m,
    double? navReturn3m,
    double? navReturn6m,
    double? navReturn1y,
  }) {
    double totalShares = 0;
    double totalCost = 0;
    
    for (final tx in transactions) {
      if (tx.isBuy) {
        totalShares += tx.shares;
        totalCost += tx.amount;
      } else if (tx.isSell) {
        if (totalShares > 0) {
          final costPerShare = totalCost / totalShares;
          totalCost -= tx.shares * costPerShare;
          totalShares -= tx.shares;
        }
      }
    }
    
    final averageCost = totalShares > 0 ? totalCost / totalShares : 0.0;
    final transactionIds = transactions.map((tx) => tx.id).toList();
    
    return FundHolding(
      clientId: clientId,
      clientName: clientName,
      fundCode: fundCode,
      fundName: fundName,
      totalShares: totalShares,
      totalCost: totalCost,
      averageCost: averageCost.toDouble(),
      navDate: navDate,
      currentNav: currentNav.toDouble(),
      isValid: isValid,
      remarks: remarks,
      isPinned: isPinned,
      pinnedTimestamp: pinnedTimestamp,
      navReturn1m: navReturn1m,
      navReturn3m: navReturn3m,
      navReturn6m: navReturn6m,
      navReturn1y: navReturn1y,
      transactionIds: transactionIds,
    );
  }
}
import 'package:uuid/uuid.dart';

enum TransactionType {
  buy,
  sell,
}

extension TransactionTypeExtension on TransactionType {
  String get displayName {
    switch (this) {
      case TransactionType.buy:
        return '买入';
      case TransactionType.sell:
        return '卖出';
    }
  }

  String get code {
    switch (this) {
      case TransactionType.buy:
        return 'BUY';
      case TransactionType.sell:
        return 'SELL';
    }
  }

  static TransactionType fromCode(String code) {
    switch (code.toUpperCase()) {
      case 'BUY':
        return TransactionType.buy;
      case 'SELL':
        return TransactionType.sell;
      default:
        throw ArgumentError('Unknown transaction type code: $code');
    }
  }
}

class TransactionRecord {
  final String id;
  final String clientId;
  final String clientName;
  final String fundCode;
  final String fundName;
  final TransactionType type;
  final double amount;
  final double shares;
  final DateTime tradeDate;
  final double? nav;
  final double? fee;
  final String remarks;
  final DateTime createdAt;
  final bool isAfter1500;
  final bool isPending;
  final double? confirmedNav;

  TransactionRecord({
    String? id,
    required this.clientId,
    required this.clientName,
    required this.fundCode,
    required this.fundName,
    required this.type,
    required this.amount,
    required this.shares,
    required this.tradeDate,
    this.nav,
    this.fee,
    this.remarks = '',
    DateTime? createdAt,
    this.isAfter1500 = false,
    this.isPending = false,
    this.confirmedNav,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  bool get isBuy => type == TransactionType.buy;
  bool get isSell => type == TransactionType.sell;

  double get netAmount => isBuy ? amount : -amount;
  double get netShares => isBuy ? shares : -shares;

  TransactionRecord copyWith({
    String? id,
    String? clientId,
    String? clientName,
    String? fundCode,
    String? fundName,
    TransactionType? type,
    double? amount,
    double? shares,
    DateTime? tradeDate,
    double? nav,
    double? fee,
    String? remarks,
    DateTime? createdAt,
    bool? isAfter1500,
    bool? isPending,
    double? confirmedNav,
  }) {
    return TransactionRecord(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      fundCode: fundCode ?? this.fundCode,
      fundName: fundName ?? this.fundName,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      shares: shares ?? this.shares,
      tradeDate: tradeDate ?? this.tradeDate,
      nav: nav ?? this.nav,
      fee: fee ?? this.fee,
      remarks: remarks ?? this.remarks,
      createdAt: createdAt ?? this.createdAt,
      isAfter1500: isAfter1500 ?? this.isAfter1500,
      isPending: isPending ?? this.isPending,
      confirmedNav: confirmedNav ?? this.confirmedNav,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientId': clientId,
      'clientName': clientName,
      'fundCode': fundCode,
      'fundName': fundName,
      'type': type.code,
      'amount': amount,
      'shares': shares,
      'tradeDate': tradeDate.toIso8601String(),
      'nav': nav,
      'fee': fee,
      'remarks': remarks,
      'createdAt': createdAt.toIso8601String(),
      'isAfter1500': isAfter1500,
      'isPending': isPending,
      'confirmedNav': confirmedNav,
    };
  }

  factory TransactionRecord.fromJson(Map<String, dynamic> json) {
    return TransactionRecord(
      id: json['id'] as String?,
      clientId: json['clientId'] as String,
      clientName: json['clientName'] as String,
      fundCode: json['fundCode'] as String,
      fundName: json['fundName'] as String,
      type: TransactionTypeExtension.fromCode(json['type'] as String),
      amount: (json['amount'] as num).toDouble(),
      shares: (json['shares'] as num).toDouble(),
      tradeDate: DateTime.parse(json['tradeDate'] as String),
      nav: json['nav'] != null ? (json['nav'] as num).toDouble() : null,
      fee: json['fee'] != null ? (json['fee'] as num).toDouble() : null,
      remarks: json['remarks'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      isAfter1500: json['isAfter1500'] as bool? ?? false,
      isPending: json['isPending'] as bool? ?? false,
      confirmedNav: json['confirmedNav'] != null ? (json['confirmedNav'] as num).toDouble() : null,
    );
  }

  /// 转换为 SQLite Map（用于数据库存储）
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'holding_id': '${clientId}_$fundCode',
      'client_id': clientId,
      'client_name': clientName,
      'fund_code': fundCode,
      'fund_name': fundName,
      'type': type.code,
      'amount': amount,
      'shares': shares,
      'nav': nav,
      'fee_rate': 0.0,
      'fee_amount': fee ?? 0.0,
      'trade_date': tradeDate.toIso8601String(),
      'confirm_date': null,
      'is_after_1500': isAfter1500 ? 1 : 0,
      'status': isPending ? 'pending' : 'confirmed',
      'remarks': remarks,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// 从 SQLite Map 创建对象（用于数据库读取）
  factory TransactionRecord.fromMap(Map<String, dynamic> map) {
    return TransactionRecord(
      id: map['id'] as String,
      clientId: map['client_id'] as String? ?? '',
      clientName: map['client_name'] as String? ?? '',
      fundCode: map['fund_code'] as String? ?? '',
      fundName: map['fund_name'] as String? ?? '',
      type: TransactionTypeExtension.fromCode(map['type'] as String),
      amount: (map['amount'] as num).toDouble(),
      shares: (map['shares'] as num?)?.toDouble() ?? 0.0,
      tradeDate: DateTime.parse(map['trade_date'] as String),
      nav: map['nav'] != null ? (map['nav'] as num).toDouble() : null,
      fee: map['fee_amount'] != null ? (map['fee_amount'] as num).toDouble() : null,
      remarks: map['remarks'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      isAfter1500: (map['is_after_1500'] as int?) == 1,
      isPending: (map['status'] as String?) == 'pending',
      confirmedNav: map['confirmed_nav'] != null ? (map['confirmed_nav'] as num).toDouble() : null,
    );
  }

  @override
  String toString() {
    return 'TransactionRecord(id: $id, type: ${type.displayName}, '
        'fundCode: $fundCode, amount: $amount, shares: $shares, '
        'tradeDate: $tradeDate)';
  }
}

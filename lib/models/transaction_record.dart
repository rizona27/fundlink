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
  final double? nav; // 交易时填写的净值(可能为null)
  final double? fee;
  final String remarks;
  final DateTime createdAt;
  final bool isAfter1500; // 是否15:00后交易（影响净值日期选择）
  final bool isPending; // 是否为待确认交易(当天15:00前的交易,净值尚未公布)
  final double? confirmedNav; // 已确认的净值(T+1或T+2日后从API获取)

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
    this.isAfter1500 = false, // 默认15:00前
    this.isPending = false, // 默认为已确认
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

  @override
  String toString() {
    return 'TransactionRecord(id: $id, type: ${type.displayName}, '
        'fundCode: $fundCode, amount: $amount, shares: $shares, '
        'tradeDate: $tradeDate)';
  }
}

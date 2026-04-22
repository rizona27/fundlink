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
    );
  }

  @override
  String toString() {
    return 'TransactionRecord(id: $id, type: ${type.displayName}, '
        'fundCode: $fundCode, amount: $amount, shares: $shares, '
        'tradeDate: $tradeDate)';
  }
}

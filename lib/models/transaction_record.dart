import 'package:uuid/uuid.dart';

enum TransactionType {
  buy,
  sell,
}

/// 交易申请状态枚举
enum TransactionStatus {
  pendingSubmit,   // 待提交：用户已下单，尚未到达合法交易时间（如节假日前置申请）
  submitted,       // 已提交：交易指令已到达交易系统，等待未知价净值
  pendingConfirm,  // 待确认：T日净值已出，已成交易成本，正等待份额到账
  confirmed,       // 已确认：份额已到账
  confirmFailed,   // 确认失败：重试5次后仍无法获取份额，转为人工处理
  cancelled,       // 已撤销：在规定时间内撤单
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
  final TransactionStatus status;           // 交易状态
  final int retryCount;                     // 净值获取重试次数
  final DateTime? applicationDate;          // 交易申请日(T日_申请)
  final DateTime? confirmDate;              // 确认日期(份额到账日)
  final double? frozenShares;               // 冻结份额(用于赎回)

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
    this.status = TransactionStatus.submitted,
    this.retryCount = 0,
    this.applicationDate,
    this.confirmDate,
    this.frozenShares,
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
    TransactionStatus? status,
    int? retryCount,
    DateTime? applicationDate,
    DateTime? confirmDate,
    double? frozenShares,
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
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      applicationDate: applicationDate ?? this.applicationDate,
      confirmDate: confirmDate ?? this.confirmDate,
      frozenShares: frozenShares ?? this.frozenShares,
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
      'status': status.name,
      'retryCount': retryCount,
      'applicationDate': applicationDate?.toIso8601String(),
      'confirmDate': confirmDate?.toIso8601String(),
      'frozenShares': frozenShares,
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
      status: json['status'] != null 
          ? TransactionStatus.values.firstWhere((e) => e.name == json['status'], orElse: () => TransactionStatus.submitted)
          : TransactionStatus.submitted,
      retryCount: json['retryCount'] as int? ?? 0,
      applicationDate: json['applicationDate'] != null ? DateTime.parse(json['applicationDate'] as String) : null,
      confirmDate: json['confirmDate'] != null ? DateTime.parse(json['confirmDate'] as String) : null,
      frozenShares: json['frozenShares'] != null ? (json['frozenShares'] as num).toDouble() : null,
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

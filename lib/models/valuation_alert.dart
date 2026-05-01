import 'package:uuid/uuid.dart';

/// 估值预警规则模型
class ValuationAlert {
  final String id;
  final String fundCode;
  String fundName;
  final double? thresholdUp;    // 上涨阈值（百分比）
  final double? thresholdDown;  // 下跌阈值（百分比）
  bool isEnabled;
  final String? activeHoursStart; // 活跃开始时间 "09:30"
  final String? activeHoursEnd;   // 活跃结束时间 "15:30"
  final DateTime createdAt;
  final DateTime updatedAt;

  ValuationAlert({
    String? id,
    required this.fundCode,
    this.fundName = '',
    this.thresholdUp,
    this.thresholdDown,
    this.isEnabled = true,
    this.activeHoursStart,
    this.activeHoursEnd,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory ValuationAlert.fromMap(Map<String, dynamic> map) {
    return ValuationAlert(
      id: map['id'] as String,
      fundCode: map['fund_code'] as String,
      fundName: map['fund_name'] as String? ?? '',
      thresholdUp: map['threshold_up'] as double?,
      thresholdDown: map['threshold_down'] as double?,
      isEnabled: (map['is_enabled'] as int) == 1,
      activeHoursStart: map['active_hours_start'] as String?,
      activeHoursEnd: map['active_hours_end'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fund_code': fundCode,
      'fund_name': fundName,
      'threshold_up': thresholdUp,
      'threshold_down': thresholdDown,
      'is_enabled': isEnabled ? 1 : 0,
      'active_hours_start': activeHoursStart,
      'active_hours_end': activeHoursEnd,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  ValuationAlert copyWith({
    String? fundCode,
    String? fundName,
    double? thresholdUp,
    double? thresholdDown,
    bool? isEnabled,
    String? activeHoursStart,
    String? activeHoursEnd,
  }) {
    return ValuationAlert(
      id: id,
      fundCode: fundCode ?? this.fundCode,
      fundName: fundName ?? this.fundName,
      thresholdUp: thresholdUp ?? this.thresholdUp,
      thresholdDown: thresholdDown ?? this.thresholdDown,
      isEnabled: isEnabled ?? this.isEnabled,
      activeHoursStart: activeHoursStart ?? this.activeHoursStart,
      activeHoursEnd: activeHoursEnd ?? this.activeHoursEnd,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'ValuationAlert(id: $id, fundCode: $fundCode, up: $thresholdUp, down: $thresholdDown, enabled: $isEnabled)';
  }

  /// 创建一个空对象，用于判断是否存在
  static ValuationAlert empty() {
    return ValuationAlert(
      id: '',
      fundCode: '',
    );
  }
}

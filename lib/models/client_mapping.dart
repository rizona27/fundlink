/// 客户号与客户名映射关系模型
class ClientMapping {
  final String id;              // 唯一标识
  final String clientId;        // 客户号
  final String clientName;      // 客户名
  final DateTime createdAt;     // 创建时间
  final DateTime updatedAt;     // 更新时间

  ClientMapping({
    required this.id,
    required this.clientId,
    required this.clientName,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 从 JSON 创建
  factory ClientMapping.fromJson(Map<String, dynamic> json) {
    return ClientMapping(
      id: json['id'] as String,
      clientId: json['clientId'] as String,
      clientName: json['clientName'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientId': clientId,
      'clientName': clientName,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 复制并更新
  ClientMapping copyWith({
    String? id,
    String? clientId,
    String? clientName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ClientMapping(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'ClientMapping(id: $id, clientId: $clientId, clientName: $clientName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ClientMapping &&
        other.id == id &&
        other.clientId == clientId &&
        other.clientName == clientName;
  }

  @override
  int get hashCode {
    return id.hashCode ^ clientId.hashCode ^ clientName.hashCode;
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum LogType {
  info,
  success,
  error,
  warning,
  network,
  cache,
}

extension LogTypeExtension on LogType {
  String get displayName {
    switch (this) {
      case LogType.info:
        return '信息';
      case LogType.success:
        return '成功';
      case LogType.error:
        return '错误';
      case LogType.warning:
        return '警告';
      case LogType.network:
        return '网络';
      case LogType.cache:
        return '缓存';
    }
  }

  Color get color {
    switch (this) {
      case LogType.info:
        return const Color(0xFF007AFF);
      case LogType.success:
        return const Color(0xFF34C759);
      case LogType.error:
        return const Color(0xFFFF3B30);
      case LogType.warning:
        return const Color(0xFFFF9500);
      case LogType.network:
        return const Color(0xFFAF52DE); 
      case LogType.cache:
        return const Color(0xFFFF2D55);
    }
  }
}

@immutable
class LogEntry {
  final String id;
  final String message;
  final LogType type;
  final DateTime timestamp;

  const LogEntry({
    required this.id,
    required this.message,
    required this.type,
    required this.timestamp,
  });

  factory LogEntry.create({
    required String message,
    required LogType type,
  }) {
    return LogEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      message: message,
      type: type,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'message': message,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      id: json['id'] as String,
      message: json['message'] as String,
      type: LogType.values.firstWhere(
            (e) => e.name == json['type'],
        orElse: () => LogType.info,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LogEntry && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
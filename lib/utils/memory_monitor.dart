import 'dart:async';
import 'package:flutter/foundation.dart';

/// 内存监控工具
class MemoryMonitor {
  static final MemoryMonitor _instance = MemoryMonitor._internal();
  factory MemoryMonitor() => _instance;
  MemoryMonitor._internal();
  
  Timer? _monitorTimer;
  final List<MemorySnapshot> _history = [];
  static const int maxHistorySize = 100;
  
  // 阈值配置
  int warningThresholdMB = 200;
  int criticalThresholdMB = 400;
  
  // 回调函数
  Function(MemorySnapshot)? onWarning;
  Function(MemorySnapshot)? onCritical;
  
  /// 开始监控
  void startMonitoring({Duration interval = const Duration(seconds: 10)}) {
    stopMonitoring();
    
    _monitorTimer = Timer.periodic(interval, (_) {
      _checkMemory();
    });
    
    debugPrint('内存监控已启动');
  }
  
  /// 停止监控
  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    debugPrint('内存监控已停止');
  }
  
  /// 检查内存使用
  void _checkMemory() {
    final snapshot = takeSnapshot();
    
    // 保存历史记录
    _history.add(snapshot);
    if (_history.length > maxHistorySize) {
      _history.removeAt(0);
    }
    
    // 检查阈值
    final memoryMB = snapshot.memoryUsageMB;
    
    if (memoryMB >= criticalThresholdMB) {
      debugPrint('⚠️ 严重警告: 内存使用 ${memoryMB.toStringAsFixed(2)} MB');
      onCritical?.call(snapshot);
    } else if (memoryMB >= warningThresholdMB) {
      debugPrint('⚡ 警告: 内存使用 ${memoryMB.toStringAsFixed(2)} MB');
      onWarning?.call(snapshot);
    }
  }
  
  /// 获取内存快照
  MemorySnapshot takeSnapshot() {
    final info = MemoryInfo.current();
    return MemorySnapshot(
      timestamp: DateTime.now(),
      memoryUsageMB: info.currentRSS / (1024 * 1024),
      cacheCount: _cacheCount,
      widgetCount: _widgetCount,
    );
  }
  
  // 缓存和组件计数（需要手动更新）
  int _cacheCount = 0;
  int _widgetCount = 0;
  
  void updateCacheCount(int count) {
    _cacheCount = count;
  }
  
  void updateWidgetCount(int count) {
    _widgetCount = count;
  }
  
  /// 获取内存历史
  List<MemorySnapshot> get history => List.unmodifiable(_history);
  
  /// 获取平均内存使用
  double get averageMemoryUsageMB {
    if (_history.isEmpty) return 0.0;
    final sum = _history.fold<double>(0, (sum, item) => sum + item.memoryUsageMB);
    return sum / _history.length;
  }
  
  /// 获取峰值内存使用
  double get peakMemoryUsageMB {
    if (_history.isEmpty) return 0.0;
    return _history.map((e) => e.memoryUsageMB).reduce((a, b) => a > b ? a : b);
  }
  
  /// 打印内存报告
  void printReport() {
    final current = takeSnapshot();
    debugPrint('''
===== 内存使用报告 =====
当前使用: ${current.memoryUsageMB.toStringAsFixed(2)} MB
平均使用: ${averageMemoryUsageMB.toStringAsFixed(2)} MB
峰值使用: ${peakMemoryUsageMB.toStringAsFixed(2)} MB
缓存数量: ${current.cacheCount}
组件数量: ${current.widgetCount}
========================
''');
  }
  
  /// 清理资源
  void dispose() {
    stopMonitoring();
    _history.clear();
  }
}

/// 内存快照
class MemorySnapshot {
  final DateTime timestamp;
  final double memoryUsageMB;
  final int cacheCount;
  final int widgetCount;
  
  MemorySnapshot({
    required this.timestamp,
    required this.memoryUsageMB,
    required this.cacheCount,
    required this.widgetCount,
  });
  
  @override
  String toString() {
    return 'MemorySnapshot(${memoryUsageMB.toStringAsFixed(2)} MB, caches: $cacheCount, widgets: $widgetCount)';
  }
}

/// 内存信息（跨平台兼容）
class MemoryInfo {
  static MemoryInfoData current() {
    try {
      // 注意：ProcessInfo 只在部分平台可用
      // 这里返回模拟数据，实际使用时需要根据平台适配
      return MemoryInfoData(
        currentRSS: 50 * 1024 * 1024, // 默认 50MB
        maxRSS: 200 * 1024 * 1024,   // 默认 200MB
      );
    } catch (e) {
      return MemoryInfoData(currentRSS: 0, maxRSS: 0);
    }
  }
}

class MemoryInfoData {
  final int currentRSS;
  final int maxRSS;
  
  MemoryInfoData({required this.currentRSS, required this.maxRSS});
}

import 'dart:async';
import 'package:flutter/foundation.dart';

// ✅ 条件导入：原生平台使用 flutter_memory_info，Web平台使用模拟数据
import 'memory_info_native.dart' if (dart.library.html) 'memory_info_web.dart' as memory_info;

/// 内存监控工具
class MemoryMonitor {
  static final MemoryMonitor _instance = MemoryMonitor._internal();
  factory MemoryMonitor() => _instance;
  MemoryMonitor._internal();
  
  Timer? _monitorTimer;
  final List<MemorySnapshot> _history = [];
  static const int maxHistorySize = 100;
  
  // 防止已销毁后仍执行操作
  bool _disposed = false;
  
  // 阈值配置
  int warningThresholdMB = 200;
  int criticalThresholdMB = 400;
  
  // 回调函数
  Function(MemorySnapshot)? onWarning;
  Function(MemorySnapshot)? onCritical;
  
  /// 开始监控
  void startMonitoring({Duration interval = const Duration(seconds: 10)}) {
    if (_disposed) return;  // ✅ 防止已销毁后仍启动
    
    stopMonitoring();
    
    _monitorTimer = Timer.periodic(interval, (_) {
      if (!_disposed) {  // ✅ 每次执行前检查
        // 使用 unawaited 来处理 async 函数
        _checkMemory().catchError((e) {
          debugPrint('内存检查异常: $e');
        });
      }
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
  Future<void> _checkMemory() async {
    final snapshot = await takeSnapshot();
    
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
  Future<MemorySnapshot> takeSnapshot() async {
    double memoryUsageMB = 0;
    
    try {
      // ✅ 使用条件导入的平台特定实现
      final info = await memory_info.getMemoryInfo();
      memoryUsageMB = info / (1024 * 1024);
    } catch (e) {
      debugPrint('获取内存信息失败: $e');
      memoryUsageMB = 50.0; // 降级：默认 50MB
    }
    
    return MemorySnapshot(
      timestamp: DateTime.now(),
      memoryUsageMB: memoryUsageMB,
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
    current.then((snapshot) {  // ✅ 修复：takeSnapshot返回Future
      debugPrint('''
===== 内存使用报告 =====
当前使用: ${snapshot.memoryUsageMB.toStringAsFixed(2)} MB
平均使用: ${averageMemoryUsageMB.toStringAsFixed(2)} MB
峰值使用: ${peakMemoryUsageMB.toStringAsFixed(2)} MB
缓存数量: ${snapshot.cacheCount}
组件数量: ${snapshot.widgetCount}
========================
''');
    });
  }
  
  /// 清理资源
  void dispose() {
    _disposed = true;  // ✅ 标记为已销毁
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

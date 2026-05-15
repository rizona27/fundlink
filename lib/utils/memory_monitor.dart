import 'dart:async';

import 'memory_info_native.dart' if (dart.library.html) 'memory_info_web.dart' as memory_info;

class MemoryMonitor {
  static final MemoryMonitor _instance = MemoryMonitor._internal();
  factory MemoryMonitor() => _instance;
  MemoryMonitor._internal();
  
  Timer? _monitorTimer;
  final List<MemorySnapshot> _history = [];
  static const int maxHistorySize = 100;
  
  bool _disposed = false;
  
  int warningThresholdMB = 200;
  int criticalThresholdMB = 400;
  
  Function(MemorySnapshot)? onWarning;
  Function(MemorySnapshot)? onCritical;
  
  void startMonitoring({Duration interval = const Duration(seconds: 10)}) {
    if (_disposed) return;
    
    stopMonitoring();
    
    _monitorTimer = Timer.periodic(interval, (_) {
      if (!_disposed) {
        _checkMemory().catchError((e) {
        });
      }
    });
  }
  
  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }
  
  Future<void> _checkMemory() async {
    final snapshot = await takeSnapshot();
    
    _history.add(snapshot);
    if (_history.length > maxHistorySize) {
      _history.removeAt(0);
    }
    
    final memoryMB = snapshot.memoryUsageMB;
    
    if (memoryMB >= criticalThresholdMB) {
      onCritical?.call(snapshot);
    } else if (memoryMB >= warningThresholdMB) {
      onWarning?.call(snapshot);
    }
  }
  
  Future<MemorySnapshot> takeSnapshot() async {
    double memoryUsageMB = 0;
    
    try {
      final info = await memory_info.getMemoryInfo();
      memoryUsageMB = info / (1024 * 1024);
    } catch (e) {
      memoryUsageMB = 50.0;
    }
    
    return MemorySnapshot(
      timestamp: DateTime.now(),
      memoryUsageMB: memoryUsageMB,
      cacheCount: _cacheCount,
      widgetCount: _widgetCount,
    );
  }
  
  int _cacheCount = 0;
  int _widgetCount = 0;
  
  void updateCacheCount(int count) {
    _cacheCount = count;
  }
  
  void updateWidgetCount(int count) {
    _widgetCount = count;
  }
  
  List<MemorySnapshot> get history => List.unmodifiable(_history);
  
  double get averageMemoryUsageMB {
    if (_history.isEmpty) return 0.0;
    final sum = _history.fold<double>(0, (sum, item) => sum + item.memoryUsageMB);
    return sum / _history.length;
  }
  
  double get peakMemoryUsageMB {
    if (_history.isEmpty) return 0.0;
    return _history.map((e) => e.memoryUsageMB).reduce((a, b) => a > b ? a : b);
  }
  
  void printReport() {
    final current = takeSnapshot();
    current.then((snapshot) {
    });
  }
  
  void dispose() {
    _disposed = true;
    stopMonitoring();
    _history.clear();
  }
}

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

class MemoryInfo {
  static MemoryInfoData current() {
    try {
      return MemoryInfoData(
        currentRSS: 50 * 1024 * 1024,
        maxRSS: 200 * 1024 * 1024,
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

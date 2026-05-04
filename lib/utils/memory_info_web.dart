/// Web平台内存信息实现
/// Web平台不支持 dart:ffi，使用浏览器 Performance API 获取近似值

import 'dart:js_interop';

@JS('performance.memory')
external JSObject? get jsMemoryInfo;

/// 获取内存使用量（字节）
/// 
/// 注意：Chrome/Edge 支持 performance.memory API
/// 其他浏览器可能返回 null，此时使用估算值
Future<int> getMemoryInfo() async {
  try {
    // 尝试使用 Chrome 的 performance.memory API
    final memory = jsMemoryInfo;
    if (memory != null) {
      final usedJSHeapSize = (memory as dynamic)['usedJSHeapSize'] as num?;
      if (usedJSHeapSize != null && usedJSHeapSize > 0) {
        return usedJSHeapSize.toInt();
      }
    }
    
    // 降级方案：基于 Dart VM 估算
    // Web平台无法获取精确的原生内存，只能估算
    return _estimateWebMemory();
  } catch (e) {
    // 任何错误都返回默认值
    return 50 * 1024 * 1024; // 50MB
  }
}

/// 估算Web内存使用
int _estimateWebMemory() {
  // 简单估算：基于常见的Flutter Web应用内存使用
  // 实际值可能在 30-100MB 之间
  return 50 * 1024 * 1024; // 50MB
}

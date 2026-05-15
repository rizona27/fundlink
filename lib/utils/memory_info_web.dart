
import 'dart:js_interop';

@JS('performance.memory')
external JSObject? get jsMemoryInfo;

Future<int> getMemoryInfo() async {
  try {
    final memory = jsMemoryInfo;
    if (memory != null) {
      final usedJSHeapSize = (memory as dynamic)['usedJSHeapSize'] as num?;
      if (usedJSHeapSize != null && usedJSHeapSize > 0) {
        return usedJSHeapSize.toInt();
      }
    }
    
    return _estimateWebMemory();
  } catch (e) {
    return 50 * 1024 * 1024;
  }
}

int _estimateWebMemory() {
  return 50 * 1024 * 1024;
}

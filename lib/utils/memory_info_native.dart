
import 'dart:io';

Future<int> getMemoryInfo() async {
  try {
    if (Platform.isMacOS || Platform.isIOS) {
      return 50 * 1024 * 1024;
    }
    
    return 50 * 1024 * 1024;
  } catch (e) {
    return 50 * 1024 * 1024;
  }
}

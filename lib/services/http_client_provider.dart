import 'package:http/http.dart' as http;

/// HTTP Client 提供者
/// 
/// 提供全局共享的 HTTP client 实例，实现连接池复用，提高网络请求效率。
/// 
/// 使用示例：
/// ```dart
/// // 发送 GET 请求
/// final response = await HttpClientProvider.client.get(
///   Uri.parse('https://api.example.com/data'),
/// );
/// 
/// // 发送 POST 请求
/// final response = await HttpClientProvider.client.post(
///   Uri.parse('https://api.example.com/submit'),
///   body: {'key': 'value'},
/// );
/// ```
class HttpClientProvider {
  /// 共享的 HTTP client 实例（单例）
  static final http.Client _sharedClient = http.Client();

  /// 获取共享的 HTTP client
  static http.Client get client => _sharedClient;

  /// 关闭共享的 HTTP client
  /// 
  /// 通常在应用退出时调用，用于释放资源。
  static void dispose() {
    _sharedClient.close();
  }
}

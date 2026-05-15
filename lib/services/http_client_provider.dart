import 'package:http/http.dart' as http;

class HttpClientProvider {
  static final http.Client _sharedClient = http.Client();

  static http.Client get client => _sharedClient;

  static void dispose() {
    _sharedClient.close();
  }
}

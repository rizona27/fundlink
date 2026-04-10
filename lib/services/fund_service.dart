import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/fund_holding.dart';

class FundService {
  static const String _eastmoneyUrl = 'https://fundgz.1234567.com.cn/js';

  final Map<String, Future<Map<String, dynamic>>> _activeRequests = {};
  final Map<String, Map<String, dynamic>> _cache = {};

  // 只返回净值信息，不返回完整的 FundHolding 对象
  Future<Map<String, dynamic>> fetchFundInfo(String code) async {
    debugPrint('╔══════════════════════════════════════════════════════════════════╗');
    debugPrint('║ [🌐 API请求] 开始获取基金数据                                      ║');
    debugPrint('╠══════════════════════════════════════════════════════════════════╣');
    debugPrint('║ 基金代码: $code');
    debugPrint('║ 请求时间: ${DateTime.now()}');
    debugPrint('╚══════════════════════════════════════════════════════════════════╝');

    // 检查缓存
    if (_cache.containsKey(code)) {
      final cached = _cache[code]!;
      debugPrint('✅ [缓存命中] 基金代码 $code');
      return cached;
    }

    // 检查进行中的请求
    if (_activeRequests.containsKey(code)) {
      debugPrint('🔄 [并发请求] 基金代码 $code 已有请求进行中');
      return await _activeRequests[code]!;
    }

    final future = _fetchFromEastmoney(code);
    _activeRequests[code] = future;

    try {
      final result = await future;
      _cache[code] = result;
      return result;
    } catch (e) {
      debugPrint('❌ API失败: $e');
      return {
        'fundName': '加载失败',
        'currentNav': 0.0,
        'navDate': DateTime.now(),
        'isValid': false,
        'error': e.toString(),
      };
    } finally {
      _activeRequests.remove(code);
    }
  }

  // 通用JSONP解析函数
  String _extractJsonFromJsonp(String rawBody) {
    String jsonStr = rawBody.trim();

    // 查找第一个 { 和最后一个 } 的位置
    int startIndex = jsonStr.indexOf('{');
    int endIndex = jsonStr.lastIndexOf('}');

    if (startIndex != -1 && endIndex != -1 && startIndex < endIndex) {
      return jsonStr.substring(startIndex, endIndex + 1);
    }

    // 如果找不到标准的JSON格式，返回原字符串
    debugPrint('⚠️ 未找到有效的JSON格式');
    return jsonStr;
  }

  Future<Map<String, dynamic>> _fetchFromEastmoney(String code) async {
    debugPrint('┌──────────────────────────────────────────────────────────────────┐');
    debugPrint('│ [天天基金API] 开始请求                                             │');
    debugPrint('│ 基金代码: $code');
    debugPrint('└──────────────────────────────────────────────────────────────────┘');

    String responseBody = '';

    try {
      final url = Uri.parse('$_eastmoneyUrl/$code.js');
      debugPrint('📍 请求URL: $url');

      // 使用 http 包（更简单可靠）
      final client = http.Client();

      final request = http.Request('GET', url);
      request.headers.addAll({
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Referer': 'https://fund.eastmoney.com/',
      });

      // 增加超时时间到30秒
      final response = await client.send(request).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          client.close();
          throw TimeoutException('请求超时');
        },
      );

      responseBody = await response.stream.transform(utf8.decoder).join();
      client.close();

      final statusCode = response.statusCode;
      debugPrint('📡 响应状态码: $statusCode');

      if (statusCode != 200) {
        debugPrint('❌ 请求失败: HTTP $statusCode');
        return {
          'fundName': '加载失败',
          'currentNav': 0.0,
          'navDate': DateTime.now(),
          'isValid': false,
          'error': 'HTTP $statusCode',
        };
      }

      if (responseBody.isEmpty || responseBody.length < 20) {
        debugPrint('❌ 响应数据为空或太短');
        return {
          'fundName': '加载失败',
          'currentNav': 0.0,
          'navDate': DateTime.now(),
          'isValid': false,
          'error': 'Empty response',
        };
      }

      debugPrint('📦 响应数据长度: ${responseBody.length} 字符');

      // 使用通用JSONP解析函数提取JSON
      String jsonStr = _extractJsonFromJsonp(responseBody);
      debugPrint('📝 提取的JSON: ${jsonStr.substring(0, jsonStr.length > 100 ? 100 : jsonStr.length)}...');

      // 解析JSON
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      debugPrint('📊 解析成功，字段: ${json.keys.join(', ')}');

      final fundName = json['name'] as String? ?? '未知基金';
      final dwjz = double.tryParse(json['dwjz']?.toString() ?? '');
      final gsz = double.tryParse(json['gsz']?.toString() ?? '');
      final currentNav = dwjz ?? gsz ?? 0.0;

      DateTime navDate = DateTime.now();
      if (json['jzrq'] != null) {
        final dateStr = json['jzrq'].toString();
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          try {
            navDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          } catch (e) {
            debugPrint('日期解析失败: $dateStr');
          }
        }
      }

      debugPrint('📈 基金名称: $fundName');
      debugPrint('📈 单位净值: $dwjz');
      debugPrint('📈 估算净值: $gsz');
      debugPrint('📈 使用净值: $currentNav');
      debugPrint('📅 净值日期: ${_formatDate(navDate)}');

      final isValid = fundName != '未知基金' && fundName != '加载失败' && currentNav > 0;

      return {
        'fundName': fundName,
        'currentNav': currentNav,
        'navDate': navDate,
        'isValid': isValid,
      };

    } on SocketException catch (e) {
      debugPrint('❌ 网络异常: $e');
      debugPrint('   可能原因: 无法连接到服务器、DNS解析失败');
      return {
        'fundName': '加载失败',
        'currentNav': 0.0,
        'navDate': DateTime.now(),
        'isValid': false,
        'error': 'Network error: $e',
      };
    } on TimeoutException catch (e) {
      debugPrint('❌ 超时异常: $e');
      debugPrint('   尝试增加超时时间或检查网络连接');
      return {
        'fundName': '加载失败',
        'currentNav': 0.0,
        'navDate': DateTime.now(),
        'isValid': false,
        'error': 'Timeout: 请求超时30秒',
      };
    } on FormatException catch (e) {
      debugPrint('❌ 数据格式异常: $e');
      if (responseBody.isNotEmpty) {
        debugPrint('   原始响应内容: ${responseBody.length > 200 ? responseBody.substring(0, 200) : responseBody}');
      }
      return {
        'fundName': '加载失败',
        'currentNav': 0.0,
        'navDate': DateTime.now(),
        'isValid': false,
        'error': 'Parse error: $e',
      };
    } catch (e) {
      debugPrint('❌ 未知异常: $e');
      return {
        'fundName': '加载失败',
        'currentNav': 0.0,
        'navDate': DateTime.now(),
        'isValid': false,
        'error': e.toString(),
      };
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
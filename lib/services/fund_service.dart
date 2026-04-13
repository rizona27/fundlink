import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
// 不再需要 GBK 解码，移除 fast_gbk 导入
import '../models/log_entry.dart';
import 'data_manager.dart';

class FundService {
  final DataManager? _dataManager;

  final Map<String, Future<Map<String, dynamic>>> _activeRequests = {};
  final Map<String, Map<String, dynamic>> _cache = {};

  FundService([this._dataManager]);

  void clearCache([String? code]) {
    if (code != null) {
      _cache.remove(code);
      _activeRequests.remove(code);
    } else {
      _cache.clear();
      _activeRequests.clear();
    }
  }

  Future<Map<String, dynamic>> fetchFundInfo(String code, {bool forceRefresh = false}) async {
    if (forceRefresh) clearCache(code);

    debugPrint('╔══════════════════════════════════════════════════════════════════╗');
    debugPrint('║ [🌐 API请求] 开始获取基金数据                                      ║');
    debugPrint('╠══════════════════════════════════════════════════════════════════╣');
    debugPrint('║ 基金代码: $code');
    debugPrint('║ 请求时间: ${DateTime.now()}');
    debugPrint('╚══════════════════════════════════════════════════════════════════╝');

    _dataManager?.addLog('开始查询基金代码: $code', type: LogType.network);

    if (!forceRefresh && _cache.containsKey(code)) {
      final cached = _cache[code]!;
      debugPrint('✅ [缓存命中] 基金代码 $code');
      _dataManager?.addLog('基金代码 $code: 使用缓存数据', type: LogType.cache);
      return cached;
    }

    if (_activeRequests.containsKey(code)) {
      debugPrint('🔄 [并发请求] 基金代码 $code 已有请求进行中');
      _dataManager?.addLog('基金代码 $code: 使用进行中的请求', type: LogType.cache);
      return await _activeRequests[code]!;
    }

    final future = _fetchFromPingzhongdata(code);
    _activeRequests[code] = future;

    try {
      final result = await future;
      if (!forceRefresh) _cache[code] = result;
      return result;
    } catch (e) {
      debugPrint('❌ API失败: $e');
      _dataManager?.addLog('基金代码 $code: API请求失败 - $e', type: LogType.error);
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

  // 使用天天基金 pingzhongdata 接口（UTF-8 编码）
  Future<Map<String, dynamic>> _fetchFromPingzhongdata(String code) async {
    debugPrint('┌──────────────────────────────────────────────────────────────────┐');
    debugPrint('│ [天天基金数据接口] 开始请求                                        │');
    debugPrint('│ 基金代码: $code');
    debugPrint('└──────────────────────────────────────────────────────────────────┘');

    try {
      final url = Uri.parse('https://fund.eastmoney.com/pingzhongdata/$code.js');
      debugPrint('📍 请求URL: $url');

      final response = await http.get(url).timeout(const Duration(seconds: 15));
      final statusCode = response.statusCode;
      debugPrint('📡 响应状态码: $statusCode');

      if (statusCode != 200) {
        debugPrint('❌ 请求失败: HTTP $statusCode');
        _dataManager?.addLog('基金代码 $code: HTTP $statusCode', type: LogType.error);
        return {
          'fundName': '加载失败',
          'currentNav': 0.0,
          'navDate': DateTime.now(),
          'isValid': false,
          'error': 'HTTP $statusCode',
        };
      }

      final jsString = utf8.decode(response.bodyBytes);
      debugPrint('✅ 响应解码成功，长度: ${jsString.length}');

      // 1. 提取基金名称（支持双引号、单引号、无引号）
      String fundName = '未知基金';
      // 匹配 fS_name = "xxx" 或 fS_name = 'xxx' 或 fS_name = xxx
      final namePatterns = [
        RegExp(r'fS_name\s*=\s*"([^"]+)"'),   // 双引号
        RegExp(r"fS_name\s*=\s*'([^']+)'"),   // 单引号
        RegExp(r'fS_name\s*=\s*([^;]+)'),     // 无引号（直到分号）
      ];
      for (final pattern in namePatterns) {
        final match = pattern.firstMatch(jsString);
        if (match != null) {
          fundName = match.group(1)!.trim();
          if (fundName.isNotEmpty && fundName != 'undefined' && fundName != 'null') {
            break;
          }
        }
      }
      debugPrint('📈 基金名称: $fundName');

      // 2. 提取净值趋势 Data_netWorthTrend
      double currentNav = 0.0;
      DateTime navDate = DateTime.now();
      final trendRegex = RegExp(r'Data_netWorthTrend\s*=\s*(\[[\s\S]+?\])');
      final trendMatch = trendRegex.firstMatch(jsString);
      if (trendMatch != null) {
        final trendArrayStr = trendMatch.group(1)!;
        try {
          final List<dynamic> trendList = jsonDecode(trendArrayStr);
          if (trendList.isNotEmpty) {
            final latest = trendList.last;
            currentNav = (latest['y'] as num).toDouble();
            final timestamp = latest['x'] as int; // 毫秒时间戳
            navDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
            debugPrint('📈 最新净值: $currentNav，日期: $navDate');
          }
        } catch (e) {
          debugPrint('⚠️ 解析净值趋势失败: $e');
        }
      } else {
        debugPrint('⚠️ 未找到 Data_netWorthTrend');
      }

      // 3. 提取收益率（可选）
      double? navReturn1m, navReturn3m, navReturn6m, navReturn1y;
      final ret1mRegex = RegExp(r"syl_1y\s*=\s*'([^']+)'");
      final ret1mMatch = ret1mRegex.firstMatch(jsString);
      if (ret1mMatch != null) navReturn1m = double.tryParse(ret1mMatch.group(1)!);

      final ret3mRegex = RegExp(r"syl_3y\s*=\s*'([^']+)'");
      final ret3mMatch = ret3mRegex.firstMatch(jsString);
      if (ret3mMatch != null) navReturn3m = double.tryParse(ret3mMatch.group(1)!);

      final ret6mRegex = RegExp(r"syl_6y\s*=\s*'([^']+)'");
      final ret6mMatch = ret6mRegex.firstMatch(jsString);
      if (ret6mMatch != null) navReturn6m = double.tryParse(ret6mMatch.group(1)!);

      final ret1yRegex = RegExp(r"syl_1n\s*=\s*'([^']+)'");
      final ret1yMatch = ret1yRegex.firstMatch(jsString);
      if (ret1yMatch != null) navReturn1y = double.tryParse(ret1yMatch.group(1)!);

      debugPrint('📈 收益率: 1月=$navReturn1m, 3月=$navReturn3m, 6月=$navReturn6m, 1年=$navReturn1y');

      final isValid = fundName != '未知基金' && currentNav > 0;

      if (isValid) {
        _dataManager?.addLog('基金代码 $code: 获取成功 - $fundName, 净值: $currentNav', type: LogType.success);
      } else {
        _dataManager?.addLog('基金代码 $code: 数据无效 - fundName: $fundName, currentNav: $currentNav', type: LogType.error);
      }

      return {
        'fundName': fundName,
        'currentNav': currentNav,
        'navDate': navDate,
        'isValid': isValid,
        'navReturn1m': navReturn1m,
        'navReturn3m': navReturn3m,
        'navReturn6m': navReturn6m,
        'navReturn1y': navReturn1y,
      };

    } on SocketException catch (e) {
      debugPrint('❌ 网络异常: $e');
      _dataManager?.addLog('基金代码 $code: 网络异常 - $e', type: LogType.error);
      return {
        'fundName': '加载失败',
        'currentNav': 0.0,
        'navDate': DateTime.now(),
        'isValid': false,
        'error': 'Network error: $e',
      };
    } on TimeoutException catch (e) {
      debugPrint('❌ 超时异常: $e');
      _dataManager?.addLog('基金代码 $code: 请求超时 - $e', type: LogType.error);
      return {
        'fundName': '加载失败',
        'currentNav': 0.0,
        'navDate': DateTime.now(),
        'isValid': false,
        'error': 'Timeout: 请求超时15秒',
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
}
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
      final namePatterns = [
        RegExp(r'fS_name\s*=\s*"([^"]+)"'),   // 双引号
        RegExp(r"fS_name\s*=\s*'([^']+)'"),   // 单引号
        RegExp(r'fS_name\s*=\s*([^;]+)'),     // 无引号
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
            final timestamp = latest['x'] as int;
            navDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
            debugPrint('📈 最新净值: $currentNav，日期: $navDate');
          }
        } catch (e) {
          debugPrint('⚠️ 解析净值趋势失败: $e');
        }
      } else {
        debugPrint('⚠️ 未找到 Data_netWorthTrend');
      }

      // 3. 提取收益率（修正正则：使用双引号，并兼容无引号情况）
      double? navReturn1m, navReturn3m, navReturn6m, navReturn1y;

      // 近1月：syl_1y
      final ret1mPatterns = [
        RegExp(r'syl_1y\s*=\s*"([^"]*)"'),
        RegExp(r"syl_1y\s*=\s*'([^']*)'"),
        RegExp(r'syl_1y\s*=\s*([^;]+)'),
      ];
      for (final pattern in ret1mPatterns) {
        final match = pattern.firstMatch(jsString);
        if (match != null) {
          final val = match.group(1)!.trim();
          if (val.isNotEmpty && val != 'undefined' && val != 'null') {
            navReturn1m = double.tryParse(val);
            if (navReturn1m != null) break;
          }
        }
      }

      // 近3月：syl_3y
      final ret3mPatterns = [
        RegExp(r'syl_3y\s*=\s*"([^"]*)"'),
        RegExp(r"syl_3y\s*=\s*'([^']*)'"),
        RegExp(r'syl_3y\s*=\s*([^;]+)'),
      ];
      for (final pattern in ret3mPatterns) {
        final match = pattern.firstMatch(jsString);
        if (match != null) {
          final val = match.group(1)!.trim();
          if (val.isNotEmpty && val != 'undefined' && val != 'null') {
            navReturn3m = double.tryParse(val);
            if (navReturn3m != null) break;
          }
        }
      }

      // 近6月：syl_6y
      final ret6mPatterns = [
        RegExp(r'syl_6y\s*=\s*"([^"]*)"'),
        RegExp(r"syl_6y\s*=\s*'([^']*)'"),
        RegExp(r'syl_6y\s*=\s*([^;]+)'),
      ];
      for (final pattern in ret6mPatterns) {
        final match = pattern.firstMatch(jsString);
        if (match != null) {
          final val = match.group(1)!.trim();
          if (val.isNotEmpty && val != 'undefined' && val != 'null') {
            navReturn6m = double.tryParse(val);
            if (navReturn6m != null) break;
          }
        }
      }

      // 近1年：syl_1n
      final ret1yPatterns = [
        RegExp(r'syl_1n\s*=\s*"([^"]*)"'),
        RegExp(r"syl_1n\s*=\s*'([^']*)'"),
        RegExp(r'syl_1n\s*=\s*([^;]+)'),
      ];
      for (final pattern in ret1yPatterns) {
        final match = pattern.firstMatch(jsString);
        if (match != null) {
          final val = match.group(1)!.trim();
          if (val.isNotEmpty && val != 'undefined' && val != 'null') {
            navReturn1y = double.tryParse(val);
            if (navReturn1y != null) break;
          }
        }
      }

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
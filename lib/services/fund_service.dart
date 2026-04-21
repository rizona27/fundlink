import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import '../models/log_entry.dart';
import '../models/net_worth_point.dart';
import '../models/top_holding.dart';
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

      String fundName = '未知基金';
      final namePatterns = [
        RegExp(r'fS_name\s*=\s*"([^"]+)"'),
        RegExp(r"fS_name\s*=\s*'([^']+)'"),
        RegExp(r'fS_name\s*=\s*([^;]+)'),
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

      double? navReturn1m, navReturn3m, navReturn6m, navReturn1y;

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


  Future<List<NetWorthPoint>> fetchNetWorthTrend(String code) async {
    final url = Uri.parse('https://fund.eastmoney.com/pingzhongdata/$code.js');
    final response = await http.get(url).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    final jsString = utf8.decode(response.bodyBytes);
    final trendRegex = RegExp(r'Data_netWorthTrend\s*=\s*(\[[\s\S]+?\])');
    final match = trendRegex.firstMatch(jsString);
    if (match == null) return [];
    final trendArrayStr = match.group(1)!;
    final List<dynamic> trendList = jsonDecode(trendArrayStr);
    return trendList.map((item) => NetWorthPoint.fromJson(item)).toList();
  }

  Future<Map<String, List<NetWorthPoint>>> fetchBenchmarkData(String code) async {
    final url = Uri.parse('https://fund.eastmoney.com/pingzhongdata/$code.js');
    final response = await http.get(url).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    final jsString = utf8.decode(response.bodyBytes);

    final grandTotalRegex = RegExp(r'Data_grandTotal\s*=\s*(\[[\s\S]*?\])\s*;', multiLine: true);
    final match = grandTotalRegex.firstMatch(jsString);
    if (match == null) return {'average': [], 'hs300': []};

    final grandTotalStr = match.group(1)!;
    List<dynamic> grandTotal;
    try {
      grandTotal = jsonDecode(grandTotalStr);
    } catch (e) {
      grandTotal = [];
      final seriesRegex = RegExp(r'\{[^{}]*"name"\s*:\s*"([^"]+)"[^{}]*"data"\s*:\s*(\[[\s\S]*?\])[^{}]*\}');
      final seriesMatches = seriesRegex.allMatches(jsString);
      for (final seriesMatch in seriesMatches) {
        final name = seriesMatch.group(1)!;
        final dataStr = seriesMatch.group(2)!;
        List<dynamic> dataPoints;
        try {
          dataPoints = jsonDecode(dataStr);
        } catch (e) {
          final pointRegex = RegExp(r'\[(\d+),([\d\.]+)\]');
          dataPoints = pointRegex.allMatches(dataStr).map((m) {
            return [int.parse(m.group(1)!), double.parse(m.group(2)!)];
          }).toList();
        }
        grandTotal.add({'name': name, 'data': dataPoints});
      }
    }

    List<NetWorthPoint> averagePoints = [];
    List<NetWorthPoint> hs300Points = [];

    for (var series in grandTotal) {
      final name = series['name'] as String;
      final data = series['data'] as List;
      if (name.contains('同类平均')) {
        averagePoints = data.map((item) {
          final ts = item[0] as int;
          final val = (item[1] as num).toDouble();
          return NetWorthPoint(
            date: DateTime.fromMillisecondsSinceEpoch(ts),
            nav: val,
            series: 'average',
          );
        }).toList();
      } else if (name.contains('沪深300')) {
        hs300Points = data.map((item) {
          final ts = item[0] as int;
          final val = (item[1] as num).toDouble();
          return NetWorthPoint(
            date: DateTime.fromMillisecondsSinceEpoch(ts),
            nav: val,
            series: 'hs300',
          );
        }).toList();
      }
    }

    return {'average': averagePoints, 'hs300': hs300Points};
  }

  Future<List<TopHolding>> fetchTopHoldingsFromHtml(String code) async {
    debugPrint('🔍 开始获取基金 $code 的十大重仓股...');
    final url = Uri.parse('https://fundf10.eastmoney.com/FundArchivesDatas.aspx?type=jjcc&code=$code&topline=10');
    final response = await http.get(
      url,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://fund.eastmoney.com/',
      },
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    final htmlString = utf8.decode(response.bodyBytes);
    final document = html_parser.parse(htmlString);

    final tbody = document.querySelector('tbody');
    if (tbody == null) {
      debugPrint('❌ 未找到 tbody');
      return [];
    }

    final thead = document.querySelector('thead');
    List<String> headers = [];
    if (thead != null) {
      final ths = thead.querySelectorAll('th');
      headers = ths.map((th) => th.text.trim()).toList();
      debugPrint('📋 表头: $headers');
    }

    int ratioIndex = -1;
    for (int i = 0; i < headers.length; i++) {
      if (headers[i].contains('占净值比例') || headers[i].contains('占比')) {
        ratioIndex = i;
        break;
      }
    }
    if (ratioIndex == -1) ratioIndex = 5;

    final rows = tbody.querySelectorAll('tr');
    final holdings = <TopHolding>[];
    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 3) continue;

      final codeRaw = cells[1].text.trim();
      final codeMatch = RegExp(r'(\d{6})').firstMatch(codeRaw);
      final stockCode = codeMatch?.group(1) ?? codeRaw;

      final stockName = cells[2].text.trim();

      String ratioRaw = '';
      if (cells.length > ratioIndex) {
        ratioRaw = cells[ratioIndex].text.trim().replaceAll('%', '');
      } else {
        for (int i = cells.length - 1; i >= 0; i--) {
          final text = cells[i].text.trim();
          if (text.contains('%')) {
            ratioRaw = text.replaceAll('%', '');
            break;
          }
        }
      }
      final ratio = double.tryParse(ratioRaw) ?? 0.0;

      debugPrint('  解析: 代码=$stockCode, 名称=$stockName, 占比=$ratioRaw%');
      if (stockCode.isNotEmpty && stockName.isNotEmpty && ratio > 0) {
        holdings.add(TopHolding(stockCode: stockCode, stockName: stockName, ratio: ratio));
      }
    }

    debugPrint('✅ 最终解析到 ${holdings.length} 条有效重仓股');
    return holdings.take(10).toList();
  }

  Future<Map<String, double>> fetchStockQuotes(List<String> stockCodes) async {
    if (stockCodes.isEmpty) return {};
    final codesParam = stockCodes.map((code) {
      if (code.length == 5 && RegExp(r'^\d{5}$').hasMatch(code)) {
        return 'hk$code';
      }
      if (code.startsWith('6')) return 'sh$code';
      if (code.startsWith('0') || code.startsWith('3')) return 'sz$code';
      if (code.startsWith('5')) return 'sz$code';
      return code;
    }).join(',');
    final url = Uri.parse('https://qt.gtimg.cn/q=$codesParam');
    debugPrint('📊 请求股票行情: $url');
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return {};
    String body;
    try {
      body = utf8.decode(response.bodyBytes);
    } catch (e) {
      body = String.fromCharCodes(response.bodyBytes);
    }
    final Map<String, double> quoteMap = {};
    final lines = body.split('\n');
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      final match = RegExp(r'v_([^=]+)="([^"]+)"').firstMatch(line);
      if (match != null) {
        final code = match.group(1)!;
        final parts = match.group(2)!.split('~');
        if (parts.length > 4) {
          final currentPrice = double.tryParse(parts[3]) ?? 0.0;
          final lastClose = double.tryParse(parts[4]) ?? 0.0;
          final changePercent = lastClose > 0 ? ((currentPrice - lastClose) / lastClose) * 100 : 0.0;
          quoteMap[code] = changePercent;
          debugPrint('📊 股票 $code 当前价=$currentPrice, 昨收=$lastClose, 涨跌幅=$changePercent%');
        }
      }
    }
    return quoteMap;
  }

  Future<Map<String, dynamic>?> fetchRealtimeValuation(String code) async {
    if (code.isEmpty || code.length != 6 || !RegExp(r'^\d{6}$').hasMatch(code)) {
      debugPrint('❌ [估值请求] 无效的基金代码格式: $code');
      return null;
    }

    final url = Uri.parse('https://fundgz.1234567.com.cn/js/$code.js?rt=${DateTime.now().millisecondsSinceEpoch}');
    debugPrint('📊 [估值请求] 开始获取基金 $code 的实时估值');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('❌ [估值请求] 基金 $code 返回HTTP ${response.statusCode}');
        return null;
      }

      final bodyBytes = response.bodyBytes;
      if (bodyBytes.isEmpty) {
        debugPrint('❌ [估值请求] 基金 $code 返回空内容');
        return null;
      }

      String jsString;
      try {
        jsString = utf8.decode(bodyBytes);
      } catch (e) {
        try {
          jsString = String.fromCharCodes(bodyBytes);
        } catch (e2) {
          debugPrint('❌ [估值请求] 基金 $code 解码失败: $e2');
          return null;
        }
      }

      final trimmed = jsString.trim();
      if (trimmed.isEmpty || trimmed == 'null' || trimmed == 'jsonpgz();') {
        debugPrint('⚠️ [估值请求] 基金 $code 处于封闭期或无实时估值数据');
        return null;
      }

      if (!trimmed.contains('{') || !trimmed.contains('}')) {
        debugPrint('❌ [估值请求] 基金 $code 返回内容不是有效的JSON格式');
        debugPrint('   返回内容: ${trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed}');
        return null;
      }

      String jsonStr = trimmed;
      if (trimmed.contains('(') && trimmed.contains(')')) {
        final startIdx = trimmed.indexOf('(');
        final endIdx = trimmed.lastIndexOf(')');
        if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
          jsonStr = trimmed.substring(startIdx + 1, endIdx);
        }
      }

      jsonStr = jsonStr.trim();
      if (jsonStr.endsWith(';')) {
        jsonStr = jsonStr.substring(0, jsonStr.length - 1);
      }

      if (jsonStr.isEmpty) {
        debugPrint('❌ [估值请求] 基金 $code 提取的JSON字符串为空');
        return null;
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(jsonStr);
      } on FormatException catch (e) {
        debugPrint('❌ [估值请求] 基金 $code JSON解析失败: $e');
        debugPrint('   原始内容: ${trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed}');
        return null;
      } catch (e) {
        debugPrint('❌ [估值请求] 基金 $code JSON解析未知错误: $e');
        return null;
      }

      final returnedFundCode = data['fundcode']?.toString() ?? '';
      if (returnedFundCode.isNotEmpty && returnedFundCode != code) {
        debugPrint('⚠️ [估值请求] 基金 $code 返回的代码不匹配: $returnedFundCode');
      }

      final fundName = data['name']?.toString() ?? '';
      if (fundName.isEmpty || fundName == 'null' || fundName == 'undefined') {
        debugPrint('❌ [估值请求] 基金 $code 不存在或已退市');
        return null;
      }

      String gszStr = data['gsz']?.toString() ?? '';
      if (gszStr.isEmpty || gszStr == 'null' || gszStr == 'undefined') {
        debugPrint('❌ [估值请求] 基金 $code 缺少估值数据');
        return null;
      }

      double gsz;
      double gszzl;
      try {
        gsz = double.tryParse(gszStr) ?? 0.0;
        gszzl = double.tryParse(data['gszzl']?.toString() ?? '0') ?? 0.0;
      } catch (e) {
        debugPrint('❌ [估值请求] 基金 $code 解析数值失败: $e');
        return null;
      }

      if (gsz <= 0 && gszzl == 0) {
        debugPrint('⚠️ [估值请求] 基金 $code 当前估值为0，可能非交易时间');
      }

      debugPrint('✅ [估值请求] 基金 $code 估值成功: $fundName, 净值=$gsz, 涨跌幅=$gszzl%');
      return {
        'fundCode': code,
        'name': fundName,
        'dwjz': double.tryParse(data['dwjz']?.toString() ?? '0') ?? 0.0,
        'gsz': gsz,
        'gszzl': gszzl,
        'gztime': data['gztime']?.toString() ?? '',
        'jzrq': data['jzrq']?.toString() ?? '',
      };
    } on SocketException catch (e) {
      debugPrint('❌ [估值请求] 基金 $code 网络异常: $e');
      return null;
    } on TimeoutException catch (e) {
      debugPrint('❌ [估值请求] 基金 $code 请求超时: $e');
      return null;
    } catch (e) {
      debugPrint('❌ [估值请求] 基金 $code 未知异常: $e');
      return null;
    }
  }
}
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import '../models/log_entry.dart';
import '../models/net_worth_point.dart';
import '../models/top_holding.dart';
import '../models/fund_info_cache.dart';
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

    _dataManager?.addLog('开始查询基金代码: $code', type: LogType.network);

    // 优先检查 DataManager 的持久化缓存
    if (!forceRefresh && _dataManager != null) {
      final cachedInfo = _dataManager!.getFundInfoCache(code);
      if (cachedInfo != null) {
        _dataManager?.addLog('基金代码 $code: 使用持久化缓存数据', type: LogType.cache);
        return {
          'fundName': cachedInfo.fundName,
          'currentNav': cachedInfo.currentNav,
          'navDate': cachedInfo.navDate,
          'navReturn1m': cachedInfo.navReturn1m,
          'navReturn3m': cachedInfo.navReturn3m,
          'navReturn6m': cachedInfo.navReturn6m,
          'navReturn1y': cachedInfo.navReturn1y,
          'isValid': true,
        };
      }
    }

    if (!forceRefresh && _cache.containsKey(code)) {
      final cached = _cache[code]!;
      _dataManager?.addLog('基金代码 $code: 使用内存缓存数据', type: LogType.cache);
      return cached;
    }

    if (_activeRequests.containsKey(code)) {
      _dataManager?.addLog('基金代码 $code: 使用进行中的请求', type: LogType.cache);
      return await _activeRequests[code]!;
    }

    final future = _fetchFromPingzhongdata(code);
    _activeRequests[code] = future;

    try {
      final result = await future;
      
      // 保存到 DataManager 的持久化缓存
      if (_dataManager != null && result['isValid'] == true) {
        final fundInfo = FundInfoCache(
          fundCode: code,
          fundName: result['fundName'] as String,
          currentNav: result['currentNav'] as double,
          navDate: result['navDate'] as DateTime,
          navReturn1m: result['navReturn1m'] as double?,
          navReturn3m: result['navReturn3m'] as double?,
          navReturn6m: result['navReturn6m'] as double?,
          navReturn1y: result['navReturn1y'] as double?,
          cacheTime: DateTime.now(),
        );
        _dataManager!.saveFundInfoCache(fundInfo);
      }
      
      if (!forceRefresh) _cache[code] = result;
      return result;
    } catch (e) {
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
    try {
      final url = Uri.parse('https://fund.eastmoney.com/pingzhongdata/$code.js');

      // iOS优化：添加重试机制和更长的超时时间
      http.Response? response;
      var retryCount = 0;
      const maxRetries = 2; // 最多重试2次
      Exception? lastException;
      
      while (retryCount <= maxRetries) {
        try {
          response = await http.get(
            url,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Accept': '*/*',
            },
          ).timeout(const Duration(seconds: 20)); // iOS增加到20秒
          
          // 如果成功，跳出重试循环
          if (response.statusCode == 200) {
            break;
          }
        } catch (e) {
          lastException = e is Exception ? e : Exception(e.toString());
          retryCount++;
          
          if (retryCount <= maxRetries) {
            // 指数退避：第1次等500ms，第2次等1000ms
            await Future.delayed(Duration(milliseconds: 500 * retryCount));
          }
        }
      }
      
      // 如果所有重试都失败
      if (response == null) {
        throw lastException ?? Exception('请求失败');
      }
      
      final statusCode = response.statusCode;

      if (statusCode != 200) {
        _dataManager?.addLog('基金代码 $code: HTTP $statusCode', type: LogType.error);
        return {
          'fundName': '加载失败',
          'currentNav': 0.0,
          'navDate': DateTime.now(),
          'isValid': false,
          'error': 'HTTP $statusCode',
        };
      }

      // iOS优化：使用allowMalformed处理不完整的UTF-8序列
      final jsString = utf8.decode(response.bodyBytes, allowMalformed: true);

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
          }
        } catch (e) {
        }
      } else {
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

    } on TimeoutException catch (e) {
      _dataManager?.addLog('基金代码 $code: 请求超时 - $e', type: LogType.error);
      return {
        'fundName': '加载失败',
        'currentNav': 0.0,
        'navDate': DateTime.now(),
        'isValid': false,
        'error': 'Timeout: 请求超时15秒',
      };
    } catch (e) {
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
    print('正在获取基金 $code 的净值趋势...');
    final url = Uri.parse('https://fund.eastmoney.com/pingzhongdata/$code.js');
    final response = await http.get(url).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      print('基金 $code HTTP错误: ${response.statusCode}');
      throw Exception('HTTP ${response.statusCode}');
    }
    final jsString = utf8.decode(response.bodyBytes);
    final trendRegex = RegExp(r'Data_netWorthTrend\s*=\s*(\[[\s\S]+?\])');
    final match = trendRegex.firstMatch(jsString);
    if (match == null) {
      print('基金 $code 未找到Data_netWorthTrend数据');
      return [];
    }
    final trendArrayStr = match.group(1)!;
    final List<dynamic> trendList = jsonDecode(trendArrayStr);
    print('基金 $code 原始数据点数: ${trendList.length}');
    
    // 解析所有净值点
    final allPoints = trendList.map((item) => NetWorthPoint.fromJson(item)).toList();
    
    // 过滤掉今天及未来的数据，只保留已确认的净值
    // 使用昨天的日期作为截止点（因为今天的净值通常还没出来）
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final cutoffDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
    
    final confirmedPoints = allPoints.where((point) {
      return point.date.isBefore(cutoffDate) || point.date.isAtSameMomentAs(cutoffDate);
    }).toList();
    
    print('基金 $code 过滤后数据点数: ${confirmedPoints.length}');
    if (confirmedPoints.isNotEmpty) {
      print('基金 $code 最早日期: ${confirmedPoints.first.date}, 最新日期: ${confirmedPoints.last.date}');
    }
    
    // 如果过滤后没有数据（可能是新基金），则返回原始数据
    final result = confirmedPoints.isEmpty ? allPoints : confirmedPoints;
    print('基金 $code 最终返回数据点数: ${result.length}');
    return result;
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
    final url = Uri.parse('https://fundf10.eastmoney.com/FundArchivesDatas.aspx?type=jjcc&code=$code&topline=10');
    
    // iOS优化：添加重试机制
    http.Response? response;
    var retryCount = 0;
    const maxRetries = 2; // 最多重试2次
    Exception? lastException;
    
    while (retryCount <= maxRetries) {
      try {
        response = await http.get(
          url,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'https://fund.eastmoney.com/',
          },
        ).timeout(const Duration(seconds: 15));
        
        // 如果成功，跳出重试循环
        if (response.statusCode == 200) {
          break;
        }
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        retryCount++;
        
        if (retryCount <= maxRetries) {
          // 指数退避：第1次等500ms，第2次等1000ms
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
        }
      }
    }
    
    // 如果所有重试都失败
    if (response == null) {
      throw lastException ?? Exception('请求失败');
    }
    
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    final htmlString = utf8.decode(response.bodyBytes);
    final document = html_parser.parse(htmlString);

    final tbody = document.querySelector('tbody');
    if (tbody == null) {
      return [];
    }

    final thead = document.querySelector('thead');
    List<String> headers = [];
    if (thead != null) {
      final ths = thead.querySelectorAll('th');
      headers = ths.map((th) => th.text.trim()).toList();
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

      if (stockCode.isNotEmpty && stockName.isNotEmpty && ratio > 0) {
        holdings.add(TopHolding(stockCode: stockCode, stockName: stockName, ratio: ratio));
      }
    }

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
        }
      }
    }
    return quoteMap;
  }

  Future<Map<String, dynamic>?> fetchRealtimeValuation(String code) async {
    if (code.isEmpty || code.length != 6 || !RegExp(r'^\d{6}$').hasMatch(code)) {
      return null;
    }

    final url = Uri.parse('https://fundgz.1234567.com.cn/js/$code.js?rt=${DateTime.now().millisecondsSinceEpoch}');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return null;
      }

      final bodyBytes = response.bodyBytes;
      if (bodyBytes.isEmpty) {
        return null;
      }

      String jsString;
      try {
        jsString = utf8.decode(bodyBytes);
      } catch (e) {
        try {
          jsString = String.fromCharCodes(bodyBytes);
        } catch (e2) {
          return null;
        }
      }

      final trimmed = jsString.trim();
      if (trimmed.isEmpty || trimmed == 'null' || trimmed == 'jsonpgz();') {
        return null;
      }

      if (!trimmed.contains('{') || !trimmed.contains('}')) {
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
        return null;
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(jsonStr);
      } on FormatException catch (e) {
        return null;
      } catch (e) {
        return null;
      }

      final returnedFundCode = data['fundcode']?.toString() ?? '';

      final fundName = data['name']?.toString() ?? '';
      if (fundName.isEmpty || fundName == 'null' || fundName == 'undefined') {
        return null;
      }

      String gszStr = data['gsz']?.toString() ?? '';
      if (gszStr.isEmpty || gszStr == 'null' || gszStr == 'undefined') {
        return null;
      }

      double gsz;
      double gszzl;
      try {
        gsz = double.tryParse(gszStr) ?? 0.0;
        gszzl = double.tryParse(data['gszzl']?.toString() ?? '0') ?? 0.0;
      } catch (e) {
        return null;
      }

      return {
        'fundCode': code,
        'name': fundName,
        'dwjz': double.tryParse(data['dwjz']?.toString() ?? '0') ?? 0.0,
        'gsz': gsz,
        'gszzl': gszzl,
        'gztime': data['gztime']?.toString() ?? '',
        'jzrq': data['jzrq']?.toString() ?? '',
      };
    } on TimeoutException catch (e) {
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 获取指数K线数据（使用东方财富API）
  /// indexCode: 指数代码，如 '000905' (中证500), '000852' (中证1000)
  Future<List<NetWorthPoint>> fetchIndexData(String indexCode) async {
    // 使用东方财富指数K线API
    final url = Uri.parse(
      'https://push2.eastmoney.com/api/qt/kline/get?'
      'secid=1.$indexCode&'
      'klt=101&'
      'fqt=1&'
      'beg=19900101&'
      'end=20500101&'
      'lmt=10000',
    );
    
    final response = await http.get(url).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    
    final jsonData = jsonDecode(utf8.decode(response.bodyBytes));
    final data = jsonData['data'];
    if (data == null || data['klines'] == null) {
      return [];
    }
    
    final klines = data['klines'] as List;
    final points = <NetWorthPoint>[];
    
    for (var kline in klines) {
      // 格式: "日期,开盘,收盘,最高,最低,成交量,成交额,..."
      final parts = kline.split(',');
      if (parts.length >= 3) {
        try {
          final dateStr = parts[0];
          final closePrice = double.parse(parts[2]);
          
          // 解析日期: "2024-01-01"
          final dateParts = dateStr.split('-');
          if (dateParts.length == 3) {
            final date = DateTime(
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
              int.parse(dateParts[2]),
            );
            
            points.add(NetWorthPoint(
              date: date,
              nav: closePrice,
              series: 'index',
            ));
          }
        } catch (e) {
          // 跳过解析失败的行
          continue;
        }
      }
    }
    
    return points;
  }
}
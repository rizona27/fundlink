import 'dart:convert';
import 'package:fast_gbk/fast_gbk.dart';
import '../services/http_client_provider.dart';

class StockQuote {
  final String code;
  final double price;
  final double? pe;
  final double? pb;
  final double? totalMv;

  const StockQuote({
    required this.code,
    required this.price,
    this.pe,
    this.pb,
    this.totalMv,
  });

  /// Market cap classification based on total market value (亿元).
  /// Thresholds: >= 200 亿 → 大盘, >= 50 亿 → 中盘, < 50 亿 → 小盘.
  String get marketCapStyle {
    if (totalMv == null) return '未知';
    if (totalMv! >= 200) return '大盘';
    if (totalMv! >= 50) return '中盘';
    return '小盘';
  }

  /// Value / Growth / Balanced classification.
  String get valueStyle {
    if (pe == null && pb == null) return '未知';
    final lowPE = pe != null && pe! > 0 && pe! < 15;
    final lowPB = pb != null && pb! > 0 && pb! < 1.5;
    final highPE = pe != null && pe! > 25;
    final highPB = pb != null && pb! > 3;

    if (lowPE && lowPB) return '价值';
    if (highPE || highPB) return '成长';
    return '均衡';
  }

  /// Market label for display.
  String get marketLabel {
    if (code.startsWith('hk')) return 'HK';
    if (code.startsWith('sh')) return '沪A';
    if (code.startsWith('sz')) return '深A';
    return '';
  }
}

class StockQuoteService {
  static const int _batchSize = 20;
  static const Duration _ttl = Duration(minutes: 3);

  final Map<String, StockQuote> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};

  /// Fetch quotes for a batch of raw stock codes.
  /// Results are cached with a [_ttl] expiry; stale entries are re-fetched.
  Future<Map<String, StockQuote>> fetchQuotes(List<String> rawCodes) async {
    if (rawCodes.isEmpty) return {};

    final uniqueCodes = rawCodes.map((c) => toFullCode(c)).toSet().toList();
    final now = DateTime.now();

    // Split into cached (still fresh) and uncached / stale.
    final fresh = <String, StockQuote>{};
    final stale = <String>[];
    for (final code in uniqueCodes) {
      final ts = _cacheTimestamps[code];
      if (_cache.containsKey(code) && ts != null && now.difference(ts) < _ttl) {
        fresh[code] = _cache[code]!;
      } else {
        stale.add(code);
      }
    }

    // Fetch stale / uncached in 20-stock chunks.
    if (stale.isNotEmpty) {
      for (var i = 0; i < stale.length; i += _batchSize) {
        final end = (i + _batchSize > stale.length) ? stale.length : i + _batchSize;
        final chunk = stale.sublist(i, end);
        await _fetchBatch(chunk);
      }
    }

    // Build result: prefer fresh-then-cached, skip missing.
    final result = <String, StockQuote>{};
    for (final code in uniqueCodes) {
      if (fresh.containsKey(code)) {
        result[code] = fresh[code]!;
      } else if (_cache.containsKey(code)) {
        result[code] = _cache[code]!;
      }
    }
    return result;
  }

  String toFullCode(String rawCode) {
    if (rawCode.length == 5 && RegExp(r'^\d{5}$').hasMatch(rawCode)) {
      return 'hk$rawCode';
    }
    if (rawCode.startsWith('6')) return 'sh$rawCode';
    if (rawCode.startsWith('0') || rawCode.startsWith('3')) return 'sz$rawCode';
    if (rawCode.startsWith('5')) return 'sz$rawCode';
    return rawCode;
  }

  /// Fallback market cap style based on stock exchange / board when API data
  /// is unavailable.
  static String fallbackMarketCapStyle(String rawCode) {
    if (rawCode.length == 5 && RegExp(r'^\d{5}$').hasMatch(rawCode)) {
      return '中盘'; // HK stocks: too varied, assume mid
    }
    if (rawCode.startsWith('688')) return '中盘'; // STAR board
    if (rawCode.startsWith('300') || rawCode.startsWith('301')) return '中盘'; // ChiNext
    if (rawCode.startsWith('6')) return '大盘'; // Shanghai main
    if (rawCode.startsWith('0') || rawCode.startsWith('3')) return '中盘'; // SZ main / ChiNext
    return '中盘';
  }

  // ---------------------------------------------------------------------------
  // Network
  // ---------------------------------------------------------------------------

  Future<void> _fetchBatch(List<String> fullCodes) async {
    try {
      final codesParam = fullCodes.join(',');
      final url = Uri.parse('https://qt.gtimg.cn/q=$codesParam');

      final response = await HttpClientProvider.client
          .get(url)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return;

      final bytes = response.bodyBytes;

      // Tencent API returns GBK — decode with fast_gbk first.
      // Fall back to latin1 only if GBK produces no valid lines.
      String body;
      try {
        body = gbk.decode(bytes);
        // Quick sanity: the response should contain 'v_' markers.
        if (!body.contains('v_') || !body.contains('~')) {
          body = latin1.decode(bytes);
        }
      } catch (_) {
        body = latin1.decode(bytes);
      }

      final now = DateTime.now();
      final lines = body.split('\n');
      for (final line in lines) {
        if (line.trim().isEmpty) continue;

        final match = RegExp(r'v_([^=]+)="([^"]*)"').firstMatch(line);
        if (match == null) continue;

        final code = match.group(1)!;
        String value = match.group(2)!;

        // Some responses escape quotes inside the value — strip trailing junk.
        final endQuote = value.indexOf('"');
        if (endQuote > 0) value = value.substring(0, endQuote);

        final parts = value.split('~');
        if (parts.length < 4) continue;

        final price = double.tryParse(parts[3]) ?? 0.0;
        if (price <= 0) continue;

        double? pe;
        if (parts.length > 39) {
          final v = parts[39].trim();
          if (v.isNotEmpty && v != '-' && v != '--') {
            pe = double.tryParse(v);
          }
        }

        double? pb;
        if (parts.length > 46) {
          final v = parts[46].trim();
          if (v.isNotEmpty && v != '-' && v != '--') {
            pb = double.tryParse(v);
          }
        }

        double? totalMvYi;
        if (parts.length > 45) {
          final v = parts[45].trim();
          if (v.isNotEmpty && v != '-' && v != '--') {
            final wan = double.tryParse(v);
            if (wan != null && wan > 0) {
              totalMvYi = wan / 10000; // 万元 → 亿元
            }
          }
        }

        _cache[code] = StockQuote(
          code: code,
          price: price,
          pe: pe,
          pb: pb,
          totalMv: totalMvYi,
        );
        _cacheTimestamps[code] = now;
      }
    } catch (_) {
      // Non-fatal: cached data is returned if available.
    }
  }

  void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }
}

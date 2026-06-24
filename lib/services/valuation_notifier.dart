import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import '../models/log_entry.dart';
import '../services/database_repository.dart';
import '../services/fund_service.dart';
import '../services/log_notifier.dart';

/// Manages real-time fund valuation caching and refresh with ChangeNotifier.
class ValuationNotifier extends ChangeNotifier {
  final DatabaseRepository? _repository;
  final LogNotifier _logNotifier;
  final List<Map<String, dynamic>> Function() _getHoldings; // callback for holdings access

  Map<String, dynamic> _fValCache = {};
  bool _isValuationRefreshing = false;
  double _fValuationRefreshProgress = 0.0;
  String _lastValuationUpdateTime = '';
  bool _fIsValuationRefreshInProgress = false;
  Completer<void>? _currentValuationRefreshCompleter;
  bool _disposed = false;

  ValuationNotifier(
    this._repository,
    this._logNotifier,
    this._getHoldings,
  );

  // valuationCache getter removed since internal field type differs
  bool get isValuationRefreshing => _isValuationRefreshing;
  double get valuationRefreshProgress => _fValuationRefreshProgress;
  String get lastValuationUpdateTime => _lastValuationUpdateTime;
  bool get isValuationRefreshInProgress => _fIsValuationRefreshInProgress;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ─── Cache persistence ───

  Future<void> loadValuationCache() async {
    if (_disposed) return;
    if (kIsWeb) {
      _fValCache = {};
      return;
    }
    try {
      final cacheStr = await _repository!.getSetting('valuation_cache');
      if (cacheStr != null && cacheStr.isNotEmpty) {
        final Map<String, dynamic> cacheMap = jsonDecode(cacheStr);
        _fValCache = cacheMap
            .map((key, value) => MapEntry(key, value as Map<String, dynamic>));
      } else {
        _fValCache = {};
      }
    } catch (e) {
      debugPrint('[ValuationNotifier] 加载估值缓存失败: $e');
      _fValCache = {};
    }
  }

  Future<void> saveValuationCache() async {
    if (_disposed || kIsWeb) return;
    try {
      final cacheStr = jsonEncode(_fValCache);
      await _repository!.saveSetting('valuation_cache', cacheStr);
    } catch (e) {
      debugPrint('[ValuationNotifier] 保存估值缓存失败: $e');
    }
  }

  // ─── Cache access ───

  Map<String, dynamic>? getValuation(String fundCode) {
    final cached = _fValCache[fundCode];
    if (cached == null) return null;
    final cacheTime = DateTime.tryParse(cached['cacheTime'] ?? '');
    if (cacheTime == null) return null;

    final now = DateTime.now();
    if (now.difference(cacheTime).inSeconds >
        AppConstants.valuationCacheValidSeconds) {
      return null;
    }

    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 60 + minute;
    final isTradingTime =
        (currentTime >= 9 * 60 + 30 && currentTime <= 11 * 60 + 30) ||
        (currentTime >= 13 * 60 && currentTime <= 15 * 60);

    if (!isTradingTime) {
      final cachedDate = DateTime.parse(cached['cacheTime']);
      final todayOnly = DateTime(now.year, now.month, now.day);
      final cachedDateOnly =
          DateTime(cachedDate.year, cachedDate.month, cachedDate.day);
      if (cachedDateOnly.isAtSameMomentAs(todayOnly)) {
        return {
          'gsz': cached['gsz'],
          'gszzl': cached['gszzl'],
          'gztime': cached['gztime'],
        };
      }
    }

    return {
      'gsz': cached['gsz'],
      'gszzl': cached['gszzl'],
      'gztime': cached['gztime'],
    };
  }

  Future<void> updateValuationCache(
      String fundCode, Map<String, dynamic> valuation) async {
    _fValCache[fundCode] = {
      'gsz': valuation['gsz'],
      'gszzl': valuation['gszzl'],
      'gztime': valuation['gztime'],
      'cacheTime': DateTime.now().toIso8601String(),
    };
    await saveValuationCache();
    notifyListeners();
  }

  // ─── Refresh state management ───

  void startValuationRefresh() {
    if (_isValuationRefreshing) return;
    _isValuationRefreshing = true;
    _fValuationRefreshProgress = 0.0;
    notifyListeners();
  }

  void updateValuationRefreshProgress(double progress) {
    if (!_isValuationRefreshing) return;
    _fValuationRefreshProgress = progress;
    notifyListeners();
  }

  void finishValuationRefresh({String? updateTime}) {
    _isValuationRefreshing = false;
    _fValuationRefreshProgress = 0.0;
    if (updateTime != null && updateTime.isNotEmpty) {
      _lastValuationUpdateTime = updateTime;
    }
    notifyListeners();
  }

  void setValuationUpdateTime(String time) {
    _lastValuationUpdateTime = time;
    notifyListeners();
  }

  // ─── Valuation refresh with FundService ───

  Future<void> refreshAllValuations(FundService fundService,
      {bool silent = false}) async {
    if (_fIsValuationRefreshInProgress &&
        _currentValuationRefreshCompleter != null) {
      if (!silent) {
        await _logNotifier.addLog('估值刷新正在进行中，请稍后', type: LogType.info);
      }
      return _currentValuationRefreshCompleter!.future;
    }

    _fIsValuationRefreshInProgress = true;
    _currentValuationRefreshCompleter = Completer<void>();

    startValuationRefresh();

    try {
      final holdings = _getHoldings();
      if (holdings.isEmpty) {
        finishValuationRefresh();
        _currentValuationRefreshCompleter!.complete();
        _fIsValuationRefreshInProgress = false;
        _currentValuationRefreshCompleter = null;
        return;
      }

      int successCount = 0;
      int failCount = 0;
      final total = holdings.length;
      String latestUpdateTime = _lastValuationUpdateTime;

      const batchSize = 5;
      for (int batchStart = 0; batchStart < total; batchStart += batchSize) {
        final batchEnd = (batchStart + batchSize < total)
            ? batchStart + batchSize
            : total;
        final batch = holdings.sublist(batchStart, batchEnd);

        final results = await Future.wait(
          batch.map((holding) async {
            try {
              final valuation = await fundService
                  .fetchRealtimeValuation(holding['fundCode'] as String);
              if (valuation != null &&
                  valuation['gsz'] != null &&
                  valuation['gsz'] > 0) {
                await updateValuationCache(holding['fundCode'] as String, {
                  'gsz': valuation['gsz'],
                  'gszzl': valuation['gszzl'] ?? 0.0,
                  'gztime': valuation['gztime'] ?? '',
                });
                if (valuation['gztime'] != null &&
                    valuation['gztime'].toString().isNotEmpty) {
                  return {'success': true, 'gztime': valuation['gztime']};
                }
                return {'success': true, 'gztime': ''};
              } else {
                await _logNotifier.addLog(
                    '基金 ${holding['fundCode']} 估值获取失败: 数据无效',
                    type: LogType.error);
                return {'success': false, 'gztime': ''};
              }
            } catch (e) {
              await _logNotifier.addLog(
                  '基金 ${holding['fundCode']} 估值获取异常: $e',
                  type: LogType.error);
              return {'success': false, 'gztime': ''};
            }
          }),
        );

        for (final result in results) {
          if (result['success'] == true) {
            successCount++;
            final gztime = result['gztime'] as String;
            if (gztime.isNotEmpty) {
              latestUpdateTime = _formatGzTime(gztime);
            }
          } else {
            failCount++;
          }
        }

        updateValuationRefreshProgress(batchEnd / total);

        if (batchEnd < total) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      if (latestUpdateTime.isNotEmpty) {
        setValuationUpdateTime(latestUpdateTime);
      }

      if (!silent) {
        await _logNotifier.addLog(
            '估值刷新完成: 成功 $successCount, 失败 $failCount',
            type: LogType.success);
      }

      _currentValuationRefreshCompleter!.complete();
    } catch (e) {
      await _logNotifier.addLog('估值刷新异常: $e', type: LogType.error);
      _currentValuationRefreshCompleter!.completeError(e);
    } finally {
      finishValuationRefresh();
      _fIsValuationRefreshInProgress = false;
      _currentValuationRefreshCompleter = null;
    }
  }

  String _formatGzTime(String gztime) {
    if (gztime.isEmpty) return '--';
    try {
      final parts = gztime.split(' ');
      if (parts.length >= 2) {
        final dateParts = parts[0].split('-');
        if (dateParts.length >= 3) {
          return '${dateParts[1]}/${dateParts[2]} ${parts[1].substring(0, 5)}';
        }
      }
    } catch (e) {
      // fall through
    }
    return gztime;
  }
}

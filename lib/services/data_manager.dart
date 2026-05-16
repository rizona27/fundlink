import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../models/fund_holding.dart';
import '../models/fund_info_cache.dart';
import '../models/log_entry.dart';
import '../models/profit_result.dart';
import '../models/transaction_record.dart';
import '../services/china_trading_day_service.dart';
import '../services/database_helper.dart';
import '../services/database_repository.dart';
import '../services/fund_service.dart';
import '../services/version_check_service.dart';
import '../utils/error_handler.dart';
import '../utils/smart_cache.dart';
import '../widgets/theme_switch.dart' show ThemeMode;

extension ThemeModeDisplayName on ThemeMode {
  String get displayName {
    switch (this) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }
}

class DataManager extends ChangeNotifier {
  final DatabaseRepository? _repository = kIsWeb ? null : DatabaseRepository();

  List<FundHolding> _holdings = [];
  List<TransactionRecord> _transactions = [];
  List<LogEntry> _logs = [];
  bool _isPrivacyMode = true;
  ThemeMode _themeMode = ThemeMode.system;
  Map<String, Map<String, dynamic>> _valuationCache = {};
  Map<String, FundInfoCache> _fundInfoCache = {};
  bool _showHoldersOnSummaryCard = true;

  bool _isValuationRefreshing = false;
  double _valuationRefreshProgress = 0.0;
  String _lastValuationUpdateTime = '';

  bool _isValuationRefreshInProgress = false;
  Completer<void>? _currentValuationRefreshCompleter;

  bool _disposed = false;
  
  bool _isAutoConfirming = false;
  
  final SmartCache<String, ProfitResult> _profitCache = SmartCache(
    maxSize: AppConstants.profitCacheMaxSize,
    ttl: AppConstants.profitCacheTtl,
  );
  
  final SmartCache<String, List<TransactionRecord>> _transactionHistoryCache = SmartCache(
    maxSize: AppConstants.transactionHistoryCacheMaxSize,
    ttl: AppConstants.transactionHistoryCacheTtl,
  );
  
  Timer? _cacheCleanupTimer;
  
  VersionInfo? _latestVersionInfo;
  
  void _clearRelatedCaches(String clientId, String fundCode) {
    final cacheKey = '${clientId}_$fundCode';
    _transactionHistoryCache.remove(cacheKey);
    
    _profitCache.removeWhere((key, value) => key.startsWith('${clientId}_$fundCode'));
  }

  List<FundHolding> get holdings => List.unmodifiable(_holdings);
  List<TransactionRecord> get transactions => List.unmodifiable(_transactions);
  List<LogEntry> get logs => List.unmodifiable(_logs);
  bool get isPrivacyMode => _isPrivacyMode;
  ThemeMode get themeMode => _themeMode;
  bool get isValuationRefreshing => _isValuationRefreshing;
  double get valuationRefreshProgress => _valuationRefreshProgress;
  String get lastValuationUpdateTime => _lastValuationUpdateTime;
  bool get isValuationRefreshInProgress => _isValuationRefreshInProgress;
  bool get showHoldersOnSummaryCard => _showHoldersOnSummaryCard;
  VersionInfo? get latestVersionInfo => _latestVersionInfo;

  FundInfoCache? getFundInfoCache(String fundCode) {
    final cached = _fundInfoCache[fundCode];
    if (cached == null) {
      return null;
    }
    
    final now = DateTime.now();
    
    final cacheAgeDays = now.difference(cached.cacheTime).inDays;
    if (cacheAgeDays > AppConstants.fundInfoCacheValidDays) {
      _fundInfoCache.remove(fundCode);
      return null;
    }
    
    final navDateOnly = DateTime(cached.navDate.year, cached.navDate.month, cached.navDate.day);
    final todayOnly = DateTime(now.year, now.month, now.day);
    final daysDiff = todayOnly.difference(navDateOnly).inDays;
    
    if (daysDiff < 0) {
      _fundInfoCache.remove(fundCode);
      return null;
    }
    
    if (daysDiff > 7) {
      _fundInfoCache.remove(fundCode);
      return null;
    }
        
    final hasReturns = cached.navReturn1m != null || cached.navReturn3m != null || 
                      cached.navReturn6m != null || cached.navReturn1y != null;
    final returnCacheAge = now.difference(cached.cacheTime).inDays;
    final returnsNeedRefresh = hasReturns && returnCacheAge >= AppConstants.fundReturnCacheValidDays;
    
    if (returnsNeedRefresh) {
    }
    
    return cached;
  }

  void saveFundInfoCache(FundInfoCache fundInfo) {
    _fundInfoCache[fundInfo.fundCode] = fundInfo;
    saveFundInfoCacheToPrefs();
  }

  List<FundHolding> get pinnedHoldings {
    return _holdings.where((h) => h.isPinned).toList();
  }

  List<FundHolding> get unpinnedHoldings {
    return _holdings.where((h) => !h.isPinned).toList();
  }

  DataManager() {
    loadData();
    _startCacheCleanup();
    _setupLifecycleObserver();
  }
  
  void _setupLifecycleObserver() {
    if (_disposed) return;
    
    WidgetsBinding.instance.addObserver(_AppLifecycleObserver(this));
  }
  
  void _startCacheCleanup() {
    if (_disposed) return;
    
    _cacheCleanupTimer = Timer.periodic(AppConstants.cacheCleanupInterval, (_) {
      if (!_disposed) {
        _cleanupExpiredCaches();
      }
    });
  }
  
  Future<void> _cleanupExpiredCaches() async {
    if (_disposed) return;
    
    try {
      final profitCleaned = _profitCache.cleanup();
      if (profitCleaned > 0) {
      }
      
      final transactionCleaned = _transactionHistoryCache.cleanup();
      if (transactionCleaned > 0) {
      }
      
      await _checkMemoryAndCleanup();
    } catch (e) {
    }
  }
  
  Future<void> _checkMemoryAndCleanup() async {
    try {
      if (_profitCache.size > 40 || _transactionHistoryCache.size > 25) {
        _profitCache.clear();
        _transactionHistoryCache.clear();
        await addLog('内存优化：已清理缓存', type: LogType.info);
      }
    } catch (e) {
      ErrorHandler.handleError(e, context: '内存检查清理', dataManager: this);
    }
  }
  
  Future<void> forceCleanupCaches() async {
    if (_disposed) return;
    
    _profitCache.clear();
    _transactionHistoryCache.clear();
    await addLog('手动清理所有缓存', type: LogType.info);
  }
  
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    
    WidgetsBinding.instance.removeObserver(_AppLifecycleObserver(this));
    
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = null;
    
    _profitCache.clear();
    _transactionHistoryCache.clear();
    
    super.dispose();
  }
  
  Future<void> saveOnBackground() async {
    if (_disposed) return;
    
    try {
      await saveData();
      await saveFundInfoCacheToPrefs();
      await saveValuationCache();
      await saveVersionInfoToPrefs();
      await addLog('应用进入后台，数据已保存', type: LogType.info);
    } catch (e) {
    }
  }
  
  Future<void> reloadOnResume() async {
    if (_disposed) return;
    
  }

  Future<void> loadData() async {
    try {
      if (kIsWeb) {
        await _loadDataFromPrefs();
      } else {
        await _loadDataFromSQLite();
      }

      await loadValuationCache();
      
      await loadFundInfoCache();
      
      await loadVersionInfo();
      
      
      notifyListeners();
    } catch (e) {
      await addLog('数据加载异常: $e', type: LogType.error);
    }
  }
  
  Future<void> _loadDataFromSQLite() async {
    _holdings = await _repository!.getAllHoldings();
    
    _transactions = await _repository!.getAllTransactions();
    
    _logs = await _repository!.getLogs(limit: AppConstants.maxLogEntries);
    
    final privacyModeStr = await _repository!.getSetting('privacy_mode');
    if (privacyModeStr != null) {
      _isPrivacyMode = privacyModeStr == 'true';
    }
    
    final themeModeStr = await _repository!.getSetting('theme_mode');
    if (themeModeStr != null) {
      _themeMode = _parseThemeMode(themeModeStr);
    } else {
      _themeMode = ThemeMode.system;
    }
    
    final showHoldersStr = await _repository!.getSetting('show_holders_on_summary');
    if (showHoldersStr != null) {
      _showHoldersOnSummaryCard = showHoldersStr == 'true';
    }
    
  }
  
  Future<void> _loadDataFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final holdingsJson = prefs.getStringList(AppConstants.keyHoldings);
    if (holdingsJson != null) {
      _holdings = holdingsJson
          .map((json) => FundHolding.fromJson(jsonDecode(json)))
          .toList();
    }

    final transactionsJson = prefs.getStringList(AppConstants.keyTransactions);
    if (transactionsJson != null) {
      _transactions = transactionsJson
          .map((json) => TransactionRecord.fromJson(jsonDecode(json)))
          .toList();
    }

    final logsJson = prefs.getStringList(AppConstants.keyLogs);
    if (logsJson != null) {
      _logs = logsJson
          .map((json) => LogEntry.fromJson(jsonDecode(json)))
          .toList();
    }

    _isPrivacyMode = prefs.getBool(AppConstants.keyPrivacyMode) ?? true;

    final themeModeString = prefs.getString(AppConstants.keyThemeMode);
    if (themeModeString != null) {
      _themeMode = _parseThemeMode(themeModeString);
    } else {
      _themeMode = ThemeMode.system;
    }

    _showHoldersOnSummaryCard = prefs.getBool(AppConstants.keyShowHoldersOnSummaryCard) ?? true;
  }

  ThemeMode _parseThemeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> saveData() async {
    try {
      if (kIsWeb) {
        await _saveDataToPrefs();
      } else {
        await _saveSettingsToPrefs();
        
        await _repository!.flush();
      }
      notifyListeners();
    } catch (e) {
    }
  }
  
  Future<void> _saveSettingsToPrefs() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.keyPrivacyMode, _isPrivacyMode);
      await prefs.setString(AppConstants.keyThemeMode, _themeModeToString(_themeMode));
      await prefs.setBool(AppConstants.keyShowHoldersOnSummaryCard, _showHoldersOnSummaryCard);
    } else {
      await _repository!.saveSetting('privacy_mode', _isPrivacyMode.toString());
      await _repository!.saveSetting('theme_mode', _themeModeToString(_themeMode));
      await _repository!.saveSetting('show_holders_on_summary_card', _showHoldersOnSummaryCard.toString());
    }
  }
  
  Future<void> _saveDataToPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final holdingsJson = _holdings
        .map((holding) => jsonEncode(holding.toJson()))
        .toList();
    await prefs.setStringList(AppConstants.keyHoldings, holdingsJson);

    final transactionsJson = _transactions
        .map((tx) => jsonEncode(tx.toJson()))
        .toList();
    await prefs.setStringList(AppConstants.keyTransactions, transactionsJson);

    final logsJson = _logs
        .take(AppConstants.maxLogEntries)
        .map((log) => jsonEncode(log.toJson()))
        .toList();
    await prefs.setStringList(AppConstants.keyLogs, logsJson);

    await prefs.setBool(AppConstants.keyPrivacyMode, _isPrivacyMode);
    await prefs.setString(AppConstants.keyThemeMode, _themeModeToString(_themeMode));
    await prefs.setBool(AppConstants.keyShowHoldersOnSummaryCard, _showHoldersOnSummaryCard);
  }

  Future<void> loadValuationCache() async {
    if (kIsWeb) {
      _valuationCache = {};
      return;
    }
    
    try {
      final cacheStr = await _repository!.getSetting('valuation_cache');
      if (cacheStr != null && cacheStr.isNotEmpty) {
        final Map<String, dynamic> cacheMap = jsonDecode(cacheStr);
        _valuationCache = cacheMap.map((key, value) => MapEntry(key, value as Map<String, dynamic>));
      } else {
        _valuationCache = {};
      }
    } catch (e) {
      _valuationCache = {};
    }
  }

  Future<void> saveValuationCache() async {
    if (kIsWeb) {
      return;
    }
    
    try {
      final cacheStr = jsonEncode(_valuationCache);
      await _repository!.saveSetting('valuation_cache', cacheStr);
    } catch (e) {
    }
  }

  Future<void> loadFundInfoCache() async {
    
    if (kIsWeb) {
      _fundInfoCache = {};
      return;
    }
    
    try {
      final cacheStr = await _repository!.getSetting('fund_info_cache');
      
      if (cacheStr == null) {
        _fundInfoCache = {};
        return;
      }
      
      if (cacheStr.isEmpty) {
        _fundInfoCache = {};
        return;
      }
      
      final Map<String, dynamic> cacheMap = jsonDecode(cacheStr);
      
      _fundInfoCache = cacheMap.map((key, value) {
        return MapEntry(key, FundInfoCache.fromJson(value));
      });
      
      for (final entry in _fundInfoCache.entries) {
        final navDateStr = '${entry.value.navDate.year}-${entry.value.navDate.month.toString().padLeft(2, '0')}-${entry.value.navDate.day.toString().padLeft(2, '0')}';
        final hasReturns = entry.value.navReturn1m != null || entry.value.navReturn3m != null || 
                          entry.value.navReturn6m != null || entry.value.navReturn1y != null;
      }
    } catch (e) {
      _fundInfoCache = {};
    }
  }

  Future<void> saveFundInfoCacheToPrefs() async {
    if (kIsWeb) {
      return;
    }
    
    try {
      if (_fundInfoCache.isEmpty) {
        return;
      }
      
      final cacheMap = _fundInfoCache.map((key, value) {
        return MapEntry(key, value.toJson());
      });
      final cacheStr = jsonEncode(cacheMap);
      await _repository!.saveSetting('fund_info_cache', cacheStr);
      
      final verifyStr = await _repository!.getSetting('fund_info_cache');
      if (verifyStr != null && verifyStr.isNotEmpty) {
        final verifyMap = jsonDecode(verifyStr);
      } else {
      }
    } catch (e) {
    }
  }

  Map<String, dynamic>? getValuation(String fundCode) {
    final cached = _valuationCache[fundCode];
    if (cached == null) return null;
    final cacheTime = DateTime.tryParse(cached['cacheTime'] ?? '');
    if (cacheTime == null) return null;
    
    final now = DateTime.now();
    if (now.difference(cacheTime).inSeconds > AppConstants.valuationCacheValidSeconds) {
      return null;
    }
    
    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 60 + minute;
    final isTradingTime = (currentTime >= 9 * 60 + 30 && currentTime <= 11 * 60 + 30) ||
                          (currentTime >= 13 * 60 && currentTime <= 15 * 60);
    
    if (!isTradingTime) {
      final cachedDate = DateTime.parse(cached['cacheTime']);
      final todayOnly = DateTime(now.year, now.month, now.day);
      final cachedDateOnly = DateTime(cachedDate.year, cachedDate.month, cachedDate.day);
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

  Future<void> updateValuationCache(String fundCode, Map<String, dynamic> valuation) async {
    _valuationCache[fundCode] = {
      'gsz': valuation['gsz'],
      'gszzl': valuation['gszzl'],
      'gztime': valuation['gztime'],
      'cacheTime': DateTime.now().toIso8601String(),
    };
    await saveValuationCache();
    notifyListeners();
  }

  void startValuationRefresh() {
    if (_isValuationRefreshing) return;
    _isValuationRefreshing = true;
    _valuationRefreshProgress = 0.0;
    notifyListeners();
  }

  void updateValuationRefreshProgress(double progress) {
    if (!_isValuationRefreshing) return;
    _valuationRefreshProgress = progress;
    notifyListeners();
  }

  void finishValuationRefresh({String? updateTime}) {
    _isValuationRefreshing = false;
    _valuationRefreshProgress = 0.0;
    if (updateTime != null && updateTime.isNotEmpty) {
      _lastValuationUpdateTime = updateTime;
    }
    notifyListeners();
  }

  void setValuationUpdateTime(String time) {
    _lastValuationUpdateTime = time;
    notifyListeners();
  }

  void setLatestVersionInfo(VersionInfo? versionInfo) {
    _latestVersionInfo = versionInfo;
    saveVersionInfoToPrefs();
    notifyListeners();
  }
  
  Future<void> loadVersionInfo() async {
    if (kIsWeb) {
      return;
    }
    
    try {
      final cacheStr = await _repository!.getSetting('version_info_cache');
      if (cacheStr != null && cacheStr.isNotEmpty) {
        final Map<String, dynamic> cacheMap = jsonDecode(cacheStr);
        final cachedTime = DateTime.tryParse(cacheMap['cachedTime'] ?? '');
        
        if (cachedTime != null) {
          final now = DateTime.now();
          if (now.difference(cachedTime).inHours < 24) {
            _latestVersionInfo = VersionInfo.fromJson(cacheMap['versionInfo']);
          } else {
            _latestVersionInfo = null;
          }
        }
      }
    } catch (e) {
    }
  }
  
  Future<void> saveVersionInfoToPrefs() async {
    if (kIsWeb || _latestVersionInfo == null) {
      return;
    }
    
    try {
      final cacheMap = {
        'versionInfo': _latestVersionInfo!.toJson(),
        'cachedTime': DateTime.now().toIso8601String(),
      };
      final cacheStr = jsonEncode(cacheMap);
      await _repository!.saveSetting('version_info_cache', cacheStr);
    } catch (e) {
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
    }
    return gztime;
  }

  Future<void> refreshAllValuations(FundService fundService, {bool silent = false}) async {
    if (_isValuationRefreshInProgress && _currentValuationRefreshCompleter != null) {
      if (!silent) {
        await addLog('估值刷新正在进行中，请稍后', type: LogType.info);
      }
      return _currentValuationRefreshCompleter!.future;
    }

    _isValuationRefreshInProgress = true;
    _currentValuationRefreshCompleter = Completer<void>();

    startValuationRefresh();

    try {
      final holdings = _holdings;
      if (holdings.isEmpty) {
        finishValuationRefresh();
        _currentValuationRefreshCompleter!.complete();
        _isValuationRefreshInProgress = false;
        _currentValuationRefreshCompleter = null;
        return;
      }

      int successCount = 0;
      int failCount = 0;
      final total = holdings.length;
      String latestUpdateTime = _lastValuationUpdateTime;

      const batchSize = 5; 
      for (int batchStart = 0; batchStart < total; batchStart += batchSize) {
        final batchEnd = (batchStart + batchSize < total) ? batchStart + batchSize : total;
        final batch = holdings.sublist(batchStart, batchEnd);
        
        final results = await Future.wait(
          batch.map((holding) async {
            try {
              final valuation = await fundService.fetchRealtimeValuation(holding.fundCode);
              if (valuation != null && valuation['gsz'] != null && valuation['gsz'] > 0) {
                await updateValuationCache(holding.fundCode, {
                  'gsz': valuation['gsz'],
                  'gszzl': valuation['gszzl'] ?? 0.0,
                  'gztime': valuation['gztime'] ?? '',
                });
                if (valuation['gztime'] != null && valuation['gztime'].toString().isNotEmpty) {
                  return {'success': true, 'gztime': valuation['gztime']};
                }
                return {'success': true, 'gztime': ''};
              } else {
                await addLog('基金 ${holding.fundCode} 估值获取失败: 数据无效', type: LogType.error);
                return {'success': false, 'gztime': ''};
              }
            } catch (e) {
              await addLog('基金 ${holding.fundCode} 估值获取异常: $e', type: LogType.error);
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
        await addLog('估值刷新完成: 成功 $successCount, 失败 $failCount', type: LogType.success);
      }
      if (failCount > 0) {
      }

      _currentValuationRefreshCompleter!.complete();
    } catch (e) {
      await addLog('估值刷新异常: $e', type: LogType.error);
      _currentValuationRefreshCompleter!.completeError(e);
    } finally {
      finishValuationRefresh();
      _isValuationRefreshInProgress = false;
      _currentValuationRefreshCompleter = null;
    }
  }

  Future<void> addHolding(FundHolding holding) async {
    if (!holding.isValidHolding) {
      await addLog('添加持仓失败: 数据无效', type: LogType.error);
      throw Exception('无效的持仓数据');
    }

    if (!kIsWeb) {
      await _repository!.insertHolding(holding);
    }
    _holdings = [..._holdings, holding];
    
    await addLog('新增持仓: ${holding.fundCode} - ${holding.clientName}', type: LogType.success);
    await saveData();
    notifyListeners();
  }

  Future<void> batchAddHoldings(List<FundHolding> holdings) async {
    if (holdings.isEmpty) return;
    
    for (final holding in holdings) {
      if (!holding.isValidHolding) {
        await addLog('批量添加持仓失败: 持仓 ${holding.fundCode} 数据无效', type: LogType.error);
        throw Exception('无效的持仓数据: ${holding.fundCode}');
      }
    }
    
    if (!kIsWeb) {
      await _repository!.batchInsertHoldings(holdings);
    }
    
    _holdings = [..._holdings, ...holdings];
    
    await addLog('批量添加 ${holdings.length} 个持仓', type: LogType.success);
    await saveData();
    notifyListeners();
  }
  
  Future<void> batchAddTransactions(List<TransactionRecord> transactions) async {
    if (transactions.isEmpty) return;
    
    for (final tx in transactions) {
      if (tx.amount <= 0) {
        await addLog('批量添加交易失败: 交易金额必须大于0', type: LogType.error);
        throw Exception('无效的交易数据: ${tx.fundCode}');
      }
    }
    
    final enhancedTransactions = <TransactionRecord>[];
    for (final tx in transactions) {
      final applicationDate = await getTradeApplicationDate(tx.tradeDate);
      TransactionStatus initialStatus;
      double? frozenShares;
      
      if (tx.isPending) {
        initialStatus = TransactionStatus.submitted;
        if (tx.type == TransactionType.sell) {
          frozenShares = tx.shares;
        }
      } else {
        initialStatus = TransactionStatus.confirmed;
        frozenShares = null;
      }
      
      enhancedTransactions.add(tx.copyWith(
        status: initialStatus,
        applicationDate: applicationDate,
        frozenShares: frozenShares,
      ));
    }
    
    if (!kIsWeb) {
      await _repository!.batchInsertTransactions(enhancedTransactions);
    }
    
    _transactions = [..._transactions, ...enhancedTransactions];
    
    final uniquePairs = <String>{};
    for (final tx in enhancedTransactions) {
      final key = '${tx.clientId}_${tx.fundCode}';
      if (!uniquePairs.contains(key)) {
        uniquePairs.add(key);
        await _rebuildHolding(tx.clientId, tx.fundCode);
      }
    }
    
    await addLog('批量添加 ${enhancedTransactions.length} 笔交易', type: LogType.success);
    await saveData();
    notifyListeners();
  }

  Future<void> addTransaction(TransactionRecord transaction) async {
    if (transaction.amount <= 0) {
      await addLog('添加交易失败: 金额必须大于0', type: LogType.error);
      throw Exception('无效的交易数据');
    }
    
    if (!transaction.isPending && transaction.shares <= 0) {
      await addLog('添加交易失败: 已确认交易必须有份额', type: LogType.error);
      throw Exception('无效的交易数据');
    }

    final applicationDate = await getTradeApplicationDate(transaction.tradeDate);
    TransactionStatus initialStatus;
    double? frozenShares;
    
    if (transaction.isPending) {
      initialStatus = TransactionStatus.submitted;
      
      if (transaction.type == TransactionType.sell) {
        frozenShares = transaction.shares;
        await freezeSharesForRedemption(
          transaction.clientId,
          transaction.fundCode,
          transaction.shares,
        );
      }
    } else {
      initialStatus = TransactionStatus.confirmed;
      frozenShares = null;
    }
    
    final enhancedTransaction = transaction.copyWith(
      status: initialStatus,
      applicationDate: applicationDate,
      frozenShares: frozenShares,
    );

    if (!kIsWeb) {
      await _repository!.insertTransaction(enhancedTransaction);
    }
    _transactions = [..._transactions, enhancedTransaction];
    
    _clearRelatedCaches(enhancedTransaction.clientId, enhancedTransaction.fundCode);

    await _rebuildHolding(enhancedTransaction.clientId, enhancedTransaction.fundCode);

    await addLog(
      '${enhancedTransaction.type.displayName}交易: ${enhancedTransaction.fundCode} - ${enhancedTransaction.clientName}, '
      '金额: ${enhancedTransaction.amount.toStringAsFixed(2)}元, '
      '份额: ${enhancedTransaction.shares.toStringAsFixed(2)}份'
      '${enhancedTransaction.isPending ? '\n申请日期: ${applicationDate.year}-${applicationDate.month.toString().padLeft(2, '0')}-${applicationDate.day.toString().padLeft(2, '0')}\n状态: 待确认' : ''}',
      type: LogType.success,
    );
    await saveData();
    notifyListeners();
  }

  Future<void> _rebuildHolding(String clientId, String fundCode) async {
    final relatedTransactions = _transactions
        .where((tx) => tx.clientId == clientId && tx.fundCode == fundCode)
        .toList()
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));

    if (relatedTransactions.isEmpty) {
      final holdingToRemove = _holdings.firstWhere(
        (h) => h.clientId == clientId && h.fundCode == fundCode,
        orElse: () => FundHolding.invalid(fundCode: fundCode),
      );
      _holdings.removeWhere((h) => h.clientId == clientId && h.fundCode == fundCode);
      
      if (!kIsWeb && holdingToRemove.id.isNotEmpty) {
        await _repository!.deleteHolding(holdingToRemove.id);
      }
      return;
    }

    final firstTx = relatedTransactions.first;
    final lastTx = relatedTransactions.last;

    final existingHolding = _holdings.firstWhere(
      (h) => h.clientId == clientId && h.fundCode == fundCode,
      orElse: () => FundHolding.invalid(fundCode: fundCode),
    );

    final newHolding = FundHolding.fromTransactions(
      clientId: clientId,
      clientName: firstTx.clientName,
      fundCode: fundCode,
      fundName: firstTx.fundName,
      transactions: relatedTransactions,
      navDate: existingHolding.navDate,
      currentNav: existingHolding.currentNav,
      isValid: existingHolding.isValid,
      isPinned: existingHolding.isPinned,
      pinnedTimestamp: existingHolding.pinnedTimestamp,
      navReturn1m: existingHolding.navReturn1m,
      navReturn3m: existingHolding.navReturn3m,
      navReturn6m: existingHolding.navReturn6m,
      navReturn1y: existingHolding.navReturn1y,
    );

    final existingIndex = _holdings.indexWhere(
      (h) => h.clientId == clientId && h.fundCode == fundCode,
    );

    if (existingIndex != -1) {
      _holdings[existingIndex] = newHolding;
      if (!kIsWeb) {
        await _repository!.updateHolding(newHolding.id, newHolding);
      }
    } else {
      _holdings = [..._holdings, newHolding];
      if (!kIsWeb) {
        await _repository!.insertHolding(newHolding);
      }
    }
  }

  List<TransactionRecord> getTransactionHistory(String clientId, String fundCode) {
    final cacheKey = '${clientId}_$fundCode';
    
    if (_transactionHistoryCache.containsKey(cacheKey)) {
      return _transactionHistoryCache[cacheKey]!;
    }
    
    final result = _transactions
        .where((tx) => tx.clientId == clientId && tx.fundCode == fundCode)
        .toList()
      ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
    
    if (_transactionHistoryCache.length >= AppConstants.maxCacheSize) {
      final oldestKey = _transactionHistoryCache.keys.first;
      _transactionHistoryCache.remove(oldestKey);
    }
    
    _transactionHistoryCache[cacheKey] = result;
    return result;
  }

  Future<void> deleteTransaction(String transactionId) async {
    final index = _transactions.indexWhere((tx) => tx.id == transactionId);
    if (index == -1) {
      await addLog('删除交易失败: 未找到交易记录', type: LogType.error);
      throw Exception('交易记录不存在');
    }

    final transaction = _transactions[index];
    
    if (transaction.isPending && 
        transaction.type == TransactionType.sell && 
        transaction.frozenShares != null && 
        transaction.frozenShares! > 0) {
      await releaseFrozenShares(transactionId);
    }
    
    if (!kIsWeb) {
      await _repository!.deleteTransaction(transactionId);
    }
    _transactions = List.from(_transactions)..removeAt(index);
    
    _clearRelatedCaches(transaction.clientId, transaction.fundCode);

    await _rebuildHolding(transaction.clientId, transaction.fundCode);

    await addLog('删除交易记录: ${transaction.fundCode} - ${transaction.type.displayName}', type: LogType.info);
    await saveData();
    notifyListeners();
  }

  Future<void> updateHolding(FundHolding updatedHolding) async {
    final index = _holdings.indexWhere((h) => h.id == updatedHolding.id);
    if (index == -1) {
      await addLog('更新持仓失败: 未找到持仓 ${updatedHolding.fundCode}', type: LogType.error);
      throw Exception('持仓不存在');
    }

    if (!kIsWeb) {
      await _repository!.updateHolding(updatedHolding.id, updatedHolding);
    }
    
    final newHoldings = List<FundHolding>.from(_holdings);
    newHoldings[index] = updatedHolding;
    _holdings = newHoldings;

    await addLog('更新持仓: ${updatedHolding.fundCode} - ${updatedHolding.clientName}', type: LogType.success);
    await saveData();
    notifyListeners();
  }

  Future<void> updateHoldingNav(String clientId, String fundCode, double currentNav, DateTime navDate) async {
    final index = _holdings.indexWhere((h) => h.clientId == clientId && h.fundCode == fundCode);
    if (index == -1) return;

    final holding = _holdings[index];
    final updatedHolding = holding.copyWith(
      currentNav: currentNav,
      navDate: navDate,
      isValid: currentNav > 0,
    );

    _holdings[index] = updatedHolding;
  }

  Future<void> commitBatchUpdates() async {
    if (!kIsWeb && _repository != null) {
      try {
        await _repository!.batchInsertHoldings(_holdings);
      } catch (e) {
      }
    }
    notifyListeners();
  }

  Future<void> autoConfirmRelatedPendingTransactions(String fundCode, FundService fundService) async {
    try {
      final pendingTransactions = getPendingTransactions()
          .where((tx) => tx.fundCode == fundCode)
          .toList();
      
      if (pendingTransactions.isEmpty) return;
      
      int confirmedCount = 0;
      final now = DateTime.now();
      
      for (final tx in pendingTransactions) {
        try {
          final fundInfo = await fundService.fetchFundInfo(tx.fundCode);
          if (fundInfo['isValid'] == true && fundInfo['currentNav'] > 0) {
            final navDate = await calculateNavDateForTradeAsync(tx.tradeDate, tx.isAfter1500);
            final fundNavDate = fundInfo['navDate'] as DateTime?;
            
            if (fundNavDate != null && !fundNavDate.isBefore(navDate)) {
              await confirmPendingTransaction(tx.id, fundInfo['currentNav']);
              confirmedCount++;
              continue;
            }
          }
          
          final canConfirmDate = await calculateConfirmDateAsync(tx.tradeDate, tx.isAfter1500);
          
          if ((now.isAfter(canConfirmDate) || now.isAtSameMomentAs(canConfirmDate)) &&
              fundInfo['isValid'] == true && fundInfo['currentNav'] > 0) {
            await confirmPendingTransaction(tx.id, fundInfo['currentNav']);
            confirmedCount++;
          }
        } catch (e) {
          await addLog('自动确认单笔交易失败 (${tx.fundCode}): $e', type: LogType.error);
        }
      }
      
      if (confirmedCount > 0) {
        await addLog('自动确认 $confirmedCount 笔待确认交易（基金: $fundCode）', type: LogType.success);
        notifyListeners();
      }
    } catch (e) {
      await addLog('自动确认相关待确认交易失败: $e', type: LogType.error);
    }
  }

  Future<void> deleteHoldingAt(int index) async {
    if (index < 0 || index >= _holdings.length) return;

    final removed = _holdings[index];
    
    final pendingTxs = _transactions.where(
      (tx) => tx.clientId == removed.clientId && tx.fundCode == removed.fundCode && tx.isPending,
    ).toList();
    
    for (final tx in pendingTxs) {
      await _repository?.deleteTransaction(tx.id);
      _transactions.remove(tx);
      await addLog('删除持仓时同步删除待确认交易: ${tx.fundCode} - ${tx.type.displayName}', type: LogType.info);
    }
    
    if (!kIsWeb) {
      await _repository!.deleteHolding(removed.id);
    }
    
    _holdings = List.from(_holdings)..removeAt(index);
    await addLog('删除持仓: ${removed.fundCode} - ${removed.clientName}', type: LogType.info);
    await saveData();
    notifyListeners();
  }

  Future<void> clearAllHoldings() async {
    final count = _holdings.length;
    
    if (!kIsWeb) {
      final db = await DatabaseHelper.instance.database;
      await db.delete('holdings');
      await db.delete('transactions');
    }
    
    _holdings = [];
    _transactions = [];
    _profitCache.clear();
    _transactionHistoryCache.clear();
    
    await addLog('清空所有持仓数据，共删除 $count 条记录', type: LogType.warning);
    notifyListeners();
  }

  Future<void> batchUpdateHoldings(List<FundHolding> newHoldings) async {
    if (!kIsWeb) {
      await _repository!.batchInsertHoldings(newHoldings);
    }
    _holdings = newHoldings;
    notifyListeners();
  }

  Future<void> refreshAllHoldings(FundService fundService, void Function(int, int)? onProgress) async {
    final total = _holdings.length;
    
    const batchSize = 5; 
    for (int batchStart = 0; batchStart < total; batchStart += batchSize) {
      final batchEnd = (batchStart + batchSize < total) ? batchStart + batchSize : total;
      
      for (int i = batchStart; i < batchEnd; i++) {
        final holding = _holdings[i];
        final fetched = await fundService.fetchFundInfo(holding.fundCode, forceRefresh: true);
        if (fetched['isValid'] == true) {
          final index = _holdings.indexWhere((h) => h.id == holding.id);
          if (index != -1) {
            final updated = _holdings[index].copyWith(
              fundName: fetched['fundName'] as String? ?? holding.fundName,
              currentNav: fetched['currentNav'] as double? ?? holding.currentNav,
              navDate: fetched['navDate'] as DateTime? ?? holding.navDate,
              isValid: true,
              navReturn1m: fetched['navReturn1m'],
              navReturn3m: fetched['navReturn3m'],
              navReturn6m: fetched['navReturn6m'],
              navReturn1y: fetched['navReturn1y'],
            );
            _holdings[index] = updated;
          }
          
          await autoConfirmRelatedPendingTransactions(holding.fundCode, fundService);
        } else {
          await addLog('强制刷新基金 ${holding.fundCode} 失败', type: LogType.error);
        }
        onProgress?.call(i + 1, total);
      }
      
      if (batchEnd < total) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    
    await commitBatchUpdates();
  }
  
  @Deprecated('Use refreshAllHoldings instead')
  Future<void> refreshAllHoldingsWithAutoConfirm(FundService fundService, void Function(int, int)? onProgress) async {
    await refreshAllHoldings(fundService, onProgress);
  }
  
  @Deprecated('Use refreshAllHoldings instead')
  Future<void> refreshAllHoldingsForce(FundService fundService, Function(int current, int total)? onProgress) async {
    await refreshAllHoldings(fundService, onProgress);
  }

  Future<void> togglePinStatus(String holdingId) async {
    final index = _holdings.indexWhere((h) => h.id == holdingId);
    if (index != -1) {
      final newHoldings = List<FundHolding>.from(_holdings);
      final holding = newHoldings[index];
      final newIsPinned = !holding.isPinned;
      final newHolding = holding.copyWith(
        isPinned: newIsPinned,
        pinnedTimestamp: newIsPinned ? DateTime.now() : null,
      );
      
      if (!kIsWeb) {
        await _repository!.updateHolding(holdingId, newHolding);
      }
      
      newHoldings[index] = newHolding;

      newHoldings.sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        if (a.isPinned && b.isPinned) {
          final aTime = a.pinnedTimestamp ?? DateTime(1970);
          final bTime = b.pinnedTimestamp ?? DateTime(1970);
          return bTime.compareTo(aTime);
        }
        return 0;
      });

      _holdings = newHoldings;
      await addLog('${newIsPinned ? "置顶" : "取消置顶"}: ${holding.fundCode} - ${holding.clientName}', type: LogType.info);
      await saveData();
      notifyListeners();
    }
  }

  Future<void> addLog(String message, {LogType type = LogType.info}) async {
    final logEntry = LogEntry.create(message: message, type: type);
    
    if (!kIsWeb) {
      await _repository!.insertLog(logEntry);
    }
    
    _logs = [logEntry, ..._logs];

    if (_logs.length > 200) {
      _logs = _logs.take(200).toList();
    }

    notifyListeners();
  }

  Future<void> clearAllLogs() async {
    if (!kIsWeb) {
      final db = await DatabaseHelper.instance.database;
      await db.delete('logs');
    }
    
    _logs = [];
    await addLog('日志已清空', type: LogType.info);
    notifyListeners();
  }

  Future<void> togglePrivacyMode() async {
    _isPrivacyMode = !_isPrivacyMode;
    
    if (!kIsWeb) {
      await _repository!.saveSetting('privacy_mode', _isPrivacyMode.toString());
    }
    
    await addLog('隐私模式: ${_isPrivacyMode ? "开启" : "关闭"}', type: LogType.info);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode != mode) {
      _themeMode = mode;
      
      if (!kIsWeb) {
        await _repository!.saveSetting('theme_mode', _themeModeToString(_themeMode));
      }
      
      await addLog('主题模式: ${mode.displayName}', type: LogType.info);
      notifyListeners();
    }
  }

  Future<void> setShowHoldersOnSummaryCard(bool value) async {
    if (_showHoldersOnSummaryCard != value) {
      _showHoldersOnSummaryCard = value;
      
      if (!kIsWeb) {
        await _repository!.saveSetting('show_holders_on_summary', value.toString());
      }
      
      await addLog('一览卡片持有人显示: ${value ? "开启" : "关闭"}', type: LogType.info);
      notifyListeners();
    }
  }

  String obscuredName(String name) {
    if (!_isPrivacyMode || name.isEmpty) return name;

    final firstChar = name[0];
    if (name.length == 1) return name;

    return '$firstChar${'*' * (name.length - 1)}';
  }

  ProfitResult calculateProfit(FundHolding holding) {
    final cacheKey = '${holding.clientId}_${holding.fundCode}_${holding.totalShares}_${holding.totalCost}_${holding.currentNav}';
    
    if (_profitCache.containsKey(cacheKey)) {
      return _profitCache[cacheKey]!;
    }
    
    if (holding.totalShares <= 0 || holding.currentNav <= 0 || holding.totalCost <= 0) {
      const result = ProfitResult(absolute: 0.0, annualized: 0.0);
      _profitCache[cacheKey] = result;
      return result;
    }

    final currentMarketValue = holding.currentNav * holding.totalShares;
    final absoluteProfit = currentMarketValue - holding.totalCost;

    final relatedTransactions = getTransactionHistory(holding.clientId, holding.fundCode);
    if (relatedTransactions.isEmpty) {
      final result = ProfitResult(absolute: absoluteProfit, annualized: 0.0);
      _profitCache[cacheKey] = result;
      return result;
    }
    
    final firstTradeDate = relatedTransactions.last.tradeDate;
    final days = DateTime.now().difference(firstTradeDate).inDays;

    if (days <= 0) {
      final result = ProfitResult(absolute: absoluteProfit, annualized: 0.0);
      _profitCache[cacheKey] = result;
      return result;
    }

    final annualizedReturn = (absoluteProfit / holding.totalCost) / days * 365 * 100;
    final result = ProfitResult(absolute: absoluteProfit, annualized: annualizedReturn);
    
    if (_profitCache.length >= AppConstants.maxCacheSize) {
      final oldestKey = _profitCache.keys.first;
      _profitCache.remove(oldestKey);
    }
    
    _profitCache[cacheKey] = result;
    return result;
  }

  List<FundHolding> getPinnedSortedHoldings() {
    final sorted = List<FundHolding>.from(_holdings);
    sorted.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      if (a.isPinned && b.isPinned) {
        final aTime = a.pinnedTimestamp ?? DateTime(1970);
        final bTime = b.pinnedTimestamp ?? DateTime(1970);
        return bTime.compareTo(aTime);
      }
      return a.fundCode.compareTo(b.fundCode);
    });
    return sorted;
  }
  
  List<TransactionRecord> getPendingTransactions() {
    return _transactions.where((tx) => tx.isPending).toList();
  }
  
  Future<void> confirmPendingTransaction(String transactionId, double confirmedNav) async {
    try {
      final index = _transactions.indexWhere((tx) => tx.id == transactionId);
      if (index == -1) {
        throw Exception('交易记录不存在');
      }
      
      final transaction = _transactions[index];
      if (!transaction.isPending) {
        throw Exception('该交易已经确认');
      }
      
      double calculatedShares = transaction.shares;
      double calculatedAmount = transaction.amount;
      
      if (transaction.type == TransactionType.buy) {
        if (transaction.shares <= 0 && transaction.amount > 0 && confirmedNav > 0) {
          final feeRate = transaction.fee ?? 0.0; 
          calculatedShares = transaction.amount / (1 + feeRate / 100) / confirmedNav;
        }
      } else {
        if (transaction.amount <= 0 && transaction.shares > 0 && confirmedNav > 0) {
          final feeRate = transaction.fee ?? 0.0; 
          calculatedAmount = transaction.shares * confirmedNav * (1 - feeRate / 100);
        }
      }
      
      final confirmDate = await calculateConfirmDateAsync(transaction.tradeDate, transaction.isAfter1500);
      
      final updatedTransaction = transaction.copyWith(
        isPending: false,
        status: TransactionStatus.confirmed,
        confirmedNav: confirmedNav,
        shares: calculatedShares,
        amount: calculatedAmount,
        confirmDate: confirmDate,
        frozenShares: 0,
      );
      
      _transactions[index] = updatedTransaction;
      
      if (!kIsWeb) {
        await _repository!.updateTransaction(updatedTransaction.id, updatedTransaction);
      }
      
      _clearRelatedCaches(transaction.clientId, transaction.fundCode);
      
      await _rebuildHolding(transaction.clientId, transaction.fundCode);
      
      await saveData();
      
      final confirmDateStr = DateTime.now();
      await addLog(
        '✅ 确认交易: ${transaction.fundName}(${transaction.fundCode})\n'
        '客户: ${transaction.clientName}(${transaction.clientId})\n'
        '类型: ${transaction.type.displayName}\n'
        '交易日期: ${transaction.tradeDate.year}-${transaction.tradeDate.month.toString().padLeft(2, '0')}-${transaction.tradeDate.day.toString().padLeft(2, '0')}\n'
        '金额: ${calculatedAmount.toStringAsFixed(2)}元 | 份额: ${calculatedShares.toStringAsFixed(2)}份\n'
        '确认净值: $confirmedNav\n'
        '确认日期: ${confirmDate.year}-${confirmDate.month.toString().padLeft(2, '0')}-${confirmDate.day.toString().padLeft(2, '0')}\n'
        '确认时间: ${confirmDateStr.year}-${confirmDateStr.month.toString().padLeft(2, '0')}-${confirmDateStr.day.toString().padLeft(2, '0')} ${confirmDateStr.hour.toString().padLeft(2, '0')}:${confirmDateStr.minute.toString().padLeft(2, '0')}',
        type: LogType.success,
      );
      
      notifyListeners();
    } catch (e) {
      await addLog('确认交易异常: $e', type: LogType.error);
      rethrow;
    }
  }
  
  Future<int> autoConfirmPendingTransactions(FundService fundService) async {
    return await autoConfirmPendingTransactionsWithRetry(fundService);
  }
  
  static bool isWeekday(DateTime date) {
    final weekday = date.weekday; 
    return weekday >= DateTime.monday && weekday <= DateTime.friday;
  }
  
  static Future<bool> isTradingDay(DateTime date) async {
    final service = ChinaTradingDayService();
    return await service.isTradingDay(date);
  }
  
  static Future<DateTime> getNextTradingDay({DateTime? from}) async {
    final service = ChinaTradingDayService();
    return await service.getNextTradingDay(from: from);
  }
  
  static Future<DateTime> getPreviousTradingDay({DateTime? from}) async {
    final service = ChinaTradingDayService();
    return await service.getPreviousTradingDay(from: from);
  }
  
  static DateTime getNextWeekday(DateTime from) {
    DateTime next = from.add(const Duration(days: 1));
    while (!isWeekday(next)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }
  
  static DateTime calculateNavDateForTrade(DateTime tradeDate, bool isAfter1500) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tradeDay = DateTime(tradeDate.year, tradeDate.month, tradeDate.day);
    
    final isTradeWeekday = isWeekday(tradeDay);
    
    if (tradeDay.isBefore(today)) {
      if (!isTradeWeekday) {
        return getNextWeekday(tradeDay);
      } else {
        if (isAfter1500) {
          return getNextWeekday(tradeDay);
        } else {
          return tradeDay;
        }
      }
    }
    
    final effectiveIsAfter1500 = isTradeWeekday ? isAfter1500 : false;
    
    if (effectiveIsAfter1500) {
      return getNextWeekday(tradeDay);
    } else {
      return isTradeWeekday ? tradeDay : getNextWeekday(tradeDay);
    }
  }
  
  static Future<DateTime> calculateNavDateForTradeAsync(DateTime tradeDate, bool isAfter1500) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tradeDay = DateTime(tradeDate.year, tradeDate.month, tradeDate.day);
    
    final isTradeTradingDay = await isTradingDay(tradeDay);
    
    if (tradeDay.isBefore(today)) {
      if (!isTradeTradingDay) {
        return await getNextTradingDay(from: tradeDay);
      } else {
        if (isAfter1500) {
          return await getNextTradingDay(from: tradeDay);
        } else {
          return tradeDay;
        }
      }
    }
    
    final effectiveIsAfter1500 = isTradeTradingDay ? isAfter1500 : false;
    
    if (effectiveIsAfter1500) {
      return await getNextTradingDay(from: tradeDay);
    } else {
      return isTradeTradingDay ? tradeDay : await getNextTradingDay(from: tradeDay);
    }
  }
  
  static DateTime calculateConfirmDate(DateTime tradeDate, bool isAfter1500) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    final navDate = calculateNavDateForTrade(tradeDate, isAfter1500);
    final navDay = DateTime(navDate.year, navDate.month, navDate.day);
    
    if (navDay.isBefore(today)) {
      return tradeDate;
    }
    
    final tradeDay = DateTime(tradeDate.year, tradeDate.month, tradeDate.day);
    final isTradeWeekday = isWeekday(tradeDay);
    final effectiveIsAfter1500 = isTradeWeekday ? isAfter1500 : false;
    
    DateTime actualNavDate;
    if (effectiveIsAfter1500) {
      actualNavDate = getNextWeekday(tradeDay); 
    } else {
      actualNavDate = isTradeWeekday ? tradeDay : getNextWeekday(tradeDay); 
    }
    
    final confirmDate = getNextWeekday(actualNavDate);
    
    final service = ChinaTradingDayService();
    return service.getNextTradingDaySync(from: confirmDate);
  }
  
  static Future<DateTime> calculateConfirmDateAsync(DateTime tradeDate, bool isAfter1500) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    final navDate = await calculateNavDateForTradeAsync(tradeDate, isAfter1500);
    final navDay = DateTime(navDate.year, navDate.month, navDate.day);
    
    if (navDay.isBefore(today)) {
      return tradeDate;
    }
    
    final tradeDay = DateTime(tradeDate.year, tradeDate.month, tradeDate.day);
    final isTradeTradingDay = await isTradingDay(tradeDay);
    final effectiveIsAfter1500 = isTradeTradingDay ? isAfter1500 : false;
    
    if (effectiveIsAfter1500) {
      final actualNavDate = await getNextTradingDay(from: tradeDay); 
      return await getNextTradingDay(from: actualNavDate); 
    } else {
      final actualNavDate = isTradeTradingDay ? tradeDay : await getNextTradingDay(from: tradeDay); 
      return await getNextTradingDay(from: actualNavDate); 
    }
  }
  
  static bool isTransactionPending(DateTime tradeDate, bool isAfter1500) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    final navDate = calculateNavDateForTrade(tradeDate, isAfter1500);
    final navDay = DateTime(navDate.year, navDate.month, navDate.day);
    
    return !navDay.isBefore(today);
  }
  
  static Future<bool> isTransactionPendingAsync(DateTime tradeDate, bool isAfter1500) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    final navDate = await calculateNavDateForTradeAsync(tradeDate, isAfter1500);
    final navDay = DateTime(navDate.year, navDate.month, navDate.day);
    
    return !navDay.isBefore(today);
  }
  
  static Future<DateTime> getTradeApplicationDate(DateTime submitTime) async {
    final submitDay = DateTime(submitTime.year, submitTime.month, submitTime.day);
    final hour = submitTime.hour;
    final minute = submitTime.minute;
    
    final isTradingDay = await DataManager.isTradingDay(submitDay);
    
    if (isTradingDay) {
      if (hour < 15 || (hour == 15 && minute == 0)) {
        return submitDay;
      } else {
        return await DataManager.getNextTradingDay(from: submitDay);
      }
    } else {
      return await DataManager.getNextTradingDay(from: submitDay);
    }
  }
  
  Future<bool> confirmPendingTransactionWithRetry(
    String transactionId,
    FundService fundService,
  ) async {
    try {
      final index = _transactions.indexWhere((tx) => tx.id == transactionId);
      if (index == -1) {
        throw Exception('交易记录不存在');
      }
      
      final transaction = _transactions[index];
      if (!transaction.isPending) {
        throw Exception('该交易已经确认');
      }
      
      if (transaction.retryCount >= 5) {
        final failedTransaction = transaction.copyWith(
          status: TransactionStatus.confirmFailed,
        );
        _transactions[index] = failedTransaction;
        
        if (!kIsWeb) {
          await _repository!.updateTransaction(failedTransaction.id, failedTransaction);
        }
        
        await saveData();
        
        await addLog(
          '❌ 交易确认失败（已重试5次）: ${transaction.fundName}(${transaction.fundCode})\n'
          '客户: ${transaction.clientName}\n'
          '请手动更新确认净值和份额',
          type: LogType.error,
        );
        
        notifyListeners();
        return false;
      }
      
      final fundInfo = await fundService.fetchFundInfo(transaction.fundCode);
      
      if (fundInfo['isValid'] == true && fundInfo['currentNav'] > 0) {
        await confirmPendingTransaction(transactionId, fundInfo['currentNav']);
        
        final confirmedIndex = _transactions.indexWhere((tx) => tx.id == transactionId);
        if (confirmedIndex != -1) {
          final confirmedTx = _transactions[confirmedIndex].copyWith(
            status: TransactionStatus.confirmed,
            retryCount: transaction.retryCount + 1,
          );
          _transactions[confirmedIndex] = confirmedTx;
          
          if (!kIsWeb) {
            await _repository!.updateTransaction(confirmedTx.id, confirmedTx);
          }
          
          await saveData();
        }
        
        return true;
      } else {
        final retryTransaction = transaction.copyWith(
          retryCount: transaction.retryCount + 1,
        );
        _transactions[index] = retryTransaction;
        
        if (!kIsWeb) {
          await _repository!.updateTransaction(retryTransaction.id, retryTransaction);
        }
        
        await saveData();
        
        await addLog(
          '⚠️ 净值获取失败（第${retryTransaction.retryCount}次重试）: ${transaction.fundName}\n'
          '将在下一个交易日再次尝试',
          type: LogType.warning,
        );
        
        notifyListeners();
        return false;
      }
    } catch (e) {
      await addLog('净值获取重试异常: $e', type: LogType.error);
      return false;
    }
  }
  
  Future<int> autoConfirmPendingTransactionsWithRetry(FundService fundService) async {
    if (_isAutoConfirming) {
      return 0;
    }
    
    _isAutoConfirming = true;
    try {
      final pendingTransactions = getPendingTransactions();
      if (pendingTransactions.isEmpty) return 0;
      
      int confirmedCount = 0;
      int failedCount = 0;
      final now = DateTime.now();
      
      for (final tx in pendingTransactions) {
        try {
          final fundInfo = await fundService.fetchFundInfo(tx.fundCode);
          if (fundInfo['isValid'] == true && fundInfo['currentNav'] > 0) {
            final navDate = await calculateNavDateForTradeAsync(tx.tradeDate, tx.isAfter1500);
            final fundNavDate = fundInfo['navDate'] as DateTime?;
            
            if (fundNavDate != null && !fundNavDate.isBefore(navDate)) {
              final success = await confirmPendingTransactionWithRetry(tx.id, fundService);
              if (success) {
                confirmedCount++;
                continue;
              }
            }
          }
          
          final applicationDate = await getTradeApplicationDate(tx.tradeDate);
          final appDay = DateTime(applicationDate.year, applicationDate.month, applicationDate.day);
          
          if (now.isBefore(appDay)) {
            continue;
          }
          
          final canConfirmDate = await calculateConfirmDateAsync(tx.tradeDate, tx.isAfter1500);
          
          if (now.isAfter(canConfirmDate) || now.isAtSameMomentAs(canConfirmDate)) {
            final success = await confirmPendingTransactionWithRetry(tx.id, fundService);
            if (success) {
              confirmedCount++;
            } else {
              final txIndex = _transactions.indexWhere((t) => t.id == tx.id);
              if (txIndex != -1) {
                final updatedTx = _transactions[txIndex];
                if (updatedTx.status == TransactionStatus.confirmFailed) {
                  failedCount++;
                }
              }
            }
          }
        } catch (e) {
          await addLog('自动确认交易失败 (${tx.fundCode}): $e', type: LogType.error);
        }
      }
      
      if (confirmedCount > 0) {
        await addLog('✅ 自动确认 $confirmedCount 笔待确认交易', type: LogType.success);
      }
      if (failedCount > 0) {
        await addLog('❌ $failedCount 笔交易确认失败（需人工处理）', type: LogType.error);
      }
      
      return confirmedCount;
    } finally {
      _isAutoConfirming = false;
    }
  }
  
  Future<void> freezeSharesForRedemption(String clientId, String fundCode, double sharesToFreeze) async {
    try {
      final holdingIndex = _holdings.indexWhere(
        (h) => h.clientId == clientId && h.fundCode == fundCode,
      );
      
      if (holdingIndex == -1) {
        throw Exception('持仓不存在');
      }
      
      final holding = _holdings[holdingIndex];
      
      final availableShares = holding.totalShares - _getFrozenShares(clientId, fundCode);
      if (sharesToFreeze > availableShares) {
        throw Exception('可用份额不足（可用: ${availableShares.toStringAsFixed(2)}份）');
      }
      
      await addLog(
        '🔒 冻结份额: ${holding.fundName}\n'
        '客户: ${holding.clientName}\n'
        '冻结份额: ${sharesToFreeze.toStringAsFixed(2)}份',
        type: LogType.info,
      );
      
      notifyListeners();
    } catch (e) {
      await addLog('冻结份额失败: $e', type: LogType.error);
      rethrow;
    }
  }
  
  double _getFrozenShares(String clientId, String fundCode) {
    double frozenShares = 0;
    for (final tx in _transactions) {
      if (tx.clientId == clientId && 
          tx.fundCode == fundCode && 
          tx.type == TransactionType.sell && 
          tx.isPending &&
          tx.frozenShares != null) {
        frozenShares += tx.frozenShares!;
      }
    }
    return frozenShares;
  }
  
  Future<void> releaseFrozenShares(String transactionId) async {
    try {
      final index = _transactions.indexWhere((tx) => tx.id == transactionId);
      if (index == -1) return;
      
      final transaction = _transactions[index];
      if (transaction.frozenShares == null || transaction.frozenShares! <= 0) return;
      
      final releasedTx = transaction.copyWith(frozenShares: 0);
      _transactions[index] = releasedTx;
      
      if (!kIsWeb) {
        await _repository!.updateTransaction(releasedTx.id, releasedTx);
      }
      
      await saveData();
      
      await addLog(
        '🔓 释放冻结份额: ${transaction.fundName}\n'
        '释放份额: ${transaction.frozenShares!.toStringAsFixed(2)}份',
        type: LogType.info,
      );
      
      notifyListeners();
    } catch (e) {
      await addLog('释放冻结份额失败: $e', type: LogType.error);
    }
  }
  
  int calculateHoldingDays(String clientId, String fundCode) {
    final transactions = getTransactionHistory(clientId, fundCode);
    if (transactions.isEmpty) return 0;
    
    final firstConfirmedBuy = transactions.where(
      (tx) => tx.type == TransactionType.buy && !tx.isPending
    ).firstOrNull;
    
    if (firstConfirmedBuy == null) return 0;
    
    final startDate = firstConfirmedBuy.confirmDate ?? 
                      firstConfirmedBuy.tradeDate.add(const Duration(days: 1));
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(startDate.year, startDate.month, startDate.day);
    
    return today.difference(startDay).inDays;
  }
  
  Future<void> manuallyConfirmTransaction(
    String transactionId,
    double confirmedNav,
    double? confirmedShares,
    double? confirmedAmount,
  ) async {
    try {
      final index = _transactions.indexWhere((tx) => tx.id == transactionId);
      if (index == -1) {
        throw Exception('交易记录不存在');
      }
      
      final transaction = _transactions[index];
      
      double calculatedShares = confirmedShares ?? transaction.shares;
      double calculatedAmount = confirmedAmount ?? transaction.amount;
      
      if (transaction.type == TransactionType.buy && confirmedShares == null) {
        if (transaction.amount > 0 && confirmedNav > 0) {
          final feeRate = transaction.fee ?? 0.0;
          calculatedShares = transaction.amount / (1 + feeRate / 100) / confirmedNav;
        }
      }
      
      if (transaction.type == TransactionType.sell && confirmedAmount == null) {
        if (transaction.shares > 0 && confirmedNav > 0) {
          final feeRate = transaction.fee ?? 0.0;
          calculatedAmount = transaction.shares * confirmedNav * (1 - feeRate / 100);
        }
      }
      
      final updatedTransaction = transaction.copyWith(
        isPending: false,
        status: TransactionStatus.confirmed,
        confirmedNav: confirmedNav,
        shares: calculatedShares,
        amount: calculatedAmount,
        confirmDate: DateTime.now(),
        frozenShares: 0,
      );
      
      _transactions[index] = updatedTransaction;
      
      if (!kIsWeb) {
        await _repository!.updateTransaction(updatedTransaction.id, updatedTransaction);
      }
      
      _clearRelatedCaches(transaction.clientId, transaction.fundCode);
      
      await _rebuildHolding(transaction.clientId, transaction.fundCode);
      
      await saveData();
      
      await addLog(
        '✍️ 手动确认交易: ${transaction.fundName}(${transaction.fundCode})\n'
        '客户: ${transaction.clientName}\n'
        '类型: ${transaction.type.displayName}\n'
        '确认净值: $confirmedNav\n'
        '确认份额: ${calculatedShares.toStringAsFixed(2)}份\n'
        '确认金额: ${calculatedAmount.toStringAsFixed(2)}元',
        type: LogType.success,
      );
      
      notifyListeners();
    } catch (e) {
      await addLog('手动确认交易失败: $e', type: LogType.error);
      rethrow;
    }
  }
}

class DataManagerProvider extends InheritedWidget {
  final DataManager dataManager;

  const DataManagerProvider({
    super.key,
    required this.dataManager,
    required super.child,
  });

  static DataManager of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<DataManagerProvider>();
    assert(provider != null, 'No DataManagerProvider found in context');
    return provider!.dataManager;
  }
  
  static DataManager? maybeOf(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<DataManagerProvider>();
    return provider?.dataManager;
  }

  @override
  bool updateShouldNotify(DataManagerProvider oldWidget) {
    return dataManager != oldWidget.dataManager;
  }
}

class _AppLifecycleObserver with WidgetsBindingObserver {
  final DataManager _dataManager;
  
  _AppLifecycleObserver(this._dataManager);
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _dataManager.saveOnBackground();
        break;
      case AppLifecycleState.resumed:
        break;
      case AppLifecycleState.detached:
        _dataManager.saveOnBackground();
        break;
      default:
        break;
    }
  }
}
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
import '../services/client_mapping_service.dart';
import '../services/database_helper.dart';
import '../services/database_repository.dart';
import '../services/fund_service.dart';
import '../services/log_notifier.dart';
import '../services/settings_notifier.dart';
import '../services/transaction_utils.dart';
import '../services/valuation_notifier.dart';
import '../services/version_check_service.dart';
import '../utils/smart_cache.dart';
import '../constants/app_constants.dart' show ThemeMode, ThemeModeExtension;

class DataManager extends ChangeNotifier {
  final DatabaseRepository? _repository = kIsWeb ? null : DatabaseRepository();

  // ─── Sub-notifiers ───
  late final LogNotifier logNotifier;
  late final SettingsNotifier settingsNotifier;
  late final ValuationNotifier valuationNotifier;

  // ─── Core data (holdings & transactions) ───
  List<FundHolding> _holdings = [];
  List<TransactionRecord> _transactions = [];
  Map<String, FundInfoCache> _fundInfoCache = {};
  int _holdingsVersion = 0;

  // ─── Caches ───
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

  bool _disposed = false;
  bool _isAutoConfirming = false;

  int get holdingsVersion => _holdingsVersion;

  void _incrementHoldingsVersion() {
    _holdingsVersion++;
  }
  
  void _clearRelatedCaches(String clientId, String fundCode) {
    final cacheKey = '${clientId}_$fundCode';
    _transactionHistoryCache.remove(cacheKey);

    _profitCache.removeWhere((key, value) => key.startsWith('${clientId}_$fundCode'));
  }

  Future<void> _syncHolding(String clientId, String fundCode) async {
    _clearRelatedCaches(clientId, fundCode);
    await _rebuildHolding(clientId, fundCode);
    _incrementHoldingsVersion();
  }

  List<FundHolding> get holdings => List.unmodifiable(_holdings);
  List<TransactionRecord> get transactions => List.unmodifiable(_transactions);
  List<LogEntry> get logs => logNotifier.logs;
  bool get isPrivacyMode => settingsNotifier.isPrivacyMode;
  ThemeMode get themeMode => settingsNotifier.themeMode;
  bool get isValuationRefreshing => valuationNotifier.isValuationRefreshing;
  double get valuationRefreshProgress => valuationNotifier.valuationRefreshProgress;
  String get lastValuationUpdateTime => valuationNotifier.lastValuationUpdateTime;
  bool get isValuationRefreshInProgress => valuationNotifier.isValuationRefreshInProgress;
  bool get showHoldersOnSummaryCard => settingsNotifier.showHoldersOnSummaryCard;
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

  void _onSubNotifierChanged() {
    notifyListeners();
  }

  DataManager() {
    // Create sub-notifiers
    logNotifier = LogNotifier(_repository);
    settingsNotifier = SettingsNotifier(_repository);
    valuationNotifier = ValuationNotifier(
      _repository,
      logNotifier,
      () => _holdings
          .map((h) => {
                'fundCode': h.fundCode,
                'fundName': h.fundName,
                'clientId': h.clientId,
              })
          .toList(),
    );

    // Forward sub-notifier notifications
    logNotifier.addListener(_onSubNotifierChanged);
    settingsNotifier.addListener(_onSubNotifierChanged);
    valuationNotifier.addListener(_onSubNotifierChanged);

    loadData();
    _startCacheCleanup();
    _setupLifecycleObserver();
  }
  
  _AppLifecycleObserver? _lifecycleObserver;

  void _setupLifecycleObserver() {
    if (_disposed) return;

    _lifecycleObserver = _AppLifecycleObserver(this);
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
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
      debugPrint('[DataManager] 过期缓存清理失败: $e');
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
      debugPrint('[DataManager] 内存检查清理失败: $e');
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
    
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      _lifecycleObserver = null;
    }
    
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = null;
    
    _profitCache.clear();
    _transactionHistoryCache.clear();

    logNotifier.removeListener(_onSubNotifierChanged);
    settingsNotifier.removeListener(_onSubNotifierChanged);
    valuationNotifier.removeListener(_onSubNotifierChanged);
    logNotifier.dispose();
    settingsNotifier.dispose();
    valuationNotifier.dispose();

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
      debugPrint('[DataManager] 后台保存数据失败: $e');
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

      await valuationNotifier.loadValuationCache();

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

    // Logs loaded directly into LogNotifier
    final logs = await _repository!.getLogs(limit: AppConstants.maxLogEntries);
    logNotifier.loadLogsFromJson(logs);

    final privacyModeStr = await _repository!.getSetting('privacy_mode');
    final themeModeStr = await _repository!.getSetting('theme_mode');
    final showHoldersStr = await _repository!.getSetting('show_holders_on_summary');

    settingsNotifier.loadFromValues(
      isPrivacyMode: privacyModeStr != null ? privacyModeStr == 'true' : true,
      themeMode: _parseThemeMode(themeModeStr ?? 'system'),
      showHoldersOnSummaryCard: showHoldersStr != null ? showHoldersStr == 'true' : true,
    );
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
      logNotifier.loadLogsFromJson(
        logsJson.map((json) => LogEntry.fromJson(jsonDecode(json))).toList(),
      );
    }

    settingsNotifier.loadFromValues(
      isPrivacyMode: prefs.getBool(AppConstants.keyPrivacyMode) ?? true,
      themeMode: _parseThemeMode(
          prefs.getString(AppConstants.keyThemeMode) ?? 'system'),
      showHoldersOnSummaryCard:
          prefs.getBool(AppConstants.keyShowHoldersOnSummaryCard) ?? true,
    );
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
      debugPrint('[DataManager] 保存数据失败: $e');
    }
  }
  
  Future<void> _saveSettingsToPrefs() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
          AppConstants.keyPrivacyMode, settingsNotifier.isPrivacyMode);
      await prefs.setString(AppConstants.keyThemeMode,
          _themeModeToString(settingsNotifier.themeMode));
      await prefs.setBool(AppConstants.keyShowHoldersOnSummaryCard,
          settingsNotifier.showHoldersOnSummaryCard);
    } else {
      await _repository!.saveSetting(
          'privacy_mode', settingsNotifier.isPrivacyMode.toString());
      await _repository!.saveSetting(
          'theme_mode', _themeModeToString(settingsNotifier.themeMode));
      await _repository!.saveSetting('show_holders_on_summary',
          settingsNotifier.showHoldersOnSummaryCard.toString());
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

    final logsJson = logNotifier
        .serializeLogs()
        .take(AppConstants.maxLogEntries)
        .map((log) => jsonEncode(log.toJson()))
        .toList();
    await prefs.setStringList(AppConstants.keyLogs, logsJson);

    await prefs.setBool(AppConstants.keyPrivacyMode, settingsNotifier.isPrivacyMode);
    await prefs.setString(AppConstants.keyThemeMode,
        _themeModeToString(settingsNotifier.themeMode));
    await prefs.setBool(AppConstants.keyShowHoldersOnSummaryCard,
        settingsNotifier.showHoldersOnSummaryCard);
  }

  Future<void> loadValuationCache() async =>
      valuationNotifier.loadValuationCache();

  Future<void> saveValuationCache() async =>
      valuationNotifier.saveValuationCache();

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
        debugPrint('[DataManager] 基金信息缓存验证读取失败');
      }
    } catch (e) {
      debugPrint('[DataManager] 保存基金信息缓存失败: $e');
    }
  }

  Map<String, dynamic>? getValuation(String fundCode) =>
      valuationNotifier.getValuation(fundCode);

  Future<void> updateValuationCache(
          String fundCode, Map<String, dynamic> valuation) async =>
      valuationNotifier.updateValuationCache(fundCode, valuation);

  void startValuationRefresh() => valuationNotifier.startValuationRefresh();

  void updateValuationRefreshProgress(double progress) =>
      valuationNotifier.updateValuationRefreshProgress(progress);

  void finishValuationRefresh({String? updateTime}) =>
      valuationNotifier.finishValuationRefresh(updateTime: updateTime);

  void setValuationUpdateTime(String time) =>
      valuationNotifier.setValuationUpdateTime(time);

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

  Future<void> refreshAllValuations(FundService fundService,
          {bool silent = false}) async =>
      valuationNotifier.refreshAllValuations(fundService, silent: silent);

  Future<void> addHolding(FundHolding holding) async {
    if (!holding.isValidHolding) {
      await addLog('添加持仓失败: 数据无效', type: LogType.error);
      throw Exception('无效的持仓数据');
    }

    if (!kIsWeb) {
      await _repository!.insertHolding(holding);
    }
    _holdings = [..._holdings, holding];
    _incrementHoldingsVersion();

    await addLog('新增持仓: ${holding.fundCode} - ${holding.clientName}', type: LogType.success);
    await saveData();
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
    _incrementHoldingsVersion();
    
    await addLog('批量添加 ${holdings.length} 个持仓', type: LogType.success);
    await saveData();
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
  }

  Future<void> addTransaction(TransactionRecord transaction) async {
    // Pending transactions may have amount=0 (NAV not yet known).
    if (!transaction.isPending && transaction.amount <= 0) {
      await addLog('添加交易失败: 金额必须大于0', type: LogType.error);
      throw Exception('金额必须大于0');
    }

    if (!transaction.isPending && transaction.shares <= 0) {
      await addLog('添加交易失败: 已确认交易必须有份额', type: LogType.error);
      throw Exception('已确认交易必须输入份额');
    }

    // Pending sell requires shares > 0 at minimum.
    if (transaction.isPending && transaction.type == TransactionType.sell && transaction.shares <= 0) {
      await addLog('添加交易失败: 待确认卖出必须输入份额', type: LogType.error);
      throw Exception('待确认卖出必须输入份额');
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
    
    await _syncHolding(enhancedTransaction.clientId, enhancedTransaction.fundCode);

    await addLog(
      '${enhancedTransaction.type.displayName}交易: ${enhancedTransaction.fundCode} - ${enhancedTransaction.clientName}, '
      '金额: ${enhancedTransaction.amount.toStringAsFixed(2)}元, '
      '份额: ${enhancedTransaction.shares.toStringAsFixed(2)}份'
      '${enhancedTransaction.isPending ? '\n申请日期: ${applicationDate.year}-${applicationDate.month.toString().padLeft(2, '0')}-${applicationDate.day.toString().padLeft(2, '0')}\n状态: 待确认' : ''}',
      type: LogType.success,
    );
    await saveData();
  }

  /// Batch import transactions without per-row saveData/log calls.
  /// Used by the import flow for performance.
  Future<int> addTransactionsBatch(
    List<TransactionRecord> transactions, {
    void Function(double progress)? onProgress,
  }) async {
    if (transactions.isEmpty) return 0;

    int successCount = 0;
    final affectedPairs = <String>{};
    final enhancedList = <TransactionRecord>[];

    // Phase A: validate and prepare (fast, in-memory)
    for (final transaction in transactions) {
      if (transaction.amount <= 0) continue;
      if (!transaction.isPending && transaction.shares <= 0) continue;

      final applicationDate = await getTradeApplicationDate(transaction.tradeDate);
      final enhancedTransaction = transaction.copyWith(
        status: TransactionStatus.confirmed,
        applicationDate: applicationDate,
        frozenShares: null,
      );

      enhancedList.add(enhancedTransaction);
      affectedPairs.add('${enhancedTransaction.clientId}_${enhancedTransaction.fundCode}');
      successCount++;
    }

    onProgress?.call(0.25);

    // Phase B: batch insert into DB (single DB transaction)
    if (!kIsWeb && enhancedList.isNotEmpty) {
      await _repository!.batchInsertTransactions(enhancedList);
    }

    // Single list append instead of O(n²) per-row copies
    _transactions = [..._transactions, ...enhancedList];

    for (final tx in enhancedList) {
      _clearRelatedCaches(tx.clientId, tx.fundCode);
    }

    onProgress?.call(0.50);

    // Phase C: rebuild each affected holding once
    final pairs = affectedPairs.toList();
    for (int i = 0; i < pairs.length; i++) {
      final parts = pairs[i].split('_');
      await _rebuildHolding(parts[0], parts[1]);
      if (pairs.length > 3 && i % ((pairs.length / 4).ceil()) == 0) {
        onProgress?.call(0.50 + 0.40 * (i / pairs.length));
      }
    }

    onProgress?.call(0.90);

    // Phase D: save once and notify once
    await saveData();

    onProgress?.call(1.0);
    return successCount;
  }

  Future<void> _rebuildHolding(String clientId, String fundCode) async {
    final relatedTransactions = _transactions
        .where((tx) => tx.clientId == clientId && tx.fundCode == fundCode)
        .toList()
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));

    if (relatedTransactions.isEmpty) {
      final existingIndex = _holdings.indexWhere(
        (h) => h.clientId == clientId && h.fundCode == fundCode,
      );
      if (existingIndex != -1) {
        final holdingToRemove = _holdings[existingIndex];
        _holdings.removeAt(existingIndex);
        if (!kIsWeb && holdingToRemove.id.isNotEmpty) {
          await _repository!.deleteHolding(holdingToRemove.id);
        }
      }
      // If no holding exists either, nothing to clean up
      return;
    }

    final firstTx = relatedTransactions.first;

    final existingIndex = _holdings.indexWhere(
      (h) => h.clientId == clientId && h.fundCode == fundCode,
    );
    final FundHolding? existingHolding =
        existingIndex != -1 ? _holdings[existingIndex] : null;

    // If existing holding lacks valid NAV, try to derive from confirmed transactions
    double effectiveNav = existingHolding?.currentNav ?? 0.0;
    DateTime effectiveNavDate =
        existingHolding?.navDate ?? DateTime(2000);
    bool effectiveIsValid = existingHolding?.isValid ?? false;

    if (!effectiveIsValid || effectiveNav <= 0) {
      for (final tx in relatedTransactions.reversed) {
        if (!tx.isPending && tx.confirmedNav != null && tx.confirmedNav! > 0) {
          effectiveNav = tx.confirmedNav!;
          effectiveNavDate = tx.confirmDate ?? tx.tradeDate;
          effectiveIsValid = true;
          break;
        }
      }
    }

    final newHolding = FundHolding.fromTransactions(
      clientId: clientId,
      clientName: firstTx.clientName,
      fundCode: fundCode,
      fundName: firstTx.fundName,
      transactions: relatedTransactions,
      navDate: effectiveNavDate,
      currentNav: effectiveNav,
      isValid: effectiveIsValid,
      isPinned: existingHolding?.isPinned ?? false,
      pinnedTimestamp: existingHolding?.pinnedTimestamp,
      navReturn1m: existingHolding?.navReturn1m,
      navReturn3m: existingHolding?.navReturn3m,
      navReturn6m: existingHolding?.navReturn6m,
      navReturn1y: existingHolding?.navReturn1y,
    );

    final rebuildIndex = _holdings.indexWhere(
      (h) => h.clientId == clientId && h.fundCode == fundCode,
    );

    if (rebuildIndex != -1) {
      _holdings[rebuildIndex] = newHolding;
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
      ..sort((a, b) {
        final dateCmp = b.tradeDate.compareTo(a.tradeDate);
        if (dateCmp != 0) return dateCmp;
        return b.createdAt.compareTo(a.createdAt);
      });
    
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
    
    await _syncHolding(transaction.clientId, transaction.fundCode);

    await addLog('删除交易记录: ${transaction.fundCode} - ${transaction.type.displayName}', type: LogType.info);
    await saveData();
  }

  Future<void> cancelPendingTransaction(String transactionId) async {
    final index = _transactions.indexWhere((tx) => tx.id == transactionId);
    if (index == -1) {
      await addLog('取消交易失败: 未找到交易记录', type: LogType.error);
      throw Exception('交易记录不存在');
    }

    final transaction = _transactions[index];
    if (!transaction.isPending) {
      await addLog('取消交易失败: 该交易已确认', type: LogType.error);
      throw Exception('已确认的交易无法取消');
    }

    if (transaction.type == TransactionType.sell &&
        transaction.frozenShares != null &&
        transaction.frozenShares! > 0) {
      await releaseFrozenShares(transactionId);
    }

    final cancelled = transaction.copyWith(
      isPending: false,
      status: TransactionStatus.cancelled,
      frozenShares: 0,
    );
    _transactions[index] = cancelled;

    if (!kIsWeb) {
      await _repository!.updateTransaction(cancelled.id, cancelled);
    }

    await _syncHolding(transaction.clientId, transaction.fundCode);

    await addLog('取消待确认交易: ${transaction.fundName}(${transaction.fundCode}) - ${transaction.type.displayName}', type: LogType.info);
    await saveData();
  }

  Future<void> updateTransaction(TransactionRecord updated) async {
    final index = _transactions.indexWhere((tx) => tx.id == updated.id);
    if (index == -1) {
      await addLog('更新交易失败: 未找到交易记录', type: LogType.error);
      throw Exception('交易记录不存在');
    }

    final old = _transactions[index];

    if (!kIsWeb) {
      await _repository!.updateTransaction(updated.id, updated);
    }
    _transactions[index] = updated;

    _clearRelatedCaches(old.clientId, old.fundCode);
    if (updated.clientId != old.clientId || updated.fundCode != old.fundCode) {
      _clearRelatedCaches(updated.clientId, updated.fundCode);
      await _rebuildHolding(old.clientId, old.fundCode);
    }
    await _rebuildHolding(updated.clientId, updated.fundCode);

    await addLog('更新交易记录: ${updated.fundCode} - ${updated.type.displayName}', type: LogType.info);
    await saveData();
  }

  /// Sync client names from mapping index to all holdings and transactions.
  /// Call after mappings are imported, added, updated, or deleted.
  Future<int> syncClientNamesFromMappings() async {
    final mappingService = ClientMappingService();
    final mappings = await mappingService.getAllMappings();
    final mappingMap = <String, String>{};
    for (final m in mappings) {
      mappingMap[m.clientId] = m.clientName;
    }

    int changedCount = 0;

    // Update holdings
    for (int i = 0; i < _holdings.length; i++) {
      final holding = _holdings[i];
      final mappedName = mappingMap[holding.clientId];
      if (mappedName != null && mappedName.isNotEmpty && mappedName != holding.clientName) {
        _holdings[i] = holding.copyWith(clientName: mappedName);
        if (!kIsWeb) {
          await _repository!.updateHolding(holding.id, _holdings[i]);
        }
        changedCount++;
      }
    }

    // Update transactions
    for (int i = 0; i < _transactions.length; i++) {
      final tx = _transactions[i];
      final mappedName = mappingMap[tx.clientId];
      if (mappedName != null && mappedName.isNotEmpty && mappedName != tx.clientName) {
        _transactions[i] = tx.copyWith(clientName: mappedName);
        if (!kIsWeb) {
          await _repository!.updateTransaction(tx.id, _transactions[i]);
        }
        changedCount++;
      }
    }

    if (changedCount > 0) {
      await saveData();
    }

    return changedCount;
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
    _incrementHoldingsVersion();

    await addLog('更新持仓: ${updatedHolding.fundCode} - ${updatedHolding.clientName}', type: LogType.success);
    await saveData();
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
        debugPrint('[DataManager] 批量更新持仓失败: $e');
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
          final fundNavDate = fundInfo['navDate'] as DateTime?;
          final navDate = await calculateNavDateForTradeAsync(tx.tradeDate, tx.isAfter1500);
          if (fundInfo['isValid'] == true && fundInfo['currentNav'] > 0) {
            if (fundNavDate != null && !fundNavDate.isBefore(navDate)) {
              await confirmPendingTransaction(tx.id, fundInfo['currentNav']);
              confirmedCount++;
              continue;
            }
          }

          final canConfirmDate = await calculateConfirmDateAsync(tx.tradeDate, tx.isAfter1500);

          if ((now.isAfter(canConfirmDate) || now.isAtSameMomentAs(canConfirmDate)) &&
              fundInfo['isValid'] == true && fundInfo['currentNav'] > 0 &&
              fundNavDate != null && !fundNavDate.isBefore(navDate)) {
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
    
    // Delete ALL related transactions (confirmed + pending), not just pending.
    // Otherwise confirmed transactions survive and resurrect the holding on re-add.
    final relatedTxs = _transactions.where(
      (tx) => tx.clientId == removed.clientId && tx.fundCode == removed.fundCode,
    ).toList();

    for (final tx in relatedTxs) {
      if (tx.isPending &&
          tx.type == TransactionType.sell &&
          tx.frozenShares != null &&
          tx.frozenShares! > 0) {
        await releaseFrozenShares(tx.id);
      }

      if (!kIsWeb) {
        await _repository?.deleteTransaction(tx.id);
      }
      _transactions.remove(tx);
      await addLog('删除持仓时同步删除交易: ${tx.fundCode} - ${tx.type.displayName}', type: LogType.info);
    }
    
    if (!kIsWeb) {
      await _repository!.deleteHolding(removed.id);
    }
    
    _holdings = List.from(_holdings)..removeAt(index);
    _incrementHoldingsVersion();
    await addLog('删除持仓: ${removed.fundCode} - ${removed.clientName}', type: LogType.info);
    await saveData();
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
    _incrementHoldingsVersion();

    await saveData();
    await addLog('清空所有持仓数据，共删除 $count 条记录', type: LogType.warning);
    notifyListeners();
  }

  Future<void> batchUpdateHoldings(List<FundHolding> newHoldings) async {
    if (!kIsWeb) {
      await _repository!.batchInsertHoldings(newHoldings);
    }
    _holdings = newHoldings;
    _incrementHoldingsVersion();
    notifyListeners();
  }

  Future<void> refreshAllHoldings(FundService fundService, void Function(int, int)? onProgress, {bool forceRefresh = false}) async {
    final total = _holdings.length;

    // For short-press refresh (forceRefresh=false), allow a generous NAV
    // date tolerance so weekly-updating funds are not re-fetched every time.
    // Long-press (forceRefresh=true) bypasses the cache entirely.
    const navToleranceTradingDays = 3;

    const batchSize = 5;
    for (int batchStart = 0; batchStart < total; batchStart += batchSize) {
      final batchEnd = (batchStart + batchSize < total) ? batchStart + batchSize : total;

      for (int i = batchStart; i < batchEnd; i++) {
        final holding = _holdings[i];
        final fetched = await fundService.fetchFundInfo(
          holding.fundCode,
          forceRefresh: forceRefresh,
          navToleranceTradingDays: forceRefresh ? 0 : navToleranceTradingDays,
        );
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
            _profitCache.remove('${updated.clientId}_${updated.fundCode}');
          }

          await autoConfirmRelatedPendingTransactions(holding.fundCode, fundService);
        } else {
          await addLog('刷新基金 ${holding.fundCode} 失败', type: LogType.error);
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
  
  Future<void> refreshAllHoldingsForce(FundService fundService, Function(int current, int total)? onProgress) async {
    await refreshAllHoldings(fundService, onProgress, forceRefresh: true);
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
      _incrementHoldingsVersion();
      await addLog('${newIsPinned ? "置顶" : "取消置顶"}: ${holding.fundCode} - ${holding.clientName}', type: LogType.info);
      await saveData();
    }
  }

  Future<void> addLog(String message, {LogType type = LogType.info}) async {
    await logNotifier.addLog(message, type: type);
  }

  Future<void> clearAllLogs() async {
    await logNotifier.clearAllLogs();
    await logNotifier.addLog('日志已清空', type: LogType.info);
  }

  Future<void> togglePrivacyMode() async {
    await settingsNotifier.togglePrivacyMode();
    await logNotifier.addLog(
        '隐私模式: ${settingsNotifier.isPrivacyMode ? "开启" : "关闭"}',
        type: LogType.info);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await settingsNotifier.setThemeMode(mode);
    await logNotifier.addLog('主题模式: ${mode.displayName}', type: LogType.info);
  }

  Future<void> setShowHoldersOnSummaryCard(bool value) async {
    await settingsNotifier.setShowHoldersOnSummaryCard(value);
    await logNotifier.addLog(
        '一览卡片持有人显示: ${value ? "开启" : "关闭"}',
        type: LogType.info);
  }

  String obscuredName(String name) {
    return settingsNotifier.obscuredName(name);
  }

  ProfitResult calculateProfit(FundHolding holding) {
    final cacheKey = '${holding.clientId}_${holding.fundCode}';
    
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
      
      await _syncHolding(transaction.clientId, transaction.fundCode);
      
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
  
  // ─── Static utility methods (delegated to TransactionUtils) ───

  static bool isWeekday(DateTime date) => TransactionUtils.isWeekday(date);

  static Future<bool> isTradingDay(DateTime date) =>
      TransactionUtils.isTradingDay(date);

  static Future<DateTime> getNextTradingDay({DateTime? from}) =>
      TransactionUtils.getNextTradingDay(from: from);

  static Future<DateTime> getPreviousTradingDay({DateTime? from}) =>
      TransactionUtils.getPreviousTradingDay(from: from);

  static DateTime getNextWeekday(DateTime from) =>
      TransactionUtils.getNextWeekday(from);

  static DateTime calculateNavDateForTrade(DateTime tradeDate, bool isAfter1500) =>
      TransactionUtils.calculateNavDateForTrade(tradeDate, isAfter1500);

  static Future<DateTime> calculateNavDateForTradeAsync(
          DateTime tradeDate, bool isAfter1500) =>
      TransactionUtils.calculateNavDateForTradeAsync(tradeDate, isAfter1500);

  static DateTime calculateConfirmDate(DateTime tradeDate, bool isAfter1500) =>
      TransactionUtils.calculateConfirmDate(tradeDate, isAfter1500);

  static Future<DateTime> calculateConfirmDateAsync(
          DateTime tradeDate, bool isAfter1500) =>
      TransactionUtils.calculateConfirmDateAsync(tradeDate, isAfter1500);

  static bool isTransactionPending(DateTime tradeDate, bool isAfter1500) =>
      TransactionUtils.isTransactionPending(tradeDate, isAfter1500);

  static Future<bool> isTransactionPendingAsync(
          DateTime tradeDate, bool isAfter1500) =>
      TransactionUtils.isTransactionPendingAsync(tradeDate, isAfter1500);

  static Future<DateTime> getTradeApplicationDate(DateTime submitTime) =>
      TransactionUtils.getTradeApplicationDate(submitTime);
  
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
      final navDate = await calculateNavDateForTradeAsync(transaction.tradeDate, transaction.isAfter1500);
      final fundNavDate = fundInfo['navDate'] as DateTime?;

      if (fundInfo['isValid'] == true && fundInfo['currentNav'] > 0 &&
          fundNavDate != null && !fundNavDate.isBefore(navDate)) {
        await confirmPendingTransaction(transactionId, fundInfo['currentNav']);
        
        final confirmedIndex = _transactions.indexWhere((tx) => tx.id == transactionId);
        if (confirmedIndex != -1) {
          final confirmedTx = _transactions[confirmedIndex].copyWith(
            status: TransactionStatus.confirmed,
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

      // Cache fund info per run to avoid duplicate API calls for same fund.
      final fundInfoCache = <String, Map<String, dynamic>?>{};

      for (final tx in pendingTransactions) {
        try {
          final fundInfo = fundInfoCache[tx.fundCode] ??
              (fundInfoCache[tx.fundCode] = await fundService.fetchFundInfo(tx.fundCode));
          if (fundInfo == null) continue;
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
      
      await _syncHolding(transaction.clientId, transaction.fundCode);
      
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
    // DataManager is a singleton per app instance. Sub-notifier changes are
    // propagated via ChangeNotifier.addListener, not via InheritedWidget rebuilds.
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
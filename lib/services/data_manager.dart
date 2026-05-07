import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import '../models/fund_holding.dart';
import '../models/transaction_record.dart';
import '../models/log_entry.dart';
import '../models/profit_result.dart';
import '../models/fund_info_cache.dart';
import '../services/fund_service.dart';
import '../services/china_trading_day_service.dart';
import '../services/version_check_service.dart';
import '../services/database_repository.dart';
import '../services/database_helper.dart';
import '../widgets/theme_switch.dart' show ThemeMode;
import '../constants/app_constants.dart';
import '../utils/smart_cache.dart';

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

/// 数据管理器 - 应用核心数据服务
/// 
/// 负责管理所有业务数据，包括：
/// - 持仓管理（增删改查）
/// - 交易记录管理
/// - 日志系统
/// - 缓存管理（智能缓存 + 自动清理）
/// - 用户设置（隐私模式、主题等）
/// - 估值数据刷新
/// 
/// 特性：
/// - 跨平台支持（Web 使用 SharedPreferences，移动端/桌面端使用 SQLite）
/// - 智能缓存机制（TTL + LRU）
/// - 自动内存监控和缓存清理
/// - 响应式数据更新（ChangeNotifier）
/// 
/// 使用示例：
/// ```dart
/// final dataManager = DataManager();
/// 
/// // 监听数据变化
/// dataManager.addListener(() {
///   print('数据已更新');
/// });
/// 
/// // 添加持仓
/// await dataManager.addHolding(holding);
/// 
/// // 获取持仓列表
/// final holdings = dataManager.holdings;
/// ```
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

  bool _shouldNotifyListeners = true;
  
  // 防止已销毁后仍执行操作
  bool _disposed = false;
  
  // 使用智能缓存
  final SmartCache<String, ProfitResult> _profitCache = SmartCache(
    maxSize: 50,
    ttl: const Duration(minutes: 30),
  );
  
  final SmartCache<String, List<TransactionRecord>> _transactionHistoryCache = SmartCache(
    maxSize: 30,
    ttl: const Duration(hours: 1),
  );
  
  // 内存监控和自动清理
  Timer? _cacheCleanupTimer;
  static const int memoryWarningThresholdMB = 200;
  static const int memoryCriticalThresholdMB = 400;
  
  // 版本信息
  VersionInfo? _latestVersionInfo;
  
  // Helper to clear related caches automatically
  void _clearRelatedCaches(String clientId, String fundCode) {
    final cacheKey = '${clientId}_$fundCode';
    _transactionHistoryCache.remove(cacheKey);
    
    // Clear profit cache for this specific holding
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
    if (cached == null) return null;
    
    final now = DateTime.now();
    if (now.difference(cached.cacheTime).inDays > AppConstants.fundInfoCacheValidDays) {
      _fundInfoCache.remove(fundCode);
      return null;
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
  
  /// 设置应用生命周期监听
  void _setupLifecycleObserver() {
    if (_disposed) return;
    
    // 监听应用生命周期事件
    WidgetsBinding.instance.addObserver(_AppLifecycleObserver(this));
  }
  
  /// 启动定期缓存清理
  void _startCacheCleanup() {
    if (_disposed) return;  // ✅ 防止已销毁后仍启动
    
    // 每 5 分钟清理一次过期缓存
    _cacheCleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!_disposed) {  // ✅ 每次执行前检查
        _cleanupExpiredCaches();
      }
    });
  }
  
  /// 清理过期缓存
  Future<void> _cleanupExpiredCaches() async {
    if (_disposed) return;  // ✅ 防止已销毁后仍执行
    
    try {
      // 清理收益缓存
      final profitCleaned = _profitCache.cleanup();
      if (profitCleaned > 0) {
        debugPrint('清理收益缓存: $profitCleaned 条');
      }
      
      // 清理交易历史缓存
      final transactionCleaned = _transactionHistoryCache.cleanup();
      if (transactionCleaned > 0) {
        debugPrint('清理交易历史缓存: $transactionCleaned 条');
      }
      
      // 检查内存使用情况，如果超过阈值则主动清理
      await _checkMemoryAndCleanup();
    } catch (e) {
      debugPrint('缓存清理异常: $e');
    }
  }
  
  /// 检查内存并主动清理
  Future<void> _checkMemoryAndCleanup() async {
    try {
      // 这里可以集成 MemoryMonitor 来获取真实内存数据
      // 简化版本：当缓存数量超过一定阈值时主动清理
      if (_profitCache.size > 40 || _transactionHistoryCache.size > 25) {
        debugPrint('缓存数量较多，执行主动清理');
        _profitCache.clear();
        _transactionHistoryCache.clear();
        await addLog('内存优化：已清理缓存', type: LogType.info);
      }
    } catch (e) {
      debugPrint('内存检查异常: $e');
    }
  }
  
  /// 手动触发缓存清理（供外部调用）
  Future<void> forceCleanupCaches() async {
    if (_disposed) return;  // ✅ 防止已销毁后仍执行
    
    _profitCache.clear();
    _transactionHistoryCache.clear();
    await addLog('手动清理所有缓存', type: LogType.info);
  }
  
  /// 释放资源（在应用退出时调用）
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    
    // 移除生命周期观察者
    WidgetsBinding.instance.removeObserver(_AppLifecycleObserver(this));
    
    // 取消定时器
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = null;
    
    // 清理所有缓存
    _profitCache.clear();
    _transactionHistoryCache.clear();
    
    super.dispose();
  }
  
  /// 应用进入后台时保存数据
  Future<void> saveOnBackground() async {
    if (_disposed) return;
    
    debugPrint('应用进入后台，保存数据...');
    try {
      await saveData();
      await addLog('应用进入后台，数据已保存', type: LogType.info);
    } catch (e) {
      debugPrint('后台保存数据失败: $e');
    }
  }
  
  /// 应用恢复时重新加载数据
  Future<void> reloadOnResume() async {
    if (_disposed) return;
    
    debugPrint('应用恢复，跳过重新加载（内存数据保持最新）');
    // ✅ 关键修复：不从数据库重新加载，保持内存中的最新数据
    // 因为导入/新增时已经写入SQLite并flush，内存数据是最新的
    // 重新加载会导致未完全同步的数据被空数据覆盖
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

      notifyListeners();
    } catch (e) {
      await addLog('数据加载异常: $e', type: LogType.error);
    }
  }
  
  Future<void> _loadDataFromSQLite() async {
    debugPrint('[DataManager] 开始从 SQLite 加载数据...');
    _holdings = await _repository!.getAllHoldings();
    debugPrint('[DataManager] 加载持仓: ${_holdings.length}条');
    
    _transactions = await _repository!.getAllTransactions();
    debugPrint('[DataManager] 加载交易: ${_transactions.length}条');
    
    _logs = await _repository!.getLogs(limit: AppConstants.maxLogEntries);
    debugPrint('[DataManager] 加载日志: ${_logs.length}条');
    
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
    
    debugPrint('[DataManager] SQLite 数据加载完成');
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
      debugPrint('[DataManager] saveData 开始...');
      if (kIsWeb) {
        await _saveDataToPrefs();
        debugPrint('[DataManager] Web 平台数据已保存');
      } else {
        // ✅ 修复：非 Web 平台需要同时保存数据和设置
        // 数据已通过 insert/update 写入 SQLite，这里确保设置也同步保存
        await _saveSettingsToPrefs();
        debugPrint('[DataManager] 设置已保存');
        
        // ✅ 关键修复：强制刷新数据库，确保数据立即写入磁盘
        // iOS 可能在应用退出时杀死进程，导致 SQLite 缓冲数据丢失
        // 必须等待 flush 完成，不能异步执行
        await _repository!.flush();
        debugPrint('[DataManager] 数据库已刷新');
      }
      notifyListeners();
      debugPrint('[DataManager] saveData 完成');
    } catch (e, stackTrace) {
      debugPrint('[DataManager] ❌ 保存数据失败: $e');
      debugPrint('[DataManager] 堆栈跟踪: $stackTrace');
    }
  }
  
  /// 保存设置到 SharedPreferences（跨平台通用）
  Future<void> _saveSettingsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyPrivacyMode, _isPrivacyMode);
    await prefs.setString(AppConstants.keyThemeMode, _themeModeToString(_themeMode));
    await prefs.setBool(AppConstants.keyShowHoldersOnSummaryCard, _showHoldersOnSummaryCard);
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
    // 估值缓存使用内存存储，无需加载
    _valuationCache = {};
  }

  Future<void> saveValuationCache() async {
    // 估值缓存使用内存存储，无需保存
  }

  Future<void> loadFundInfoCache() async {
    // 基金信息缓存使用内存存储，无需加载
    _fundInfoCache = {};
  }

  Future<void> saveFundInfoCacheToPrefs() async {
    // 基金信息缓存使用内存存储，无需保存
  }

  Map<String, dynamic>? getValuation(String fundCode) {
    final cached = _valuationCache[fundCode];
    if (cached == null) return null;
    final cacheTime = DateTime.tryParse(cached['cacheTime'] ?? '');
    if (cacheTime == null) return null;
    if (DateTime.now().difference(cacheTime).inSeconds > AppConstants.valuationCacheValidSeconds) {
      return null;
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

  /// 设置最新版本信息
  void setLatestVersionInfo(VersionInfo? versionInfo) {
    _latestVersionInfo = versionInfo;
    notifyListeners();
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
      debugPrint('格式化估值时间失败 ($gztime): $e');
      // 返回原始字符串
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

  Future<void> addTransaction(TransactionRecord transaction) async {
    if (transaction.amount <= 0) {
      await addLog('添加交易失败: 金额必须大于0', type: LogType.error);
      throw Exception('无效的交易数据');
    }
    
    if (!transaction.isPending && transaction.shares <= 0) {
      await addLog('添加交易失败: 已确认交易必须有份额', type: LogType.error);
      throw Exception('无效的交易数据');
    }

    if (!kIsWeb) {
      await _repository!.insertTransaction(transaction);
    }
    _transactions = [..._transactions, transaction];
    
    _clearRelatedCaches(transaction.clientId, transaction.fundCode);

    await _rebuildHolding(transaction.clientId, transaction.fundCode);

    await addLog(
      '${transaction.type.displayName}交易: ${transaction.fundCode} - ${transaction.clientName}, '
      '金额: ${transaction.amount.toStringAsFixed(2)}元, '
      '份额: ${transaction.shares.toStringAsFixed(2)}份',
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
      // 从内存中移除
      final holdingToRemove = _holdings.firstWhere(
        (h) => h.clientId == clientId && h.fundCode == fundCode,
        orElse: () => FundHolding.invalid(fundCode: fundCode),
      );
      _holdings.removeWhere((h) => h.clientId == clientId && h.fundCode == fundCode);
      
      // ✅ 关键修复：从数据库中删除持仓
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
      // 更新内存
      _holdings[existingIndex] = newHolding;
      // ✅ 关键修复：更新数据库中的持仓
      if (!kIsWeb) {
        await _repository!.updateHolding(newHolding.id, newHolding);
      }
    } else {
      // 添加到内存
      _holdings = [..._holdings, newHolding];
      // ✅ 关键修复：插入新持仓到数据库
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
    
    if (!kIsWeb) {
      await _repository!.deleteTransaction(transactionId);
    }
    _transactions = List.from(_transactions)..removeAt(index);
    
    // Automatic cache invalidation
    _clearRelatedCaches(transaction.clientId, transaction.fundCode);

    await _rebuildHolding(transaction.clientId, transaction.fundCode);

    await addLog('删除交易记录: ${transaction.fundCode} - ${transaction.type.displayName}', type: LogType.info);
    await saveData();
    notifyListeners();
  }

  /// 更新持仓信息
  /// 
  /// 用于更新持仓的净值、收益率等动态数据。
  /// 注意：此方法不会触发交易记录重建，仅更新持仓对象本身。
  /// 
  /// 参数：
  /// - [updatedHolding]: 更新后的持仓对象
  /// 
  /// 异常：
  /// - [Exception]: 当持仓不存在时抛出
  /// 
  /// 示例：
  /// ```dart
  /// final updated = holding.copyWith(currentNav: 1.2345, navDate: DateTime.now());
  /// await dataManager.updateHolding(updated);
  /// ```
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
          final canConfirmDate = await calculateConfirmDateAsync(tx.tradeDate, tx.isAfter1500);
          
          if (now.isAfter(canConfirmDate) || now.isAtSameMomentAs(canConfirmDate)) {
            final fundInfo = await fundService.fetchFundInfo(tx.fundCode);
            if (fundInfo['isValid'] == true && fundInfo['currentNav'] > 0) {
              await confirmPendingTransaction(tx.id, fundInfo['currentNav']);
              confirmedCount++;
            }
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

  /// 删除持仓
  /// 
  /// 根据索引删除指定持仓，同时会删除相关的交易记录。
  /// 
  /// 参数：
  /// - [index]: 持仓在列表中的索引位置
  /// 
  /// 注意：
  /// - 删除操作不可逆
  /// - 会自动清理相关缓存
  /// - 会记录日志
  Future<void> deleteHoldingAt(int index) async {
    if (index < 0 || index >= _holdings.length) return;

    final removed = _holdings[index];
    
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

  /// 刷新所有持仓信息
  /// 
  /// [fundService] 基金服务
  /// [onProgress] 进度回调函数 (current, total)
  /// 刷新所有持仓信息
  /// 
  /// 从 API 获取最新的基金净值和收益率数据，并更新所有持仓。
  /// 此方法会：
  /// 1. 批量获取基金信息（每批5个，避免并发过多）
  /// 2. 自动确认已到确认日的待确认交易
  /// 3. 更新持仓的净值、收益率等字段
  /// 
  /// 参数：
  /// - [fundService]: 基金服务实例，用于调用 API
  /// - [onProgress]: 进度回调函数 (current, total)
  /// 
  /// 示例：
  /// ```dart
  /// await dataManager.refreshAllHoldings(fundService, (current, total) {
  ///   print('进度: $current/$total');
  /// });
  /// ```
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
          
          // 自动确认相关待确认交易
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
  
  /// 向后兼容的方法名（已废弃，请使用 refreshAllHoldings）
  @Deprecated('Use refreshAllHoldings instead')
  Future<void> refreshAllHoldingsWithAutoConfirm(FundService fundService, void Function(int, int)? onProgress) async {
    await refreshAllHoldings(fundService, onProgress);
  }
  
  /// 向后兼容的方法名（已废弃，请使用 refreshAllHoldings）
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
      
      final updatedTransaction = transaction.copyWith(
        isPending: false,
        confirmedNav: confirmedNav,
        shares: calculatedShares,
        amount: calculatedAmount,
      );
      
      _transactions[index] = updatedTransaction;
      
      // Automatic cache invalidation
      _clearRelatedCaches(transaction.clientId, transaction.fundCode);
      
      await _rebuildHolding(transaction.clientId, transaction.fundCode);
      
      await saveData();
      
      final confirmDate = DateTime.now();
      await addLog(
        '✅ 确认交易: ${transaction.fundName}(${transaction.fundCode})\n'
        '客户: ${transaction.clientName}(${transaction.clientId})\n'
        '类型: ${transaction.type.displayName}\n'
        '交易日期: ${transaction.tradeDate.year}-${transaction.tradeDate.month.toString().padLeft(2, '0')}-${transaction.tradeDate.day.toString().padLeft(2, '0')}\n'
        '金额: ${calculatedAmount.toStringAsFixed(2)}元 | 份额: ${calculatedShares.toStringAsFixed(2)}份\n'
        '确认净值: $confirmedNav\n'
        '确认时间: ${confirmDate.year}-${confirmDate.month.toString().padLeft(2, '0')}-${confirmDate.day.toString().padLeft(2, '0')} ${confirmDate.hour.toString().padLeft(2, '0')}:${confirmDate.minute.toString().padLeft(2, '0')}',
        type: LogType.success,
      );
      
      notifyListeners();
    } catch (e) {
      await addLog('确认交易异常: $e', type: LogType.error);
      rethrow;
    }
  }
  
  Future<int> autoConfirmPendingTransactions(FundService fundService) async {
    final pendingTransactions = getPendingTransactions();
    if (pendingTransactions.isEmpty) return 0;
    
    int confirmedCount = 0;
    final now = DateTime.now();
    
    for (final tx in pendingTransactions) {
      try {
        final canConfirmDate = await calculateConfirmDateAsync(tx.tradeDate, tx.isAfter1500);
        
        if (now.isAfter(canConfirmDate) || now.isAtSameMomentAs(canConfirmDate)) {
          final fundInfo = await fundService.fetchFundInfo(tx.fundCode);
          if (fundInfo['isValid'] == true && fundInfo['currentNav'] > 0) {
            await confirmPendingTransaction(tx.id, fundInfo['currentNav']);
            confirmedCount++;
          }
        }
      } catch (e) {
        await addLog('自动确认交易失败: $e', type: LogType.error);
      }
    }
    
    if (confirmedCount > 0) {
      await addLog('自动确认 $confirmedCount 笔待确认交易', type: LogType.success);
    }
    
    return confirmedCount;
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
  
  static DataManager? maybeOf(BuildContext context) {  // ✅ 添加 maybeOf 方法
    final provider = context.dependOnInheritedWidgetOfExactType<DataManagerProvider>();
    return provider?.dataManager;
  }

  @override
  bool updateShouldNotify(DataManagerProvider oldWidget) {
    return dataManager != oldWidget.dataManager;
  }
}

/// 应用生命周期观察者
class _AppLifecycleObserver with WidgetsBindingObserver {
  final DataManager _dataManager;
  
  _AppLifecycleObserver(this._dataManager);
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // 应用进入后台 - 必须同步等待保存完成
        debugPrint('应用状态: paused (进入后台)');
        _dataManager.saveOnBackground();
        break;
      case AppLifecycleState.resumed:
        // 应用恢复前台 - 不需要重新加载，内存中的数据是最新的
        debugPrint('应用状态: resumed (恢复前台) - 跳过重新加载');
        // 不调用 reloadOnResume()，避免覆盖内存中的最新数据
        break;
      case AppLifecycleState.detached:
        // 应用被销毁 - 必须同步等待保存完成
        debugPrint('应用状态: detached (被销毁)');
        _dataManager.saveOnBackground();
        break;
      default:
        break;
    }
  }
}
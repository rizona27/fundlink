import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fund_holding.dart';
import '../models/transaction_record.dart';
import '../models/log_entry.dart';
import '../models/profit_result.dart';
import '../models/fund_info_cache.dart';
import '../services/fund_service.dart';
import '../services/china_trading_day_service.dart';
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
  static const String _holdingsKey = 'fund_holdings';
  static const String _transactionsKey = 'fund_transactions';
  static const String _logsKey = 'logs';
  static const String _privacyModeKey = 'privacy_mode';
  static const String _themeModeKey = 'theme_mode';
  static const String _valuationCacheKey = 'valuation_cache';
  static const String _showHoldersOnSummaryCardKey = 'show_holders_on_summary_card';
  static const String _fundInfoCacheKey = 'fund_info_cache';
  static const int _valuationCacheValidSeconds = 180;
  static const int _fundInfoCacheValidDays = 7;

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

  // 性能优化：选择性通知标志，避免不必要的全局重建
  bool _shouldNotifyListeners = true;
  
  // 性能优化：计算结果缓存
  final Map<String, ProfitResult> _profitCache = {};
  final Map<String, List<TransactionRecord>> _transactionHistoryCache = {};
  static const int _maxCacheSize = 500; // LRU缓存最大大小

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

  /// 获取基金信息缓存
  FundInfoCache? getFundInfoCache(String fundCode) {
    final cached = _fundInfoCache[fundCode];
    if (cached == null) return null;
    
    final now = DateTime.now();
    if (now.difference(cached.cacheTime).inDays > _fundInfoCacheValidDays) {
      _fundInfoCache.remove(fundCode);
      return null;
    }
    
    return cached;
  }

  /// 保存基金信息缓存
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
  }

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final holdingsJson = prefs.getStringList(_holdingsKey);
    if (holdingsJson != null) {
      _holdings = holdingsJson
          .map((json) => FundHolding.fromJson(jsonDecode(json)))
          .toList();
    }

    final transactionsJson = prefs.getStringList(_transactionsKey);
    if (transactionsJson != null) {
      _transactions = transactionsJson
          .map((json) => TransactionRecord.fromJson(jsonDecode(json)))
          .toList();
    }

    final logsJson = prefs.getStringList(_logsKey);
    if (logsJson != null) {
      _logs = logsJson
          .map((json) => LogEntry.fromJson(jsonDecode(json)))
          .toList();
    }

    _isPrivacyMode = prefs.getBool(_privacyModeKey) ?? true;

    final themeModeString = prefs.getString(_themeModeKey);
    if (themeModeString != null) {
      _themeMode = _parseThemeMode(themeModeString);
    } else {
      _themeMode = ThemeMode.system;
    }

    _showHoldersOnSummaryCard = prefs.getBool(_showHoldersOnSummaryCardKey) ?? true;

    await loadValuationCache();
    await loadFundInfoCache();

    notifyListeners();
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
    final prefs = await SharedPreferences.getInstance();

    final holdingsJson = _holdings
        .map((holding) => jsonEncode(holding.toJson()))
        .toList();
    await prefs.setStringList(_holdingsKey, holdingsJson);

    final transactionsJson = _transactions
        .map((tx) => jsonEncode(tx.toJson()))
        .toList();
    await prefs.setStringList(_transactionsKey, transactionsJson);

    final logsJson = _logs
        .take(100)
        .map((log) => jsonEncode(log.toJson()))
        .toList();
    await prefs.setStringList(_logsKey, logsJson);

    await prefs.setBool(_privacyModeKey, _isPrivacyMode);
    await prefs.setString(_themeModeKey, _themeModeToString(_themeMode));
    await prefs.setBool(_showHoldersOnSummaryCardKey, _showHoldersOnSummaryCard);
  }

  Future<void> loadValuationCache() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_valuationCacheKey);
    if (jsonStr != null) {
      try {
        final Map<String, dynamic> raw = jsonDecode(jsonStr);
        _valuationCache = raw.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
      } catch (e) {
      }
    }
  }

  Future<void> saveValuationCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_valuationCacheKey, jsonEncode(_valuationCache));
  }

  // 加载基金信息缓存
  Future<void> loadFundInfoCache() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_fundInfoCacheKey);
    if (jsonStr != null) {
      try {
        final List<dynamic> rawList = jsonDecode(jsonStr);
        _fundInfoCache = {};
        for (final raw in rawList) {
          final fundInfo = FundInfoCache.fromJson(Map<String, dynamic>.from(raw));
          _fundInfoCache[fundInfo.fundCode] = fundInfo;
        }
      } catch (e) {
      }
    }
  }

  Future<void> saveFundInfoCacheToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheList = _fundInfoCache.values.map((info) => info.toJson()).toList();
    await prefs.setString(_fundInfoCacheKey, jsonEncode(cacheList));
  }

  Map<String, dynamic>? getValuation(String fundCode) {
    final cached = _valuationCache[fundCode];
    if (cached == null) return null;
    final cacheTime = DateTime.tryParse(cached['cacheTime'] ?? '');
    if (cacheTime == null) return null;
    if (DateTime.now().difference(cacheTime).inSeconds > _valuationCacheValidSeconds) {
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

      for (int i = 0; i < total; i++) {
        final holding = holdings[i];
        try {
          final valuation = await fundService.fetchRealtimeValuation(holding.fundCode);
          if (valuation != null && valuation['gsz'] != null && valuation['gsz'] > 0) {
            await updateValuationCache(holding.fundCode, {
              'gsz': valuation['gsz'],
              'gszzl': valuation['gszzl'] ?? 0.0,
              'gztime': valuation['gztime'] ?? '',
            });
            successCount++;
            if (valuation['gztime'] != null && valuation['gztime'].toString().isNotEmpty) {
              latestUpdateTime = _formatGzTime(valuation['gztime']);
            }
          } else {
            failCount++;
            await addLog('基金 ${holding.fundCode} 估值获取失败: 数据无效', type: LogType.error);
          }
        } catch (e) {
          failCount++;
          await addLog('基金 ${holding.fundCode} 估值获取异常: $e', type: LogType.error);
        }

        updateValuationRefreshProgress((i + 1) / total);
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

    _holdings = [..._holdings, holding];
    await saveData();
    await addLog('新增持仓: ${holding.fundCode} - ${holding.clientName}', type: LogType.success);
    notifyListeners();
  }

  /// 添加交易记录并自动更新持仓
  Future<void> addTransaction(TransactionRecord transaction) async {
    // 验证交易数据
    // 对于待确认交易，份额可以为0，等待后续确认时计算
    if (transaction.amount <= 0) {
      await addLog('添加交易失败: 金额必须大于0', type: LogType.error);
      throw Exception('无效的交易数据');
    }
    
    // 非待确认交易必须有份额
    if (!transaction.isPending && transaction.shares <= 0) {
      await addLog('添加交易失败: 已确认交易必须有份额', type: LogType.error);
      throw Exception('无效的交易数据');
    }

    // 添加交易记录
    _transactions = [..._transactions, transaction];
    
    // 清除该客户基金的交易历史缓存
    final cacheKey = '${transaction.clientId}_${transaction.fundCode}';
    _transactionHistoryCache.remove(cacheKey);

    // 重新计算该客户该基金的持仓
    await _rebuildHolding(transaction.clientId, transaction.fundCode);

    await saveData();
    await addLog(
      '${transaction.type.displayName}交易: ${transaction.fundCode} - ${transaction.clientName}, '
      '金额: ${transaction.amount.toStringAsFixed(2)}元, '
      '份额: ${transaction.shares.toStringAsFixed(2)}份',
      type: LogType.success,
    );
    notifyListeners();
  }

  /// 根据交易记录重建持仓
  Future<void> _rebuildHolding(String clientId, String fundCode) async {
    // 获取该客户该基金的所有交易记录
    final relatedTransactions = _transactions
        .where((tx) => tx.clientId == clientId && tx.fundCode == fundCode)
        .toList()
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));

    if (relatedTransactions.isEmpty) {
      // 如果没有交易记录，删除对应的持仓
      _holdings.removeWhere((h) => h.clientId == clientId && h.fundCode == fundCode);
      return;
    }

    // 获取最新的基金信息
    final firstTx = relatedTransactions.first;
    final lastTx = relatedTransactions.last;

    // 从现有持仓中获取净值信息，如果没有则使用默认值
    final existingHolding = _holdings.firstWhere(
      (h) => h.clientId == clientId && h.fundCode == fundCode,
      orElse: () => FundHolding.invalid(fundCode: fundCode),
    );

    // 基于交易记录重新计算持仓
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

    // 如果持仓已存在，更新它；否则添加新持仓
    final existingIndex = _holdings.indexWhere(
      (h) => h.clientId == clientId && h.fundCode == fundCode,
    );

    if (existingIndex != -1) {
      _holdings[existingIndex] = newHolding;
    } else {
      _holdings = [..._holdings, newHolding];
    }
  }

  /// 获取指定客户和基金的交易历史（带缓存优化）
  List<TransactionRecord> getTransactionHistory(String clientId, String fundCode) {
    final cacheKey = '${clientId}_$fundCode';
    
    // 检查缓存
    if (_transactionHistoryCache.containsKey(cacheKey)) {
      return _transactionHistoryCache[cacheKey]!;
    }
    
    // 计算并缓存
    final result = _transactions
        .where((tx) => tx.clientId == clientId && tx.fundCode == fundCode)
        .toList()
      ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
    
    // LRU缓存管理
    if (_transactionHistoryCache.length >= _maxCacheSize) {
      // 移除最旧的缓存项
      final oldestKey = _transactionHistoryCache.keys.first;
      _transactionHistoryCache.remove(oldestKey);
    }
    
    _transactionHistoryCache[cacheKey] = result;
    return result;
  }

  /// 删除交易记录并重新计算持仓
  Future<void> deleteTransaction(String transactionId) async {
    final index = _transactions.indexWhere((tx) => tx.id == transactionId);
    if (index == -1) {
      await addLog('删除交易失败: 未找到交易记录', type: LogType.error);
      throw Exception('交易记录不存在');
    }

    final transaction = _transactions[index];
    _transactions = List.from(_transactions)..removeAt(index);
    
    // 清除该客户基金的交易历史缓存
    final cacheKey = '${transaction.clientId}_${transaction.fundCode}';
    _transactionHistoryCache.remove(cacheKey);

    // 重新计算持仓
    await _rebuildHolding(transaction.clientId, transaction.fundCode);

    await saveData();
    await addLog('删除交易记录: ${transaction.fundCode} - ${transaction.type.displayName}', type: LogType.info);
    notifyListeners();
  }

  Future<void> updateHolding(FundHolding updatedHolding) async {
    final index = _holdings.indexWhere((h) => h.id == updatedHolding.id);
    if (index == -1) {
      await addLog('更新持仓失败: 未找到持仓 ${updatedHolding.fundCode}', type: LogType.error);
      throw Exception('持仓不存在');
    }

    final newHoldings = List<FundHolding>.from(_holdings);
    newHoldings[index] = updatedHolding;
    _holdings = newHoldings;

    await saveData();
    await addLog('更新持仓: ${updatedHolding.fundCode} - ${updatedHolding.clientName}', type: LogType.success);
    notifyListeners();
  }

  /// 更新持仓的净值信息（不改变交易记录）- 优化版，支持批量更新
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
    // 不在这里保存和通知，由调用者决定何时批量保存
  }

  /// 批量保存并通知（用于refreshAllHoldingsForce等批量操作）
  Future<void> commitBatchUpdates() async {
    await saveData();
    notifyListeners();
  }

  Future<void> deleteHoldingAt(int index) async {
    if (index < 0 || index >= _holdings.length) return;

    final removed = _holdings[index];
    _holdings = List.from(_holdings)..removeAt(index);
    await saveData();
    await addLog('删除持仓: ${removed.fundCode} - ${removed.clientName}', type: LogType.info);
    notifyListeners();
  }

  Future<void> clearAllHoldings() async {
    final count = _holdings.length;
    _holdings = [];
    // 清空缓存
    _profitCache.clear();
    _transactionHistoryCache.clear();
    await saveData();
    await addLog('清空所有持仓数据，共删除 $count 条记录', type: LogType.warning);
    notifyListeners();
  }

  /// 批量更新持仓（减少notifyListeners调用次数）
  Future<void> batchUpdateHoldings(List<FundHolding> newHoldings) async {
    _holdings = newHoldings;
    await saveData();
    notifyListeners();
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
      await saveData();
      await addLog('${newIsPinned ? "置顶" : "取消置顶"}: ${holding.fundCode} - ${holding.clientName}', type: LogType.info);
      notifyListeners();
    }
  }

  Future<void> refreshAllHoldingsForce(FundService fundService, Function(int current, int total)? onProgress) async {
    final total = _holdings.length;
    for (int i = 0; i < total; i++) {
      final holding = _holdings[i];
      final fetched = await fundService.fetchFundInfo(holding.fundCode, forceRefresh: true);
      if (fetched['isValid'] == true) {
        await updateHoldingNav(
          holding.clientId,
          holding.fundCode,
          fetched['currentNav'],
          fetched['navDate'],
        );
        
        // 同时更新收益率信息
        final index = _holdings.indexWhere((h) => h.id == holding.id);
        if (index != -1) {
          final updated = _holdings[index].copyWith(
            navReturn1m: fetched['navReturn1m'],
            navReturn3m: fetched['navReturn3m'],
            navReturn6m: fetched['navReturn6m'],
            navReturn1y: fetched['navReturn1y'],
          );
          _holdings[index] = updated;
        }
      } else {
        await addLog('强制刷新基金 ${holding.fundCode} 失败', type: LogType.error);
      }
      onProgress?.call(i + 1, total);
    }
    // 优化：批量保存和通知，减少I/O和重建次数
    await commitBatchUpdates();
  }

  Future<void> addLog(String message, {LogType type = LogType.info}) async {
    final logEntry = LogEntry.create(message: message, type: type);
    _logs = [logEntry, ..._logs];

    if (_logs.length > 200) {
      _logs = _logs.take(200).toList();
    }

    await saveData();
    notifyListeners();
  }

  Future<void> clearAllLogs() async {
    _logs = [];
    await saveData();
    await addLog('日志已清空', type: LogType.info);
    notifyListeners();
  }

  Future<void> togglePrivacyMode() async {
    _isPrivacyMode = !_isPrivacyMode;
    await saveData();
    await addLog('隐私模式: ${_isPrivacyMode ? "开启" : "关闭"}', type: LogType.info);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode != mode) {
      _themeMode = mode;
      await saveData();
      await addLog('主题模式: ${mode.displayName}', type: LogType.info);
      notifyListeners();
    }
  }

  Future<void> setShowHoldersOnSummaryCard(bool value) async {
    if (_showHoldersOnSummaryCard != value) {
      _showHoldersOnSummaryCard = value;
      await saveData();
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
    // 使用缓存键
    final cacheKey = '${holding.clientId}_${holding.fundCode}_${holding.totalShares}_${holding.totalCost}_${holding.currentNav}';
    
    // 检查缓存
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

    // 计算持有天数：从首次买入到现在
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
    
    // LRU缓存管理
    if (_profitCache.length >= _maxCacheSize) {
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
  
  /// 获取所有待确认的交易
  List<TransactionRecord> getPendingTransactions() {
    return _transactions.where((tx) => tx.isPending).toList();
  }
  
  /// 确认待确认交易(当净值可用时)
  Future<void> confirmPendingTransaction(String transactionId, double confirmedNav) async {
    final index = _transactions.indexWhere((tx) => tx.id == transactionId);
    if (index == -1) {
      throw Exception('交易记录不存在');
    }
    
    final transaction = _transactions[index];
    if (!transaction.isPending) {
      throw Exception('该交易已经确认');
    }
    
    // 根据交易类型计算缺失的值
    double calculatedShares = transaction.shares;
    double calculatedAmount = transaction.amount;
    
    if (transaction.type == TransactionType.buy) {
      // 买入：如果份额为0，根据金额和净值计算份额
      if (transaction.shares <= 0 && transaction.amount > 0 && confirmedNav > 0) {
        // 使用内扣法计算份额：份额 = 金额 / (1 + 费率%) / 净值
        final feeRate = transaction.fee ?? 0.0; // 获取保存的费率，默认为0
        calculatedShares = transaction.amount / (1 + feeRate / 100) / confirmedNav;
        print('确认买入交易时计算份额: 金额=${transaction.amount}, 费率=$feeRate%, 净值=$confirmedNav, 份额=$calculatedShares');
      }
    } else {
      // 卖出：如果金额为0，根据份额和净值计算金额
      if (transaction.amount <= 0 && transaction.shares > 0 && confirmedNav > 0) {
        // 金额 = 份额 * 净值 * (1 - 费率%)
        final feeRate = transaction.fee ?? 0.0; // 获取保存的费率，默认为0
        calculatedAmount = transaction.shares * confirmedNav * (1 - feeRate / 100);
        print('确认卖出交易时计算金额: 份额=${transaction.shares}, 费率=$feeRate%, 净值=$confirmedNav, 金额=$calculatedAmount');
      }
    }
    
    // 更新交易记录
    final updatedTransaction = transaction.copyWith(
      isPending: false,
      confirmedNav: confirmedNav,
      shares: calculatedShares,
      amount: calculatedAmount,
    );
    
    _transactions[index] = updatedTransaction;
    
    // 重新计算持仓
    await _rebuildHolding(transaction.clientId, transaction.fundCode);
    
    await saveData();
    
    // 记录详细的确认日志
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
  }
  
  /// 批量确认已过期的待确认交易
  Future<int> autoConfirmPendingTransactions(FundService fundService) async {
    final pendingTransactions = getPendingTransactions();
    if (pendingTransactions.isEmpty) return 0;
    
    int confirmedCount = 0;
    final now = DateTime.now();
    
    for (final tx in pendingTransactions) {
      try {
        // 使用新的异步方法计算该交易何时可以确认（考虑节假日和调休）
        final canConfirmDate = await calculateConfirmDateAsync(tx.tradeDate, tx.isAfter1500);
        
        // 如果当前日期 >= 可确认日期,则尝试获取净值并确认
        if (now.isAfter(canConfirmDate) || now.isAtSameMomentAs(canConfirmDate)) {
          // 获取该基金的最新净值
          final fundInfo = await fundService.fetchFundInfo(tx.fundCode);
          if (fundInfo['isValid'] == true && fundInfo['currentNav'] > 0) {
            await confirmPendingTransaction(tx.id, fundInfo['currentNav']);
            confirmedCount++;
          }
        }
      } catch (e) {
        print('自动确认交易失败: $e');
      }
    }
    
    if (confirmedCount > 0) {
      await addLog('自动确认 $confirmedCount 笔待确认交易', type: LogType.success);
    }
    
    return confirmedCount;
  }
  
  /// 判断是否为工作日(周一到周五,不考虑节假日)
  /// @deprecated 请使用 ChinaTradingDayService.isTradingDay() 获取更准确的交易日判断
  static bool isWeekday(DateTime date) {
    final weekday = date.weekday; // 1=Monday, 7=Sunday
    return weekday >= DateTime.monday && weekday <= DateTime.friday;
  }
  
  /// 判断是否为中国 A 股交易日（考虑法定节假日和调休补班）
  /// 使用三层降级策略：
  /// 1. 专业节假日 API（包含调休补班信息）
  /// 2. world_holidays 包（法定节假日）
  /// 3. 本地周一到周五判断（兜底方案）
  static Future<bool> isTradingDay(DateTime date) async {
    final service = ChinaTradingDayService();
    return await service.isTradingDay(date);
  }
  
  /// 获取下一个交易日
  static Future<DateTime> getNextTradingDay({DateTime? from}) async {
    final service = ChinaTradingDayService();
    return await service.getNextTradingDay(from: from);
  }
  
  /// 获取上一个交易日
  static Future<DateTime> getPreviousTradingDay({DateTime? from}) async {
    final service = ChinaTradingDayService();
    return await service.getPreviousTradingDay(from: from);
  }
  
  /// 获取下一个工作日
  /// @deprecated 请使用 getNextTradingDay() 获取更准确的下一个交易日
  static DateTime getNextWeekday(DateTime from) {
    DateTime next = from.add(const Duration(days: 1));
    while (!isWeekday(next)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }
  
  /// 计算交易应该使用的净值日期
  /// - 过去日期:
  ///   * 工作日: 
  ///     - 15:00前: 使用T日(当天)的净值
  ///     - 15:00后: 使用T+1日(下一个工作日)的净值
  ///   * 非工作日: 统一按下一个工作日的15:00前处理
  /// - 今天或未来: 
  ///   * 工作日15:00前: 使用T日(当天)的净值,在T+1日公布
  ///   * 工作日15:00后: 使用T+1日(下一个工作日)的净值,在T+2日公布
  ///   * 非工作日: 统一按下一个工作日的15:00前处理，使用下一个工作日的净值
  static DateTime calculateNavDateForTrade(DateTime tradeDate, bool isAfter1500) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tradeDay = DateTime(tradeDate.year, tradeDate.month, tradeDate.day);
    
    // 判断是否为工作日
    final isTradeWeekday = isWeekday(tradeDay);
    
    // 过去的交易
    if (tradeDay.isBefore(today)) {
      if (!isTradeWeekday) {
        // 非工作日：统一视为下一个工作日的15:00前
        return getNextWeekday(tradeDay);
      } else {
        // 工作日：根据15:00前后决定
        if (isAfter1500) {
          // 15:00后，使用下一个工作日的净值(T+1日)
          return getNextWeekday(tradeDay);
        } else {
          // 15:00前，使用当天的净值(T日)
          return tradeDay;
        }
      }
    }
    
    // 今天或未来的交易
    // 如果是非工作日，统一视为下一个工作日的15:00前
    final effectiveIsAfter1500 = isTradeWeekday ? isAfter1500 : false;
    
    if (effectiveIsAfter1500) {
      // 15:00后,使用下一个工作日的净值(T+1日)
      return getNextWeekday(tradeDay);
    } else {
      // 15:00前,使用当天的净值(T日),如果是周末则用下一个工作日
      return isTradeWeekday ? tradeDay : getNextWeekday(tradeDay);
    }
  }
  
  /// 计算交易应该使用的净值日期（异步版本，考虑法定节假日和调休补班）
  /// @deprecated 请使用 calculateNavDateForTradeAsync
  static Future<DateTime> calculateNavDateForTradeAsync(DateTime tradeDate, bool isAfter1500) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tradeDay = DateTime(tradeDate.year, tradeDate.month, tradeDate.day);
    
    // 判断是否为交易日
    final isTradeTradingDay = await isTradingDay(tradeDay);
    
    // 过去的交易
    if (tradeDay.isBefore(today)) {
      if (!isTradeTradingDay) {
        // 非交易日：统一视为下一个交易日的15:00前
        return await getNextTradingDay(from: tradeDay);
      } else {
        // 交易日：根据15:00前后决定
        if (isAfter1500) {
          // 15:00后，使用下一个交易日的净值(T+1日)
          return await getNextTradingDay(from: tradeDay);
        } else {
          // 15:00前，使用当天的净值(T日)
          return tradeDay;
        }
      }
    }
    
    // 今天或未来的交易
    // 如果是非交易日，统一视为下一个交易日的15:00前
    final effectiveIsAfter1500 = isTradeTradingDay ? isAfter1500 : false;
    
    if (effectiveIsAfter1500) {
      // 15:00后,使用下一个交易日的净值(T+1日)
      return await getNextTradingDay(from: tradeDay);
    } else {
      // 15:00前,使用当天的净值(T日),如果是非交易日则用下一个交易日
      return isTradeTradingDay ? tradeDay : await getNextTradingDay(from: tradeDay);
    }
  }
  
  /// 计算交易净值何时可以确认(净值公布时间)
  /// 关键：基于净值日期而非交易日期来判断
  /// - 如果净值日期是过去：已确认，返回交易日期
  /// - 如果净值日期是今天或未来：
  ///   * 工作日15:00前: T+1日可确认（使用T日净值）
  ///   * 工作日15:00后: T+2日可确认（使用T+1日净值）
  ///   * 非工作日: 统一按下一个工作日的15:00前处理，T+1日可确认（使用下一个工作日净值）
  static DateTime calculateConfirmDate(DateTime tradeDate, bool isAfter1500) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // 先计算该交易应该使用的净值日期
    final navDate = calculateNavDateForTrade(tradeDate, isAfter1500);
    final navDay = DateTime(navDate.year, navDate.month, navDate.day);
    
    // 如果净值日期是过去，说明已经确认
    if (navDay.isBefore(today)) {
      return tradeDate;
    }
    
    // 净值日期是今天或未来，需要计算确认日期
    final tradeDay = DateTime(tradeDate.year, tradeDate.month, tradeDate.day);
    final isTradeWeekday = isWeekday(tradeDay);
    final effectiveIsAfter1500 = isTradeWeekday ? isAfter1500 : false;
    
    if (effectiveIsAfter1500) {
      // 15:00后，使用T+1日净值，T+2日可确认
      final actualNavDate = getNextWeekday(tradeDay); // T+1日（净值日期）
      return getNextWeekday(actualNavDate); // T+2日（确认日期）
    } else {
      // 15:00前，使用T日净值，T+1日可确认
      final actualNavDate = isTradeWeekday ? tradeDay : getNextWeekday(tradeDay); // T日（净值日期）
      return getNextWeekday(actualNavDate); // T+1日（确认日期）
    }
  }
  
  /// 计算交易净值何时可以确认（异步版本，考虑法定节假日和调休补班）
  static Future<DateTime> calculateConfirmDateAsync(DateTime tradeDate, bool isAfter1500) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // 先计算该交易应该使用的净值日期（使用新的异步方法）
    final navDate = await calculateNavDateForTradeAsync(tradeDate, isAfter1500);
    final navDay = DateTime(navDate.year, navDate.month, navDate.day);
    
    // 如果净值日期是过去，说明已经确认
    if (navDay.isBefore(today)) {
      return tradeDate;
    }
    
    // 净值日期是今天或未来，需要计算确认日期
    final tradeDay = DateTime(tradeDate.year, tradeDate.month, tradeDate.day);
    final isTradeTradingDay = await isTradingDay(tradeDay);
    final effectiveIsAfter1500 = isTradeTradingDay ? isAfter1500 : false;
    
    if (effectiveIsAfter1500) {
      // 15:00后，使用T+1日净值，T+2日可确认
      final actualNavDate = await getNextTradingDay(from: tradeDay); // T+1日（净值日期）
      return await getNextTradingDay(from: actualNavDate); // T+2日（确认日期）
    } else {
      // 15:00前，使用T日净值，T+1日可确认
      final actualNavDate = isTradeTradingDay ? tradeDay : await getNextTradingDay(from: tradeDay); // T日（净值日期）
      return await getNextTradingDay(from: actualNavDate); // T+1日（确认日期）
    }
  }
  
  /// 判断交易是否为待确认状态
  /// 关键：基于净值日期而非交易日期来判断
  /// - 如果净值日期是今天或未来：待确认（净值还未公布）
  /// - 如果净值日期是过去：已确认（净值已公布）
  static bool isTransactionPending(DateTime tradeDate, bool isAfter1500) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // 先计算该交易应该使用的净值日期
    final navDate = calculateNavDateForTrade(tradeDate, isAfter1500);
    final navDay = DateTime(navDate.year, navDate.month, navDate.day);
    
    // 如果净值日期是今天或未来，说明净值还未公布，需要待确认
    return !navDay.isBefore(today);
  }
  
  /// 判断交易是否为待确认状态（异步版本，考虑节假日）
  static Future<bool> isTransactionPendingAsync(DateTime tradeDate, bool isAfter1500) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // 先计算该交易应该使用的净值日期（使用异步方法，考虑节假日）
    final navDate = await calculateNavDateForTradeAsync(tradeDate, isAfter1500);
    final navDay = DateTime(navDate.year, navDate.month, navDate.day);
    
    // 如果净值日期是今天或未来，说明净值还未公布，需要待确认
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

  @override
  bool updateShouldNotify(DataManagerProvider oldWidget) {
    return dataManager != oldWidget.dataManager;
  }
}
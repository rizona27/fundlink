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
  static const int _fundInfoCacheValidDays = 7; // 基金信息缓存有效期7天

  List<FundHolding> _holdings = [];
  List<TransactionRecord> _transactions = [];
  List<LogEntry> _logs = [];
  bool _isPrivacyMode = true;
  ThemeMode _themeMode = ThemeMode.system;
  Map<String, Map<String, dynamic>> _valuationCache = {};
  Map<String, FundInfoCache> _fundInfoCache = {}; // 基金信息缓存
  bool _showHoldersOnSummaryCard = true;

  bool _isValuationRefreshing = false;
  double _valuationRefreshProgress = 0.0;
  String _lastValuationUpdateTime = '';

  bool _isValuationRefreshInProgress = false;
  Completer<void>? _currentValuationRefreshCompleter;

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

  // 获取基金信息缓存
  FundInfoCache? getFundInfoCache(String fundCode) {
    final cached = _fundInfoCache[fundCode];
    if (cached == null) return null;
    
    // 检查缓存是否过期（7天）
    final now = DateTime.now();
    if (now.difference(cached.cacheTime).inDays > _fundInfoCacheValidDays) {
      _fundInfoCache.remove(fundCode);
      return null;
    }
    
    return cached;
  }

  // 保存基金信息缓存
  void saveFundInfoCache(FundInfoCache fundInfo) {
    _fundInfoCache[fundInfo.fundCode] = fundInfo;
    saveFundInfoCacheToPrefs(); // 异步保存到本地
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

    // 加载持仓数据
    final holdingsJson = prefs.getStringList(_holdingsKey);
    if (holdingsJson != null) {
      _holdings = holdingsJson
          .map((json) => FundHolding.fromJson(jsonDecode(json)))
          .toList();
      debugPrint('DataManager: 持仓数据加载成功，总数: ${_holdings.length}');
    } else {
      debugPrint('DataManager: 没有找到持仓数据');
    }

    // 加载交易记录
    final transactionsJson = prefs.getStringList(_transactionsKey);
    if (transactionsJson != null) {
      _transactions = transactionsJson
          .map((json) => TransactionRecord.fromJson(jsonDecode(json)))
          .toList();
      debugPrint('DataManager: 交易记录加载成功，总数: ${_transactions.length}');
    } else {
      debugPrint('DataManager: 没有找到交易记录');
    }

    final logsJson = prefs.getStringList(_logsKey);
    if (logsJson != null) {
      _logs = logsJson
          .map((json) => LogEntry.fromJson(jsonDecode(json)))
          .toList();
      debugPrint('DataManager: 日志数据加载成功，总数: ${_logs.length}');
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

    debugPrint('DataManager: 所有数据保存成功');
  }

  Future<void> loadValuationCache() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_valuationCacheKey);
    if (jsonStr != null) {
      try {
        final Map<String, dynamic> raw = jsonDecode(jsonStr);
        _valuationCache = raw.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
        debugPrint('DataManager: 估值缓存加载成功，共 ${_valuationCache.length} 条');
      } catch (e) {
        debugPrint('DataManager: 加载估值缓存失败: $e');
      }
    }
  }

  Future<void> saveValuationCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_valuationCacheKey, jsonEncode(_valuationCache));
    debugPrint('DataManager: 估值缓存已保存');
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
        debugPrint('DataManager: 基金信息缓存加载成功，共 ${_fundInfoCache.length} 条');
      } catch (e) {
        debugPrint('DataManager: 加载基金信息缓存失败: $e');
      }
    }
  }

  // 保存基金信息缓存到本地
  Future<void> saveFundInfoCacheToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheList = _fundInfoCache.values.map((info) => info.toJson()).toList();
    await prefs.setString(_fundInfoCacheKey, jsonEncode(cacheList));
    debugPrint('DataManager: 基金信息缓存已保存，共 ${cacheList.length} 条');
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
      debugPrint('格式化估值时间失败: $e');
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
        debugPrint('估值刷新部分失败: 成功$successCount, 失败$failCount');
      }

      _currentValuationRefreshCompleter!.complete();
    } catch (e) {
      debugPrint('估值刷新过程异常: $e');
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
    if (transaction.amount <= 0 || transaction.shares <= 0) {
      await addLog('添加交易失败: 金额和份额必须大于0', type: LogType.error);
      throw Exception('无效的交易数据');
    }

    // 添加交易记录
    _transactions = [..._transactions, transaction];

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
      navReturn1w: existingHolding.navReturn1w,
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

  /// 获取指定客户和基金的交易历史
  List<TransactionRecord> getTransactionHistory(String clientId, String fundCode) {
    return _transactions
        .where((tx) => tx.clientId == clientId && tx.fundCode == fundCode)
        .toList()
      ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate)); // 按时间倒序
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

  /// 更新持仓的净值信息（不改变交易记录）
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
    await saveData();
    await addLog('清空所有持仓数据，共删除 $count 条记录', type: LogType.warning);
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
            navReturn1w: fetched['navReturn1w'],
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
    await saveData();
  }

  Future<void> addLog(String message, {LogType type = LogType.info}) async {
    final logEntry = LogEntry.create(message: message, type: type);
    _logs = [logEntry, ..._logs];

    if (_logs.length > 200) {
      _logs = _logs.take(200).toList();
    }

    await saveData();
    debugPrint('[${type.displayName}] $message');
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
    if (holding.totalShares <= 0 || holding.currentNav <= 0 || holding.totalCost <= 0) {
      return const ProfitResult(absolute: 0.0, annualized: 0.0);
    }

    final currentMarketValue = holding.currentNav * holding.totalShares;
    final absoluteProfit = currentMarketValue - holding.totalCost;

    // 计算持有天数：从首次买入到现在
    final relatedTransactions = getTransactionHistory(holding.clientId, holding.fundCode);
    if (relatedTransactions.isEmpty) {
      return ProfitResult(absolute: absoluteProfit, annualized: 0.0);
    }
    
    final firstTradeDate = relatedTransactions.last.tradeDate; // 因为是倒序，最后一条是最早的
    final days = DateTime.now().difference(firstTradeDate).inDays;

    if (days <= 0) {
      return ProfitResult(absolute: absoluteProfit, annualized: 0.0);
    }

    final annualizedReturn = (absoluteProfit / holding.totalCost) / days * 365 * 100;

    return ProfitResult(absolute: absoluteProfit, annualized: annualizedReturn);
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
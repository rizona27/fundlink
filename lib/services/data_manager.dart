import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../models/profit_result.dart';
import '../services/fund_service.dart';
import '../widgets/theme_switch.dart' show ThemeMode;

// 扩展 ThemeMode 显示名称
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
  static const String _logsKey = 'logs';
  static const String _privacyModeKey = 'privacy_mode';
  static const String _themeModeKey = 'theme_mode';

  List<FundHolding> _holdings = [];
  List<LogEntry> _logs = [];
  bool _isPrivacyMode = true;
  ThemeMode _themeMode = ThemeMode.system;

  List<FundHolding> get holdings => List.unmodifiable(_holdings);
  List<LogEntry> get logs => List.unmodifiable(_logs);
  bool get isPrivacyMode => _isPrivacyMode;
  ThemeMode get themeMode => _themeMode;

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
      debugPrint('DataManager: 持仓数据加载成功，总数: ${_holdings.length}');
    } else {
      debugPrint('DataManager: 没有找到持仓数据');
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

    final logsJson = _logs
        .take(100)
        .map((log) => jsonEncode(log.toJson()))
        .toList();
    await prefs.setStringList(_logsKey, logsJson);

    await prefs.setBool(_privacyModeKey, _isPrivacyMode);
    await prefs.setString(_themeModeKey, _themeModeToString(_themeMode));

    debugPrint('DataManager: 所有数据保存成功');
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
        final updated = holding.copyWith(
          fundName: fetched['fundName'],
          currentNav: fetched['currentNav'],
          navDate: fetched['navDate'],
          isValid: true,
          navReturn1m: fetched['navReturn1m'],
          navReturn3m: fetched['navReturn3m'],
          navReturn6m: fetched['navReturn6m'],
          navReturn1y: fetched['navReturn1y'],
        );
        await updateHolding(updated);
      } else {
        await addLog('强制刷新基金 ${holding.fundCode} 失败', type: LogType.error);
      }
      onProgress?.call(i + 1, total);
    }
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

  String obscuredName(String name) {
    if (!_isPrivacyMode || name.isEmpty) return name;

    final firstChar = name[0];
    if (name.length == 1) return name;

    return '$firstChar${'*' * (name.length - 1)}';
  }

  ProfitResult calculateProfit(FundHolding holding) {
    if (holding.purchaseShares <= 0 || holding.currentNav <= 0 || holding.purchaseAmount <= 0) {
      return const ProfitResult(absolute: 0.0, annualized: 0.0);
    }

    final currentMarketValue = holding.currentNav * holding.purchaseShares;
    final absoluteProfit = currentMarketValue - holding.purchaseAmount;

    final days = DateTime.now().difference(holding.purchaseDate).inDays;

    if (days <= 0) {
      return ProfitResult(absolute: absoluteProfit, annualized: 0.0);
    }

    final annualizedReturn = (absoluteProfit / holding.purchaseAmount) / days * 365 * 100;

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

// ==================== DataManagerProvider ====================
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
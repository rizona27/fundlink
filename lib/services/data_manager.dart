import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/fund_holding.dart';
import '../models/log_entry.dart';
import '../models/profit_result.dart';

class DataManager extends ChangeNotifier {
  static const String _holdingsKey = 'fund_holdings';
  static const String _logsKey = 'logs';
  static const String _privacyModeKey = 'privacy_mode';

  final Uuid _uuid = const Uuid();

  List<FundHolding> _holdings = [];
  List<LogEntry> _logs = [];
  bool _isPrivacyMode = true;

  // Getters
  List<FundHolding> get holdings => List.unmodifiable(_holdings);
  List<LogEntry> get logs => List.unmodifiable(_logs);
  bool get isPrivacyMode => _isPrivacyMode;

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
    notifyListeners();
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

    // 创建新列表，替换对应项
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
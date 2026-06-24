import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import '../models/log_entry.dart';
import '../services/database_helper.dart';
import '../services/database_repository.dart';

/// Manages application log entries with ChangeNotifier for targeted UI updates.
class LogNotifier extends ChangeNotifier {
  final DatabaseRepository? _repository;
  List<LogEntry> _logs = [];
  bool _disposed = false;

  LogNotifier(this._repository);

  List<LogEntry> get logs => List.unmodifiable(_logs);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> loadLogs(int limit) async {
    if (_disposed) return;
    if (kIsWeb) return;

    _logs = await _repository!.getLogs(limit: limit);
    notifyListeners();
  }

  void loadLogsFromJson(List<LogEntry> entries) {
    if (_disposed) return;
    _logs = entries;
  }

  Future<void> addLog(String message, {LogType type = LogType.info}) async {
    if (_disposed) return;

    final logEntry = LogEntry.create(message: message, type: type);

    if (!kIsWeb) {
      await _repository!.insertLog(logEntry);
    }

    _logs = [logEntry, ..._logs];

    if (_logs.length > AppConstants.maxLogEntries) {
      _logs = _logs.take(AppConstants.maxLogEntries).toList();
    }

    notifyListeners();
  }

  Future<void> clearAllLogs() async {
    if (_disposed) return;

    if (!kIsWeb) {
      final db = await DatabaseHelper.instance.database;
      await db.delete('logs');
    }

    _logs = [];
    notifyListeners();
  }

  List<LogEntry> serializeLogs() => _logs;
}

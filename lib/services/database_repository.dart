import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/fund_holding.dart';
import '../models/transaction_record.dart';
import '../models/log_entry.dart';
import '../services/database_helper.dart';

/// 数据库访问层 - 封装所有数据库操作
class DatabaseRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;
  
  // ==================== 持仓操作 ====================
  
  Future<List<FundHolding>> getAllHoldings({
    int? limit,
    int? offset,
    String? sortBy,
    bool ascending = false,
  }) async {
    try {
      final rows = await _db.queryAllHoldings(
        limit: limit,
        offset: offset,
        sortBy: sortBy,
        ascending: ascending,
      );
      return rows.map((row) => FundHolding.fromMap(row)).toList();
    } catch (e) {
      debugPrint('查询持仓失败: $e');
      return [];
    }
  }
  
  Future<List<FundHolding>> getPinnedHoldings() async {
    try {
      final rows = await _db.queryPinnedHoldings();
      return rows.map((row) => FundHolding.fromMap(row)).toList();
    } catch (e) {
      debugPrint('查询置顶持仓失败: $e');
      return [];
    }
  }
  
  Future<int> insertHolding(FundHolding holding) async {
    return await _db.insertHolding(holding.toMap());
  }
  
  Future<int> updateHolding(String id, FundHolding holding) async {
    return await _db.updateHolding(id, holding.toMap());
  }
  
  Future<int> deleteHolding(String id) async {
    return await _db.deleteHolding(id);
  }
  
  Future<int> getHoldingsCount() async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM holdings');
    return Sqflite.firstIntValue(result) ?? 0;
  }
  
  // ==================== 交易记录操作 ====================
  
  Future<List<TransactionRecord>> getAllTransactions({
    int? limit,
    int? offset,
  }) async {
    try {
      final rows = await _db.queryAllTransactions(
        limit: limit,
        offset: offset,
      );
      return rows.map((row) => TransactionRecord.fromMap(row)).toList();
    } catch (e) {
      debugPrint('查询交易记录失败: $e');
      return [];
    }
  }
  
  Future<List<TransactionRecord>> getTransactionsByHoldingId(String holdingId) async {
    try {
      final rows = await _db.queryTransactionsByHoldingId(holdingId);
      return rows.map((row) => TransactionRecord.fromMap(row)).toList();
    } catch (e) {
      debugPrint('查询持仓交易记录失败: $e');
      return [];
    }
  }
  
  Future<List<TransactionRecord>> getPendingTransactions() async {
    try {
      final rows = await _db.queryPendingTransactions();
      return rows.map((row) => TransactionRecord.fromMap(row)).toList();
    } catch (e) {
      debugPrint('查询待确认交易失败: $e');
      return [];
    }
  }
  
  Future<int> insertTransaction(TransactionRecord transaction) async {
    return await _db.insertTransaction(transaction.toMap());
  }
  
  Future<int> updateTransaction(String id, TransactionRecord transaction) async {
    return await _db.updateTransaction(id, transaction.toMap());
  }
  
  Future<int> deleteTransaction(String id) async {
    return await _db.deleteTransaction(id);
  }
  
  // ==================== 日志操作 ====================
  
  Future<List<LogEntry>> getLogs({int limit = 100}) async {
    try {
      final rows = await _db.queryLogs(limit: limit);
      return rows.map((row) => LogEntry.fromMap(row)).toList();
    } catch (e) {
      debugPrint('查询日志失败: $e');
      return [];
    }
  }
  
  Future<int> insertLog(LogEntry log) async {
    return await _db.insertLog(log.toMap());
  }
  
  Future<int> clearOldLogs(int daysToKeep) async {
    return await _db.clearOldLogs(daysToKeep);
  }
  
  // ==================== 设置操作 ====================
  
  Future<String?> getSetting(String key) async {
    return await _db.getSetting(key);
  }
  
  Future<void> saveSetting(String key, String value) async {
    await _db.saveSetting(key, value);
  }
  
  // ==================== 批量操作 ====================
  
  Future<void> batchInsertHoldings(List<FundHolding> holdings) async {
    final db = await _db.database;
    final batch = db.batch();
    
    for (final holding in holdings) {
      batch.insert('holdings', holding.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    
    await batch.commit(noResult: true);
  }
  
  Future<void> batchInsertTransactions(List<TransactionRecord> transactions) async {
    final db = await _db.database;
    final batch = db.batch();
    
    for (final transaction in transactions) {
      batch.insert('transactions', transaction.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    
    await batch.commit(noResult: true);
  }
  
  Future<void> batchInsertLogs(List<LogEntry> logs) async {
    final db = await _db.database;
    final batch = db.batch();
    
    for (final log in logs) {
      batch.insert('logs', log.toMap());
    }
    
    await batch.commit(noResult: true);
  }
  
  // ==================== 高级查询 ====================
  
  /// 按客户分组统计
  Future<List<Map<String, dynamic>>> getHoldingsByClient() async {
    final db = await _db.database;
    return await db.rawQuery('''
      SELECT client_id, client_name, COUNT(*) as holding_count, 
             SUM(total_cost) as total_cost, SUM(total_shares * current_nav) as total_value
      FROM holdings
      GROUP BY client_id
      ORDER BY total_value DESC
    ''');
  }
  
  /// 按基金分组统计
  Future<List<Map<String, dynamic>>> getHoldingsByFund() async {
    final db = await _db.database;
    return await db.rawQuery('''
      SELECT fund_code, fund_name, COUNT(*) as holder_count,
             SUM(total_shares) as total_shares, SUM(total_cost) as total_cost
      FROM holdings
      GROUP BY fund_code
      ORDER BY holder_count DESC
    ''');
  }
  
  /// 搜索持仓
  Future<List<FundHolding>> searchHoldings(String keyword) async {
    final db = await _db.database;
    final rows = await db.query(
      'holdings',
      where: 'client_name LIKE ? OR client_id LIKE ? OR fund_code LIKE ? OR fund_name LIKE ?',
      whereArgs: ['%$keyword%', '%$keyword%', '%$keyword%', '%$keyword%'],
      orderBy: 'created_at DESC',
    );
    return rows.map((row) => FundHolding.fromMap(row)).toList();
  }
  
  // ==================== 数据库同步操作 ====================
  
  /// ✅ 修复：强制刷新数据库，确保数据立即写入磁盘
  /// iOS/Android 可能在应用退出时杀死进程，导致 SQLite 缓冲数据丢失
  Future<void> flush() async {
    try {
      final db = await _db.database;
      
      // 先检查当前 journal_mode
      final modeResult = await db.rawQuery('PRAGMA journal_mode');
      final currentMode = modeResult.first.values.first.toString();
      
      debugPrint('[Database] 当前数据库模式: $currentMode');
      
      // 如果是 WAL 模式，执行 FULL checkpoint
      if (currentMode.toLowerCase() == 'wal') {
        final checkpointResult = await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
        debugPrint('[Database] WAL checkpoint 已执行, 结果: $checkpointResult');
      } else {
        // 非 WAL 模式下，设置 synchronous 为 FULL 并执行写操作触发同步
        await db.execute('PRAGMA synchronous = FULL');
        // 执行一个简单的写操作来触发同步
        await db.execute('INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (?, ?, ?)', [
          '_last_flush',
          DateTime.now().toIso8601String(),
          DateTime.now().toIso8601String(),
        ]);
        debugPrint('[Database] 数据库已同步 (synchronous=FULL)');
      }
      
      // 验证数据是否真的写入了
      final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM transactions');
      final count = countResult.first['count'];
      debugPrint('[Database] 数据库中交易记录数: $count');
      
    } catch (e, stackTrace) {
      // flush 失败不应该影响主流程，但需要记录详细错误
      debugPrint('[Database] ❌ 数据库刷新失败: $e');
      debugPrint('[Database] 堆栈跟踪: $stackTrace');
    }
  }
}

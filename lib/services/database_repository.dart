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
}

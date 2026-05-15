import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../models/fund_holding.dart';
import '../models/transaction_record.dart';
import '../models/log_entry.dart';
import '../services/database_helper.dart';

class DatabaseRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;
  
  
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
      return [];
    }
  }
  
  Future<List<FundHolding>> getPinnedHoldings() async {
    try {
      final rows = await _db.queryPinnedHoldings();
      return rows.map((row) => FundHolding.fromMap(row)).toList();
    } catch (e) {
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
      return [];
    }
  }
  
  Future<List<TransactionRecord>> getTransactionsByHoldingId(String holdingId) async {
    try {
      final rows = await _db.queryTransactionsByHoldingId(holdingId);
      return rows.map((row) => TransactionRecord.fromMap(row)).toList();
    } catch (e) {
      return [];
    }
  }
  
  Future<List<TransactionRecord>> getPendingTransactions() async {
    try {
      final rows = await _db.queryPendingTransactions();
      return rows.map((row) => TransactionRecord.fromMap(row)).toList();
    } catch (e) {
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
  
  
  Future<List<LogEntry>> getLogs({int limit = 100}) async {
    try {
      final rows = await _db.queryLogs(limit: limit);
      return rows.map((row) => LogEntry.fromMap(row)).toList();
    } catch (e) {
      return [];
    }
  }
  
  Future<int> insertLog(LogEntry log) async {
    return await _db.insertLog(log.toMap());
  }
  
  Future<int> clearOldLogs(int daysToKeep) async {
    return await _db.clearOldLogs(daysToKeep);
  }
  
  
  Future<String?> getSetting(String key) async {
    return await _db.getSetting(key);
  }
  
  Future<void> saveSetting(String key, String value) async {
    await _db.saveSetting(key, value);
  }
  
  
  Future<void> batchInsertHoldings(List<FundHolding> holdings) async {
    if (holdings.isEmpty) return;
    
    final db = await _db.database;
    
    await db.transaction((txn) async {
      for (final holding in holdings) {
        await txn.insert(
          'holdings',
          holding.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
  
  Future<void> batchInsertTransactions(List<TransactionRecord> transactions) async {
    if (transactions.isEmpty) return;
    
    final db = await _db.database;
    
    await db.transaction((txn) async {
      for (final transaction in transactions) {
        await txn.insert(
          'transactions',
          transaction.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
  
  Future<void> batchInsertLogs(List<LogEntry> logs) async {
    if (logs.isEmpty) return;
    
    final db = await _db.database;
    
    await db.transaction((txn) async {
      for (final log in logs) {
        await txn.insert('logs', log.toMap());
      }
    });
  }
  
  
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
  
  
  Future<void> flush() async {
    try {
      final db = await _db.database;
      
      final modeResult = await db.rawQuery('PRAGMA journal_mode');
      final currentMode = modeResult.first.values.first.toString();
      
      if (currentMode.toLowerCase() == 'wal') {
        await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } else {
        await db.execute('PRAGMA synchronous = FULL');
        await db.execute('INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (?, ?, ?)', [
          '_last_flush',
          DateTime.now().toIso8601String(),
          DateTime.now().toIso8601String(),
        ]);
      }
      
      await db.rawQuery('SELECT COUNT(*) as count FROM transactions');
      
    } catch (e) {
    }
  }
}

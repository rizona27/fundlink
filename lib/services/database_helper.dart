import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 数据库帮助类 - 跨平台 SQLite 支持
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (_database != null) return _database!;
    
    if (kIsWeb) {
      throw UnsupportedError('Web platform uses SharedPreferences instead of SQLite');
    }

    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      _database = await _initDesktopDatabase();
    } else {
      _database = await _initMobileDatabase();
    }
    
    return _database!;
  }

  /// 移动端初始化（iOS/Android）
  Future<Database> _initMobileDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'fundlink.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createSchema,
      onUpgrade: _upgradeDatabase,
    );
  }

  /// 桌面端初始化（Windows/macOS/Linux）
  Future<Database> _initDesktopDatabase() async {
    // 初始化 FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // 获取应用数据目录
    final appDataDir = await getApplicationSupportDirectory();
    final dbPath = join(appDataDir.path, 'fundlink.db');

    // 检查数据库是否存在，不存在则从资源复制或创建
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      await _copyOrCreateDatabase(dbPath);
    }

    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: _createSchema,
      onUpgrade: _upgradeDatabase,
    );
  }

  /// 从资源复制预置数据库或创建新数据库
  Future<void> _copyOrCreateDatabase(String targetPath) async {
    try {
      // 尝试从 assets 读取预置数据库
      final byteData = await rootBundle.load('assets/database/fundlink_template.db');
      final buffer = byteData.buffer.asUint8List();
      
      // 写入到目标位置
      final file = File(targetPath);
      await file.create(recursive: true);
      await file.writeAsBytes(buffer);
      
      debugPrint('已从资源复制数据库模板');
    } catch (e) {
      debugPrint('未找到预置数据库，将创建新数据库: $e');
      // 如果资源中没有，就创建新的空数据库
      final db = await openDatabase(targetPath);
      await _createSchema(db, 1);
      await db.close();
    }
  }

  /// 创建数据库表结构
  Future<void> _createSchema(Database db, int version) async {
    // 持仓表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS holdings (
        id TEXT PRIMARY KEY,
        client_name TEXT NOT NULL,
        client_id TEXT,
        fund_code TEXT NOT NULL,
        fund_name TEXT NOT NULL,
        total_cost REAL NOT NULL DEFAULT 0,
        total_shares REAL NOT NULL DEFAULT 0,
        avg_cost REAL,
        current_nav REAL,
        nav_date TEXT,
        remarks TEXT,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 交易记录表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        id TEXT PRIMARY KEY,
        holding_id TEXT NOT NULL,
        client_id TEXT NOT NULL,
        client_name TEXT NOT NULL,
        fund_code TEXT NOT NULL,
        fund_name TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        shares REAL,
        nav REAL,
        fee_rate REAL DEFAULT 0,
        fee_amount REAL DEFAULT 0,
        trade_date TEXT NOT NULL,
        confirm_date TEXT,
        is_after_1500 INTEGER DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        confirmed_nav REAL,
        remarks TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (holding_id) REFERENCES holdings(id) ON DELETE CASCADE
      )
    ''');

    // 日志表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message TEXT NOT NULL,
        type TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    // 用户设置表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    
    // 创建索引以提升查询性能
    await db.execute('CREATE INDEX IF NOT EXISTS idx_holdings_client ON holdings(client_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_holdings_fund ON holdings(fund_code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_holdings_pinned ON holdings(is_pinned)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_holding ON transactions(holding_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(trade_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status)');
    
    // 新增复合索引，优化常用查询
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_client_fund ON transactions(client_id, fund_code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_client_date ON transactions(client_id, trade_date DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON logs(timestamp DESC)');

    debugPrint('数据库 schema 创建完成 (version $version)');
  }

/// 数据库升级处理
Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
  debugPrint('数据库升级: $oldVersion -> $newVersion');
}

  // ==================== 持仓操作 ====================

  Future<int> insertHolding(Map<String, dynamic> holding) async {
    final db = await database;
    return await db.insert('holdings', holding, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> queryAllHoldings({
    int? limit,
    int? offset,
    String? sortBy,
    bool ascending = false,
  }) async {
    final db = await database;
    
    String orderBy = 'created_at DESC';
    if (sortBy != null) {
      final direction = ascending ? 'ASC' : 'DESC';
      orderBy = '$sortBy $direction';
    }
    
    return await db.query(
      'holdings',
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  Future<List<Map<String, dynamic>>> queryPinnedHoldings() async {
    final db = await database;
    return await db.query(
      'holdings',
      where: 'is_pinned = ?',
      whereArgs: [1],
      orderBy: 'created_at DESC',
    );
  }

  Future<int> updateHolding(String id, Map<String, dynamic> holding) async {
    final db = await database;
    return await db.update(
      'holdings',
      holding,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteHolding(String id) async {
    final db = await database;
    return await db.delete(
      'holdings',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== 交易记录操作 ====================

  Future<int> insertTransaction(Map<String, dynamic> transaction) async {
    final db = await database;
    return await db.insert('transactions', transaction, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> queryAllTransactions({
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    return await db.query(
      'transactions',
      orderBy: 'trade_date DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<List<Map<String, dynamic>>> queryTransactionsByHoldingId(String holdingId) async {
    final db = await database;
    return await db.query(
      'transactions',
      where: 'holding_id = ?',
      whereArgs: [holdingId],
      orderBy: 'trade_date DESC',
    );
  }

  Future<List<Map<String, dynamic>>> queryPendingTransactions() async {
    final db = await database;
    return await db.query(
      'transactions',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'trade_date DESC',
    );
  }

  Future<int> updateTransaction(String id, Map<String, dynamic> transaction) async {
    final db = await database;
    return await db.update(
      'transactions',
      transaction,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTransaction(String id) async {
    final db = await database;
    return await db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== 日志操作 ====================

  Future<int> insertLog(Map<String, dynamic> log) async {
    final db = await database;
    return await db.insert('logs', log);
  }

  Future<List<Map<String, dynamic>>> queryLogs({int limit = 100}) async {
    final db = await database;
    return await db.query(
      'logs',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  Future<int> clearOldLogs(int daysToKeep) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
    return await db.delete(
      'logs',
      where: 'timestamp < ?',
      whereArgs: [cutoffDate.toIso8601String()],
    );
  }

  // ==================== 设置操作 ====================

  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final result = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    
    if (result.isEmpty) return null;
    return result.first['value'] as String?;
  }

  /// 关闭数据库
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}

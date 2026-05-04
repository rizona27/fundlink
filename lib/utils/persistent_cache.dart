import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../services/database_helper.dart';
import 'smart_cache.dart';

/// 持久化缓存包装器
/// 将 SmartCache 的数据持久化到 SQLite 数据库
class PersistentCache<K, V> {
  final SmartCache<K, V> _memoryCache;
  final String _tableName;
  final String Function(K) _keySerializer;
  final K Function(String) _keyDeserializer;
  final String Function(V) _valueSerializer;
  final V Function(String) _valueDeserializer;
  
  bool _isInitialized = false;
  
  PersistentCache({
    required int maxSize,
    required Duration ttl,
    required String tableName,  // ✅ 修复：移除下划线前缀
    required K Function(String) keyDeserializer,  // ✅ 修复：移除下划线前缀
    required String Function(K) keySerializer,  // ✅ 修复：移除下划线前缀
    required String Function(V) valueSerializer,  // ✅ 修复：移除下划线前缀
    required V Function(String) valueDeserializer,  // ✅ 修复：移除下划线前缀
  }) : _tableName = tableName,
       _keyDeserializer = keyDeserializer,
       _keySerializer = keySerializer,
       _valueSerializer = valueSerializer,
       _valueDeserializer = valueDeserializer,
       _memoryCache = SmartCache<K, V>(maxSize: maxSize, ttl: ttl);
  
  /// 初始化持久化缓存
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final db = await DatabaseHelper.instance.database;
      
      // 创建表（如果不存在）
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableName (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          last_accessed INTEGER NOT NULL,
          access_count INTEGER NOT NULL DEFAULT 0
        )
      ''');
      
      // 从数据库加载数据到内存缓存
      await _loadFromDatabase();
      
      _isInitialized = true;
      debugPrint('持久化缓存 $_tableName 初始化成功');
    } catch (e) {
      debugPrint('持久化缓存 $_tableName 初始化失败: $e');
    }
  }
  
  /// 从数据库加载数据
  Future<void> _loadFromDatabase() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final ttlMillis = _memoryCache.ttl.inMilliseconds;
      
      // 只加载未过期的数据
      final results = await db.query(
        _tableName,
        where: 'created_at > ?',
        whereArgs: [now - ttlMillis],
      );
      
      for (final row in results) {
        final key = _keyDeserializer(row['key'] as String);
        final value = _valueDeserializer(row['value'] as String);
        _memoryCache.put(key, value);
      }
      
      debugPrint('从数据库加载 ${results.length} 条缓存数据到 $_tableName');
    } catch (e) {
      debugPrint('从数据库加载缓存失败: $e');
    }
  }
  
  /// 获取缓存值
  V? get(K key) {
    final value = _memoryCache.get(key);
    if (value != null) {
      _saveToDatabaseAsync(key, value); // 异步保存
    }
    return value;
  }
  
  /// 设置缓存值
  Future<void> put(K key, V value) async {
    _memoryCache.put(key, value);
    await _saveToDatabase(key, value);
  }
  
  /// 同步保存到数据库
  Future<void> _saveToDatabase(K key, V value) async {
    if (!_isInitialized) return;
    
    try {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      await db.insert(
        _tableName,
        {
          'key': _keySerializer(key),
          'value': _valueSerializer(value),
          'created_at': now,
          'last_accessed': now,
          'access_count': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('保存缓存到数据库失败: $e');
    }
  }
  
  /// 异步保存到数据库（不等待完成）
  void _saveToDatabaseAsync(K key, V value) {
    if (!_isInitialized) return;
    
    // 使用 unawaited 避免阻塞
    _saveToDatabase(key, value).catchError((e) {
      debugPrint('异步保存缓存失败: $e');
    });
  }
  
  /// 删除缓存
  Future<void> remove(K key) async {
    _memoryCache.remove(key);
    
    if (!_isInitialized) return;
    
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete(
        _tableName,
        where: 'key = ?',
        whereArgs: [_keySerializer(key)],
      );
    } catch (e) {
      debugPrint('从数据库删除缓存失败: $e');
    }
  }
  
  /// 清空缓存
  Future<void> clear() async {
    _memoryCache.clear();
    
    if (!_isInitialized) return;
    
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete(_tableName);
      debugPrint('已清空持久化缓存 $_tableName');
    } catch (e) {
      debugPrint('清空持久化缓存失败: $e');
    }
  }
  
  /// 清理过期缓存
  Future<int> cleanup() async {
    final cleaned = _memoryCache.cleanup();
    
    if (!_isInitialized) return cleaned;
    
    try {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final ttlMillis = _memoryCache.ttl.inMilliseconds;
      
      final deleted = await db.delete(
        _tableName,
        where: 'created_at < ?',
        whereArgs: [now - ttlMillis],
      );
      
      if (deleted > 0) {
        debugPrint('从数据库清理 $deleted 条过期缓存 ($_tableName)');
      }
      
      return cleaned + deleted;
    } catch (e) {
      debugPrint('清理过期缓存失败: $e');
      return cleaned;
    }
  }
  
  /// 获取缓存大小
  int get size => _memoryCache.size;
  
  /// 检查键是否存在
  bool containsKey(K key) => _memoryCache.containsKey(key);
}

/// 基金信息持久化缓存
class FundInfoPersistentCache extends PersistentCache<String, Map<String, dynamic>> {
  FundInfoPersistentCache({
    int maxSize = 100,
    Duration ttl = const Duration(days: 7),
  }) : super(
          maxSize: maxSize,
          ttl: ttl,
          tableName: 'fund_info_persistent_cache',  // ✅ 修复：使用新参数名
          keySerializer: (key) => key,
          keyDeserializer: (str) => str,
          valueSerializer: (value) => jsonEncode(value),
          valueDeserializer: (str) => jsonDecode(str) as Map<String, dynamic>,
        );
}

/// 净值趋势持久化缓存
class NetWorthPersistentCache extends PersistentCache<String, List<Map<String, dynamic>>> {
  NetWorthPersistentCache({
    int maxSize = 50,
    Duration ttl = const Duration(hours: 24),
  }) : super(
          maxSize: maxSize,
          ttl: ttl,
          tableName: 'net_worth_persistent_cache',  // ✅ 修复：使用新参数名
          keySerializer: (key) => key,
          keyDeserializer: (str) => str,
          valueSerializer: (value) => jsonEncode(value),
          valueDeserializer: (str) => (jsonDecode(str) as List).cast<Map<String, dynamic>>(),
        );
}

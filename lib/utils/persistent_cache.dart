import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../services/database_helper.dart';
import 'smart_cache.dart';

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
    required String tableName,
    required K Function(String) keyDeserializer,
    required String Function(K) keySerializer,
    required String Function(V) valueSerializer,
    required V Function(String) valueDeserializer,
  }) : _tableName = tableName,
       _keyDeserializer = keyDeserializer,
       _keySerializer = keySerializer,
       _valueSerializer = valueSerializer,
       _valueDeserializer = valueDeserializer,
       _memoryCache = SmartCache<K, V>(maxSize: maxSize, ttl: ttl);
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final db = await DatabaseHelper.instance.database;
      
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableName (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          last_accessed INTEGER NOT NULL,
          access_count INTEGER NOT NULL DEFAULT 0
        )
      ''');
      
      await _loadFromDatabase();
      
      _isInitialized = true;
    } catch (e) {
    }
  }
  
  Future<void> _loadFromDatabase() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final ttlMillis = _memoryCache.ttl.inMilliseconds;
      
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
    } catch (e) {
    }
  }
  
  V? get(K key) {
    final value = _memoryCache.get(key);
    if (value != null) {
      _saveToDatabaseAsync(key, value);
    }
    return value;
  }
  
  Future<void> put(K key, V value) async {
    _memoryCache.put(key, value);
    await _saveToDatabase(key, value);
  }
  
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
    }
  }
  
  void _saveToDatabaseAsync(K key, V value) {
    if (!_isInitialized) return;
    
    _saveToDatabase(key, value).catchError((e) {
    });
  }
  
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
    }
  }
  
  Future<void> clear() async {
    _memoryCache.clear();
    
    if (!_isInitialized) return;
    
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete(_tableName);
    } catch (e) {
    }
  }
  
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
      
      return cleaned + deleted;
    } catch (e) {
      return cleaned;
    }
  }
  
  int get size => _memoryCache.size;
  
  bool containsKey(K key) => _memoryCache.containsKey(key);
}

class FundInfoPersistentCache extends PersistentCache<String, Map<String, dynamic>> {
  FundInfoPersistentCache({
    int maxSize = 100,
    Duration ttl = const Duration(days: 7),
  }) : super(
          maxSize: maxSize,
          ttl: ttl,
          tableName: 'fund_info_persistent_cache',
          keySerializer: (key) => key,
          keyDeserializer: (str) => str,
          valueSerializer: (value) => jsonEncode(value),
          valueDeserializer: (str) => jsonDecode(str) as Map<String, dynamic>,
        );
}

class NetWorthPersistentCache extends PersistentCache<String, List<Map<String, dynamic>>> {
  NetWorthPersistentCache({
    int maxSize = 50,
    Duration ttl = const Duration(hours: 24),
  }) : super(
          maxSize: maxSize,
          ttl: ttl,
          tableName: 'net_worth_persistent_cache',
          keySerializer: (key) => key,
          keyDeserializer: (str) => str,
          valueSerializer: (value) => jsonEncode(value),
          valueDeserializer: (str) => (jsonDecode(str) as List).cast<Map<String, dynamic>>(),
        );
}

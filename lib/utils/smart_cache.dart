import 'dart:collection';
import 'package:flutter/foundation.dart';

/// 缓存条目
class _CacheEntry<V> {
  V value;
  DateTime createdAt;
  DateTime lastAccessed;
  int accessCount;
  
  _CacheEntry({
    required this.value,
    required this.createdAt,
    required this.lastAccessed,
    this.accessCount = 0,
  });
}

/// 智能 LRU 缓存 - 支持 TTL 和最大容量限制
class SmartCache<K, V> {
  final int maxSize;
  final Duration ttl;
  final LinkedHashMap<K, _CacheEntry<V>> _cache = LinkedHashMap();
  
  // 统计信息
  int _hitCount = 0;
  int _missCount = 0;
  int _evictionCount = 0;
  
  SmartCache({
    this.maxSize = 100,
    this.ttl = const Duration(hours: 1),
  });
  
  /// 获取缓存值
  V? get(K key) {
    final entry = _cache[key];
    
    if (entry == null) {
      _missCount++;
      return null;
    }
    
    // 检查 TTL
    final now = DateTime.now();
    if (now.difference(entry.createdAt) > ttl) {
      _cache.remove(key);
      _missCount++;
      debugPrint('缓存过期: $key');
      return null;
    }
    
    // 更新访问信息（LRU）
    entry.lastAccessed = now;
    entry.accessCount++;
    
    // 移到末尾（最近使用）
    _cache.remove(key);
    _cache[key] = entry;
    
    _hitCount++;
    return entry.value;
  }
  
  /// 设置缓存值
  void put(K key, V value) {
    // 如果已存在，先移除
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    }
    
    // 如果达到最大容量，移除最久未使用的
    while (_cache.length >= maxSize) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
      _evictionCount++;
      debugPrint('缓存淘汰: $oldestKey (当前大小: ${_cache.length})');
    }
    
    _cache[key] = _CacheEntry(
      value: value,
      createdAt: DateTime.now(),
      lastAccessed: DateTime.now(),
      accessCount: 0,
    );
  }
  
  /// 删除缓存
  void remove(K key) {
    _cache.remove(key);
  }
  
  /// 根据条件删除缓存
  void removeWhere(bool Function(K key, V value) test) {
    final keysToRemove = <K>[];
    for (final entry in _cache.entries) {
      if (test(entry.key, entry.value.value)) {
        keysToRemove.add(entry.key);
      }
    }
    for (final key in keysToRemove) {
      _cache.remove(key);
    }
  }
  
  /// [] 运算符支持
  V? operator [](K key) => get(key);
  
  /// []= 运算符支持
  void operator []=(K key, V value) => put(key, value);
  
  /// 清空缓存
  void clear() {
    _cache.clear();
    debugPrint('缓存已清空');
  }
  
  /// 检查键是否存在
  bool containsKey(K key) {
    return _cache.containsKey(key);
  }
  
  /// 获取缓存大小
  int get size => _cache.length;
  
  /// length 别名（兼容性）
  int get length => _cache.length;
  
  /// 获取所有键
  Iterable<K> get keys => _cache.keys;
  
  /// 获取命中率
  double get hitRate {
    final total = _hitCount + _missCount;
    return total > 0 ? _hitCount / total : 0.0;
  }
  
  /// 获取统计信息
  CacheStats get stats {
    return CacheStats(
      size: _cache.length,
      maxSize: maxSize,
      hitCount: _hitCount,
      missCount: _missCount,
      evictionCount: _evictionCount,
      hitRate: hitRate,
    );
  }
  
  /// 清理过期缓存
  int cleanup() {
    final now = DateTime.now();
    final expiredKeys = <K>[];
    
    for (final entry in _cache.entries) {
      if (now.difference(entry.value.createdAt) > ttl) {
        expiredKeys.add(entry.key);
      }
    }
    
    for (final key in expiredKeys) {
      _cache.remove(key);
    }
    
    if (expiredKeys.isNotEmpty) {
      debugPrint('清理过期缓存: ${expiredKeys.length} 条');
    }
    
    return expiredKeys.length;
  }
  
  /// 打印统计信息
  void printStats() {
    final stats = this.stats;
    debugPrint('''
===== 缓存统计 =====
大小: ${stats.size}/${stats.maxSize}
命中: ${stats.hitCount}
未命中: ${stats.missCount}
淘汰: ${stats.evictionCount}
命中率: ${(stats.hitRate * 100).toStringAsFixed(2)}%
==================
''');
  }
}

/// 缓存统计信息
class CacheStats {
  final int size;
  final int maxSize;
  final int hitCount;
  final int missCount;
  final int evictionCount;
  final double hitRate;
  
  CacheStats({
    required this.size,
    required this.maxSize,
    required this.hitCount,
    required this.missCount,
    required this.evictionCount,
    required this.hitRate,
  });
  
  @override
  String toString() {
    return 'CacheStats(size: $size/$maxSize, hitRate: ${(hitRate * 100).toStringAsFixed(2)}%)';
  }
}

import 'dart:collection';

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

class SmartCache<K, V> {
  final int maxSize;
  final Duration ttl;
  final LinkedHashMap<K, _CacheEntry<V>> _cache = LinkedHashMap();
  
  int _hitCount = 0;
  int _missCount = 0;
  int _evictionCount = 0;
  
  SmartCache({
    this.maxSize = 100,
    this.ttl = const Duration(hours: 1),
  });
  
  V? get(K key) {
    final entry = _cache[key];
    
    if (entry == null) {
      _missCount++;
      return null;
    }
    
    final now = DateTime.now();
    if (now.difference(entry.createdAt) > ttl) {
      _cache.remove(key);
      _missCount++;
      return null;
    }
    
    entry.lastAccessed = now;
    entry.accessCount++;
    
    _cache.remove(key);
    _cache[key] = entry;
    
    _hitCount++;
    return entry.value;
  }
  
  void put(K key, V value) {
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    }
    
    while (_cache.length >= maxSize) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
      _evictionCount++;
    }
    
    _cache[key] = _CacheEntry(
      value: value,
      createdAt: DateTime.now(),
      lastAccessed: DateTime.now(),
      accessCount: 0,
    );
  }
  
  void remove(K key) {
    _cache.remove(key);
  }
  
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
  
  V? operator [](K key) => get(key);
  
  void operator []=(K key, V value) => put(key, value);
  
  void clear() {
    _cache.clear();
  }
  
  bool containsKey(K key) {
    return _cache.containsKey(key);
  }
  
  int get size => _cache.length;
  
  int get length => _cache.length;
  
  Iterable<K> get keys => _cache.keys;
  
  double get hitRate {
    final total = _hitCount + _missCount;
    return total > 0 ? _hitCount / total : 0.0;
  }
  
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
    
    return expiredKeys.length;
  }
  
  void printStats() {
  }
}

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

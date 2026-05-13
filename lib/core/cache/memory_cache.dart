class MemoryCache<K, V> {
  final Duration ttl;
  final Map<K, (DateTime, V)> _store = {};

  MemoryCache({this.ttl = const Duration(minutes: 5)});

  V? get(K key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.$1) > ttl) {
      _store.remove(key);
      return null;
    }
    return entry.$2;
  }

  void set(K key, V value) => _store[key] = (DateTime.now(), value);
  void invalidate(K key) => _store.remove(key);
  void clear() => _store.clear();
}

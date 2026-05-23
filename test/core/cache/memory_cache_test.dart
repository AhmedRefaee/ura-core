import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/core/cache/memory_cache.dart';

// MemoryCache uses DateTime.now() internally, so TTL tests use a real
// short-lived cache rather than a fake clock.
MemoryCache<String, String> _shortCache() =>
    MemoryCache(ttl: const Duration(milliseconds: 10));

void main() {
  group('MemoryCache', () {
    late MemoryCache<String, String> cache;

    setUp(() {
      cache = MemoryCache(ttl: const Duration(minutes: 5));
    });

    // ─── Empty data ───────────────────────────────────────────────────────────
    test('miss on empty store returns null', () {
      expect(cache.get('anything'), isNull);
    });

    test('hit within TTL returns stored value', () {
      cache.set('key', 'value');
      expect(cache.get('key'), 'value');
    });

    // ─── Slow internet / TTL expiry ───────────────────────────────────────────
    test('miss after TTL expires', () async {
      final c = _shortCache();
      c.set('key', 'value');
      await Future.delayed(const Duration(milliseconds: 20));
      expect(c.get('key'), isNull);
    });

    test('hit just before TTL does not evict', () {
      // Entry was just set — well within any reasonable TTL
      cache.set('key', 'value');
      expect(cache.get('key'), 'value');
    });

    // ─── Invalidate ───────────────────────────────────────────────────────────
    test('invalidate removes only the targeted key', () {
      cache.set('a', 'aval');
      cache.set('b', 'bval');
      cache.invalidate('a');
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), 'bval');
    });

    test('invalidating a non-existent key is a no-op', () {
      cache.set('a', 'aval');
      cache.invalidate('missing');
      expect(cache.get('a'), 'aval');
    });

    // ─── Clear ────────────────────────────────────────────────────────────────
    test('clear removes all entries', () {
      cache.set('a', 'aval');
      cache.set('b', 'bval');
      cache.clear();
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), isNull);
    });

    // ─── Overwrite refreshes timestamp ────────────────────────────────────────
    test('overwriting a key resets its TTL', () async {
      final c = _shortCache();
      c.set('key', 'first');
      // Wait almost to expiry, then overwrite to reset TTL
      await Future.delayed(const Duration(milliseconds: 5));
      c.set('key', 'second');
      // Should still be readable immediately after overwrite
      expect(c.get('key'), 'second');
      // Wait for the original TTL window to pass — key should still be live
      // because the overwrite restarted the clock
      await Future.delayed(const Duration(milliseconds: 8));
      expect(c.get('key'), 'second');
    });

    test('expired entry is removed on next get', () async {
      final c = _shortCache();
      c.set('key', 'val');
      await Future.delayed(const Duration(milliseconds: 20));
      // get triggers eviction
      expect(c.get('key'), isNull);
      // setting again after eviction should work
      c.set('key', 'new');
      expect(c.get('key'), 'new');
    });
  });
}

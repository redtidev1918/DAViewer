import 'dart:async';

/// Repository-level request contract: one in-flight request per resource key,
/// optional success cache, failed results never cached, and explicit
/// invalidation. Providers may read through this gate but must not reimplement
/// dedup/cache themselves.
final class RepositoryRequestGate<T> {
  final Map<String, Completer<T>> _inflight = <String, Completer<T>>{};
  final Map<String, T> _cache = <String, T>{};

  Future<T> load(
    String key,
    Future<T> Function() loader, {
    bool force = false,
  }) {
    if (!force && _cache.containsKey(key)) {
      return Future<T>.value(_cache[key]!);
    }
    final active = _inflight[key];
    if (active != null) return active.future;

    final completer = Completer<T>();
    _inflight[key] = completer;
    unawaited(() async {
      try {
        final value = await loader();
        _cache[key] = value;
        completer.complete(value);
      } on Object catch (error, stack) {
        completer.completeError(error, stack);
      } finally {
        _inflight.remove(key);
      }
    }());
    return completer.future;
  }

  void invalidate(String key) {
    _cache.remove(key);
  }

  /// Drops an in-flight request so a later call with the same key starts a
  /// fresh request instead of awaiting the abandoned completer forever.
  void cancel(String key) {
    _inflight.remove(key);
  }

  void clear() {
    _cache.clear();
  }
}

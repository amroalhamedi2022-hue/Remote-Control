import 'dart:collection';

// Keep this process-local replay cache bounded even if a caller misconfigures it.
const int _maxNonceEntries = 4096;
const Duration _maxNonceLifetime = Duration(days: 1);
const int _maxSafeMonotonicMicros = 0x7fffffffffffffff;

/// Rejects replayed signed hello nonces within one process-local pairing guard.
///
/// This is a defense-in-depth replay check for the experimental pairing lab,
/// not a substitute for a reviewed production protocol. Expiry uses a monotonic
/// clock so wall-clock adjustments cannot extend a nonce's lifetime.
class PairingNonceGuard {
  PairingNonceGuard({
    this.lifetime = const Duration(minutes: 5),
    this.maxEntries = 256,
    int Function()? monotonicMicros,
  }) : _monotonicMicros = monotonicMicros {
    if (lifetime <= Duration.zero ||
        lifetime > _maxNonceLifetime ||
        maxEntries < 1 ||
        maxEntries > _maxNonceEntries) {
      throw ArgumentError('Nonce guard limits are outside safe bounds');
    }
    _watch.start();
  }

  final Duration lifetime;
  final int maxEntries;
  final int Function()? _monotonicMicros;
  final Stopwatch _watch = Stopwatch();
  final LinkedHashMap<String, int> _expiresAtMicros = LinkedHashMap();

  int? _lastObservedMicros;
  bool _clockBroken = false;

  /// A monotonic-clock rollback invalidates all cached nonces and disables this
  /// guard until the pairing session creates a fresh instance. Clearing and
  /// immediately accepting new values would reopen replay of an old nonce.
  int? _readNowMicros() {
    if (_clockBroken) return null;
    final now = _monotonicMicros?.call() ?? _watch.elapsedMicroseconds;
    final previous = _lastObservedMicros;
    if (previous != null && now < previous) {
      _expiresAtMicros.clear();
      _clockBroken = true;
      return null;
    }
    _lastObservedMicros = now;
    return now;
  }

  /// Returns false for a duplicate or when capacity is full.
  ///
  /// Capacity fails closed instead of evicting an unexpired nonce, because
  /// eviction would let an attacker replay an earlier hello before its TTL.
  bool remember(String identity, String nonce) {
    const encodedField = r'^[A-Za-z0-9_-]{1,255}$';
    if (!RegExp(encodedField).hasMatch(identity) ||
        !RegExp(encodedField).hasMatch(nonce)) {
      throw const FormatException('Invalid pairing identity or nonce encoding');
    }
    final now = _readNowMicros();
    if (now == null) return false;
    _purge(now);
    final key = '$identity:$nonce';
    if (_expiresAtMicros.containsKey(key)) return false;
    if (_expiresAtMicros.length >= maxEntries) return false;
    final ttlMicros = lifetime.inMicroseconds;
    // A broken/wrapped monotonic counter must not turn a fresh nonce into an
    // already-expired entry, which would make the same signed hello replayable.
    if (now > _maxSafeMonotonicMicros - ttlMicros) {
      _expiresAtMicros.clear();
      _clockBroken = true;
      return false;
    }
    _expiresAtMicros[key] = now + ttlMicros;
    return true;
  }

  int get length {
    final now = _readNowMicros();
    if (now == null) return 0;
    _purge(now);
    return _expiresAtMicros.length;
  }

  void _purge(int nowMicros) {
    _expiresAtMicros.removeWhere((_, expiresAt) => nowMicros >= expiresAt);
  }
}

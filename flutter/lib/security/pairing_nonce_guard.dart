import 'dart:collection';

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
    if (lifetime <= Duration.zero || maxEntries < 1) {
      throw ArgumentError('Nonce guard limits must be positive');
    }
    _watch.start();
  }

  final Duration lifetime;
  final int maxEntries;
  final int Function()? _monotonicMicros;
  final Stopwatch _watch = Stopwatch();
  final LinkedHashMap<String, int> _expiresAtMicros = LinkedHashMap();

  int get _nowMicros => _monotonicMicros?.call() ?? _watch.elapsedMicroseconds;

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
    final now = _nowMicros;
    _purge(now);
    final key = '$identity:$nonce';
    if (_expiresAtMicros.containsKey(key)) return false;
    if (_expiresAtMicros.length >= maxEntries) return false;
    _expiresAtMicros[key] = now + lifetime.inMicroseconds;
    return true;
  }

  int get length {
    _purge(_nowMicros);
    return _expiresAtMicros.length;
  }

  void _purge(int nowMicros) {
    _expiresAtMicros.removeWhere((_, expiresAt) => nowMicros >= expiresAt);
  }
}
